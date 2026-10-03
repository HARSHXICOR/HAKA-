import XCTest
@testable import Haka

@MainActor
final class HakaCoreTests: XCTestCase {
    func testInviteFormatting() {
        XCTAssertEqual(HakaAppModel.formatInvite("ab12 cd34"), "AB12-CD34")
        XCTAssertEqual(HakaAppModel.formatInvite("ab-12"), "AB12")
        XCTAssertEqual(HakaAppModel.formatInvite("ab12-cd34-more"), "AB12-CD34")
    }

    func testTimestampNormalizationSupportsSecondsAndMilliseconds() {
        let seconds = HeartDTO(score: 1_000, maxScore: 10_000, totalTaps: 0, lastUpdatedAt: 1_700_000_000, lastTapAt: nil)
        let milliseconds = HeartDTO(score: 1_000, maxScore: 10_000, totalTaps: 0, lastUpdatedAt: 1_700_000_000_000, lastTapAt: nil)
        XCTAssertEqual(seconds.normalizedLastUpdated, milliseconds.normalizedLastUpdated)
    }
}
