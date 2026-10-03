import Foundation

struct AuthUser: Codable, Sendable {
    let id: String
}

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 90 }
}

struct CreateCoupleRequest: Codable { let timezone: String; let displayName: String? }
struct CreateCoupleResponse: Codable { let coupleId: String; let inviteCode: String; let expiresAt: Int64 }
struct RedeemInviteRequest: Codable { let code: String }
struct RedeemInviteResponse: Codable { let coupleId: String }
struct TapHeartRequest: Codable { let coupleId: String; let tapId: String }
struct ThinkingOfYouRequest: Codable { let coupleId: String; let eventId: String }
struct LoveNoteRequest: Codable { let coupleId: String; let body: String }
struct MoodRequest: Codable { let coupleId: String; let mood: String }

struct BootstrapResponse: Codable, Sendable {
    let uid: String
    let user: UserDTO?
    let couple: CoupleDTO?
}

struct UserDTO: Codable, Sendable {
    let displayName: String?
    let coupleId: String?
    let createdAt: Int64?
}

struct CoupleDTO: Codable, Sendable {
    let coupleId: String
    let members: [String: String]
    let timezone: String
    let status: String
    let createdAt: Int64?
    let state: CoupleStateDTO
}

struct CoupleStateDTO: Codable, Sendable {
    var heart: HeartDTO
    var today: TodayDTO
    var streak: StreakDTO
    var history: [DailySummaryDTO]
}

struct HeartDTO: Codable, Sendable {
    var score: Int
    let maxScore: Int
    var totalTaps: Int64
    var lastUpdatedAt: Int64
    let lastTapAt: Int64?

    var normalizedLastUpdated: TimeInterval {
        let value = TimeInterval(lastUpdatedAt)
        return value < 10_000_000_000 ? value : value / 1_000
    }
}

struct TodayDTO: Codable, Sendable {
    let date: String
    let tapsByUser: [String: Int]
    var myTaps: Int
    var partnerTaps: Int
    var totalTaps: Int
    var completed: Bool
    let completedAt: Int64?
}

struct StreakDTO: Codable, Sendable {
    var current: Int
    var longest: Int
    let lastCompletedDate: String?
}

struct DailySummaryDTO: Codable, Identifiable, Sendable {
    var id: String { date }
    let date: String
    let tapsByUser: [String: Int]
    let myTaps: Int
    let partnerTaps: Int
    let totalTaps: Int
    let completed: Bool
    let completedAt: Int64?
}

struct TapResult: Codable, Sendable {
    let accepted: Bool
    let duplicate: Bool
    let score: Int
    let percentage: Double
    let totalTaps: Int64
    let today: TapToday
    let streak: StreakDTO
}

struct TapToday: Codable, Sendable {
    let myTaps: Int
    let partnerTaps: Int
    let totalTaps: Int
    let completed: Bool
}

struct ThinkingOfYouResult: Codable, Sendable {
    let accepted: Bool
    let duplicate: Bool
    let eventId: String
    let notificationSent: Bool
}

struct LoveNoteDTO: Codable, Identifiable, Sendable {
    let id: String
    let coupleId: String
    let senderUid: String
    let recipientUid: String
    let body: String
    let createdAt: Int64
    let readAt: Int64?
}

struct LoveNoteResponse: Codable, Sendable {
    let id: String
    let coupleId: String
    let senderUid: String
    let recipientUid: String
    let body: String
    let createdAt: Int64
    let readAt: Int64?
    let notificationSent: Bool

    var note: LoveNoteDTO {
        LoveNoteDTO(id: id, coupleId: coupleId, senderUid: senderUid, recipientUid: recipientUid, body: body, createdAt: createdAt, readAt: readAt)
    }
}

struct LoveNotesResponse: Codable, Sendable { let notes: [LoveNoteDTO] }
struct MoodResponse: Codable, Sendable { let day: String; let moods: [String: String] }

struct StoryRequest: Codable {
    let coupleId: String
    let action: String
    var title: String? = nil
    var caption: String? = nil
    var occurredOn: String? = nil
    var photoBase64s: [String] = []
    var photoPaths: [String] = []
    var itemId: String? = nil
    var listId: String? = nil
    var label: String? = nil
    var kind: String? = nil
    var remindAnnually: Bool = true
}

struct MemoryDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let caption: String
    let occurredOn: String?
    let photoPaths: [String]
    let photoKeys: [String]
    let createdAt: Int64
}

struct BucketItemDTO: Codable, Identifiable, Sendable {
    let id: String
    let listId: String?
    let title: String
    let completedAt: Int64?
    let createdAt: Int64
}

struct BucketListDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let createdAt: Int64
}

struct RelationshipDateDTO: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let kind: String
    let occursOn: String
    let remindAnnually: Bool
}

struct StoryResponse: Codable, Sendable {
    let memories: [MemoryDTO]
    let bucketItems: [BucketItemDTO]
    let bucketLists: [BucketListDTO]
    let dates: [RelationshipDateDTO]

    static let empty = StoryResponse(memories: [], bucketItems: [], bucketLists: [], dates: [])
}

struct WidgetSnapshot: Codable, Sendable {
    let score: Int
    let maxScore: Int
    let myTaps: Int
    let partnerTaps: Int
    let streak: Int
    let updatedAt: Date

    static let empty = WidgetSnapshot(score: 0, maxScore: HeartRules.maximumScore, myTaps: 0, partnerTaps: 0, streak: 0, updatedAt: .now)
}
