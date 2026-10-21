//
//  RoomTimelineView.swift
//  kurl
//

import SwiftUI

struct RoomTimelineView: View {
    let roomId: Int64

    @State private var detail: RoomDetail?
    @State private var model: RoomItemsModel
    @State private var composing = false
    @State private var inviting = false
    @State private var composed: Note?
    @State private var posted = 0
    @State private var showsSettings = false
    @State private var writingPost = false
    @State private var arrivingID: Int64?

    init(roomId: Int64) {
        self.roomId = roomId
        _model = State(initialValue: RoomItemsModel(.room(roomId)))
    }

    var body: some View {
        ReadingColumn(spacing: 0, background: .clear, gutter: Metrics.noteGutter) {
            if let detail {
                header(detail)
                HStack(spacing: 8) {
                    Button {
                        composing = true
                    } label: {
                        ReplyPrompt(text: Text("\(detail.name)에 한마디"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room.compose")
                    Button { writingPost = true } label: {
                        Label("글", systemImage: "doc.text")
                            .typeScale(.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PaperCapsuleStyle(prominent: false))
                    .accessibilityLabel(Text("이 방에 블로그 글 쓰기"))
                    .accessibilityIdentifier("room.writePost")
                }
                .padding(.bottom, 14)
            }
            feed
        }
        .background(Palette.readingBg)
        .environment(\.insideRoom, roomId)
        .navigationTitle(detail?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if detail != nil {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(Text("방 설정"))
                    .accessibilityIdentifier("room.settings")
                }
            }
        }
        .task {
            #if DEBUG
            switch Config.launchValue(after: "--room-sheet") {
            case "invite", "invite-qr": inviting = true
            case "compose": composing = true
            case "settings": showsSettings = true
            case "post": writingPost = true
            default: break
            }
            #endif
            async let loaded: Void = model.reload()
            detail = try? await RoomAPI.detail(roomId)
            await loaded
            if let newest = model.newestNoteId {
                try? await RoomAPI.read(roomId, upTo: newest)
                RoomsRouter.shared.changed()
            }
        }
        .refreshable { await model.reload() }
        .sheet(isPresented: $composing, onDismiss: {
            if let note = composed {
                composed = nil
                arrivingID = note.id
                model.inserted(note)
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if arrivingID == note.id { arrivingID = nil }
                }
            }
        }) {
            NoteComposeSheet(
                mode: .new(quote: nil, inReplyToId: nil),
                room: detail.map { NoteRoom(id: $0.id, name: $0.name) } ?? NoteRoom(id: roomId, name: "")
            ) { note in
                composed = note
                posted += 1
            }
        }
        .sheet(isPresented: $inviting) {
            RoomInviteSheet(
                roomId: roomId, roomName: detail?.name ?? "",
                memberIds: Set(detail?.members.map(\.id) ?? []))
        }
        .sensoryFeedback(.success, trigger: posted)
        .navigationDestination(isPresented: $writingPost) {
            ComposeView(
                post: nil,
                room: detail.map { NoteRoom(id: $0.id, name: $0.name) } ?? NoteRoom(id: roomId, name: ""),
                onSaved: { Task { await model.reload() } })
        }
        .navigationDestination(isPresented: $showsSettings) {
            if let detail {
                RoomSettingsView(detail: detail) { next in self.detail = next }
            }
        }
    }

    private func header(_ detail: RoomDetail) -> some View {
        HStack(spacing: 12) {
            Button {
                showsSettings = true
            } label: {
                HStack(spacing: 10) {
                    AvatarStack(people: detail.members.map(\.person), size: 32, limit: 5)
                    Text(memberLine(detail))
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("멤버 \(detail.memberCount)명"))
            .accessibilityIdentifier("room.members")
            Spacer(minLength: 8)
            Button {
                inviting = true
            } label: {
                Label("초대", systemImage: "person.badge.plus")
                    .typeScale(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(alone(detail) ? .white : Palette.ink)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
            }
            .buttonStyle(PaperCapsuleStyle(prominent: alone(detail)))
            .accessibilityIdentifier("room.invite")
        }
        .padding(.vertical, 12)
    }

    private func dayBreak(_ index: Int) -> LocalizedStringResource? {
        let calendar = Calendar.current
        guard let at = model.items[index].date else { return nil }
        if index > 0, let above = model.items[index - 1].date, calendar.isDate(above, inSameDayAs: at) {
            return nil
        }
        if calendar.isDateInToday(at) { return "오늘" }
        if calendar.isDateInYesterday(at) { return "어제" }
        return "\(at.formatted(.dateTime.month().day().weekday(.abbreviated)))"
    }

    private func alone(_ detail: RoomDetail) -> Bool { detail.memberCount <= 1 }

    private func arriving(_ item: HomeFeedItem) -> Bool {
        arrivingID != nil && item.note?.id == arrivingID
    }

    private func memberLine(_ detail: RoomDetail) -> String {
        let names = detail.members.prefix(2).map { $0.displayName ?? $0.username }.joined(separator: ", ")
        let rest = Int(detail.memberCount) - min(2, detail.members.count)
        return rest > 0 ? String(localized: "\(names) 외 \(rest)명") : names
    }

    @ViewBuilder
    private var feed: some View {
        switch model.phase {
        case .idle, .loading:
            NoteSkeleton()
        case .failed(let message):
            ErrorState(message: message) { Task { await model.reload() } }
        case .loaded:
            if model.items.isEmpty {
                Text("아직 이 방에 글이 없어요.")
                    .typeScale(.note)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
            } else {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    if let day = dayBreak(index) {
                        RailHeading(resource: day)
                            .padding(.top, index == 0 ? 6 : 22)
                            .padding(.bottom, 2)
                    }
                    RoomItemRow(
                        item: item,
                        onReplace: { model.replaced($0) },
                        onRemove: { model.removed($0) },
                        onQuoted: { model.inserted($0) })
                    .modifier(QuietAppear(index: arriving(item) ? .max : index))
                    .modifier(NoteArrival(active: arriving(item)))
                    .task { await model.loadMoreIfNeeded(current: item) }
                    if index < model.items.count - 1, dayBreak(index + 1) == nil {
                        Hairline().padding(.horizontal, -Metrics.noteGutter)
                    }
                }
            }
        }
    }
}

struct CreateRoomSheet: View {
    let friends: [RoomPerson]
    let onCreated: (RoomDetail) -> Void

    @State private var name = ""
    @State private var query = ""
    @State private var picked: [RoomCandidate] = []
    @State private var creating = false
    @State private var failed: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0, background: Palette.readingBg) {
                TextField("방 이름", text: $name)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .focused($focused)
                    .submitLabel(.done)
                    .padding(.top, 14)
                    .accessibilityIdentifier("createRoom.name")
                Hairline().padding(.top, 10)
                Text("최대 50명까지 들어올 수 있어요. 방 글은 멤버에게만 보여요.")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 8)
                if let failed {
                    Text(failed)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.danger)
                        .padding(.top, 6)
                }
                RailHeading("함께할 사람")
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.secondary)
                    TextField("이름이나 아이디로 찾기", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("createRoom.search")
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("지우기"))
                    }
                }
                .typeScale(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.chipBg, in: Capsule())
                .padding(.bottom, 12)
                RoomPeoplePicker(picked: $picked, query: query)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: picked)
            .navigationTitle("방 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await create() }
                    } label: {
                        if creating {
                            ProgressView()
                        } else if picked.isEmpty {
                            Text("만들기")
                        } else {
                            Text("만들고 \(picked.count)명 초대")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(GlassTokens.prominentTint)
                    .disabled(trimmed.isEmpty || trimmed.count > 50 || creating)
                    .accessibilityIdentifier("createRoom.submit")
                }
            }
            .onAppear {
                focused = true
                if picked.isEmpty { picked = friends.map(RoomCandidate.init) }
            }
        }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        let room: RoomDetail
        do {
            room = try await RoomAPI.create(name: trimmed)
        } catch {
            failed = error.localizedDescription
            return
        }
        if !picked.isEmpty {
            let ids = picked.map(\.id)
            if let waiting = try? await RoomAPI.invite(room.id, people: ids) {
                let reached = ids.filter { id in waiting.contains { $0.id == id } }.count
                if reached > 0 { ToastCenter.shared.show(String(localized: "\(reached)명에게 초대를 보냈어요")) }
            } else {
                ToastCenter.shared.show(String(localized: "초대를 보내지 못했어요"))
            }
        }
        onCreated(room)
    }
}

extension RoomDetail: Identifiable {}

struct JoinByLinkSheet: View {
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("초대 링크나 코드", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("받은 kurl 링크를 붙여 넣으세요.")
                }
            }
            .navigationTitle("초대 링크로 들어가기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("열기") {
                        if let url = URL(string: text.trimmingCharacters(in: .whitespaces)) { openURL(url) }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
