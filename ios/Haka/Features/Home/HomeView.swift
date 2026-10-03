import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: HakaAppModel
    @State private var particles: [HeartParticle] = []
    @State private var rainToken = 0
    @State private var wasFull = false

    var body: some View {
        ZStack {
            HakaBackground(bottom: Color(red: 0.15, green: 0.06, blue: 0.11))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    connection
                    thinkingButton
                    LiquidHeartView(fraction: model.heartFraction, percentage: Int(model.heartFraction * 100))
                        .frame(maxWidth: 430)
                        .aspectRatio(1.07, contentMode: .fit)
                        .contentShape(HeartShape())
                        .onTapGesture { tapped() }
                        .accessibilityLabel("Shared heart, \(Int(model.heartFraction * 100)) percent")
                        .accessibilityHint("Double tap to add love")

                    VStack(spacing: 5) {
                        Text("\(model.effectiveScore.formatted()) / \((model.heart?.maxScore ?? 10_000).formatted())")
                            .font(.title.bold())
                            .foregroundStyle(HakaPalette.softRose)
                        Label("Keep tapping to fill our heart", systemImage: "sparkles")
                            .foregroundStyle(HakaPalette.muted)
                    }

                    stats
                    encouragement
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
            let full = newValue >= (model.heart?.maxScore ?? 10_000)
            if full && !wasFull {
                rainToken += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { rainToken = 0 }
            }
            wasFull = full
        }
    }

    private var header: some View {
        HStack {
            ZStack {
                Circle().fill(HakaPalette.rose.opacity(0.2))
                Circle().stroke(HakaPalette.rose, lineWidth: 2)
                Text((model.displayName?.first.map(String.init) ?? "H").uppercased())
                    .font(.title2.bold())
            }
            .frame(width: 58, height: 58)

            Spacer()
            VStack(spacing: 3) {
                Text("Haka").font(.title.bold())
                Text("🔥 \(model.streak?.current ?? 0) day streak")
                    .foregroundStyle(HakaPalette.muted)
            }
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.title2)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(HakaPalette.line))
        }
    }

    private var connection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.connected ? HakaPalette.green : Color.orange)
                .frame(width: 13, height: 13)
                .shadow(color: model.connected ? HakaPalette.green : .orange, radius: 6)
            Text(model.connected ? "Connected" : "Offline")
                .font(.headline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(HakaPalette.rose.opacity(0.3)))
    }

    private var thinkingButton: some View {
        Button {
            Task { await model.sendThinkingOfYou() }
        } label: {
            Label(model.isBusy ? "Sending…" : "Thinking of You", systemImage: "sparkles")
                .font(.subheadline.bold())
                .foregroundStyle(HakaPalette.softRose)
                .padding(.horizontal, 19)
                .padding(.vertical, 10)
                .background(HakaPalette.rose.opacity(0.09), in: Capsule())
                .overlay(Capsule().stroke(HakaPalette.rose.opacity(0.65)))
        }
        .disabled(model.isBusy)
    }

    @ViewBuilder
    private var stats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                StatCard(title: "You", value: model.myTaps, color: HakaPalette.rose, icon: "person.fill")
                StatCard(title: "Today", value: model.totalTaps, color: HakaPalette.softRose, icon: "chart.bar.fill")
                StatCard(title: "Partner", value: model.partnerTaps, color: HakaPalette.purple, icon: "person.fill")
            }
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatCard(title: "You", value: model.myTaps, color: HakaPalette.rose, icon: "person.fill")
                    StatCard(title: "Partner", value: model.partnerTaps, color: HakaPalette.purple, icon: "person.fill")
                }
                StatCard(title: "Today", value: model.totalTaps, color: HakaPalette.softRose, icon: "chart.bar.fill")
            }
        }
    }

    private var encouragement: some View {
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

private struct StatCard: View {
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

struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.93))
        path.addCurve(
            to: CGPoint(x: w * 0.05, y: h * 0.34),
            control1: CGPoint(x: w * 0.42, y: h * 0.85),
            control2: CGPoint(x: w * 0.05, y: h * 0.65)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.21),
            control1: CGPoint(x: w * 0.04, y: h * 0.03),
            control2: CGPoint(x: w * 0.37, y: h * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.95, y: h * 0.34),
            control1: CGPoint(x: w * 0.63, y: h * 0.02),
            control2: CGPoint(x: w * 0.96, y: h * 0.03)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.93),
            control1: CGPoint(x: w * 0.95, y: h * 0.65),
            control2: CGPoint(x: w * 0.58, y: h * 0.85)
        )
        return path
    }
}

