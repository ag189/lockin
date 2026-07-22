import Foundation
import os

/// Best-effort, asynchronous sync of completed sessions to ActivityWatch.
///
/// Non-negotiables enforced here:
/// - Only `localhost:5600` is ever contacted.
/// - Only the `lockin-sessions_<hostname>` bucket is ever written. No `aw-watcher-*` bucket is
///   read for anything other than hostname discovery, and none is ever modified.
/// - A failure is never surfaced as an alert; the only signal is the pending count.
actor AWSync {
    private let store: Store
    private let baseURL = URL(string: "http://localhost:5600")!
    private let session: URLSession
    private let clientName: String
    private let bucketPrefix: String
    private let log = Logger(subsystem: "com.lockin.app", category: "awsync")

    private var cachedBucketId: String?
    /// Attempts per session id within this launch. Capped, then backed off to launch-only.
    private var attempts: [Int64: Int] = [:]
    private let maxAttemptsPerLaunch = 5

    /// Reports the current count of unsynced completed sessions to the UI.
    var onPendingCountChanged: (@Sendable (Int) -> Void)?

    init(store: Store, clientName: String = "lockin", bucketPrefix: String = "lockin-sessions") {
        self.store = store
        self.clientName = clientName
        self.bucketPrefix = bucketPrefix
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func setPendingCountHandler(_ handler: @escaping @Sendable (Int) -> Void) {
        onPendingCountChanged = handler
    }

    // MARK: - Public entry points

    /// Attempts to sync every unsynced completed session. Safe to call repeatedly.
    func syncPending() async {
        do {
            let pending = try await store.unsyncedCompletedSessions()
            await publishPending(pending.count)
            guard !pending.isEmpty else { return }

            let bucketId = try await ensureBucket()

            for s in pending {
                guard let id = s.id else { continue }
                let used = attempts[id, default: 0]
                if used >= maxAttemptsPerLaunch { continue }
                do {
                    try await syncOne(sessionId: id, bucketId: bucketId)
                    try await store.markSynced(sessionId: id)
                    attempts[id] = 0
                } catch {
                    attempts[id] = used + 1
                    log.error("Sync failed for session \(id): \(error.localizedDescription, privacy: .public)")
                }
            }
            let remaining = try await store.unsyncedCount()
            await publishPending(remaining)
        } catch {
            log.error("syncPending aborted: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Test/support helper: ensures the bucket exists and returns its id.
    func currentBucketId() async throws -> String {
        try await ensureBucket()
    }

    /// Test/support helper: fetches raw events from one of our own buckets.
    func fetchEvents(bucketId: String) async throws -> [[String: Any]] {
        let (data, response) = try await session.data(for: request(path: "/api/0/buckets/\(bucketId)/events"))
        try Self.ensureOK(response)
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Test-only cleanup: deletes one of our own buckets. Never used against `aw-watcher-*`.
    /// ActivityWatch requires `?force=1` to actually delete a bucket.
    func deleteOwnBucket(bucketId: String) async {
        guard bucketId.hasPrefix(bucketPrefix) else { return }
        _ = try? await session.data(for: request(path: "/api/0/buckets/\(bucketId)?force=1", method: "DELETE"))
    }

    func refreshPendingCount() async {
        if let count = try? await store.unsyncedCount() {
            await publishPending(count)
        }
    }

    private func publishPending(_ count: Int) async {
        onPendingCountChanged?(count)
    }

    // MARK: - Hostname discovery + bucket

    /// Reads the hostname off an existing `aw-watcher-*` bucket so our bucket lands in the same
    /// device group. Never derived independently, never hardcoded.
    private func discoverHostname() async throws -> String {
        let (data, response) = try await session.data(for: request(path: "/api/0/buckets/"))
        try Self.ensureOK(response)
        let buckets = try JSONDecoder().decode([String: BucketInfo].self, from: data)
        if let watcher = buckets.first(where: { $0.key.hasPrefix("aw-watcher-") }),
           let hostname = watcher.value.hostname, !hostname.isEmpty {
            return hostname
        }
        // No watcher bucket present yet; fall back to the machine's own name.
        if let host = Host.current().localizedName { return host }
        throw AWSyncError.hostnameUnavailable
    }

    private func ensureBucket() async throws -> String {
        if let cached = cachedBucketId { return cached }

        let hostname = try await discoverHostname()
        let bucketId = "\(bucketPrefix)_\(hostname)"

        var req = request(path: "/api/0/buckets/\(bucketId)", method: "POST")
        let body: [String: Any] = [
            "client": clientName,
            "type": "currentwindow",
            "hostname": hostname
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AWSyncError.badResponse }
        // 200/201 created; 304 already exists — both are success.
        guard http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 304 else {
            throw AWSyncError.http(http.statusCode)
        }
        cachedBucketId = bucketId
        return bucketId
    }

    // MARK: - Event write

    private func syncOne(sessionId: Int64, bucketId: String) async throws {
        guard let payload = try await store.syncPayload(sessionId: sessionId) else {
            throw AWSyncError.missingPayload
        }
        guard let start = DateISO.date(from: payload.session.startedAt),
              let endString = payload.session.endedAt,
              let end = DateISO.date(from: endString) else {
            throw AWSyncError.missingPayload
        }
        let duration = max(0, end.timeIntervalSince(start))

        // Dedupe on data.lockin_id: remove any existing event for this session, then post.
        try await deleteExistingEvents(bucketId: bucketId, lockinId: sessionId, around: start)

        let data: [String: Any] = [
            "app": payload.task.taskName,
            "title": payload.task.taskName,
            "task": payload.task.taskName,
            "kind": payload.session.kind,
            "output": payload.outputText ?? "",
            "lockin_id": sessionId
        ]
        let event: [String: Any] = [
            "timestamp": payload.session.startedAt,
            "duration": duration,
            "data": data
        ]

        var req = request(path: "/api/0/buckets/\(bucketId)/events", method: "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [event])
        let (_, response) = try await session.data(for: req)
        try Self.ensureOK(response)
    }

    private func deleteExistingEvents(bucketId: String, lockinId: Int64, around start: Date) async throws {
        let from = start.addingTimeInterval(-86_400)
        let to = start.addingTimeInterval(86_400)
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/0/buckets/\(bucketId)/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start", value: DateISO.string(from: from)),
            URLQueryItem(name: "end", value: DateISO.string(from: to)),
            URLQueryItem(name: "limit", value: "1000")
        ]
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"

        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        let events = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        for event in events {
            guard let eventId = event["id"] as? Int,
                  let payload = event["data"] as? [String: Any],
                  let existing = payload["lockin_id"] as? Int,
                  Int64(existing) == lockinId else { continue }
            var del = request(path: "/api/0/buckets/\(bucketId)/events/\(eventId)", method: "DELETE")
            del.httpBody = nil
            _ = try? await session.data(for: del)
        }
    }

    // MARK: - Helpers

    private func request(path: String, method: String = "GET") -> URLRequest {
        // Path may carry a query string (e.g. "?force=1"). Split so query params aren't
        // percent-encoded into the path component by URL.appendingPathComponent.
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var url = baseURL.appendingPathComponent(String(parts[0]))
        if parts.count == 2, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = String(parts[1])
            if let rebuilt = components.url { url = rebuilt }
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private static func ensureOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AWSyncError.badResponse }
        guard (200...299).contains(http.statusCode) else { throw AWSyncError.http(http.statusCode) }
    }
}

private struct BucketInfo: Decodable {
    var hostname: String?
}

enum AWSyncError: Error {
    case badResponse
    case http(Int)
    case hostnameUnavailable
    case missingPayload
}
