import Foundation
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class HakaAppModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case authentication
        case pairing
        case waitingForPartner
        case paired
        case failed(String)
        case configuration(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var userID = ""
    @Published private(set) var displayName: String?
    @Published private(set) var coupleID: String?
    @Published private(set) var timezone: String?
    @Published private(set) var members: [String: String] = [:]
    @Published private(set) var heart: HeartDTO?
    @Published private(set) var today: TodayDTO?
    @Published private(set) var streak: StreakDTO?
    @Published private(set) var history: [DailySummaryDTO] = []
    @Published private(set) var loveNotes: [LoveNoteDTO] = []
    @Published private(set) var moods: [String: String] = [:]
    @Published private(set) var story = StoryResponse.empty
    @Published private(set) var inviteCode: String?
    @Published private(set) var inviteExpiresAt: Date?
    @Published private(set) var isBusy = false
    @Published var message: String?
    @Published private(set) var now = Date()
    @Published var selectedTab = 0
    @Published var tapCelebration = 0
    @Published var thinkingPulse = 0

    let notifications = NotificationManager()

    private let api: HakaAPI?
    private var syncTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var oauthCallback: URL?
    private var started = false

    init() {
        do {
            api = HakaAPI(configuration: try HakaConfiguration.load())
        } catch {
            api = nil
            phase = .configuration(error.localizedDescription)
        }
    }

    var connected: Bool { phase == .paired }
    var partnerID: String? { members.keys.first { $0 != userID } }
    var myTaps: Int { today?.myTaps ?? 0 }
    var partnerTaps: Int { today?.partnerTaps ?? 0 }
    var totalTaps: Int { today?.totalTaps ?? 0 }
    var heartMaximumScore: Int { heart?.maxScore ?? HeartRules.maximumScore }

    var effectiveScore: Int {
        heart?.effectiveScore(at: now) ?? 0
    }

    var heartFraction: Double {
        HeartRules.fraction(score: effectiveScore, maxScore: heartMaximumScore)
    }

    var heartPercentage: Int {
        HeartRules.percentage(score: effectiveScore, maxScore: heartMaximumScore)
    }

    func start() async {
        guard !started else { return }
        started = true
        await notifications.refreshAuthorization()
        startClock()
        guard let api else { return }
        guard api.hasSession else {
            phase = .authentication
            return
        }
        await refresh(showLoading: true)
    }

    func continueAnonymously() async {
        await runBusy {
            guard let api else { return }
            try await api.signInAnonymously()
            await refresh(showLoading: true)
        }
    }

    func continueWithGoogle() async {
        await runBusy {
            guard let api else { return }
            try await api.signInWithGoogle()
            await refresh(showLoading: true)
        }
    }

    func linkGoogle() async {
        await runBusy {
            guard let api else { return }
            try await api.linkGoogleIdentity()
            message = "Your Haka is secured with Google."
        }
    }

    func createCouple(name: String) async {
        await runBusy {
            guard let api else { return }
            let response = try await api.createCouple(displayName: name)
            inviteCode = response.inviteCode
            inviteExpiresAt = Self.dateFromEpoch(response.expiresAt)
            coupleID = response.coupleId
            phase = .waitingForPartner
            startSync()
        }
    }

    func redeemInvite(_ rawCode: String) async {
        await runBusy {
            guard let api else { return }
            let code = Self.formatInvite(rawCode)
            _ = try await api.redeemInvite(code: code)
            await refresh(showLoading: true)
        }
    }

    func refresh(showLoading: Bool = false) async {
        guard let api else { return }
        if showLoading { phase = .loading }
        do {
            let bootstrap = try await api.bootstrap()
            apply(bootstrap)
            message = nil
        } catch {
            if heart != nil {
                message = "Offline — showing the last shared state."
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func tapHeart() {
        guard let coupleID, phase == .paired else { return }
        tapCelebration += 1
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            do {
                guard let api else { return }
                let result = try await api.tap(coupleId: coupleID)
                if result.accepted {
                    heart?.score = result.score
                    heart?.totalTaps = result.totalTaps
                    today?.myTaps = result.today.myTaps
                    today?.partnerTaps = result.today.partnerTaps
                    today?.totalTaps = result.today.totalTaps
                    today?.completed = result.today.completed
                    streak = result.streak
                }
                await refresh()
                if result.score >= heartMaximumScore { tapCelebration += HeartRules.maximumScore }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func sendThinkingOfYou() async {
        guard let api, let coupleID else { return }
        await runBusy {
            let result = try await api.thinkingOfYou(coupleId: coupleID)
            if result.accepted {
                thinkingPulse += 1
                message = result.notificationSent ? "Sent to your partner 💕" : "Saved — partner notification is unavailable."
            }
        }
    }

    func loadLove() async {
        guard let api, let coupleID else { return }
        do {
            async let notes = api.loveNotes(coupleId: coupleID)
            async let mood = api.moods(coupleId: coupleID)
            loveNotes = try await notes
            moods = try await mood.moods
        } catch {
            message = error.localizedDescription
        }
    }

    func sendLoveNote(_ body: String) async {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, let coupleID, !value.isEmpty else { return }
        await runBusy {
            let response = try await api.sendLoveNote(coupleId: coupleID, body: String(value.prefix(160)))
            loveNotes.insert(response.note, at: 0)
            message = response.notificationSent ? "Love Note sent 💌" : "Love Note saved."
        }
    }

    func setMood(_ mood: String) async {
        guard let api, let coupleID else { return }
        await runBusy {
            try await api.setMood(coupleId: coupleID, mood: mood)
            moods = try await api.moods(coupleId: coupleID).moods
        }
    }

    func loadStory() async {
        guard let api, let coupleID else { return }
        do {
            story = try await api.story(StoryRequest(coupleId: coupleID, action: "list"))
        } catch {
            message = error.localizedDescription
        }
    }

    func addMemory(title: String, caption: String, date: Date?, photos: [Data]) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: "addMemory")
            request.title = title
            request.caption = caption
            request.occurredOn = date.map(Self.isoDate)
            request.photoBase64s = photos.compactMap(Self.jpegBase64)
            _ = try await api.story(request)
            await loadStory()
        }
    }

    func updateMemory(_ memory: MemoryDTO, title: String, caption: String, date: Date?, newPhotos: [Data] = []) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: "updateMemory")
            request.itemId = memory.id
            request.title = title
            request.caption = caption
            request.occurredOn = date.map(Self.isoDate)
            request.photoPaths = memory.photoKeys
            request.photoBase64s = newPhotos.compactMap(Self.jpegBase64)
            try await api.storyCommand(request)
            await loadStory()
        }
    }

    func addBucketItem(_ title: String, listID: String? = nil) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: listID == nil ? "addBucket" : "addBucketListItem")
            request.title = title
            request.listId = listID
            _ = try await api.story(request)
            await loadStory()
        }
    }

    func addBucketList(_ title: String) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: "addBucketList")
            request.title = title
            _ = try await api.story(request)
            await loadStory()
        }
    }

    func toggleBucket(_ item: BucketItemDTO) async {
        await storyCommand(action: "toggleBucket", itemID: item.id)
    }

    func updateBucket(_ item: BucketItemDTO, title: String) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: "updateBucket")
            request.itemId = item.id
            request.title = title
            try await api.storyCommand(request)
            await loadStory()
        }
    }

    func updateBucketList(_ list: BucketListDTO, title: String) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: "updateBucketList")
            request.listId = list.id
            request.title = title
            try await api.storyCommand(request)
            await loadStory()
        }
    }

    func addRelationshipDate(label: String, kind: String, date: Date, annual: Bool) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: "addDate")
            request.label = label
            request.kind = kind
            request.occurredOn = Self.isoDate(date)
            request.remindAnnually = annual
            _ = try await api.story(request)
            await loadStory()
        }
    }

    func updateRelationshipDate(_ item: RelationshipDateDTO, label: String, kind: String, date: Date, annual: Bool) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: "updateDate")
            request.itemId = item.id
            request.label = label
            request.kind = kind
            request.occurredOn = Self.isoDate(date)
            request.remindAnnually = annual
            try await api.storyCommand(request)
            await loadStory()
        }
    }

    func deleteMemory(_ id: String) async { await storyCommand(action: "deleteMemory", itemID: id) }
    func deleteBucket(_ id: String) async { await storyCommand(action: "deleteBucket", itemID: id) }
    func deleteBucketList(_ id: String) async { await storyCommand(action: "deleteBucketList", listID: id) }
    func deleteDate(_ id: String) async { await storyCommand(action: "deleteDate", itemID: id) }

    func signOut() async {
        syncTask?.cancel()
        await api?.signOut()
        clearSharedState()
        phase = .authentication
    }

    func handleOAuthCallback(_ url: URL) {
        oauthCallback = url
    }

    static func formatInvite(_ value: String) -> String {
        let clean = value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8)
        let text = String(clean)
        guard text.count > 4 else { return text }
        return String(text.prefix(4)) + "-" + String(text.dropFirst(4))
    }

    private func storyCommand(action: String, itemID: String? = nil, listID: String? = nil) async {
        guard let api, let coupleID else { return }
        await runBusy {
            var request = StoryRequest(coupleId: coupleID, action: action)
            request.itemId = itemID
            request.listId = listID
            try await api.storyCommand(request)
            await loadStory()
        }
    }

    private func apply(_ bootstrap: BootstrapResponse) {
        userID = bootstrap.uid
        displayName = bootstrap.user?.displayName
        guard let couple = bootstrap.couple else {
            clearSharedState()
            phase = .pairing
            return
        }
        coupleID = couple.coupleId
        timezone = couple.timezone
        members = couple.members
        heart = couple.state.heart
        today = couple.state.today
        streak = couple.state.streak
        history = couple.state.history
        if couple.members.count >= 2 {
            inviteCode = nil
            phase = .paired
        } else {
            phase = .waitingForPartner
        }
        persistWidget()
        startSync()
    }

    private func clearSharedState() {
        coupleID = nil
        members = [:]
        heart = nil
        today = nil
        streak = nil
        history = []
        loveNotes = []
        moods = [:]
        story = .empty
        UserDefaults(suiteName: "group.com.haka.shared")?.removeObject(forKey: "widgetSnapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func startSync() {
        guard syncTask == nil || syncTask?.isCancelled == true else { return }
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                await self.refresh()
                if self.phase == .paired && self.selectedTab == 2 { await self.loadLove() }
                if self.phase == .paired && self.selectedTab == 3 { await self.loadStory() }
            }
        }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.now = .now
                self?.persistWidget()
            }
        }
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            message = error.localizedDescription
            if case HakaError.missingSession = error { phase = .authentication }
        }
    }

    private func persistWidget() {
        guard let heart else { return }
        let snapshot = WidgetSnapshot(
            score: heart.score,
            maxScore: heart.maxScore,
            myTaps: myTaps,
            partnerTaps: partnerTaps,
            streak: streak?.current ?? 0,
            updatedAt: Date(timeIntervalSince1970: heart.normalizedLastUpdated)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let defaults = UserDefaults(suiteName: "group.com.haka.shared")
        guard defaults?.data(forKey: "widgetSnapshot") != data else { return }
        defaults?.set(data, forKey: "widgetSnapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func dateFromEpoch(_ value: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value < 10_000_000_000 ? value : value / 1_000))
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func jpegBase64(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1440 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return rendered.jpegData(compressionQuality: 0.82)?.base64EncodedString()
    }
}
