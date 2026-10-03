import Foundation

enum HeartRules {
    static let maximumScore = 10_000
    static let tapAmount = 25
    static let decayAmount = 100
    static let decayInterval: TimeInterval = 30

    static func effectiveScore(
        score: Int,
        maxScore: Int = maximumScore,
        lastUpdatedAt: TimeInterval,
        now: Date
    ) -> Int {
        guard maxScore > 0 else { return 0 }
        let elapsed = max(0, now.timeIntervalSince1970 - lastUpdatedAt)
        let completedIntervals = Int(elapsed / decayInterval)
        return min(maxScore, max(0, score - completedIntervals * decayAmount))
    }

    static func fraction(score: Int, maxScore: Int = maximumScore) -> Double {
        guard maxScore > 0 else { return 0 }
        return min(1, max(0, Double(score) / Double(maxScore)))
    }

    static func percentage(score: Int, maxScore: Int = maximumScore) -> Int {
        Int((fraction(score: score, maxScore: maxScore) * 100).rounded(.down))
    }
}

extension HeartDTO {
    func effectiveScore(at now: Date) -> Int {
        HeartRules.effectiveScore(
            score: score,
            maxScore: maxScore,
            lastUpdatedAt: normalizedLastUpdated,
            now: now
        )
    }
}
