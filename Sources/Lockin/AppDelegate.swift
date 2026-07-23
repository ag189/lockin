import AppKit
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var sync: AWSync!
    private var model: AppModel!
    private var statusController: StatusItemController!
    private var panelController: PanelController!
    private var floatingController: FloatingTimerController!
    private var welcomeWindow: NSWindow?

    private let log = Logger(subsystem: "com.lockin.app", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            store = try Store()
        } catch {
            presentFatal("Lockin could not open its database.", detail: error.localizedDescription)
            return
        }

        sync = AWSync(store: store)
        model = AppModel(store: store, sync: sync)

        statusController = StatusItemController(model: model)
        panelController = PanelController(
            rootView: PopoverRootView().environmentObject(model),
            statusButton: statusController.button
        )
        floatingController = FloatingTimerController(model: model)

        statusController.onClick = { [weak self] in
            self?.panelController.toggle()
        }
        model.presentPopover = { [weak self] in
            self?.panelController.show()
        }
        model.repositionPopover = { [weak self] in
            self?.panelController.reposition()
        }
        panelController.onWillShow = { [weak self] in
            Task { await self?.model.refreshRecent() }
        }

        HotkeyCenter.shared.setHandler(for: .startStop) { [weak self] in
            self?.model.handleStartStopHotkey()
        }
        HotkeyCenter.shared.setHandler(for: .openPopover) { [weak self] in
            self?.model.handleOpenPopoverHotkey()
        }
        HotkeyCenter.shared.registerAll()

        Task { await model.bootstrap() }

        maybeShowWelcome()
    }

    // MARK: - First run

    private func maybeShowWelcome() {
        guard !UserDefaults.standard.bool(forKey: "didOnboard") else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: WelcomeView { [weak self] in
            UserDefaults.standard.set(true, forKey: "didOnboard")
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        })
        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func presentFatal(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}
