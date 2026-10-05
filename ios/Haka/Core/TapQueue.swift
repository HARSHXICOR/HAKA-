import Foundation

struct QueuedTap: Codable, Equatable, Identifiable, Sendable {
    let tapId: String
    let coupleId: String
    let userId: String
    let createdAt: Date
    var attempts: Int
    var lastAttemptAt: Date?

    var id: String { tapId }

    init(
        tapId: String = UUID().uuidString.lowercased(),
        coupleId: String,
        userId: String,
        createdAt: Date = .now,
        attempts: Int = 0,
        lastAttemptAt: Date? = nil
    ) {
        self.tapId = tapId
        self.coupleId = coupleId
        self.userId = userId
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
    }

    func isReady(at now: Date) -> Bool {
        guard let lastAttemptAt else { return true }
        let exponent = min(max(attempts, 1), 6)
        let delay = min(pow(2, Double(exponent)), 60)
        return now.timeIntervalSince(lastAttemptAt) >= delay
    }
}

enum TapQueueError: LocalizedError, Equatable {
    case full

    var errorDescription: String? {
        switch self {
        case .full:
            "Twenty taps are waiting to sync. Reconnect before adding more."
        }
    }
}

actor TapQueueStore {
    static let maximumCount = 20
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = TapQueueStore.defaultFileURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder.outputFormatting = [.sortedKeys]
    }

    @discardableResult
    func enqueue(_ command: QueuedTap, now: Date = .now) throws -> Int {
        var commands = try load()
        commands.removeAll { now.timeIntervalSince($0.createdAt) >= Self.retention }
        guard !commands.contains(where: { $0.tapId == command.tapId }) else {
            return commands.count
        }
        guard commands.filter({ $0.userId == command.userId }).count < Self.maximumCount else {
            throw TapQueueError.full
        }
        commands.append(command)
        try save(commands)
        return commands.filter { $0.userId == command.userId }.count
    }

    func pending(userId: String, coupleId: String, now: Date = .now) throws -> [QueuedTap] {
        var commands = try load()
        let originalCount = commands.count
        commands.removeAll { now.timeIntervalSince($0.createdAt) >= Self.retention }
        if commands.count != originalCount { try save(commands) }
        return commands
            .filter { $0.userId == userId && $0.coupleId == coupleId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func count(userId: String, now: Date = .now) throws -> Int {
        var commands = try load()
        let originalCount = commands.count
        commands.removeAll { now.timeIntervalSince($0.createdAt) >= Self.retention }
        if commands.count != originalCount { try save(commands) }
        return commands.filter { $0.userId == userId }.count
    }

    func markAttempt(_ tapId: String, at date: Date = .now) throws {
        var commands = try load()
        guard let index = commands.firstIndex(where: { $0.tapId == tapId }) else { return }
        commands[index].attempts += 1
        commands[index].lastAttemptAt = date
        try save(commands)
    }

    func remove(_ tapId: String) throws {
        var commands = try load()
        commands.removeAll { $0.tapId == tapId }
        try save(commands)
    }

    func removeAll(userId: String) throws {
        var commands = try load()
        commands.removeAll { $0.userId == userId }
        try save(commands)
    }

    private func load() throws -> [QueuedTap] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([QueuedTap].self, from: Data(contentsOf: fileURL))
    }

    private func save(_ commands: [QueuedTap]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(commands).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root.appendingPathComponent("Haka", isDirectory: true)
            .appendingPathComponent("pending-taps.json")
    }
}

struct TapReplayReport: Equatable, Sendable {
    var delivered = 0
    var discarded = 0
    var remaining = 0
}

enum TapQueueRetrier {
    static func replay(
        store: TapQueueStore,
        userId: String,
        coupleId: String,
        now: Date = .now,
        submit: (QueuedTap) async throws -> Void,
        shouldRetry: (Error) -> Bool
    ) async throws -> TapReplayReport {
        let commands = try await store.pending(userId: userId, coupleId: coupleId, now: now)
        var report = TapReplayReport()

        for command in commands {
            guard command.isReady(at: now) else { continue }
            do {
                try await submit(command)
                try await store.remove(command.tapId)
                report.delivered += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if shouldRetry(error) {
                    try await store.markAttempt(command.tapId, at: now)
                    break
                }
                try await store.remove(command.tapId)
                report.discarded += 1
            }
        }

        report.remaining = try await store.count(userId: userId, now: now)
        return report
    }
}
