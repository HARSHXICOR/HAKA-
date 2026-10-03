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

    func testDecayOnlyAppliesAtCompletedThirtySecondBoundaries() {
        let epoch: TimeInterval = 1_700_000_000
        XCTAssertEqual(
            HeartRules.effectiveScore(score: 10_000, lastUpdatedAt: epoch, now: Date(timeIntervalSince1970: epoch + 29.999)),
            10_000
        )
        XCTAssertEqual(
            HeartRules.effectiveScore(score: 10_000, lastUpdatedAt: epoch, now: Date(timeIntervalSince1970: epoch + 30)),
            9_900
        )
        XCTAssertEqual(
            HeartRules.effectiveScore(score: 10_000, lastUpdatedAt: epoch, now: Date(timeIntervalSince1970: epoch + 90)),
            9_700
        )
    }

    func testDecayClampsToHeartRange() {
        let epoch: TimeInterval = 1_700_000_000
        XCTAssertEqual(
            HeartRules.effectiveScore(score: 50, lastUpdatedAt: epoch, now: Date(timeIntervalSince1970: epoch + 30)),
            0
        )
        XCTAssertEqual(
            HeartRules.effectiveScore(score: 12_000, lastUpdatedAt: epoch, now: Date(timeIntervalSince1970: epoch)),
            10_000
        )
        XCTAssertEqual(HeartRules.percentage(score: 5_699), 56)
    }

    func testInsightsSnapshotMapsDailyStatusStreakAndContribution() {
        let today = TodayDTO(
            date: "2026-10-03",
            tapsByUser: ["me": 74, "partner": 28],
            myTaps: 74,
            partnerTaps: 28,
            totalTaps: 102,
            completed: true,
            completedAt: 1_700_000_000
        )
        let streak = StreakDTO(current: 3, longest: 11, lastCompletedDate: "2026-10-03")

        let snapshot = InsightsProjection.snapshot(today: today, streak: streak)

        XCTAssertEqual(snapshot.totalTaps, 102)
        XCTAssertEqual(snapshot.status, .completed)
        XCTAssertEqual(snapshot.currentStreak, 3)
        XCTAssertEqual(snapshot.longestStreak, 11)
        XCTAssertEqual(snapshot.contribution, ContributionSplit(mine: 73, partner: 27))
    }

    func testZeroContributionDoesNotAssignPartnerOneHundredPercent() {
        XCTAssertEqual(
            InsightsProjection.contribution(myTaps: 0, partnerTaps: 0),
            ContributionSplit(mine: 0, partner: 0)
        )
    }

    func testWeeklyProjectionUsesTodayAsAuthoritativeAndKeepsSevenDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_759_449_600) // 2025-10-03T00:00:00Z
        let history = [
            DailySummaryDTO(date: "2025-10-03", tapsByUser: [:], myTaps: 1, partnerTaps: 1, totalTaps: 2, completed: false, completedAt: nil),
            DailySummaryDTO(date: "2025-09-28", tapsByUser: [:], myTaps: 4, partnerTaps: 3, totalTaps: 7, completed: false, completedAt: nil),
            DailySummaryDTO(date: "2025-09-20", tapsByUser: [:], myTaps: 50, partnerTaps: 50, totalTaps: 100, completed: true, completedAt: nil),
        ]
        let today = TodayDTO(date: "2025-10-03", tapsByUser: [:], myTaps: 10, partnerTaps: 5, totalTaps: 15, completed: false, completedAt: nil)

        let values = InsightsProjection.weeklyValues(history: history, today: today, now: now, calendar: calendar)

        XCTAssertEqual(values.map(\.id), ["2025-09-28", "2025-10-03"])
        XCTAssertEqual(values.last?.taps, 15)
        XCTAssertEqual(values.last?.today, true)
    }
}
