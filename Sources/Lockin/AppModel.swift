import AppKit
import Combine
import Foundation
import SwiftUI
import os

/// A running session, held in memory for the label and the running view. Elapsed time is always
/// derived from `startedAt`, never accumulated, so a missed tick or a sleep never drifts.
struct ActiveSession: Equatable {
    var id: Int64
    var taskId: Int64
    var projectName: String
    var taskName: String
    var colorHex: String
    var startedAt: Date
    var kind: SessionKind
    var targetMin: Int?
}

/// What the popover is currently showing.
enum PopoverScreen: Equatable {
    case main                                   // idle or running, decided by `active`
    case output(sessionId: Int64, taskId: Int64, label: String)
}

/// The single coordinator. Owns state, the tick timer, and the wiring to Store and AWSync.
@MainActor
final class AppModel: ObservableObject {
    // Published UI state
    @Published private(set) var active: ActiveSession?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var pendingSyncCount: Int = 0
    @Published var screen: PopoverScreen = .main
    @Published private(set) var today: [TaskDetail] = []
    @Published private(set) var searchResults: [TaskDetail] = []
    /// Bumping this token asks the search field to grab focus.
    @Published var focusSearchToken = UUID()
    /// User-visible error for the last Start attempt.
    @Published private(set) var startError: String?
    /// True while the pomodoro-complete alarm is looping and awaiting silence.
    @Published private(set) var alarmActive = false

    private let alarm = AlarmPlayer()

    // Pomodoro duration memory
    @AppStorage("pomodoroMinutes") var pomodoroMinutes: Int = 25

    /// Non-destructive "Clear This List" cutoff. The Today list shows only tasks worked after
    /// this instant. Persisted so it survives relaunch; naturally superseded at midnight.
    @Published private(set) var todayClearedAt: Date?

    let store: Store
    private let sync: AWSync
    private let log = Logger(subsystem: "com.lockin.app", category: "model")

    private var allTasks: [TaskDetail] = []
    private var tickTimer: Timer?
    private var retryTimer: Timer?
    private var dayRolloverTimer: Timer?
    private var isSuspended = false

    /// Requests the AppKit layer to present the popover (set by AppDelegate).
    var presentPopover: (() -> Void)?
    /// Ask the panel to resize after content changes.
    var repositionPopover: (() -> Void)?

    init(store: Store, sync: AWSync) {
        self.store = store
        self.sync = sync
        let stored = UserDefaults.standard.double(forKey: "todayClearedAt")
        if stored > 0 { self.todayClearedAt = Date(timeIntervalSince1970: stored) }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        await sync.setPendingCountHandler { count in
            Task { @MainActor [weak self] in self?.pendingSyncCount = count }
        }
        await resumeRunningSession()
        await reloadCatalog()
        await refreshRecent()
        registerPowerObservers()
        await sync.syncPending()
        startRetryTimer()
        scheduleMidnightRefresh()
    }

