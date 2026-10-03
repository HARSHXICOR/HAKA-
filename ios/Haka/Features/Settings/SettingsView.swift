import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: HakaAppModel
    @State private var signingOut = false

    var body: some View {
        ZStack {
            HakaBackground(bottom: Color(red: 0.13, green: 0.06, blue: 0.11))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings").font(.largeTitle.bold())

                    SectionTitle("Account")
                    SettingsLine(icon: "person.fill", color: HakaPalette.rose, title: model.displayName ?? "Anonymous Haka account")
                    protectCard
                    SettingsLine(icon: "person.2.fill", color: HakaPalette.green, title: "Connection: \(model.connected ? "Connected" : "Waiting for partner")")
                    SettingsLine(icon: "globe", color: HakaPalette.purple, title: "Timezone: \(model.timezone ?? TimeZone.current.identifier)")

                    Divider().overlay(HakaPalette.line)
                    SectionTitle("Notifications")
                    HakaCard {
                        HStack(spacing: 15) {
                            SettingsIcon(icon: "bell.fill", color: HakaPalette.rose)
                            Text("Partner activity").font(.headline)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.notifications.enabled },
                                set: { value in Task { await model.notifications.setEnabled(value) } }
                            ))
                            .labelsHidden()
                            .tint(HakaPalette.rose)
                        }
                    }

                    Divider().overlay(HakaPalette.line)
                    SectionTitle("Privacy")
                    HakaCard {
                        HStack(spacing: 15) {
                            SettingsIcon(icon: "lock.fill", color: HakaPalette.rose)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Haka is private to you and your partner.").font(.headline)
                                Text("We never share your data with anyone.").foregroundStyle(HakaPalette.muted)
                            }
                        }
                    }

                    Button(role: .destructive) { signingOut = true } label: {
                        HStack(spacing: 15) {
                            SettingsIcon(icon: "rectangle.portrait.and.arrow.right", color: HakaPalette.rose)
                            Text("Sign out").font(.headline).foregroundStyle(HakaPalette.softRose)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(HakaPalette.muted)
                        }
                        .padding(18)
                        .background(HakaPalette.rose.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(HakaPalette.rose.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
                .padding(20)
            }
        }
        .navigationBarHidden(true)
        .task { await model.notifications.refreshAuthorization() }
        .confirmationDialog("Sign out of Haka?", isPresented: $signingOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your shared heart stays safely in Supabase.")
        }
    }

    private var protectCard: some View {
        HakaCard(accent: HakaPalette.rose.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    SettingsIcon(icon: "shield.checkered", color: HakaPalette.rose)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Protect your Haka").font(.title3.bold())
                        Text("Link Google before changing phones.").foregroundStyle(HakaPalette.muted)
                    }
                }
                Text("Your existing couple and heart stay attached to the same Supabase user.")
                    .foregroundStyle(HakaPalette.muted)
                Button {
                    Task { await model.linkGoogle() }
                } label: {
                    Label(model.isBusy ? "Connecting…" : "Secure with Google", systemImage: "g.circle.fill")
                }
                .buttonStyle(HakaPrimaryButtonStyle())
                .disabled(model.isBusy)
            }
        }
    }
}

private struct SectionTitle: View {
    let value: String
    init(_ value: String) { self.value = value }
    var body: some View {
        Text(value).font(.title3.bold()).foregroundStyle(HakaPalette.softRose)
    }
}

private struct SettingsLine: View {
    let icon: String
    let color: Color
    let title: String
    var body: some View {
        HStack(spacing: 15) {
            SettingsIcon(icon: icon, color: color)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(HakaPalette.muted)
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsIcon: View {
    let icon: String
    let color: Color
    var body: some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 52, height: 52)
            .background(color.opacity(0.13), in: Circle())
    }
}
