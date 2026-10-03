import Foundation

enum DailyProgressStatus: Equatable {
    case completed
    case inProgress

    init(completed: Bool) {
        self = completed ? .completed : .inProgress
    }

    var title: String {
        switch self {
        case .completed: String(localized: "Completed")
        case .inProgress: String(localized: "In progress")
        }
    }
}

struct ContributionSplit: Equatable {
    let mine: Int
    let partner: Int
}

struct InsightsSnapshot: Equatable {
    let totalTaps: Int
    let status: DailyProgressStatus
    let currentStreak: Int
    let longestStreak: Int
    let contribution: ContributionSplit
}

struct WeekValue: Identifiable, Equatable {
    let id: String
    let label: String
    let taps: Int
    let today: Bool
}

enum InsightsProjection {
    static func snapshot(today: TodayDTO?, streak: StreakDTO?) -> InsightsSnapshot {
        InsightsSnapshot(
            totalTaps: today?.totalTaps ?? 0,
            status: DailyProgressStatus(completed: today?.completed == true),
            currentStreak: streak?.current ?? 0,
            longestStreak: streak?.longest ?? 0,
            contribution: contribution(myTaps: today?.myTaps ?? 0, partnerTaps: today?.partnerTaps ?? 0)
        )
    }

    static func contribution(myTaps: Int, partnerTaps: Int) -> ContributionSplit {
        let safeMine = max(0, myTaps)
        let safePartner = max(0, partnerTaps)
        let total = safeMine + safePartner
        guard total > 0 else { return ContributionSplit(mine: 0, partner: 0) }
        let mine = Int((Double(safeMine) / Double(total) * 100).rounded())
        return ContributionSplit(mine: mine, partner: 100 - mine)
    }

    static func summary(from today: TodayDTO) -> DailySummaryDTO {
        DailySummaryDTO(
            date: today.date,
            tapsByUser: today.tapsByUser,
            myTaps: today.myTaps,
            partnerTaps: today.partnerTaps,
            totalTaps: today.totalTaps,
            completed: today.completed,
            completedAt: today.completedAt
        )
    }

    static func weeklyValues(
        history: [DailySummaryDTO],
        today: TodayDTO?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeekValue] {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"

        var summaries = Dictionary(uniqueKeysWithValues: history.map { ($0.date, $0) })
        if let today { summaries[today.date] = summary(from: today) }
        let startOfToday = calendar.startOfDay(for: now)

        return summaries.values.compactMap { summary -> (Date, DailySummaryDTO)? in
            parser.date(from: summary.date).map { ($0, summary) }
        }
        .filter { date, _ in
            guard let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day else {
                return false
            }
            return (0...6).contains(days)
        }
        .sorted { $0.0 < $1.0 }
        .map { date, summary in
            WeekValue(
                id: summary.date,
                label: date.formatted(.dateTime.weekday(.abbreviated)),
                taps: summary.totalTaps,
                today: calendar.isDate(date, inSameDayAs: now)
            )
        }
    }
}