    private func resumeRunningSession() async {
        do {
            guard let session = try await store.runningSession(),
                  let id = session.id,
                  let detail = try await store.taskDetail(taskId: session.taskId),
                  let started = DateISO.date(from: session.startedAt) else { return }

            let resumed = ActiveSession(
                id: id,
                taskId: session.taskId,
                projectName: detail.projectName,
                taskName: detail.taskName,
                colorHex: detail.colorHex,
                startedAt: started,
                kind: SessionKind(rawValue: session.kind) ?? .work,
                targetMin: session.targetMin
            )

            // Long-running guard: over 12 hours, ask once rather than silently continue or close.
            if Date().timeIntervalSince(started) > 12 * 3600 {
                if shouldEndLongRunningSession() {
                    _ = try? await store.stopSession(id: id)
                    await sync.syncPending()
                    await refreshRecent()
                    return
                }
            }
            active = resumed
            startTicking()
        } catch {
            log.error("Resume failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldEndLongRunningSession() -> Bool {
        let alert = NSAlert()
        alert.messageText = "A session has been running over 12 hours"
        alert.informativeText = "End it now, or keep it running?"
        alert.addButton(withTitle: "End session")
        alert.addButton(withTitle: "Keep running")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Catalog + search

    private func reloadCatalog() async {
        allTasks = (try? await store.searchableTasks()) ?? []
    }

    /// Recomputes the current working-session list (today's tasks after any clear cutoff).
    func refreshRecent() async {
        today = (try? await store.todayTasks(clearedAt: todayClearedAt)) ?? []
    }

    /// Non-destructive clear: sets the cutoff to now so the Today list hides everything worked
    /// before this moment. No sessions or ActivityWatch events are deleted.
    func clearTodayList() {
        let now = Date()
        todayClearedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "todayClearedAt")
        Task { await refreshRecent() }
    }

    /// Starts a pomodoro (countdown + alarm) of the given length on the typed query or top hit.
    func startPomodoro(minutes: Int, query: String) {
        pomodoroMinutes = min(max(minutes, 1), 600)
        startFromQuery(query, asPomodoro: true)
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        let scored = allTasks.compactMap { task -> (TaskDetail, Int)? in
            let haystack = task.taskName
            guard let score = Self.fuzzyScore(needle: trimmed, haystack: haystack) else { return nil }
            return (task, score)
        }
        searchResults = scored
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0.0 }
    }

    /// Case-insensitive subsequence match; rewards contiguous runs and earlier matches.
    nonisolated static func fuzzyScore(needle: String, haystack: String) -> Int? {
        let n = Array(needle.lowercased())
        let h = Array(haystack.lowercased())
        var score = 0
        var hi = 0
        var lastMatch = -2
        for ch in n {
            var found = false
            while hi < h.count {
                if h[hi] == ch {
                    score += (hi == lastMatch + 1) ? 3 : 1
                    score += max(0, 10 - hi) // earlier is better
                    lastMatch = hi
                    hi += 1
                    found = true
                    break
                }
                hi += 1
            }
            if !found { return nil }
        }
        return score
    }

    // MARK: - Starting sessions

    func startExisting(_ task: TaskDetail, asPomodoro: Bool) {
        clearStartError()
        Task { await self.start(taskId: task.taskId, projectName: task.projectName, taskName: task.taskName, colorHex: task.colorHex, asPomodoro: asPomodoro) }
    }

    func startFromQuery(_ query: String, asPomodoro: Bool) {
        clearStartError()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            startError = "Type a task name first."
            focusSearch()
            return
        }
        if let top = self.searchResults.first {
            Task { await self.start(taskId: top.taskId, projectName: top.projectName, taskName: top.taskName, colorHex: top.colorHex, asPomodoro: asPomodoro) }
        } else {
            Task { await self.createAndStart(query: trimmed, asPomodoro: asPomodoro) }
        }
    }

    private func createAndStart(query: String, asPomodoro: Bool) async {
        do {
            let (projectName, taskName) = Self.parse(query: query, lastProject: lastProjectName())
            let project = try await resolveProject(named: projectName)
            let task: TaskItem
            if let existing = try await store.task(projectId: project.id!, name: taskName) {
                task = existing
            } else {
                task = try await store.createTask(projectId: project.id!, name: taskName)
            }
            await reloadCatalog()
            await start(taskId: task.id!, projectName: project.name, taskName: task.name, colorHex: project.color, asPomodoro: asPomodoro)
        } catch {
            let message = "Could not start: \(error.localizedDescription)"
            log.error("\(message, privacy: .public)")
            startError = message
        }
    }

    /// Hidden internal project that owns every task. Never shown in the UI.
    nonisolated static let defaultProjectName = "Inbox"

    /// Tasks are flat: the whole query is the task name, always filed under the hidden project.
    nonisolated static func parse(query: String, lastProject: String?) -> (project: String, task: String) {
        return (defaultProjectName, query.trimmingCharacters(in: .whitespaces))
    }

    var lastUsedProjectName: String? { lastProjectName() }

    private func resolveProject(named name: String) async throws -> Project {
        if let existing = try await store.project(named: name) {
            return existing
        }
        let recentColors = try await store.recentProjectColors()
        let color = Palette.nextColor(recentlyUsed: recentColors)
        return try await store.createProject(name: name, color: color)
    }

    private func start(taskId: Int64, projectName: String, taskName: String, colorHex: String, asPomodoro: Bool) async {
        do {
            // If something is running, stop it first (a start implies a switch, no output prompt).
            if let current = active {
                _ = try? await store.stopSession(id: current.id)
                active = nil
                await sync.syncPending()
            } else if let running = try? await store.runningSession(), let id = running.id {
                // Defensive: if the in-memory flag and DB disagree, end the DB session before starting.
                _ = try? await store.stopSession(id: id)
                await sync.syncPending()
            }
            silenceAlarm()
            let kind: SessionKind = asPomodoro ? .pomodoro : .work
            let target = asPomodoro ? pomodoroMinutes : nil
            let session = try await store.startSession(taskId: taskId, kind: kind, targetMin: target)
            guard let id = session.id, let started = DateISO.date(from: session.startedAt) else {
                startError = "Could not start: invalid session data."
                return
            }
            setLastProject(projectName)
            // Prime elapsed so the first menu-bar render shows the correct time immediately.
            elapsed = Date().timeIntervalSince(started)
            active = ActiveSession(
                id: id,
                taskId: taskId,
                projectName: projectName,
                taskName: taskName,
                colorHex: colorHex,
                startedAt: started,
                kind: kind,
                targetMin: target
            )
            notifiedOverrun = false
            screen = .main
            startTicking()
            await refreshRecent()
            repositionPopover?()
        } catch {
            let message = "Could not start: \(error.localizedDescription)"
            log.error("\(message, privacy: .public)")
            startError = message
        }
    }