private struct LiquidHeartView: View {
    let fraction: Double
    let percentage: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            GeometryReader { proxy in
                let rect = CGRect(origin: .zero, size: proxy.size)
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    HeartShape()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.13), HakaPalette.rose.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Canvas { context, size in
                        let heart = HeartShape().path(in: CGRect(origin: .zero, size: size))
                        context.clip(to: heart)
                        let usableHeight = size.height * 0.77
                        let base = size.height * 0.88 - usableHeight * fraction
                        var liquid = Path()
                        liquid.move(to: CGPoint(x: 0, y: size.height))
                        liquid.addLine(to: CGPoint(x: 0, y: base))
                        let segments = 50
                        for index in 0...segments {
                            let x = size.width * CGFloat(index) / CGFloat(segments)
                            let wave = sin(Double(index) * 0.34 + time * 2.4) * 8
                            liquid.addLine(to: CGPoint(x: x, y: base + wave))
                        }
                        liquid.addLine(to: CGPoint(x: size.width, y: size.height))
                        liquid.closeSubpath()
                        context.fill(
                            liquid,
                            with: .linearGradient(
                                Gradient(colors: [HakaPalette.softRose, HakaPalette.rose, Color(red: 0.82, green: 0.09, blue: 0.27)]),
                                startPoint: CGPoint(x: size.width * 0.5, y: base),
                                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
                            )
                        )
                    }
                    HeartShape()
                        .stroke(
                            LinearGradient(colors: [Color.white.opacity(0.8), HakaPalette.softRose, HakaPalette.rose], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 3
                        )
                        .shadow(color: HakaPalette.rose.opacity(0.52), radius: 18)
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: rect.width * 0.13, height: rect.height * 0.34)
                        .rotationEffect(.degrees(21))
                        .offset(x: -rect.width * 0.26, y: -rect.height * 0.16)

                    VStack(spacing: 2) {
                        HStack(alignment: .lastTextBaseline, spacing: 1) {
                            Text(percentage.formatted())
                                .font(.system(size: min(74, rect.width * 0.19), weight: .bold, design: .rounded))
                            Text("%").font(.title.bold())
                        }
                        Text("of our heart").font(.title3)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                }
            }
        }
    }
}

private struct HeartParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let size: CGFloat
    let drift: CGFloat
}

private struct TapHeartParticle: View {
    let particle: HeartParticle
    @State private var animate = false

    var body: some View {
        GeometryReader { proxy in
            Image(systemName: "heart.fill")
                .font(.system(size: particle.size))
                .foregroundStyle(HakaPalette.rose)
                .shadow(color: HakaPalette.rose, radius: 8)
                .position(
                    x: proxy.size.width * particle.x + (animate ? particle.drift : 0),
                    y: proxy.size.height * 0.53 + (animate ? -240 : 20)
                )
                .opacity(animate ? 0 : 1)
                .scaleEffect(animate ? 1.35 : 0.55)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.05).delay(particle.delay)) { animate = true }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct FullHeartRain: View {
    let token: Int
    @State private var animate = false

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<34, id: \.self) { index in
                Image(systemName: "heart.fill")
                    .font(.system(size: CGFloat(14 + index % 19)))
                    .foregroundStyle(index.isMultiple(of: 3) ? HakaPalette.purple : HakaPalette.rose)
                    .position(
                        x: proxy.size.width * CGFloat((index * 37) % 100) / 100,
                        y: animate ? proxy.size.height + 80 : -80 - CGFloat((index * 53) % 260)
                    )
                    .rotationEffect(.degrees(animate ? Double(index * 43) : 0))
                    .animation(.easeIn(duration: 1.5 + Double(index % 5) * 0.13).delay(Double(index % 8) * 0.05), value: animate)
            }
        }
        .id(token)
        .ignoresSafeArea()
        .onAppear { animate = true }
    }
}
