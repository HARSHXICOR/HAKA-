import SwiftUI

struct HomeHeader: View {
    let displayName: String?
    let streak: Int

    var body: some View {
        HStack {
            ZStack {
                Circle().fill(HakaPalette.rose.opacity(0.2))
                Circle().stroke(HakaPalette.rose, lineWidth: 2)
                Text((displayName?.first.map(String.init) ?? "H").uppercased())
                    .font(.title2.bold())
            }
            .frame(width: 58, height: 58)

            Spacer()
            VStack(spacing: 3) {
                Text("Haka").font(.title.bold())
                Text("🔥 \(streak) day streak")
                    .foregroundStyle(HakaPalette.muted)
            }
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.title2)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(HakaPalette.line))
                .accessibilityLabel("Couple")
        }
    }
}

struct HomeConnectionBadge: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connected ? HakaPalette.green : Color.orange)
                .frame(width: 13, height: 13)
                .shadow(color: connected ? HakaPalette.green : .orange, radius: 6)
            Text(connected ? String(localized: "Connected") : String(localized: "Offline"))
                .font(.headline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(HakaPalette.rose.opacity(0.3)))
    }
}

struct ThinkingOfYouButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isBusy ? String(localized: "Sending…") : String(localized: "Thinking of You"), systemImage: "sparkles")
                .font(.subheadline.bold())
                .foregroundStyle(HakaPalette.softRose)
                .padding(.horizontal, 19)
                .padding(.vertical, 10)
                .background(HakaPalette.rose.opacity(0.09), in: Capsule())
                .overlay(Capsule().stroke(HakaPalette.rose.opacity(0.65)))
        }
        .disabled(isBusy)
    }
}

struct HomeStats: View {
    let myTaps: Int
    let totalTaps: Int
    let partnerTaps: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                HomeStatCard(title: "You", value: myTaps, color: HakaPalette.rose, icon: "person.fill")
                HomeStatCard(title: "Today", value: totalTaps, color: HakaPalette.softRose, icon: "chart.bar.fill")
                HomeStatCard(title: "Partner", value: partnerTaps, color: HakaPalette.purple, icon: "person.fill")
            }
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    HomeStatCard(title: "You", value: myTaps, color: HakaPalette.rose, icon: "person.fill")
                    HomeStatCard(title: "Partner", value: partnerTaps, color: HakaPalette.purple, icon: "person.fill")
                }
                HomeStatCard(title: "Today", value: totalTaps, color: HakaPalette.softRose, icon: "chart.bar.fill")
            }
        }
    }
}

private struct HomeStatCard: View {
    let title: String
    let value: Int
    let color: Color
    let icon: String

    var body: some View {
        HakaCard(accent: color.opacity(0.42)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline).foregroundStyle(color)
                    Spacer()
                    Image(systemName: icon)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(color.opacity(0.7), in: Circle())
                }
                Text(value.formatted()).font(.system(size: 31, weight: .bold, design: .rounded))
                Text("taps").foregroundStyle(HakaPalette.muted)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.25), color], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                    .padding(.top, 4)
            }
        }
    }
}

struct HomeEncouragementCard: View {
    var body: some View {
        HakaCard(accent: HakaPalette.rose.opacity(0.35)) {
            HStack(spacing: 15) {
                Image(systemName: "heart.fill")
                    .font(.title)
                    .foregroundStyle(HakaPalette.rose)
                    .frame(width: 54, height: 54)
                    .background(HakaPalette.rose.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("You’re doing great!").font(.headline)
                    Text("Keep the love going 💕").foregroundStyle(HakaPalette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(HakaPalette.muted)
            }
        }
    }
}