    // MARK: - Stop / switch / output

    /// Stops the running session. `promptOutput` distinguishes a deliberate Stop from a Switch.
    func stop(promptOutput: Bool) {
        guard let current = active else { return }
        silenceAlarm()
        stopTicking()
        active = nil
        elapsed = 0
        Task {
            _ = try? await store.stopSession(id: current.id)
            if promptOutput {
                screen = .output(sessionId: current.id, taskId: current.taskId, label: current.taskName)
            } else {
                screen = .main
            }
            await sync.syncPending()
            await refreshRecent()
        }
    }

    func saveOutput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case let .output(sessionId, taskId, _) = screen else {
            screen = .main
            return
        }
        screen = .main
        guard !trimmed.isEmpty else { return }
        Task {
            try? await store.addOutput(taskId: taskId, sessionId: sessionId, text: trimmed)
            await sync.syncPending() // re-sync so the note lands on the event
        }
    }

    func skipOutput() {
        screen = .main
    }

    // MARK: - Hotkey handlers

    func handleStartStopHotkey() {
        if active != nil {
            stop(promptOutput: true)
            presentPopover?()
        } else {
            presentPopover?()
            focusSearch()
        }
    }

    func handleOpenPopoverHotkey() {
        presentPopover?()
        if active == nil { focusSearch() }
    }

    func focusSearch() {
        clearStartError()
        focusSearchToken = UUID()
    }

    func clearStartError() {
        startError = nil
    }

    // MARK: - Ticking

    private var notifiedOverrun = false

    private func startTicking() {
        stopTicking()
        guard active != nil else { return }
        recomputeElapsed()
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.recomputeElapsed() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func recomputeElapsed() {
        guard let active else {
            elapsed = 0
            return
        }
        elapsed = Date().timeIntervalSince(active.startedAt)

        if active.kind == .pomodoro, let target = active.targetMin, !notifiedOverrun,
           elapsed >= Double(target * 60) {
            notifiedOverrun = true
            startAlarm(for: active)
        }
    }

    // MARK: - Alarm

    /// Fired when a pomodoro hits 0: loop the alarm, pop the popover, and keep the timer running.
    private func startAlarm(for session: ActiveSession) {
        alarm.start()
        alarmActive = true
        presentPopover?()
    }

    /// Stops the looping sound. The session keeps running (overrun); only the noise stops.
    func silenceAlarm() {
        alarm.stop()
        alarmActive = false
    }

    var isPomodoroOverrun: Bool {
        guard let active, active.kind == .pomodoro, let target = active.targetMin else { return false }
        return elapsed >= Double(target * 60)
    }

    // MARK: - Power / lock observers

    private func registerPowerObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(suspend), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resume), name: NSWorkspace.didWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(suspend), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(resume), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func suspend() {
        isSuspended = true
        stopTicking()
    }

    @objc private func resume() {
        guard isSuspended else { return }
        isSuspended = false
        if active != nil { startTicking() }
        // Waking may cross a day boundary; recompute today and re-arm the midnight timer.
        Task { await refreshRecent() }
        scheduleMidnightRefresh()
    }

    // MARK: - Retry timer

    private func startRetryTimer() {
        retryTimer?.invalidate()
        let timer = Timer(timeInterval: 600, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.pendingSyncCount > 0 {
                    await self.sync.syncPending()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    // MARK: - Day rollover

    /// Fires once at the next local midnight to recompute `today` so the list resets to a clean
    /// slate at the day boundary even while the app stays open. Reschedules itself for the day after.
    private func scheduleMidnightRefresh() {
        dayRolloverTimer?.invalidate()
        let calendar = Calendar.current
        let nextMidnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(24 * 3600)

        let timer = Timer(fire: nextMidnight, interval: 0, repeats: false) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshRecent()
                self.scheduleMidnightRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dayRolloverTimer = timer
    }

    // MARK: - Last project memory

    private func lastProjectName() -> String? {
        UserDefaults.standard.string(forKey: "lastProjectName")
    }

    private func setLastProject(_ name: String) {
        UserDefaults.standard.set(name, forKey: "lastProjectName")
    }
}

/// Loops a system alarm sound until stopped. Uses a bundled system sound so no asset is needed.
@MainActor
final class AlarmPlayer {
    private var sound: NSSound?

    func start() {
        guard sound == nil else { return }
        let s = NSSound(named: NSSound.Name("Sosumi")) ?? NSSound(named: NSSound.Name("Ping"))
        s?.loops = true
        s?.play()
        sound = s
    }

    func stop() {
        sound?.stop()
        sound = nil
    }
}
