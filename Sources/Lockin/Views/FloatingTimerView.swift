import SwiftUI

struct FloatingTimerView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            if let active = model.active {
                VStack(alignment: .leading, spacing: 12) {
                    // Line 1: Task name
                    Text(active.taskName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Line 2: Timer + Controls
                    HStack {
                        Text(clockText(active))
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .foregroundStyle(model.isPomodoroOverrun ? Color.orange : Color.primary)
                        
                        Spacer(minLength: 16)
                        
                        // Controls
                        HStack(spacing: 8) {
                            Button(action: {
                                if active.isPaused {
                                    model.resumeSession()
                                } else {
                                    model.pause()
                                }
                            }) {
                                Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.85))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Button(action: { model.stop(promptOutput: true) }) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.red.opacity(0.85))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { model.overlayVisible = false }) {
                                Image(systemName: "minus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)
                                    .padding(8)
                                    .background(Color.primary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Line 3: Silence Button (only if alarm active)
                    if model.alarmActive {
                        Button(action: { model.silenceAlarm() }) {
                            HStack {
                                Image(systemName: "speaker.slash.fill")
                                Text("Silence Alarm")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Line 4: Pomodoro Presets
                    HStack(spacing: 8) {
                        ForEach([25, 40, 60], id: \.self) { min in
                            Button(action: {
                                model.startPomodoro(minutes: min, query: active.taskName)
                            }) {
                                Text("\(min)m")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                .padding(8)
            } else {
                Color.clear
            }
        }
        // Width constrained, but height is flexible to fit contents
        .frame(width: 260)
    }
    
    private func clockText(_ active: ActiveSession) -> String {
        if active.kind == .pomodoro, let target = active.targetMin, !model.isPomodoroOverrun {
            return TimeFormatting.clock(Double(target * 60) - model.elapsed)
        }
        if let target = active.pomodoroTargetMin, let start = active.pomodoroStartedAt, !model.isPomodoroOverrun {
            let pomodoroElapsed = active.accumulatedPomodoroElapsed + (active.isPaused ? 0 : Date().timeIntervalSince(start))
            let remaining = max(0, Double(target * 60) - pomodoroElapsed)
            return TimeFormatting.clock(remaining)
        }
        return TimeFormatting.clock(model.elapsed)
    }
}
