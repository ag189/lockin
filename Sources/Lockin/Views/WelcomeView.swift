import SwiftUI

/// The single first-run screen (§7): what it does, offer launch at login, done. No account, no key.
struct WelcomeView: View {
    var onDone: () -> Void
    @State private var launchAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 28))
                Text("Lockin")
                    .font(.system(size: 24, weight: .semibold))
            }

            Text("A menu bar timer for what you're working on. Start a task with a keystroke; it lives next to your clock and logs each session locally.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("It runs alongside ActivityWatch and adds a lane to its Timeline. Nothing leaves this machine, and it needs no system permissions.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .font(.system(size: 13))

            HStack {
                Spacer()
                Button("Get started") {
                    LoginItem.setEnabled(launchAtLogin)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
