import Foundation

enum TimeFormatting {
    /// `mm:ss` under an hour, `h:mm` at or over an hour. Never negative.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Short human duration for the recent list, e.g. `2h`, `45m`, `0m`.
    static func compact(seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = Double(seconds) / 3600
            if hours.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(hours))h"
            }
            return String(format: "%.1fh", hours)
        }
        return "\(seconds / 60)m"
    }
}
