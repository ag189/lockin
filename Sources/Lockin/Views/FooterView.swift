import SwiftUI

struct FooterView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if model.pendingSyncCount > 0 {
                    Text("\(model.pendingSyncCount) pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Lockin")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { showSettings.toggle() }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if showSettings {
                settings
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text(HotkeyID.startStop.title)
                    .font(.system(size: 12))
                Spacer()
                ShortcutRecorder(id: .startStop)
                    .fixedSize()
            }
            HStack {
                Text(HotkeyID.openPopover.title)
                    .font(.system(size: 12))
                Spacer()
                ShortcutRecorder(id: .openPopover)
                    .fixedSize()
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                    launchAtLogin = LoginItem.isEnabled
                }
            Divider()
            Button("Quit Lockin") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}
