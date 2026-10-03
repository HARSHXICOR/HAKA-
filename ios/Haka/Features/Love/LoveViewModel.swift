import Foundation

@MainActor
final class LoveViewModel: ObservableObject {
    @Published private(set) var notes: [LoveNoteDTO] = []
    @Published private(set) var moods: [String: String] = [:]
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    let userID: String
    let partnerID: String?

    private let api: HakaAPI?
    private let coupleID: String?

    init(api: HakaAPI?, coupleID: String?, userID: String, partnerID: String?) {
        self.api = api
        self.coupleID = coupleID
        self.userID = userID
        self.partnerID = partnerID
    }

    var myMood: String? { moods[userID] }
    var partnerMood: String? { partnerID.flatMap { moods[$0] } }

    func observe() async {
        await load()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await load(silently: true)
        }
    }

    func load(silently: Bool = false) async {
        guard let api, let coupleID else { return }
        do {
            async let fetchedNotes = api.loveNotes(coupleId: coupleID)
            async let fetchedMoods = api.moods(coupleId: coupleID)
            notes = try await fetchedNotes
            moods = try await fetchedMoods.moods
        } catch where silently {
            return
        } catch {
            message = error.localizedDescription
        }
    }

    func sendThinkingOfYou() async {
        guard let api, let coupleID else { return }
        await runBusy {
            let result = try await api.thinkingOfYou(coupleId: coupleID)
            if result.accepted {
                message = result.notificationSent
                    ? String(localized: "Sent to your partner 💕")
                    : String(localized: "Saved — partner notification is unavailable.")
            }
        }
    }

    func sendLoveNote(_ body: String) async {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, let coupleID, !value.isEmpty else { return }
        await runBusy {
            let response = try await api.sendLoveNote(coupleId: coupleID, body: String(value.prefix(160)))
            notes.insert(response.note, at: 0)
            message = response.notificationSent ? String(localized: "Love Note sent 💌") : String(localized: "Love Note saved.")
        }
    }

    func setMood(_ mood: String) async {
        guard let api, let coupleID else { return }
        await runBusy {
            try await api.setMood(coupleId: coupleID, mood: mood)
            moods = try await api.moods(coupleId: coupleID).moods
        }
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            message = error.localizedDescription
        }
    }
}
