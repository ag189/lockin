import AppKit
import SwiftUI
import Carbon.HIToolbox

/// A small button that records a new global shortcut when clicked, then persists and re-registers
/// it via `HotkeyCenter`.
struct ShortcutRecorder: NSViewRepresentable {
    let id: HotkeyID

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.title = HotkeyCenter.shared.current(for: id).display
        button.onCapture = { keyCode, carbon, display in
            let hotkey = Hotkey(keyCode: keyCode, carbonModifiers: carbon, display: display)
            HotkeyCenter.shared.set(hotkey, for: id)
            button.title = display
        }
        button.onReset = {
            button.title = HotkeyCenter.shared.current(for: id).display
        }
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        if !nsView.isRecording {
            nsView.title = HotkeyCenter.shared.current(for: id).display
        }
    }
}

final class RecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32, String) -> Void)?
    var onReset: (() -> Void)?
    private(set) var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 12)
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(70, super.intrinsicContentSize.width), height: super.intrinsicContentSize.height)
    }

    @objc private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = "Type shortcut\u{2026}"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            onReset?()
            return
        }
        let carbon = Hotkey.carbonFlags(from: event.modifierFlags)
        // Require at least one modifier so shortcuts don't fire during normal typing.
        guard carbon != 0 else {
            NSSound.beep()
            return
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        let display = Hotkey.display(keyCode: UInt32(event.keyCode), carbon: carbon, chars: chars)
        isRecording = false
        onCapture?(UInt32(event.keyCode), carbon, display)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            onReset?()
        }
        return super.resignFirstResponder()
    }
}
