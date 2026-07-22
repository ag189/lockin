import Foundation

/// A runtime verification pass, invoked with `Lockin --selftest`. It exists because the machine's
/// Command Line Tools toolchain has no XCTest, so `swift test` cannot run here. The XCTest suite in
/// Tests/ remains the real test surface for anyone with full Xcode; this mirrors its key checks and
/// exercises the actual Store and AWSync code against a temp database and a throwaway AW bucket.
enum SelfTest {
    static func run() async -> Bool {
        var failures: [String] = []

        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("  PASS  \(name)")
            } else {
                print("  FAIL  \(name)")
                failures.append(name)
            }
        }

        print("Lockin self-test")
        print("- pure logic")
        check("fuzzy match hit", AppModel.fuzzyScore(needle: "aka syn", haystack: "AKA — synthesis") != nil)
        check("fuzzy match miss", AppModel.fuzzyScore(needle: "zzzq", haystack: "AKA — synthesis") == nil)
        check("parse is flat, ignores slash", AppModel.parse(query: "P / T", lastProject: nil) == (AppModel.defaultProjectName, "P / T"))
        check("parse ignores last project", AppModel.parse(query: "t", lastProject: "L") == (AppModel.defaultProjectName, "t"))
        check("parse trims whitespace", AppModel.parse(query: "  hello  ", lastProject: nil) == (AppModel.defaultProjectName, "hello"))
        check("clock mm:ss", TimeFormatting.clock(24 * 60 + 17) == "24:17")
        check("clock h:mm", TimeFormatting.clock(3600 + 2 * 60) == "1:02")
        check("compact 45m", TimeFormatting.compact(seconds: 45 * 60) == "45m")
        check("palette avoids recent", !Palette.hexColors.prefix(2).map { $0 }.contains(Palette.nextColor(recentlyUsed: Array(Palette.hexColors.prefix(2)))))
        let inst = Date(timeIntervalSince1970: 1_800_000_000.5)
        check("DateISO round trip", abs((DateISO.date(from: DateISO.string(from: inst))?.timeIntervalSince1970 ?? 0) - inst.timeIntervalSince1970) < 0.01)

        do {
            print("- store")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lockin-selftest-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("db.sqlite")
            let store = try Store(url: url)

            let project = try await store.createProject(name: "AKA project", color: "#0091FF")
            let task = try await store.createTask(projectId: project.id!, name: "synthesis pass")
            let detail = try await store.taskDetail(taskId: task.id!)
            check("task detail joins project", detail?.projectName == "AKA project" && detail?.colorHex == "#0091FF")

            let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
            var invariantHeld = false
            do {
                _ = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
            } catch {
                invariantHeld = true
            }
            check("single running invariant", invariantHeld)

            let start = DateISO.date(from: session.startedAt)!
            let stopped = try await store.stopSession(id: session.id!, endedAt: start.addingTimeInterval(120))
            check("stop ends + unsyncs", stopped?.endedAt != nil && stopped?.synced == false)
            check("no running after stop", (try await store.runningSession()) == nil)

            try await store.addOutput(taskId: task.id!, sessionId: session.id!, text: "wrote it")
            let payload = try await store.syncPayload(sessionId: session.id!)
            check("sync payload has output", payload?.outputText == "wrote it")

            let recent = try await store.recentTasks(limit: 5)
            check("recent today seconds", (recent.first?.todaySeconds ?? 0) >= 120)
            check("unsynced count", (try await store.unsyncedCount()) == 1)

            // Clear This List: a future cutoff hides today's work; a past cutoff keeps it.
            let todayBefore = try await store.todayTasks(clearedAt: nil)
            check("today lists worked task", todayBefore.contains { $0.taskId == task.id! })
            let todayCleared = try await store.todayTasks(clearedAt: Date().addingTimeInterval(60))
            check("clearedAt hides earlier work", !todayCleared.contains { $0.taskId == task.id! })
            let todayPast = try await store.todayTasks(clearedAt: Date().addingTimeInterval(-3600))
            check("past clearedAt keeps work", todayPast.contains { $0.taskId == task.id! })
        } catch {
            check("store block threw: \(error)", false)
        }

        do {
            print("- appmodel start")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lockin-selftest-model-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("db.sqlite")
            let store = try Store(url: url)
            let sync = AWSync(store: store, clientName: "lockin-test", bucketPrefix: "lockin-test-sessions")
            let model = await MainActor.run {
                let m = AppModel(store: store, sync: sync)
                m.presentPopover = {}
                m.repositionPopover = {}
                return m
            }
            await MainActor.run { model.startFromQuery("wtest", asPomodoro: true) }
            try await Task.sleep(nanoseconds: 800_000_000)
            let running = try await store.runningSession()
            check("appmodel start wrote a session", running != nil)
            check("appmodel start set pomodoro target", running?.targetMin == 25)
        } catch {
            check("appmodel start block threw: \(error)", false)
        }

        // ActivityWatch integration, if the server is up. Throwaway bucket, cleaned up after.
        print("- activitywatch sync")
        if await serverIsUp() {
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lockin-selftest-aw-\(UUID().uuidString)", isDirectory: true)
                    .appendingPathComponent("db.sqlite")
                let store = try Store(url: url)
                let sync = AWSync(store: store, clientName: "lockin-test", bucketPrefix: "lockin-test-sessions")

                let project = try await store.createProject(name: "Selftest Project", color: "#12A594")
                let task = try await store.createTask(projectId: project.id!, name: "event check")
                let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
                let start = DateISO.date(from: session.startedAt)!
                _ = try await store.stopSession(id: session.id!, endedAt: start.addingTimeInterval(90))
                try await store.addOutput(taskId: task.id!, sessionId: session.id!, text: "verified")

                let bucketId = try await sync.currentBucketId()
                await sync.syncPending()
                check("session marked synced", (try await store.unsyncedCount()) == 0)

                let events = try await sync.fetchEvents(bucketId: bucketId)
                let match = events.first { ev in
                    guard let d = ev["data"] as? [String: Any] else { return false }
                    return (d["lockin_id"] as? Int).map { Int64($0) } == session.id
                }
                check("event present with lockin_id", match != nil)
                if let d = match?["data"] as? [String: Any] {
                    check("event data.app is task name", d["app"] as? String == "event check")
                    check("event data.title is task name", d["title"] as? String == "event check")
                    check("event data.output", d["output"] as? String == "verified")
                }
                if let dur = match?["duration"] as? Double {
                    check("event duration ~90s", abs(dur - 90) < 1.5)
                }

                // Re-sync should not duplicate.
                try await store.writer.write { db in
                    try db.execute(sql: "UPDATE session SET synced = 0 WHERE id = ?", arguments: [session.id!])
                }
                await sync.syncPending()
                let after = try await sync.fetchEvents(bucketId: bucketId)
                let count = after.filter { ev in
                    guard let d = ev["data"] as? [String: Any] else { return false }
                    return (d["lockin_id"] as? Int).map { Int64($0) } == session.id
                }.count
                check("re-sync dedupes on lockin_id", count == 1)

                await sync.deleteOwnBucket(bucketId: bucketId)
            } catch {
                check("aw block threw: \(error)", false)
            }
        } else {
            print("  SKIP  ActivityWatch not reachable on localhost:5600")
        }

        print(failures.isEmpty ? "\nAll checks passed." : "\n\(failures.count) check(s) failed.")
        return failures.isEmpty
    }

    private static func serverIsUp() async -> Bool {
        var req = URLRequest(url: URL(string: "http://localhost:5600/api/0/buckets/")!)
        req.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: req)) != nil
    }
}
