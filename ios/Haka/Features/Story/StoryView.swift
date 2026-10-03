import PhotosUI
import SwiftUI

struct StoryView: View {
    @EnvironmentObject private var model: HakaAppModel
    @State private var section = 0
    @State private var addMemory = false
    @State private var addBucket = false
    @State private var addDate = false
    @State private var selectedMemory: MemoryDTO?
    @State private var selectedList: BucketListDTO?
    @State private var editingText: TextEditTarget?
    @State private var editingDate: RelationshipDateDTO?

    var body: some View {
        ZStack {
            HakaBackground(bottom: Color(red: 0.10, green: 0.06, blue: 0.13))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Us").font(.largeTitle.bold())
                            Text("Your private story, kept together.")
                                .foregroundStyle(HakaPalette.muted)
                        }
                        Spacer()
                        Button(action: addCurrent) {
                            Image(systemName: "plus")
                                .font(.title3.bold())
                                .frame(width: 44, height: 44)
                                .background(HakaPalette.rose, in: Circle())
                        }
                    }

                    Picker("Story section", selection: $section) {
                        Text("Memories").tag(0)
                        Text("Bucket List").tag(1)
                        Text("Dates").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case 0: memories
                    case 1: buckets
                    default: dates
                    }
                }
                .padding(20)
            }
            .refreshable { await model.loadStory() }
        }
        .navigationBarHidden(true)
        .task { await model.loadStory() }
        .sheet(isPresented: $addMemory) { MemoryEditor() }
        .sheet(isPresented: $addBucket) { BucketEditor() }
        .sheet(isPresented: $addDate) { RelationshipDateEditor() }
        .sheet(item: $selectedMemory) { MemoryDetail(memory: $0) }
        .sheet(item: $selectedList) { BucketListDetail(list: $0) }
        .sheet(item: $editingText) { TextEditSheet(target: $0) }
        .sheet(item: $editingDate) { RelationshipDateEditor(existing: $0) }
    }

    @ViewBuilder
    private var memories: some View {
        if model.story.memories.isEmpty {
            StoryEmpty(icon: "photo.on.rectangle.angled", text: "Add your first shared memory.")
        } else {
            LazyVStack(spacing: 14) {
                ForEach(model.story.memories) { memory in
                    Button { selectedMemory = memory } label: {
                        MemoryCard(memory: memory)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { selectedMemory = memory }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await model.deleteMemory(memory.id) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var buckets: some View {
        let standalone = model.story.bucketItems.filter { $0.listId == nil }
        if model.story.bucketLists.isEmpty && standalone.isEmpty {
            StoryEmpty(icon: "checklist", text: "Add something you want to do together.")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(model.story.bucketLists) { list in
                    let items = model.story.bucketItems.filter { $0.listId == list.id }
                    Button { selectedList = list } label: {
                        BucketListCard(list: list, items: items)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { editingText = .list(list) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await model.deleteBucketList(list.id) }
                        }
                    }
                }
                ForEach(standalone) { item in
                    BucketItemRow(item: item) { Task { await model.toggleBucket(item) } }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingText = .item(item) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.deleteBucket(item.id) }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var dates: some View {
        if model.story.dates.isEmpty {
            StoryEmpty(icon: "calendar.badge.heart", text: "Save an anniversary, birthday, or important date.")
        } else {
            LazyVStack(spacing: 12) {
                ForEach(model.story.dates) { item in
                    ImportantDateCard(item: item)
                        .onTapGesture { editingDate = item }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingDate = item }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.deleteDate(item.id) }
                            }
                        }
                }
                HakaCard(accent: HakaPalette.rose.opacity(0.5)) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Never miss an important day").font(.headline).foregroundStyle(HakaPalette.softRose)
                            Text("Haka checks your shared dates when the story syncs.").foregroundStyle(HakaPalette.muted)
                        }
                    } icon: { Text("💕").font(.title2) }
                }
            }
        }
    }

    private func addCurrent() {
        if section == 0 { addMemory = true }
        else if section == 1 { addBucket = true }
        else { addDate = true }
    }
}

private struct MemoryCard: View {
    let memory: MemoryDTO
    var body: some View {
        HakaCard(accent: HakaPalette.rose.opacity(0.36)) {
            VStack(alignment: .leading, spacing: 11) {
                if let value = memory.photoPaths.first, let url = URL(string: value) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Rectangle().fill(Color.white.opacity(0.06)).overlay { ProgressView() } }
                    }
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottomLeading) {
                        if memory.photoPaths.count > 1 {
                            Label("\(memory.photoPaths.count)", systemImage: "photo.stack")
                                .font(.caption.bold())
                                .padding(7)
                                .background(.black.opacity(0.62), in: Capsule())
                                .padding(9)
                        }
                    }
                }
                HStack {
                    Text(memory.title).font(.title3.bold())
                    Spacer()
                    Image(systemName: "heart.fill").foregroundStyle(HakaPalette.rose)
                }
                if !memory.caption.isEmpty {
                    Text(memory.caption).foregroundStyle(HakaPalette.muted).lineLimit(3)
                }
                Text(memory.occurredOn.map(prettyDay) ?? "No date")
                    .font(.caption)
                    .foregroundStyle(HakaPalette.softRose)
            }
        }
    }
}

