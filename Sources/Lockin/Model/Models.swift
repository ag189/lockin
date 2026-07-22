import Foundation
import GRDB

// MARK: - Enumerations

enum SessionKind: String, Codable {
    case work
    case pomodoro
    case breakTime = "break"
}

enum TaskStatus: String, Codable {
    case open
    case done
    case dropped
}

// MARK: - Project

struct Project: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var client: String?
    var color: String
    var archived: Bool
    var createdAt: String

    static let databaseTableName = "project"

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let client = Column("client")
        static let color = Column("color")
        static let archived = Column("archived")
        static let createdAt = Column("created_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case client
        case color
        case archived
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Task

struct TaskItem: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var projectId: Int64
    var name: String
    var estimateMin: Int?
    var status: String
    var createdAt: String
    var completedAt: String?

    static let databaseTableName = "task"

    enum Columns {
        static let id = Column("id")
        static let projectId = Column("project_id")
        static let name = Column("name")
        static let estimateMin = Column("estimate_min")
        static let status = Column("status")
        static let createdAt = Column("created_at")
        static let completedAt = Column("completed_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case name
        case estimateMin = "estimate_min"
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Session

struct Session: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var taskId: Int64
    var startedAt: String
    var endedAt: String?
    var kind: String
    var targetMin: Int?
    var intentNote: String?
    var synced: Bool
    var createdAt: String

    static let databaseTableName = "session"

    enum Columns {
        static let id = Column("id")
        static let taskId = Column("task_id")
        static let startedAt = Column("started_at")
        static let endedAt = Column("ended_at")
        static let kind = Column("kind")
        static let targetMin = Column("target_min")
        static let intentNote = Column("intent_note")
        static let synced = Column("synced")
        static let createdAt = Column("created_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case kind
        case targetMin = "target_min"
        case intentNote = "intent_note"
        case synced
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Output

struct Output: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var taskId: Int64
    var sessionId: Int64?
    var loggedAt: String
    var text: String

    static let databaseTableName = "output"

    enum CodingKeys: String, CodingKey {
        case id
        case taskId = "task_id"
        case sessionId = "session_id"
        case loggedAt = "logged_at"
        case text
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Derived view models

/// A task joined with its project, used across search, recent, and the running label.
struct TaskDetail: Hashable, Identifiable {
    var id: Int64 { taskId }
    var taskId: Int64
    var taskName: String
    var projectId: Int64
    var projectName: String
    var colorHex: String
    /// Seconds tracked against this task today (local day). Populated where relevant.
    var todaySeconds: Int = 0
}
