import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, stored as a Carbon key code + modifier mask plus a display string.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    static func modifierString(carbon: UInt32) -> String {
        var s = ""
        if carbon & UInt32(controlKey) != 0 { s += "\u{2303}" } // ⌃
        if carbon & UInt32(optionKey) != 0 { s += "\u{2325}" }  // ⌥
        if carbon & UInt32(shiftKey) != 0 { s += "\u{21E7}" }   // ⇧
        if carbon & UInt32(cmdKey) != 0 { s += "\u{2318}" }     // ⌘
        return s
    }

    static func keyName(keyCode: UInt32, chars: String) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "\u{21A9}"
        case kVK_Tab: return "\u{21E5}"
        case kVK_Escape: return "\u{238B}"
        case kVK_Delete: return "\u{232B}"
        case kVK_LeftArrow: return "\u{2190}"
        case kVK_RightArrow: return "\u{2192}"
        case kVK_UpArrow: return "\u{2191}"
        case kVK_DownArrow: return "\u{2193}"
        default:
            let trimmed = chars.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "?" : trimmed.uppercased()
        }
    }

    static func display(keyCode: UInt32, carbon: UInt32, chars: String) -> String {
        modifierString(carbon: carbon) + keyName(keyCode: keyCode, chars: chars)
    }
}

/// The two shortcuts the app exposes, with their defaults.
enum HotkeyID: String, CaseIterable {
    case startStop
    case openPopover

    var numeric: UInt32 {
        switch self {
        case .startStop: return 1
        case .openPopover: return 2
        }
    }

    var title: String {
        switch self {
        case .startStop: return "Start / stop"
        case .openPopover: return "Open popover"
        }
    }

    var defaultHotkey: Hotkey {
        let mods = UInt32(controlKey) | UInt32(optionKey)
        switch self {
        case .startStop:
            return Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: mods,
                          display: Hotkey.display(keyCode: UInt32(kVK_Space), carbon: mods, chars: " "))
        case .openPopover:
            return Hotkey(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: mods,
                          display: Hotkey.display(keyCode: UInt32(kVK_ANSI_L), carbon: mods, chars: "l"))
        }
    }
}

/// Registers global hotkeys via Carbon `RegisterEventHotKey` and dispatches presses to handlers.
/// Self-contained so the app builds with only the Command Line Tools toolchain.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x4C4F434B // 'LOCK'

    private init() {}

    func setHandler(for id: HotkeyID, _ handler: @escaping () -> Void) {
        handlers[id.numeric] = handler
    }

    func current(for id: HotkeyID) -> Hotkey {
        let key = "hotkey.\(id.rawValue)"
        if let data = UserDefaults.standard.data(forKey: key),
           let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) {
            return hotkey
        }
        return id.defaultHotkey
    }

    func set(_ hotkey: Hotkey, for id: HotkeyID) {
        let key = "hotkey.\(id.rawValue)"
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: key)
        }
        register(id)
    }

    func registerAll() {
        installHandlerIfNeeded()
        for id in HotkeyID.allCases { register(id) }
    }

    private func register(_ id: HotkeyID) {
        installHandlerIfNeeded()
        if let existing = refs[id.numeric] {
            UnregisterEventHotKey(existing)
            refs[id.numeric] = nil
        }
        let hotkey = current(for: id)
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id.numeric)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs[id.numeric] = ref
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if err == noErr {
                    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                    center.handlers[hkID.id]?()
                }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}
