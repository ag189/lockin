import AppKit
import SwiftUI
import Combine

@MainActor
final class FloatingTimerController {
    private var window: NSWindow?
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        setupWindow()
        observe()
    }

    private func setupWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Use statusBar level to ensure it hovers over absolutely everything (including full screen apps)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Allow dragging by clicking anywhere on the background
        panel.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: FloatingTimerView().environmentObject(model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 180)
        panel.contentView = hostingView
        
        positionWindow(panel)
        self.window = panel
    }
    
    private func positionWindow(_ panel: NSWindow) {
        // Fallback to the first screen if main is nil at launch
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenRect = screen.visibleFrame
        let panelRect = panel.frame
        let x = screenRect.maxX - panelRect.width - 20
        let y = screenRect.maxY - panelRect.height - 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func observe() {
        Publishers.CombineLatest(model.$active, model.$overlayVisible)
            .receive(on: RunLoop.main)
            .sink { [weak self] activeSession, visible in
                guard let self = self, let window = self.window else { return }
                
                let isRunning = activeSession != nil
                if isRunning && visible {
                    self.positionWindow(window) // Ensure correct position before showing
                    window.orderFront(nil)
                } else {
                    window.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }
}
