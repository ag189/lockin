import XCTest
@testable import Lockin

final class StoreTests: XCTestCase {
    private func makeStore() throws -> Store {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lockin-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("db.sqlite")
        return try Store(url: url)
    }

    func testCreateProjectAndTask() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "AKA project", color: "#0091FF")
        XCTAssertNotNil(project.id)
        let task = try await store.createTask(projectId: project.id!, name: "synthesis pass")
        XCTAssertNotNil(task.id)

        let detail = try await store.taskDetail(taskId: task.id!)
        XCTAssertEqual(detail?.projectName, "AKA project")
        XCTAssertEqual(detail?.taskName, "synthesis pass")
        XCTAssertEqual(detail?.colorHex, "#0091FF")
    }

    func testSingleRunningInvariant() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "P", color: "#0091FF")
        let task = try await store.createTask(projectId: project.id!, name: "T")

        _ = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
        do {
            _ = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
            XCTFail("Expected a second concurrent session to fail")
        } catch {
            // expected
        }
        let running = try await store.runningSession()
        XCTAssertNotNil(running)
        XCTAssertNil(running?.endedAt)
    }

    func testStopMarksUnsyncedAndEnds() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "P", color: "#0091FF")
        let task = try await store.createTask(projectId: project.id!, name: "T")
        let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)

        let stopped = try await store.stopSession(id: session.id!)
        XCTAssertNotNil(stopped?.endedAt)
        XCTAssertEqual(stopped?.synced, false)
        XCTAssertNil(try await store.runningSession())

        let unsynced = try await store.unsyncedCompletedSessions()
        XCTAssertEqual(unsynced.count, 1)

        // After starting a new session the invariant holds again.
        _ = try await store.startSession(taskId: task.id!, kind: .pomodoro, targetMin: 25)
        XCTAssertNotNil(try await store.runningSession())
    }

    func testRecentTasksTodaySeconds() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "P", color: "#0091FF")
        let task = try await store.createTask(projectId: project.id!, name: "T")
        let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
        // End ~2 minutes after start by faking the end time.
        let start = DateISO.date(from: session.startedAt)!
        _ = try await store.stopSession(id: session.id!, endedAt: start.addingTimeInterval(120))

        let recent = try await store.recentTasks(limit: 5)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.taskName, "T")
        XCTAssertGreaterThanOrEqual(recent.first?.todaySeconds ?? 0, 120)
    }

    func testTodayTasksClearedAtCutoff() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "P", color: "#0091FF")
        let task = try await store.createTask(projectId: project.id!, name: "T")
        let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
        let start = DateISO.date(from: session.startedAt)!
        _ = try await store.stopSession(id: session.id!, endedAt: start.addingTimeInterval(120))

        // No cutoff: the task appears with its tracked seconds.
        let all = try await store.todayTasks(clearedAt: nil)
        XCTAssertTrue(all.contains { $0.taskId == task.id! })
        XCTAssertGreaterThanOrEqual(all.first?.todaySeconds ?? 0, 120)

        // Cutoff in the future hides work that started before it.
        let cleared = try await store.todayTasks(clearedAt: Date().addingTimeInterval(60))
        XCTAssertFalse(cleared.contains { $0.taskId == task.id! })

        // Cutoff in the past keeps the work visible.
        let past = try await store.todayTasks(clearedAt: Date().addingTimeInterval(-3600))
        XCTAssertTrue(past.contains { $0.taskId == task.id! })
    }

    func testOutputAndSyncPayload() async throws {
        let store = try makeStore()
        let project = try await store.createProject(name: "AKA", color: "#0091FF")
        let task = try await store.createTask(projectId: project.id!, name: "spec")
        let session = try await store.startSession(taskId: task.id!, kind: .work, targetMin: nil)
        _ = try await store.stopSession(id: session.id!)
        try await store.addOutput(taskId: task.id!, sessionId: session.id!, text: "Wrote the section")

        let payload = try await store.syncPayload(sessionId: session.id!)
        XCTAssertEqual(payload?.task.projectName, "AKA")
        XCTAssertEqual(payload?.outputText, "Wrote the section")
    }
}
