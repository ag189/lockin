import AppKit
import SwiftUI

/// Presents and positions the popover panel beneath the status item, and manages focus.
///
/// The popover stays open while the user interacts inside it; it closes only on an explicit
/// outside click, Escape, or a toggle from the status item. This prevents SwiftUI button
/// actions from being torn down before they can commit a session (BUG-1).
@MainActor
final class PanelController {
    private let panel: PopoverPanel
    private let hosting: NSHostingView<AnyView>
    private weak var statusButton: NSStatusBarButton?

    private var clickMonitor: Any?
    private var keyMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init<Content: View>(rootView: Content, statusButton: NSStatusBarButton?) {
        self.statusButton = statusButton
        hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.translatesAutoresizingMaskIntoConstraints = true

        panel = PopoverPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200))
        panel.contentView = hosting
        panel.onClose = { [weak self] in
            self?.hide()
        }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        reposition()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startOutsideClickMonitoring()
    }

    func hide() {
        stopOutsideClickMonitoring()
        panel.orderOut(nil)
    }

    func reposition() {
        hosting.layoutSubtreeIfNeeded()
        let contentSize = hosting.fittingSize
        let width = max(320, contentSize.width)
        let height = max(120, min(contentSize.height, 520))
        panel.setContentSize(NSSize(width: width, height: height))

        guard let button = statusButton, let buttonWindow = button.window else {
            panel.center()
            return
        }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        var origin = NSPoint(
            x: screenRect.midX - width / 2,
            y: screenRect.minY - height - 6
        )

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - Outside click / Escape dismissal

    private func startOutsideClickMonitoring() {
        guard clickMonitor == nil && keyMonitor == nil else { return }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            let location = NSEvent.mouseLocation

            // Click inside the panel itself: keep it open.
            if self.panel.frame.contains(location) { return }

            // Click on the status item button: let the status item toggle handle it.
            if let button = self.statusButton, let window = button.window {
                let buttonRect = button.convert(button.bounds, to: nil)
                let screenRect = window.convertToScreen(buttonRect)
                if screenRect.contains(location) { return }
            }

            self.hide()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.keyCode == 53 else { return event }
            // Let ShortcutRecorder cancel recording with Escape instead of closing.
            if let button = self.panel.firstResponder as? RecorderButton, button.isRecording { return event }
            self.hide()
            return nil
        }
    }

    private func stopOutsideClickMonitoring() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
