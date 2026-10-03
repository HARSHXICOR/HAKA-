import SwiftUI
import WidgetKit

private let appGroup = "group.com.haka.shared"
private let snapshotKey = "widgetSnapshot"

private struct SharedHeartSnapshot: Codable {
    let score: Int
    let maxScore: Int
    let myTaps: Int
    let partnerTaps: Int
    let streak: Int
    let updatedAt: Date

    var effectiveScore: Int {
        let intervals = max(0, Int(Date().timeIntervalSince(updatedAt) / 30))
        return max(0, score - intervals * 100)
    }
}

private struct HeartEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedHeartSnapshot?

    var score: Int {
        guard let snapshot else { return 0 }
        let intervals = max(0, Int(date.timeIntervalSince(snapshot.updatedAt) / 30))
        return max(0, snapshot.score - intervals * 100)
    }

    var percent: Int {
        guard let snapshot, snapshot.maxScore > 0 else { return 0 }
        return Int((Double(score) / Double(snapshot.maxScore) * 100).rounded(.down))
    }
}

private struct HeartProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeartEntry {
        HeartEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeartEntry) -> Void) {
        completion(HeartEntry(date: .now, snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeartEntry>) -> Void) {
        let snapshot = load()
        let start = Date()
        let entries = (0..<20).map {
            HeartEntry(date: start.addingTimeInterval(Double($0) * 30), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(start.addingTimeInterval(600))))
    }

    private func load() -> SharedHeartSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(SharedHeartSnapshot.self, from: data)
    }
}

private struct HakaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeartEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.04, blue: 0.10), Color(red: 0.20, green: 0.07, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let snapshot = entry.snapshot {
                switch family {
                case .systemMedium:
                    medium(snapshot)
                default:
                    small(snapshot)
                }
            } else {
                empty
            }
        }
        .widgetURL(URL(string: "haka://open/heart"))
    }

    private func small(_ snapshot: SharedHeartSnapshot) -> some View {
        VStack(spacing: 7) {
            Text("Haka").font(.headline)
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, Double(entry.percent) / 100))
                    .stroke(
                        LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: "heart.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.pink)
                    .shadow(color: .pink.opacity(0.7), radius: 8)
            }
            .frame(width: 82, height: 82)
            Text("\(entry.percent)%").font(.title2.bold())
            Text("🔥 \(snapshot.streak) day streak")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
    }

    private func medium(_ snapshot: SharedHeartSnapshot) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(1, Double(entry.percent) / 100))
                    .stroke(
                        LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                    Text("\(entry.percent)%").font(.headline.bold())
                }
            }
            .frame(width: 102, height: 102)

            VStack(alignment: .leading, spacing: 9) {
                Text("Haka").font(.title2.bold())
                Text("Connected with love").font(.caption).foregroundStyle(.white.opacity(0.7))
                Text("\(entry.score.formatted()) / \(snapshot.maxScore.formatted())")
                    .font(.headline)
                    .foregroundStyle(.pink)
                ProgressView(value: Double(entry.score), total: Double(snapshot.maxScore))
                    .tint(.pink)
                HStack {
                    Label("\(snapshot.myTaps)", systemImage: "person.fill")
                    Spacer()
                    Label("\(snapshot.partnerTaps)", systemImage: "person.fill")
                        .foregroundStyle(.purple)
                }
                .font(.caption.bold())
            }
        }
        .padding(16)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 38))
                .foregroundStyle(.pink)
            Text("Open Haka").font(.headline)
            Text("Connect your shared heart")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
    }
}

@main
struct HakaHeartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HakaHeartWidget", provider: HeartProvider()) { entry in
            HakaWidgetView(entry: entry)
        }
        .configurationDisplayName("Shared Heart")
        .description("See your shared Haka heart and both partners’ taps.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
