import AppKit
import SwiftUI

/// Fixed 8-color palette. New projects get the next color round-robin, avoiding the most
/// recently used so adjacent projects stay visually distinct.
enum Palette {
    static let hexColors: [String] = [
        "#E5484D", // red
        "#F76B15", // orange
        "#FFB224", // amber
        "#46A758", // green
        "#12A594", // teal
        "#0091FF", // blue
        "#8E4EC6", // purple
        "#E93D82"  // pink
    ]

    /// State-based dot colors. Independent of project color.
    static let runningColor = "#E5484D" // red — a task is actively running
    static let idleColor = "#0091FF"    // blue — stopped, done, or idle

    /// Chooses the next palette color, skipping the ones most recently assigned.
    static func nextColor(recentlyUsed: [String]) -> String {
        let recent = Set(recentlyUsed.map { $0.lowercased() })
        if let unused = hexColors.first(where: { !recent.contains($0.lowercased()) }) {
            return unused
        }
        // All colors are in use; step one past the most recent to avoid an immediate repeat.
        guard let mostRecent = recentlyUsed.first,
              let idx = hexColors.firstIndex(where: { $0.lowercased() == mostRecent.lowercased() }) else {
            return hexColors[0]
        }
        return hexColors[(idx + 1) % hexColors.count]
    }
}

extension NSColor {
    convenience init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: string).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        switch string.count {
        case 8:
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255
            a = CGFloat(value & 0x0000_00FF) / 255
        default:
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
