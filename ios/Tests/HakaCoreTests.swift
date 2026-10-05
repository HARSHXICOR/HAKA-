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
    func testTapQueuePersistsOriginalIDsInFIFOOrder() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haka-queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let first = QueuedTap(
            tapId: "tap-original-1",
            coupleId: "couple-a",
            userId: "user-a",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let second = QueuedTap(
            tapId: "tap-original-2",
            coupleId: "couple-a",
            userId: "user-a",
            createdAt: Date(timeIntervalSince1970: 101)
        )

        let writer = TapQueueStore(fileURL: fileURL)
        _ = try await writer.enqueue(first, now: Date(timeIntervalSince1970: 102))
        _ = try await writer.enqueue(second, now: Date(timeIntervalSince1970: 102))

        let restored = try await TapQueueStore(fileURL: fileURL).pending(
            userId: "user-a",
            coupleId: "couple-a",
            now: Date(timeIntervalSince1970: 102)
        )
        XCTAssertEqual(restored.map(\.tapId), ["tap-original-1", "tap-original-2"])
    }

    func testTapQueueRetryAcknowledgesSuccessAndPreservesFailedCommand() async throws {
        struct Offline: Error {}
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haka-queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TapQueueStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_000)
        for (index, id) in ["tap-1", "tap-2", "tap-3"].enumerated() {
            _ = try await store.enqueue(
                QueuedTap(
                    tapId: id,
                    coupleId: "couple-a",
                    userId: "user-a",
                    createdAt: now.addingTimeInterval(Double(index))
                ),
                now: now.addingTimeInterval(3)
            )
        }
        var submitted: [String] = []

        let report = try await TapQueueRetrier.replay(
            store: store,
            userId: "user-a",
            coupleId: "couple-a",
            now: now.addingTimeInterval(4),
            submit: { command in
                submitted.append(command.tapId)
                if command.tapId == "tap-2" { throw Offline() }
            },
            shouldRetry: { $0 is Offline }
        )

        XCTAssertEqual(submitted, ["tap-1", "tap-2"])
        XCTAssertEqual(report, TapReplayReport(delivered: 1, discarded: 0, remaining: 2))
        let remaining = try await store.pending(
            userId: "user-a",
            coupleId: "couple-a",
            now: now.addingTimeInterval(4)
        )
        XCTAssertEqual(remaining.map(\.tapId), ["tap-2", "tap-3"])
        XCTAssertEqual(remaining.map(\.attempts), [1, 0])
    }

    func testTapQueueExpiresOldCommandsAndCapsPendingWork() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haka-queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = TapQueueStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_000_000)
        _ = try await store.enqueue(
            QueuedTap(
                tapId: "expired",
                coupleId: "couple-a",
                userId: "user-a",
                createdAt: now.addingTimeInterval(-TapQueueStore.retention - 1)
            ),
            now: now
        )
        for index in 0..<TapQueueStore.maximumCount {
            _ = try await store.enqueue(
                QueuedTap(
                    tapId: "tap-\(index)",
                    coupleId: "couple-a",
                    userId: "user-a",
                    createdAt: now.addingTimeInterval(Double(index))
                ),
                now: now
            )
        }

        do {
            _ = try await store.enqueue(
                QueuedTap(tapId: "overflow", coupleId: "couple-a", userId: "user-a", createdAt: now),
                now: now
            )
            XCTFail("Expected a full queue error")
        } catch {
            XCTAssertEqual(error as? TapQueueError, .full)
        }
        let pendingCount = try await store.count(userId: "user-a", now: now)
        XCTAssertEqual(pendingCount, TapQueueStore.maximumCount)
    }

}
