import SwiftUI

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

struct LiquidHeartView: View {
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
                                Gradient(colors: [HakaPalette.softRose, HakaPalette.rose, HakaPalette.deepRose]),
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

struct HeartParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let size: CGFloat
    let drift: CGFloat
}

struct TapHeartParticle: View {
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

struct FullHeartRain: View {
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
