import XCTest
@testable import Lockin

final class PureLogicTests: XCTestCase {
    func testFuzzyMatches() {
        XCTAssertNotNil(AppModel.fuzzyScore(needle: "aka syn", haystack: "AKA project — synthesis pass"))
        XCTAssertNotNil(AppModel.fuzzyScore(needle: "synth", haystack: "AKA project — synthesis pass"))
        XCTAssertNil(AppModel.fuzzyScore(needle: "zzzq", haystack: "AKA project — synthesis pass"))
    }

    func testFuzzyRanksContiguousHigher() {
        let contiguous = AppModel.fuzzyScore(needle: "synth", haystack: "synthesis")!
        let scattered = AppModel.fuzzyScore(needle: "synth", haystack: "s y n reach t h")!
        XCTAssertGreaterThan(contiguous, scattered)
    }

    func testParseIsFlatAndIgnoresSlash() {
        let parsed = AppModel.parse(query: "AKA project / synthesis pass", lastProject: "Other")
        XCTAssertEqual(parsed.project, AppModel.defaultProjectName)
        XCTAssertEqual(parsed.task, "AKA project / synthesis pass")
    }

    func testParseIgnoresLastProject() {
        let parsed = AppModel.parse(query: "write spec", lastProject: "Doctor avatar")
        XCTAssertEqual(parsed.project, AppModel.defaultProjectName)
        XCTAssertEqual(parsed.task, "write spec")
    }

    func testParseTrimsWhitespace() {
        let parsed = AppModel.parse(query: "  New thing  ", lastProject: nil)
        XCTAssertEqual(parsed.project, AppModel.defaultProjectName)
        XCTAssertEqual(parsed.task, "New thing")
    }

    func testTimeFormattingClock() {
        XCTAssertEqual(TimeFormatting.clock(0), "0:00")
        XCTAssertEqual(TimeFormatting.clock(65), "1:05")
        XCTAssertEqual(TimeFormatting.clock(24 * 60 + 17), "24:17")
        XCTAssertEqual(TimeFormatting.clock(3600), "1:00")        // h:mm at the hour
        XCTAssertEqual(TimeFormatting.clock(3600 + 2 * 60), "1:02")
        XCTAssertEqual(TimeFormatting.clock(-5), "0:00")
    }

    func testTimeFormattingCompact() {
        XCTAssertEqual(TimeFormatting.compact(seconds: 45 * 60), "45m")
        XCTAssertEqual(TimeFormatting.compact(seconds: 2 * 3600), "2h")
        XCTAssertEqual(TimeFormatting.compact(seconds: 90 * 60), "1.5h")
    }

    func testPaletteAvoidsRecent() {
        let recent = [Palette.hexColors[0], Palette.hexColors[1]]
        let next = Palette.nextColor(recentlyUsed: recent)
        XCTAssertFalse(recent.contains(next))
    }

    func testDateISORoundTripPreservesInstant() {
        let now = Date(timeIntervalSince1970: 1_800_000_000.5)
        let string = DateISO.string(from: now)
        let parsed = DateISO.date(from: string)!
        XCTAssertEqual(now.timeIntervalSince1970, parsed.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertTrue(string.contains("T"))
    }
}
