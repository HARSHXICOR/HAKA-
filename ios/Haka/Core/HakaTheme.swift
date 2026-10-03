import SwiftUI

enum HakaPalette {
    static let background = Color(red: 0.07, green: 0.04, blue: 0.08)
    static let backgroundBottom = Color(red: 0.15, green: 0.06, blue: 0.11)
    static let deepRose = Color(red: 0.82, green: 0.09, blue: 0.27)
    static let rose = Color(red: 1.00, green: 0.36, blue: 0.52)
    static let softRose = Color(red: 1.00, green: 0.61, blue: 0.71)
    static let purple = Color(red: 0.76, green: 0.36, blue: 1.00)
    static let green = Color(red: 0.29, green: 0.87, blue: 0.47)
    static let muted = Color(red: 0.79, green: 0.74, blue: 0.78)
    static let panel = Color.white.opacity(0.075)
    static let line = Color.white.opacity(0.14)
}

struct HakaBackground: View {
    var bottom = HakaPalette.backgroundBottom
    var body: some View {
        LinearGradient(colors: [HakaPalette.background, bottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct HakaCard<Content: View>: View {
    var accent: Color = HakaPalette.line
    @ViewBuilder var content: Content

    init(accent: Color = HakaPalette.line, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.54), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(accent.opacity(0.55), lineWidth: 1)
            }
    }
}

struct HakaPrimaryButtonStyle: ButtonStyle {
    var color = HakaPalette.rose
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func hakaPage(bottom: Color = HakaPalette.backgroundBottom) -> some View {
        background { HakaBackground(bottom: bottom) }
            .foregroundStyle(.white)
            .preferredColorScheme(.dark)
    }
}
