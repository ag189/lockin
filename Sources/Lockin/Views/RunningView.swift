import SwiftUI

/// The pinned "what's running now" header. Shown at the top of every main screen so the current
/// timer is always visible, even while searching to switch to another task.
struct RunningHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let active = model.active {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(hex: Palette.runningColor))
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(active.taskName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(subtitle(active))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(clockText(active))
                        .font(.system(size: 22, weight: .medium).monospacedDigit())
                        .foregroundStyle(model.isPomodoroOverrun ? Color.orange : Color.primary)
                }

                HStack(spacing: 8) {
                    Button("Stop") { model.stop(promptOutput: true) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    if model.alarmActive {
                        Button("Silence") { model.silenceAlarm() }
                            .controlSize(.small)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: Palette.runningColor).opacity(0.10))
        }
    }

    private func subtitle(_ active: ActiveSession) -> String {
        var parts = ["started \(started(active))"]
        if active.kind == .pomodoro, let target = active.targetMin {
            parts.insert(model.isPomodoroOverrun ? "\(target)m pomodoro · over" : "\(target)m pomodoro", at: 0)
        }
        return parts.joined(separator: " · ")
    }

    private func clockText(_ active: ActiveSession) -> String {
        if active.kind == .pomodoro, let target = active.targetMin, !model.isPomodoroOverrun {
            return TimeFormatting.clock(Double(target * 60) - model.elapsed)
        }
        return TimeFormatting.clock(model.elapsed)
    }

    private func started(_ active: ActiveSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: active.startedAt)
    }
}
