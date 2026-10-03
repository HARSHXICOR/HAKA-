import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: HakaAppModel
    @State private var particles: [HeartParticle] = []
    @State private var rainToken = 0
    @State private var wasFull = false

    var body: some View {
        ZStack {
            HakaBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HomeHeader(displayName: model.displayName, streak: model.streak?.current ?? 0)
                    HomeConnectionBadge(connected: model.connected)
                    ThinkingOfYouButton(isBusy: model.isBusy) {
                        Task { await model.sendThinkingOfYou() }
                    }

                    Button(action: tapped) {
                        LiquidHeartView(fraction: model.heartFraction, percentage: model.heartPercentage)
                            .frame(maxWidth: 430)
                            .aspectRatio(1.07, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                    .contentShape(HeartShape())
                    .accessibilityLabel("Shared heart")
                    .accessibilityValue("\(model.heartPercentage) percent full")
                    .accessibilityHint("Double tap to add love")

                    VStack(spacing: 5) {
                        Text("\(model.effectiveScore.formatted()) / \(model.heartMaximumScore.formatted())")
                            .font(.title.bold())
                            .foregroundStyle(HakaPalette.softRose)
                        Label("Keep tapping to fill our heart", systemImage: "sparkles")
                            .foregroundStyle(HakaPalette.muted)
                    }

                    HomeStats(myTaps: model.myTaps, totalTaps: model.totalTaps, partnerTaps: model.partnerTaps)
                    HomeEncouragementCard()
                    Label("Synced automatically with your partner", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(HakaPalette.muted)
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .refreshable { await model.refresh() }

            ForEach(particles) { particle in
                TapHeartParticle(particle: particle)
            }

            if rainToken > 0 {
                FullHeartRain(token: rainToken)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .onChange(of: model.effectiveScore) { newValue in
            let full = newValue >= model.heartMaximumScore
            if full && !wasFull {
                rainToken += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { rainToken = 0 }
            }
            wasFull = full
        }
    }

    private func tapped() {
        model.tapHeart()
        let created = (0..<5).map { index in
            HeartParticle(
                x: CGFloat.random(in: 0.16...0.84),
                delay: Double(index) * 0.045,
                size: CGFloat.random(in: 17...30),
                drift: CGFloat.random(in: -65...65)
            )
        }
        particles.append(contentsOf: created)
        let ids = Set(created.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            particles.removeAll { ids.contains($0.id) }
        }
    }
}
