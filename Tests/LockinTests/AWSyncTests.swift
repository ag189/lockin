import XCTest
@testable import Lockin

/// Integration test against a live ActivityWatch at localhost:5600. Uses a throwaway bucket
/// (`lockin-test-sessions_<host>`) so it never touches the real product bucket, and deletes that
/// bucket afterward. Skips cleanly if the server is not running.
final class AWSyncTests: XCTestCase {
    private func serverIsUp() async -> Bool {
        var req = URLRequest(url: URL(string: "http://localhost:5600/api/0/buckets/")!)
        req.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    private func makeStore() throws -> Store {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lockin-awtest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("db.sqlite")
        return try Store(url: url)
    }

    func testCompletedSessionSyncsAsEvent() async throws {
        guard await serverIsUp() else {
            throw XCTSkip("ActivityWatch not reachable on localhost:5600")
        }

        let store = try makeStore()
        let sync = AWSync(store: store, clientName: "lockin-test", bucketPrefix: "lockin-test-sessions")

        let project = try await store.createProject(name: "Lockin Test Project", color: "#12A594")
        let task = try await store.createTask(projectId: project.id!, name: "integration event")
        let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
        let start = DateISO.date(from: session.startedAt)!
        _ = try await store.stopSession(id: session.id!, endedAt: start.addingTimeInterval(90))
        try await store.addOutput(taskId: task.id!, sessionId: session.id!, text: "verified sync")

        let bucketId = try await sync.currentBucketId()
        addTeardownBlock {
            await sync.deleteOwnBucket(bucketId: bucketId)
        }

        await sync.syncPending()

        // Local row should now be marked synced.
        XCTAssertEqual(try await store.unsyncedCount(), 0)

        // The event should be present in our bucket with the expected declared data.
        let events = try await sync.fetchEvents(bucketId: bucketId)
        let match = events.first { event in
            guard let data = event["data"] as? [String: Any] else { return false }
            return (data["lockin_id"] as? Int).map { Int64($0) } == session.id
        }
        XCTAssertNotNil(match, "Expected an event carrying lockin_id \(session.id!)")

        if let data = match?["data"] as? [String: Any] {
            XCTAssertEqual(data["task"] as? String, "integration event")
            XCTAssertEqual(data["kind"] as? String, "work")
            XCTAssertEqual(data["output"] as? String, "verified sync")
            XCTAssertEqual(data["app"] as? String, "integration event")
            XCTAssertEqual(data["title"] as? String, "integration event")
        }
        if let duration = match?["duration"] as? Double {
            XCTAssertEqual(duration, 90, accuracy: 1.0)
        }
    }

    func testResyncDoesNotDuplicate() async throws {
        guard await serverIsUp() else {
            throw XCTSkip("ActivityWatch not reachable on localhost:5600")
        }
        let store = try makeStore()
        let sync = AWSync(store: store, clientName: "lockin-test", bucketPrefix: "lockin-test-sessions")
        let project = try await store.createProject(name: "Dup Project", color: "#E5484D")
        let task = try await store.createTask(projectId: project.id!, name: "dedupe")
        let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
        _ = try await store.stopSession(id: session.id!)

        let bucketId = try await sync.currentBucketId()
        addTeardownBlock { await sync.deleteOwnBucket(bucketId: bucketId) }

        await sync.syncPending()
        // Force a re-sync by clearing the synced flag and posting again.
        try await store.writer.write { db in
            try db.execute(sql: "UPDATE session SET synced = 0 WHERE id = ?", arguments: [session.id!])
        }
        await sync.syncPending()

        let events = try await sync.fetchEvents(bucketId: bucketId)
        let matches = events.filter { event in
            guard let data = event["data"] as? [String: Any] else { return false }
            return (data["lockin_id"] as? Int).map { Int64($0) } == session.id
        }
        XCTAssertEqual(matches.count, 1, "Re-sync should dedupe on lockin_id")
    }
}
