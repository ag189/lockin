import Foundation

enum SessionKind: String {
    case work
    case pomodoro
}

struct ActiveSession: Equatable {
    var id: Int64
    var taskId: Int64
    var projectName: String
    var taskName: String
    var colorHex: String
    var startedAt: Date
    var kind: SessionKind
    var targetMin: Int?
    var pomodoroTargetMin: Int?
    var pomodoroStartedAt: Date?
    
    var isPaused: Bool = false
    var accumulatedElapsed: TimeInterval = 0
    var accumulatedPomodoroElapsed: TimeInterval = 0
    
    var historicalSeconds: TimeInterval = 0
}

let active = ActiveSession(
    id: 1,
    taskId: 1,
    projectName: "P",
    taskName: "T",
    colorHex: "#FFF",
    startedAt: Date(),
    kind: .work,
    targetMin: nil,
    historicalSeconds: 9999
)

print("historical: \(active.historicalSeconds)")
print("accumulatedPomo: \(active.accumulatedPomodoroElapsed)")
