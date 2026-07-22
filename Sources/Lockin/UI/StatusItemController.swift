import AppKit
import Combine

/// Owns the menu bar `NSStatusItem` and renders "the most important 40 pixels": a colored dot and
/// a monospaced-digit timer that never reflows. Drawn as an attributed string for pixel control.
@MainActor
final class StatusItemController {
    let statusItem: NSStatusItem
    var onClick: (() -> Void)?

    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []

    private static let timeFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.imagePosition = .imageLeading
        }
        render()
        observe()
    }

    var button: NSStatusBarButton? { statusItem.button }

    private func observe() {
        // Any change to the active session or elapsed time redraws the label.
        model.$active
            .combineLatest(model.$elapsed)
            .sink { [weak self] _, _ in self?.render() }
            .store(in: &cancellables)
    }

    @objc private func handleClick() {
        onClick?()
    }

    private func render() {
        guard let button = statusItem.button else { return }

        // The app icon (timer symbol) stays visible in all states; the time/countdown is drawn
        // right next to it while a session runs.
        let icon = NSImage(systemSymbolName: "timer", accessibilityDescription: "Lockin")
        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageLeading

        guard let active = model.active else {
            button.attributedTitle = NSAttributedString(string: "")
            statusItem.length = NSStatusItem.variableLength
            return
        }

        let overrun = model.isPomodoroOverrun
        let dot = overrun ? "○" : "●"

        let timeString: String
        var suffix = ""
        if active.kind == .pomodoro, let target = active.targetMin {
            if overrun {
                timeString = TimeFormatting.clock(model.elapsed)
            } else {
                timeString = TimeFormatting.clock(Double(target * 60) - model.elapsed)
                suffix = " ↓"
            }
        } else {
            timeString = TimeFormatting.clock(model.elapsed)
        }

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: " \(dot)",
            attributes: [
                .foregroundColor: NSColor(hex: active.colorHex),
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
        ))
        result.append(NSAttributedString(
            string: " \(timeString)\(suffix)",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: Self.timeFont
            ]
        ))
        button.attributedTitle = result
        // Force enough room for icon + countdown; variableLength alone sometimes clips to icon-only.
        statusItem.length = max(72, result.size().width + 40)
    }
}
