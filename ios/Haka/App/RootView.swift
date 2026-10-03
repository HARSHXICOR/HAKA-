import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: HakaAppModel

    var body: some View {
        ZStack {
            HakaBackground()
            switch model.phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(HakaPalette.rose)
                    .accessibilityLabel("Loading Haka")
            case .authentication:
                AuthView()
            case .pairing, .waitingForPartner:
                PairingView()
            case .paired:
                MainTabs()
            case .failed(let message):
                StateMessageView(title: "Couldn’t open Haka", message: message, button: "Try again") {
                    Task { await model.refresh(showLoading: true) }
                }
            case .configuration(let message):
                StateMessageView(title: "Connect Supabase", message: message, button: nil, action: {})
            }
        }
        .overlay(alignment: .top) {
            if let message = model.message, model.phase == .paired {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(HakaPalette.rose.opacity(0.45)))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.message = nil }
            }
        }
        .animation(.snappy, value: model.phase)
        .preferredColorScheme(.dark)
    }
}

private struct MainTabs: View {
    @EnvironmentObject private var model: HakaAppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { HomeView() }
                .tag(0)
                .tabItem { Label("Heart", systemImage: "heart.fill") }
            NavigationStack { InsightsView() }
                .tag(1)
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
            NavigationStack { LoveView() }
                .tag(2)
                .tabItem { Label("Love", systemImage: "heart.text.square.fill") }
            NavigationStack { StoryView() }
                .tag(3)
                .tabItem { Label("Us", systemImage: "heart.circle.fill") }
            NavigationStack { SettingsView() }
                .tag(4)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(HakaPalette.rose)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: model.selectedTab) { newValue in
            if newValue == 2 { Task { await model.loadLove() } }
            if newValue == 3 { Task { await model.loadStory() } }
        }
    }
}

private struct StateMessageView: View {
    let title: String
    let message: String
    let button: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(HakaPalette.rose)
            Text(title).font(.largeTitle.bold())
            Text(message)
                .foregroundStyle(HakaPalette.muted)
                .multilineTextAlignment(.center)
            if let button {
                Button(button, action: action)
                    .buttonStyle(HakaPrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
    }
}
