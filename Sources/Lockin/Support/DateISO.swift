import Foundation

/// ISO8601 timestamps *with a real timezone offset*, e.g. `2026-07-21T14:02:11.000-04:00`.
///
/// ActivityWatch expects a real offset on the event `timestamp`, and the spec mandates it for
/// every stored timestamp. We store strings (not GRDB's default UTC `Date` encoding) so the
/// offset survives a round-trip and elapsed time is always computed from the absolute instant.
enum DateISO {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback parser for strings that lack fractional seconds.
    private static let formatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? formatterNoFraction.date(from: string)
    }

    static func now() -> String {
        string(from: Date())
    }
}
