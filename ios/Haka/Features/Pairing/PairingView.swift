import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: HakaAppModel
    @State private var mode = 0
    @State private var name = ""
    @State private var code = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 34)
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(HakaPalette.rose)
                    .shadow(color: HakaPalette.rose.opacity(0.45), radius: 20)
                Text("Haka").font(.system(size: 42, weight: .bold, design: .rounded))

                if model.phase == .waitingForPartner, let invite = model.inviteCode {
                    waiting(invite)
                } else {
                    setup
                }

                if let message = model.message {
                    Text(message)
                        .foregroundStyle(HakaPalette.softRose)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .hakaPage()
    }

    @ViewBuilder
    private var setup: some View {
        Picker("Pairing mode", selection: $mode) {
            Text("Create").tag(0)
            Text("Join").tag(1)
        }
        .pickerStyle(.segmented)

        VStack(spacing: 8) {
            Text(mode == 0 ? "Create your Haka" : "Join your Haka")
                .font(.title2.bold())
            Text(mode == 0 ? "You’ll get a private code for your partner." : "Enter the code your partner shared.")
                .foregroundStyle(HakaPalette.muted)
                .multilineTextAlignment(.center)
        }

        HakaCard(accent: HakaPalette.rose.opacity(0.5)) {
            VStack(spacing: 16) {
                if mode == 0 {
                    TextField("Your name (optional)", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .padding(14)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    TextField("ABCD-EFGH", text: Binding(
                        get: { code },
                        set: { code = HakaAppModel.formatInvite($0) }
                    ))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3.monospaced().weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    Task {
                        if mode == 0 { await model.createCouple(name: name) }
                        else { await model.redeemInvite(code) }
                    }
                } label: {
                    if model.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text(mode == 0 ? "Create invite" : "Join Haka")
                    }
                }
                .buttonStyle(HakaPrimaryButtonStyle())
                .disabled(model.isBusy || (mode == 1 && code.count != 9))
            }
        }
    }

    private func waiting(_ invite: String) -> some View {
        VStack(spacing: 18) {
            Text("Invite your partner").font(.title2.bold())
            Text("Both of you will enter the shared heart together after your partner joins.")
                .foregroundStyle(HakaPalette.muted)
                .multilineTextAlignment(.center)
            Text(invite)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(HakaPalette.softRose)
                .padding(.vertical, 8)
                .textSelection(.enabled)
            HStack {
                Button {
                    UIPasteboard.general.string = invite
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HakaPalette.rose)

                ShareLink(item: "Join my Haka with code \(invite)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(HakaPalette.softRose)
            }
            if let expiry = model.inviteExpiresAt {
                Text("Expires \(expiry, style: .relative)")
                    .font(.footnote)
                    .foregroundStyle(HakaPalette.muted)
            }
            ProgressView("Waiting for your partner…")
                .tint(HakaPalette.rose)
                .foregroundStyle(HakaPalette.muted)
                .padding(.top, 8)
        }
    }
}
