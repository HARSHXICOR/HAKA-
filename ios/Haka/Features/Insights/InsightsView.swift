import Charts
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var model: HakaAppModel

    var body: some View {
        ZStack {
            HakaBackground(bottom: Color(red: 0.13, green: 0.06, blue: 0.11))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Insights").font(.largeTitle.bold())
                        Text("Today, streaks, and shared progress.")
                            .font(.title3)
                            .foregroundStyle(HakaPalette.muted)
                    }

                    todayCard
                    streakCard
                    contributionCard
                    weekCard

                    Text("Daily History").font(.title2.bold()).padding(.top, 2)
                    if model.history.isEmpty {
                        HakaCard {
                            Label("Your daily summaries will appear here.", systemImage: "calendar")
                                .foregroundStyle(HakaPalette.muted)
                        }
                    } else {
                        ForEach(model.history) { summary in
                            HistoryRow(summary: summary)
                        }
                    }

                    Label("Only daily totals are shown to protect your privacy.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(HakaPalette.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                }
                .padding(20)
            }
            .refreshable { await model.refresh() }
        }
        .navigationBarHidden(true)
    }

    private var todayCard: some View {
        HakaCard(accent: HakaPalette.rose) {
            HStack(spacing: 18) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(HakaPalette.rose)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Today").font(.headline).foregroundStyle(HakaPalette.softRose)
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(model.totalTaps) taps").font(.title.bold())
                        Spacer()
                        Text(model.today?.completed == true ? "Completed" : "In progress")
                            .foregroundStyle(model.today?.completed == true ? HakaPalette.green : HakaPalette.softRose)
                    }
                    ProgressView(value: model.today?.completed == true ? 1 : min(1, Double(model.totalTaps) / 100))
                        .tint(HakaPalette.rose)
                }
            }
        }
    }

    private var streakCard: some View {
        HakaCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    StreakMetric(icon: "flame.fill", title: "Current streak", value: model.streak?.current ?? 0, color: HakaPalette.rose)
                    Divider().overlay(HakaPalette.line)
                    StreakMetric(icon: "trophy.fill", title: "Longest streak", value: model.streak?.longest ?? 0, color: HakaPalette.purple)
                }
                VStack(spacing: 18) {
                    StreakMetric(icon: "flame.fill", title: "Current streak", value: model.streak?.current ?? 0, color: HakaPalette.rose)
                    StreakMetric(icon: "trophy.fill", title: "Longest streak", value: model.streak?.longest ?? 0, color: HakaPalette.purple)
                }
            }
        }
    }

    private var contributionCard: some View {
        let total = max(1, model.myTaps + model.partnerTaps)
        let mine = Int((Double(model.myTaps) / Double(total) * 100).rounded())
        return HakaCard(accent: HakaPalette.rose.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Today’s Progress").font(.title3.bold())
                HStack(spacing: 18) {
                    Contribution(title: "You", taps: model.myTaps, percent: mine, color: HakaPalette.rose)
                    ZStack {
                        Circle().stroke(HakaPalette.purple.opacity(0.38), lineWidth: 16)
                        Circle()
                            .trim(from: 0, to: Double(mine) / 100)
                            .stroke(HakaPalette.rose, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "heart.fill").foregroundStyle(HakaPalette.softRose)
                    }
                    .frame(width: 112, height: 112)
                    Contribution(title: "Partner", taps: model.partnerTaps, percent: 100 - mine, color: HakaPalette.purple, trailing: true)
                }
                Text("You and your partner are filling the heart together 💕")
                    .foregroundStyle(HakaPalette.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var weekCard: some View {
        let values = weeklyValues
        let average = values.isEmpty ? 0 : values.map(\.taps).reduce(0, +) / values.count
        return HakaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("This Week").font(.title3.bold())
                    Spacer()
                    Text("7 Days")
                        .font(.subheadline)
                        .foregroundStyle(HakaPalette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                if values.isEmpty {
                    Text("Tap together to start this week’s progress.")
                        .foregroundStyle(HakaPalette.muted)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    Chart(values) { item in
                        BarMark(
                            x: .value("Day", item.label),
                            y: .value("Taps", item.taps)
                        )
                        .foregroundStyle(item.today ? HakaPalette.rose : HakaPalette.purple.opacity(0.72))
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(item.taps)").font(.caption2).foregroundStyle(HakaPalette.muted)
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(HakaPalette.line); AxisValueLabel() } }
                    .frame(height: 190)
                }
                HStack {
                    Label("Shared activity from real daily totals", systemImage: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(HakaPalette.muted)
                    Spacer()
                    Text("Avg: \(average) taps").foregroundStyle(HakaPalette.softRose).fontWeight(.semibold)
                }
                .font(.footnote)
            }
        }
    }

    private var weeklyValues: [WeekValue] {
        let calendar = Calendar.current
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let source = model.history + (model.today.map {
            [DailySummaryDTO(date: $0.date, tapsByUser: $0.tapsByUser, myTaps: $0.myTaps, partnerTaps: $0.partnerTaps, totalTaps: $0.totalTaps, completed: $0.completed, completedAt: $0.completedAt)]
        } ?? [])
        return source.compactMap { summary -> (Date, DailySummaryDTO)? in
            parser.date(from: summary.date).map { ($0, summary) }
        }
        .filter { calendar.dateComponents([.day], from: $0.0, to: .now).day.map { 0...6 ~= $0 } ?? false }
        .sorted { $0.0 < $1.0 }
        .map {
            WeekValue(
                id: $0.1.date,
                label: $0.0.formatted(.dateTime.weekday(.abbreviated)),
                taps: $0.1.totalTaps,
                today: calendar.isDateInToday($0.0)
            )
        }
    }
}

private struct StreakMetric: View {
    let icon: String
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 50, height: 50)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(HakaPalette.muted)
                Text("\(value) days").font(.title2.bold()).foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Contribution: View {
    let title: String
    let taps: Int
    let percent: Int
    let color: Color
    var trailing = false

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(title).foregroundStyle(color).font(.headline)
            Text("\(taps)").font(.title.bold()).foregroundStyle(color)
            Text("taps").foregroundStyle(HakaPalette.muted)
            Text("\(percent)%")
                .font(.caption.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(color.opacity(0.16), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

private struct HistoryRow: View {
    let summary: DailySummaryDTO

    var body: some View {
        HakaCard {
            HStack(spacing: 14) {
                VStack(spacing: 1) {
                    Text(day).font(.headline)
                    Text(month).font(.caption)
                }
                .frame(width: 52, height: 52)
                .background(HakaPalette.rose.opacity(0.14), in: Circle())
                .overlay(Circle().stroke(HakaPalette.rose.opacity(0.5)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(summary.totalTaps) taps").font(.headline)
                    Text(summary.completed ? "Completed" : "In progress")
                        .foregroundStyle(summary.completed ? HakaPalette.green : HakaPalette.softRose)
                }
                Spacer()
                Image(systemName: "heart.fill").foregroundStyle(HakaPalette.rose)
                Image(systemName: "chevron.right").foregroundStyle(HakaPalette.muted)
            }
        }
    }

    private var components: [String] {
        guard let date = ISO8601DateFormatter.hakaDay.date(from: summary.date) else { return ["—", ""] }
        return [date.formatted(.dateTime.day()), date.formatted(.dateTime.month(.abbreviated))]
    }
    private var day: String { components[0] }
    private var month: String { components[1] }
}

private struct WeekValue: Identifiable {
    let id: String
    let label: String
    let taps: Int
    let today: Bool
}

private extension ISO8601DateFormatter {
    static let hakaDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
