import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var model: HakaAppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 70)
                ZStack {
                    Circle()
                        .fill(HakaPalette.rose.opacity(0.13))
                        .frame(width: 154, height: 154)
                        .blur(radius: 16)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 82, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [HakaPalette.softRose, HakaPalette.rose, HakaPalette.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: HakaPalette.rose.opacity(0.55), radius: 24)
                }
                VStack(spacing: 10) {
                    Text("Welcome to Haka")
                        .font(.largeTitle.bold())
                    Text("One shared heart for two people.")
                        .font(.title3)
                        .foregroundStyle(HakaPalette.muted)
                }
                Spacer(minLength: 34)
                VStack(spacing: 13) {
                    Button {
                        Task { await model.continueWithGoogle() }
                    } label: {
                        Label("Continue with Google", systemImage: "g.circle.fill")
                    }
                    .buttonStyle(HakaPrimaryButtonStyle())
                    .disabled(model.isBusy)

                    Button {
                        Task { await model.continueAnonymously() }
                    } label: {
                        Text("Continue without Google")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.22))
                    .disabled(model.isBusy)

                    Text("Google keeps the same Haka when you change phones. You can link it later from Settings.")
                        .font(.footnote)
                        .foregroundStyle(HakaPalette.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                if model.isBusy {
                    ProgressView().tint(HakaPalette.rose)
                }
                if let message = model.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(HakaPalette.softRose)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
        }
        .hakaPage()
    }
}