private struct BucketItemRow: View {
    let item: BucketItemDTO
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 13) {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(item.completedAt == nil ? HakaPalette.muted : HakaPalette.rose)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(item.completedAt == nil ? .white : HakaPalette.muted)
                    .strikethrough(item.completedAt != nil)
                Spacer()
            }
            .padding(17)
            .background(HakaPalette.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(HakaPalette.line))
        }
        .buttonStyle(.plain)
    }
}

private struct BucketListCard: View {
    let list: BucketListDTO
    let items: [BucketItemDTO]
    var body: some View {
        let completed = items.filter { $0.completedAt != nil }.count
        return HakaCard(accent: HakaPalette.rose.opacity(0.35)) {
            VStack(spacing: 13) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(LinearGradient(colors: [HakaPalette.rose, HakaPalette.purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading) {
                        Text(list.title).font(.headline)
                        Text("\(items.count) items • \(completed) completed").font(.caption).foregroundStyle(HakaPalette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(HakaPalette.muted)
                }
                if !items.isEmpty {
                    ProgressView(value: Double(completed), total: Double(items.count)).tint(HakaPalette.rose)
                }
            }
        }
    }
}

private struct ImportantDateCard: View {
    let item: RelationshipDateDTO
    var body: some View {
        HakaCard(accent: HakaPalette.rose.opacity(0.34)) {
            HStack(spacing: 13) {
                Text(item.kind == "birthday" ? "🎁" : item.kind == "anniversary" ? "♥" : "▣")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(LinearGradient(colors: [HakaPalette.rose.opacity(0.7), HakaPalette.purple.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).font(.headline)
                    Text(prettyDay(item.occursOn)).font(.caption).foregroundStyle(HakaPalette.muted)
                    Text(item.kind.capitalized).font(.caption2).foregroundStyle(HakaPalette.muted)
                }
                Spacer()
                Text(relativeDay(item)).font(.subheadline.bold()).foregroundStyle(HakaPalette.softRose)
            }
        }
    }
}

private struct StoryEmpty: View {
    let icon: String
    let text: String
    var body: some View {
        HakaCard {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.largeTitle).foregroundStyle(HakaPalette.rose)
                Text(text).foregroundStyle(HakaPalette.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
        }
    }
}

private struct MemoryDetail: View {
    @EnvironmentObject private var model: HakaAppModel
    @Environment(\.dismiss) private var dismiss
    let memory: MemoryDTO
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TabView {
                        ForEach(memory.photoPaths, id: \.self) { value in
                            AsyncImage(url: URL(string: value)) { phase in
                                if let image = phase.image { image.resizable().scaledToFit() }
                                else { ProgressView() }
                            }
                        }
                    }
                    .frame(height: memory.photoPaths.isEmpty ? 0 : 400)
                    .tabViewStyle(.page)
                    Text(memory.title).font(.largeTitle.bold())
                    if let day = memory.occurredOn { Text(prettyDay(day)).foregroundStyle(HakaPalette.softRose) }
                    if !memory.caption.isEmpty { Text(memory.caption).font(.body) }
                }
                .padding()
            }
            .hakaPage(bottom: Color(red: 0.10, green: 0.06, blue: 0.13))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                    Button(role: .destructive) {
                        Task { await model.deleteMemory(memory.id); dismiss() }
                    } label: { Image(systemName: "trash") }
                }
            }
            .sheet(isPresented: $editing) { MemoryEditor(existing: memory) }
        }
    }
}

private struct MemoryEditor: View {
    @EnvironmentObject private var model: HakaAppModel
    @Environment(\.dismiss) private var dismiss
    var existing: MemoryDTO?
    @State private var title = ""
    @State private var caption = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var picks: [PhotosPickerItem] = []
    @State private var photos: [Data] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory") {
                    TextField("Title", text: $title)
                    TextField("Caption (optional)", text: $caption, axis: .vertical)
                    Toggle("Add a date", isOn: $hasDate)
                    if hasDate { DatePicker("Date", selection: $date, displayedComponents: .date) }
                }
                Section("Photos") {
                    PhotosPicker(selection: $picks, maxSelectionCount: max(0, 8 - (existing?.photoPaths.count ?? 0)), matching: .images) {
                        Label("Choose photos", systemImage: "photo.on.rectangle.angled")
                    }
                    if !photos.isEmpty { Text("\(photos.count) new photo(s) selected").foregroundStyle(HakaPalette.muted) }
                }
            }
            .scrollContentBackground(.hidden)
            .hakaPage()
            .navigationTitle(existing == nil ? "New memory" : "Edit memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let existing {
                                await model.updateMemory(existing, title: title, caption: caption, date: hasDate ? date : nil, newPhotos: photos)
                            } else {
                                await model.addMemory(title: title, caption: caption, date: hasDate ? date : nil, photos: photos)
                            }
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                }
            }
            .task {
                guard let existing else { return }
                title = existing.title
                caption = existing.caption
                if let value = existing.occurredOn, let parsed = dayFormatter.date(from: value) {
                    date = parsed
                    hasDate = true
                }
            }
            .onChange(of: picks) { value in
                Task {
                    photos = await withTaskGroup(of: Data?.self) { group in
                        value.forEach { item in group.addTask { try? await item.loadTransferable(type: Data.self) } }
                        var result: [Data] = []
                        for await data in group { if let data { result.append(data) } }
                        return result
                    }
                }
            }
        }
    }
}

