import SwiftUI

struct LoveView: View {
    @EnvironmentObject private var model: HakaAppModel
    @State private var composing = false
    @State private var note = ""

    var body: some View {
        ZStack {
            HakaBackground(bottom: Color(red: 0.16, green: 0.06, blue: 0.13))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Love").font(.largeTitle.bold())
                    Text("A private space for the little things you share.")
                        .font(.title3)
                        .foregroundStyle(HakaPalette.muted)

                    LoveActionCard(
                        icon: "heart.fill",
                        color: HakaPalette.rose,
                        title: "Love Notes",
                        subtitle: "Send a private note that stays between you and your partner.",
                        button: "Write a Love Note"
                    ) { composing = true }

                    LoveActionCard(
                        icon: "sparkles",
                        color: HakaPalette.purple,
                        title: "Thinking of You",
                        subtitle: "Send a small private nudge to your partner.",
                        button: model.isBusy ? "Sending…" : "Send Thinking of You"
                    ) {
                        Task { await model.sendThinkingOfYou() }
                    }

                    moodCard

                    HStack {
                        Text("Recent notes").font(.title2.bold())
                        Spacer()
                        if model.isBusy { ProgressView().tint(HakaPalette.rose) }
                    }
                    if model.loveNotes.isEmpty {
                        HakaCard {
                            VStack(spacing: 8) {
                                Image(systemName: "envelope.heart.fill")
                                    .font(.title)
                                    .foregroundStyle(HakaPalette.rose)
                                Text("No Love Notes yet").font(.headline)
                                Text("Your private notes will appear here.")
                                    .foregroundStyle(HakaPalette.muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(model.loveNotes) { item in
                            LoveNoteCard(note: item, sentByMe: item.senderUid == model.userID)
                        }
                    }
                }
                .padding(20)
            }
            .refreshable { await model.loadLove() }
        }
        .navigationBarHidden(true)
        .task { await model.loadLove() }
        .sheet(isPresented: $composing) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $note)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 170)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(HakaPalette.line))
                        .onChange(of: note) { value in
                            if value.count > 160 { note = String(value.prefix(160)) }
                        }
                    Text("\(note.count)/160")
                        .font(.caption)
                        .foregroundStyle(HakaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer()
                }
                .padding()
                .hakaPage()
                .navigationTitle("Write a Love Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { composing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send 💌") {
                            let value = note
                            note = ""
                            composing = false
                            Task { await model.sendLoveNote(value) }
                        }
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .foregroundStyle(HakaPalette.rose)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var moodCard: some View {
        let options = [
            ("happy", "😊"), ("loved", "🥰"), ("calm", "😌"), ("missing", "🥺"), ("tired", "😴")
        ]
        let mine = model.moods[model.userID]
        let partner = model.partnerID.flatMap { model.moods[$0] }
        return HakaCard(accent: HakaPalette.green.opacity(0.45)) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 13) {
                    Text("☀️")
                        .font(.title)
                        .frame(width: 50, height: 50)
                        .background(HakaPalette.green.opacity(0.12), in: Circle())
                    VStack(alignment: .leading) {
                        Text("Daily Mood").font(.title3.bold())
                        Text("How are you feeling today?").foregroundStyle(HakaPalette.muted)
                    }
                }
                HStack {
                    ForEach(options, id: \.0) { option in
                        Button {
                            Task { await model.setMood(option.0) }
                        } label: {
                            Text(option.1)
                                .font(.title3)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(
                                    mine == option.0 ? HakaPalette.rose.opacity(0.28) : Color.white.opacity(0.055),
                                    in: Circle()
                                )
                                .overlay(Circle().stroke(mine == option.0 ? HakaPalette.rose : HakaPalette.line))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("Partner").foregroundStyle(HakaPalette.muted)
                    Spacer()
                    Text(partner.map(moodLabel) ?? "Not shared yet")
                        .foregroundStyle(partner == nil ? HakaPalette.muted : HakaPalette.purple)
                        .fontWeight(.semibold)
                }
                .padding(12)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func moodLabel(_ value: String) -> String {
        switch value {
        case "happy": "😊 Happy"
        case "loved": "🥰 Loved"
        case "calm": "😌 Calm"
        case "missing": "🥺 Missing you"
        case "tired": "😴 Tired"
        default: value.capitalized
        }
    }
}

private struct LoveActionCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let button: String
    let action: () -> Void

    var body: some View {
        HakaCard(accent: color.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                        .frame(width: 54, height: 54)
                        .background(color.opacity(0.13), in: Circle())
                    Text(title).font(.title2.bold())
                }
                Text(subtitle)
                    .foregroundStyle(HakaPalette.muted)
                    .font(.body)
                Button(button, action: action)
                    .buttonStyle(HakaPrimaryButtonStyle(color: color))
            }
        }
    }
}

private struct LoveNoteCard: View {
    let note: LoveNoteDTO
    let sentByMe: Bool

    var body: some View {
        HakaCard(accent: (sentByMe ? HakaPalette.rose : HakaPalette.purple).opacity(0.38)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "heart.fill")
                    Text(sentByMe ? "You" : "Your partner").fontWeight(.semibold)
                    Spacer()
                    Text(Date(timeIntervalSince1970: TimeInterval(note.createdAt)).formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(HakaPalette.muted)
                }
                .foregroundStyle(sentByMe ? HakaPalette.rose : HakaPalette.purple)
                Text(note.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }
}
