import SwiftUI

struct IdleView: View {
    @EnvironmentObject var model: AppModel
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool
    @State private var customText: String = ""
    @State private var startHint: String?

    private let presetMinutes = [25, 40, 60, 90]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var hasTaskName: Bool { !trimmedQuery.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start a task")
                .font(.headline)

            searchField

            if !model.searchResults.isEmpty {
                resultsList
            } else if hasTaskName {
                createHint
            } else {
                taskList
            }

            if let startHint {
                Text(startHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else if let error = model.startError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Divider()
            pomodoroRow
        }
        .onAppear { focusSoon() }
        .onChange(of: model.focusSearchToken) { _, _ in focusSoon() }
        .onChange(of: model.active) { _, active in
            if active != nil {
                query = ""
                startHint = nil
                model.clearStartError()
            }
        }
    }

    private var searchField: some View {
        TextField("What are you working on?", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($searchFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: query) { _, newValue in
                startHint = nil
                model.clearStartError()
                model.search(newValue)
            }
            .onSubmit {
                guard hasTaskName else {
                    startHint = "Type a task name first."
                    return
                }
                model.startFromQuery(query, asPomodoro: false)
            }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.searchResults) { task in
                Button {
                    model.startExisting(task, asPomodoro: false)
                    query = ""
                } label: {
                    taskRow(task, trailing: nil, running: isRunning(task))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var createHint: some View {
        let label = "Create \"\(trimmedQuery)\""
        return Button {
            model.startFromQuery(query, asPomodoro: false)
            query = ""
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text(label)
                    .lineLimit(1)
                Spacer()
                Text("Return")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var taskList: some View {
        let items = model.today
        return VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                HStack {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.clearTodayList()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                ForEach(items) { task in
                    Button {
                        model.startExisting(task, asPomodoro: false)
                    } label: {
                        taskRow(task, trailing: TimeFormatting.compact(seconds: task.todaySeconds), running: isRunning(task))
                    }
                    .buttonStyle(.plain)
                }
                if model.today.count > 1 {
                    Text("total \(TimeFormatting.compact(seconds: model.today.reduce(0) { $0 + $1.todaySeconds }))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No tasks yet. Type a task name to start, or pick a pomodoro preset below.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isRunning(_ task: TaskDetail) -> Bool {
        model.active?.taskId == task.taskId
    }

    private func taskRow(_ task: TaskDetail, trailing: String?, running: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: running ? Palette.runningColor : Palette.idleColor))
                .frame(width: 8, height: 8)
            Text(task.taskName)
                .font(.system(size: 13))
                .lineLimit(1)
            if running {
                Text("running")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: Palette.runningColor))
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var pomodoroRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                ForEach(presetMinutes, id: \.self) { minutes in
                    Button {
                        startPomodoro(minutes: minutes)
                    } label: {
                        Text("\(minutes)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                TextField("min", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onChange(of: customText) { _, value in
                        let digits = value.filter(\.isNumber)
                        if digits != value { customText = digits }
                    }
                    .onSubmit { startCustomPomodoro() }
                Text("min")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Start", action: startCustomPomodoro)
                    .controlSize(.small)
            }

            Text("Preset buttons start a countdown pomodoro on the typed task (clicking a task is an open-ended stopwatch).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startPomodoro(minutes: Int) {
        guard hasTaskName else {
            startHint = "Type a task name above before starting the timer."
            searchFocused = true
            return
        }
        startHint = nil
        model.startPomodoro(minutes: minutes, query: query)
    }

    private func startCustomPomodoro() {
        let digits = customText.filter(\.isNumber)
        guard let n = Int(digits), n > 0 else {
            startHint = "Enter a number of minutes (e.g. 12)."
            return
        }
        startPomodoro(minutes: n)
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            searchFocused = true
        }
    }
}