private struct BucketEditor: View {
    @EnvironmentObject private var model: HakaAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var list = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Create a titled list", isOn: $list)
                TextField(list ? "List title" : "Something to do together", text: $title)
            }
            .scrollContentBackground(.hidden)
            .hakaPage()
            .navigationTitle(list ? "New list" : "New bucket item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if list { await model.addBucketList(title) }
                            else { await model.addBucketItem(title) }
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct BucketListDetail: View {
    @EnvironmentObject private var model: HakaAppModel
    @Environment(\.dismiss) private var dismiss
    let list: BucketListDTO
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.story.bucketItems.filter { $0.listId == list.id }) { item in
                    BucketItemRow(item: item) { Task { await model.toggleBucket(item) } }
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            Button(role: .destructive) { Task { await model.deleteBucket(item.id) } } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                HStack {
                    TextField("Add item", text: $text)
                    Button {
                        let value = text
                        text = ""
                        Task { await model.addBucketItem(value, listID: list.id) }
                    } label: { Image(systemName: "plus.circle.fill") }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .hakaPage()
            .navigationTitle(list.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        Task { await model.deleteBucketList(list.id); dismiss() }
                    } label: { Image(systemName: "trash") }
                }
            }
        }
    }
}

private enum TextEditTarget: Identifiable {
    case item(BucketItemDTO)
    case list(BucketListDTO)
    var id: String {
        switch self { case .item(let value): "item-\(value.id)"; case .list(let value): "list-\(value.id)" }
    }
    var title: String { switch self { case .item(let value): value.title; case .list(let value): value.title } }
}

private struct TextEditSheet: View {
    @EnvironmentObject private var model: HakaAppModel
    @Environment(\.dismiss) private var dismiss
    let target: TextEditTarget
    @State private var title: String

    init(target: TextEditTarget) {
        self.target = target
        _title = State(initialValue: target.title)
    }

    var body: some View {
        NavigationStack {
            Form { TextField("Title", text: $title) }
                .scrollContentBackground(.hidden)
                .hakaPage()
                .navigationTitle("Edit title")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                switch target {
                                case .item(let item): await model.updateBucket(item, title: title)
                                case .list(let list): await model.updateBucketList(list, title: title)
                                }
                                dismiss()
                            }
                        }
                    }
                }
        }
    }
}

private struct RelationshipDateEditor: View {
    @EnvironmentObject private var model: HakaAppModel
    @Environment(\.dismiss) private var dismiss
    var existing: RelationshipDateDTO?
    @State private var label = ""
    @State private var kind = "anniversary"
    @State private var date = Date()
    @State private var annual = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $label)
                Picker("Type", selection: $kind) {
                    Text("Anniversary").tag("anniversary")
                    Text("Birthday").tag("birthday")
                    Text("Custom").tag("custom")
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Annual reminder", isOn: $annual)
            }
            .scrollContentBackground(.hidden)
            .hakaPage()
            .navigationTitle(existing == nil ? "Important date" : "Edit date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let existing {
                                await model.updateRelationshipDate(existing, label: label, kind: kind, date: date, annual: annual)
                            } else {
                                await model.addRelationshipDate(label: label, kind: kind, date: date, annual: annual)
                            }
                            dismiss()
                        }
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                guard let existing else { return }
                label = existing.label
                kind = existing.kind
                annual = existing.remindAnnually
                if let parsed = dayFormatter.date(from: existing.occursOn) { date = parsed }
            }
        }
    }
}

private let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private func prettyDay(_ value: String) -> String {
    dayFormatter.date(from: value)?.formatted(date: .abbreviated, time: .omitted) ?? value
}

private func relativeDay(_ item: RelationshipDateDTO) -> String {
    guard let original = dayFormatter.date(from: item.occursOn) else { return "Unavailable" }
    var target = original
    let calendar = Calendar.current
    if item.remindAnnually {
        let components = calendar.dateComponents([.month, .day], from: original)
        target = calendar.date(from: DateComponents(year: calendar.component(.year, from: .now), month: components.month, day: components.day)) ?? original
        if target < calendar.startOfDay(for: .now) { target = calendar.date(byAdding: .year, value: 1, to: target) ?? target }
    }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: target)).day ?? 0
    if !item.remindAnnually && days < 0 { return "Passed" }
    if days == 0 { return "Today" }
    return "In \(days) days"
}
