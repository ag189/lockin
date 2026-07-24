import Foundation
import GRDB
import os

/// SQLite persistence — the single source of truth. Every session is written here first and
/// synchronously committed before ActivityWatch is ever contacted. All access goes through
/// GRDB's `DatabaseQueue`, which confines database work to its own serial queue off the main thread.
final class Store {
    let writer: DatabaseWriter
    private static let log = Logger(subsystem: "com.lockin.app", category: "store")

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lockin", isDirectory: true)
            .appendingPathComponent("lockin.sqlite", isDirectory: false)
    }

    init(url: URL = Store.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        writer = try DatabaseQueue(path: url.path, configuration: config)
        try Store.migrator.migrate(writer)
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE project (
                    id          INTEGER PRIMARY KEY,
                    name        TEXT NOT NULL UNIQUE,
                    client      TEXT,
                    color       TEXT NOT NULL,
                    archived    INTEGER NOT NULL DEFAULT 0,
                    created_at  TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE task (
                    id            INTEGER PRIMARY KEY,
                    project_id    INTEGER NOT NULL REFERENCES project(id),
                    name          TEXT NOT NULL,
                    estimate_min  INTEGER,
                    status        TEXT NOT NULL DEFAULT 'open',
                    created_at    TEXT NOT NULL,
                    completed_at  TEXT,
                    UNIQUE(project_id, name)
                );
                """)

            try db.execute(sql: """
                CREATE TABLE session (
                    id           INTEGER PRIMARY KEY,
                    task_id      INTEGER NOT NULL REFERENCES task(id),
                    started_at   TEXT NOT NULL,
                    ended_at     TEXT,
                    kind         TEXT NOT NULL DEFAULT 'work',
                    target_min   INTEGER,
                    intent_note  TEXT,
                    synced       INTEGER NOT NULL DEFAULT 0,
                    created_at   TEXT NOT NULL
                );
                """)
            try db.execute(sql: "CREATE INDEX session_started ON session(started_at);")

            // Enforce "at most one running session" at the database layer. A partial unique
            // index on `ended_at IS NULL` would not work (NULLs are distinct in SQLite), so we
            // index a constant that only exists while the session is running.
            try db.execute(sql: """
                CREATE UNIQUE INDEX session_one_running
                ON session((CASE WHEN ended_at IS NULL THEN 1 END));
                """)

            try db.execute(sql: """
                CREATE TABLE output (
                    id          INTEGER PRIMARY KEY,
                    task_id     INTEGER NOT NULL REFERENCES task(id),
                    session_id  INTEGER REFERENCES session(id),
                    logged_at   TEXT NOT NULL,
                    text        TEXT NOT NULL
                );
                """)
        }

        return migrator
    }

    // MARK: - Projects

    func project(named name: String) async throws -> Project? {
        try await writer.read { db in
            try Project.filter(Project.Columns.name == name).fetchOne(db)
        }
    }

    func allProjects(includeArchived: Bool = false) async throws -> [Project] {
        try await writer.read { db in
            var request = Project.all()
            if !includeArchived {
                request = request.filter(Project.Columns.archived == false)
            }
            return try request.order(Project.Columns.name).fetchAll(db)
        }
    }

    /// Colors already assigned, most-recent-first, so palette assignment can avoid repeats.
    func recentProjectColors(limit: Int = 8) async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT color FROM project ORDER BY id DESC LIMIT ?
                """, arguments: [limit])
        }
    }

    @discardableResult
    func createProject(name: String, color: String, client: String? = nil) async throws -> Project {
        try await writer.write { db in
            var project = Project(
                id: nil,
                name: name,
                client: client,
                color: color,
                archived: false,
                createdAt: DateISO.now()
            )
            try project.insert(db)
            return project
        }
    }

    // MARK: - Tasks

    func task(projectId: Int64, name: String) async throws -> TaskItem? {
        try await writer.read { db in
            try TaskItem
                .filter(TaskItem.Columns.projectId == projectId && TaskItem.Columns.name == name)
                .fetchOne(db)
        }
    }

    @discardableResult
    func createTask(projectId: Int64, name: String) async throws -> TaskItem {
        try await writer.write { db in
            var task = TaskItem(
                id: nil,
                projectId: projectId,
                name: name,
                estimateMin: nil,
                status: TaskStatus.open.rawValue,
                createdAt: DateISO.now(),
                completedAt: nil
            )
            try task.insert(db)
            return task
        }
    }

    func taskDetail(taskId: Int64) async throws -> TaskDetail? {
        try await writer.read { db in
            try Store.fetchTaskDetail(db, taskId: taskId)
        }
    }

    private static func fetchTaskDetail(_ db: Database, taskId: Int64) throws -> TaskDetail? {
        let row = try Row.fetchOne(db, sql: """
            SELECT t.id AS task_id, t.name AS task_name,
                   p.id AS project_id, p.name AS project_name, p.color AS color
            FROM task t JOIN project p ON p.id = t.project_id
            WHERE t.id = ?
            """, arguments: [taskId])
        guard let row else { return nil }
        return TaskDetail(
            taskId: row["task_id"],
            taskName: row["task_name"],
            projectId: row["project_id"],
            projectName: row["project_name"],
            colorHex: row["color"]
        )
    }

    /// All non-archived tasks with their project, for fuzzy search in memory.
    func searchableTasks() async throws -> [TaskDetail] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id AS task_id, t.name AS task_name,
                       p.id AS project_id, p.name AS project_name, p.color AS color
                FROM task t JOIN project p ON p.id = t.project_id
                WHERE p.archived = 0 AND t.status = 'open'
                ORDER BY t.id DESC
                """)
            return rows.map {
                TaskDetail(
                    taskId: $0["task_id"],
                    taskName: $0["task_name"],
                    projectId: $0["project_id"],
                    projectName: $0["project_name"],
                    colorHex: $0["color"]
                )
            }
        }
    }

    /// The N most recently worked tasks, each with today's tracked seconds.
    func recentTasks(limit: Int = 5) async throws -> [TaskDetail] {
        let startOfDay = DateISO.string(from: Calendar.current.startOfDay(for: Date()))
        return try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id AS task_id, t.name AS task_name,
                       p.id AS project_id, p.name AS project_name, p.color AS color,
                       MAX(s.started_at) AS last_started
                FROM session s
                JOIN task t ON t.id = s.task_id
                JOIN project p ON p.id = t.project_id
                GROUP BY t.id
                ORDER BY last_started DESC
                LIMIT ?
                """, arguments: [limit])

            return try rows.map { row -> TaskDetail in
                let taskId: Int64 = row["task_id"]
                let today = try Store.todaySeconds(db, taskId: taskId, sinceISO: startOfDay)
                return TaskDetail(
                    taskId: taskId,
                    taskName: row["task_name"],
                    projectId: row["project_id"],
                    projectName: row["project_name"],
                    colorHex: row["color"],
                    todaySeconds: today
                )
            }
        }
    }

    /// Every task worked today (local day), aggregated with today's total seconds, most recent
    /// activity first. Includes the currently running task (its time counted up to now).
    ///
    /// `clearedAt` implements the non-destructive "Clear This List" control: when set, the floor
    /// becomes `max(startOfDay, clearedAt)`, so only sessions started after the user cleared show.
    /// No data is deleted; the rollup uses the same floor so visible totals match.
    func todayTasks(clearedAt: Date? = nil) async throws -> [TaskDetail] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let floor = max(startOfDay, clearedAt ?? startOfDay)
        let floorISO = DateISO.string(from: floor)
        return try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id AS task_id, t.name AS task_name,
                       p.id AS project_id, p.name AS project_name, p.color AS color,
                       MAX(s.started_at) AS last_started
                FROM session s
                JOIN task t ON t.id = s.task_id
                JOIN project p ON p.id = t.project_id
                WHERE s.started_at >= ?
                GROUP BY t.id
                ORDER BY last_started DESC
                """, arguments: [floorISO])

            return try rows.map { row -> TaskDetail in
                let taskId: Int64 = row["task_id"]
                let today = try Store.todaySeconds(db, taskId: taskId, sinceISO: floorISO)
                return TaskDetail(
                    taskId: taskId,
                    taskName: row["task_name"],
                    projectId: row["project_id"],
                    projectName: row["project_name"],
                    colorHex: row["color"],
                    todaySeconds: today
                )
            }
        }
    }

    /// Sum of completed-session durations for a task since the given ISO instant.
    private static func todaySeconds(_ db: Database, taskId: Int64, sinceISO: String) throws -> Int {
        let sessions = try Session
            .filter(Session.Columns.taskId == taskId)
            .filter(Session.Columns.startedAt >= sinceISO)
            .fetchAll(db)
        var total = 0.0
        for s in sessions {
            guard let start = DateISO.date(from: s.startedAt) else { continue }
            let end = s.endedAt.flatMap { DateISO.date(from: $0) } ?? Date()
            total += end.timeIntervalSince(start)
        }
        return Int(total)
    }
    
    /// Sum of completed-session durations for a task before the given ISO instant.
    func historicalSeconds(taskId: Int64, before: Date) async throws -> Int {
        let beforeISO = DateISO.string(from: before)
        return try await writer.read { db in
            let sessions = try Session
                .filter(Session.Columns.taskId == taskId)
                .filter(Session.Columns.startedAt < beforeISO)
                .fetchAll(db)
            var total = 0.0
            for s in sessions {
                guard let start = DateISO.date(from: s.startedAt) else { continue }
                // Only count sessions that have ended, or cap at 'before' if somehow left dangling
                let end = s.endedAt.flatMap { DateISO.date(from: $0) } ?? before
                let duration = end.timeIntervalSince(start)
                if duration > 0 {
                    total += duration
                }
            }
            return Int(total)
        }
    }

    // MARK: - Sessions

    func runningSession() async throws -> Session? {
        try await writer.read { db in
            try Session.filter(Session.Columns.endedAt == nil).fetchOne(db)
        }
    }

    /// Starts a session. Fails if one is already running (enforced by unique index + guard).
    @discardableResult
    func startSession(taskId: Int64, kind: SessionKind, targetMin: Int?) async throws -> Session {
        try await writer.write { db in
            if try Session.filter(Session.Columns.endedAt == nil).fetchCount(db) > 0 {
                throw StoreError.sessionAlreadyRunning
            }
            let now = DateISO.now()
            var session = Session(
                id: nil,
                taskId: taskId,
                startedAt: now,
                endedAt: nil,
                kind: kind.rawValue,
                targetMin: targetMin,
                intentNote: nil,
                synced: false,
                createdAt: now
            )
            try session.insert(db)
            return session
        }
    }

    @discardableResult
    func stopSession(id: Int64, endedAt: Date = Date()) async throws -> Session? {
        try await writer.write { db in
            guard var session = try Session.fetchOne(db, key: id) else { return nil }
            guard session.endedAt == nil else { return session }
            session.endedAt = DateISO.string(from: endedAt)
            session.synced = false
            try session.update(db)
            return session
        }
    }

    func addOutput(taskId: Int64, sessionId: Int64?, text: String) async throws {
        try await writer.write { db in
            var output = Output(
                id: nil,
                taskId: taskId,
                sessionId: sessionId,
                loggedAt: DateISO.now(),
                text: text
            )
            try output.insert(db)
        }
    }

    // MARK: - Sync bookkeeping

    func unsyncedCompletedSessions() async throws -> [Session] {
        try await writer.read { db in
            try Session
                .filter(Session.Columns.endedAt != nil)
                .filter(Session.Columns.synced == false)
                .order(Session.Columns.startedAt)
                .fetchAll(db)
        }
    }

    func unsyncedCount() async throws -> Int {
        try await writer.read { db in
            try Session
                .filter(Session.Columns.endedAt != nil)
                .filter(Session.Columns.synced == false)
                .fetchCount(db)
        }
    }

    func markSynced(sessionId: Int64) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE session SET synced = 1 WHERE id = ?", arguments: [sessionId])
        }
    }

    /// Everything AWSync needs to build an event payload for a completed session.
    func syncPayload(sessionId: Int64) async throws -> SessionSyncPayload? {
        try await writer.read { db in
            guard let session = try Session.fetchOne(db, key: sessionId),
                  let detail = try Store.fetchTaskDetail(db, taskId: session.taskId) else {
                return nil
            }
            let output = try Output
                .filter(Column("session_id") == sessionId)
                .order(sql: "logged_at DESC")
                .fetchOne(db)
            return SessionSyncPayload(session: session, task: detail, outputText: output?.text)
        }
    }
}

enum StoreError: Error {
    case sessionAlreadyRunning
}

extension StoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .sessionAlreadyRunning:
            return "A session is already running."
        }
    }
}

struct SessionSyncPayload {
    var session: Session
    var task: TaskDetail
    var outputText: String?
}
