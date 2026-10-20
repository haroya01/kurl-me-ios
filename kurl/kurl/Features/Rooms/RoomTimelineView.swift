//
//  RoomTimelineView.swift
//  kurl
//

import SwiftUI

struct RoomTimelineView: View {
    let roomId: Int64

    @State private var detail: RoomDetail?
    @State private var model: NotesViewModel
    @State private var composing = false
    @State private var inviting = false
    @State private var composed: Note?
    @State private var posted = 0
    @State private var showsSettings = false

    init(roomId: Int64) {
        self.roomId = roomId
        _model = State(initialValue: NotesViewModel(room: roomId))
    }

    var body: some View {
        ReadingColumn(spacing: 0, background: .clear, gutter: Metrics.noteGutter) {
            if let detail {
                header(detail)
                Hairline().padding(.horizontal, -Metrics.noteGutter)
            }
            Color.clear.frame(height: 8)
            feed
        }
        .background(Palette.readingBg)
        .environment(\.insideRoom, roomId)
        .navigationTitle(detail?.name ?? "")
        .navigationSubtitle(detail.map { String(localized: "멤버 \($0.memberCount)명") } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    composing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(Text("이 방에 쓰기"))
                .accessibilityIdentifier("room.compose")
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
            default: break
            }
            #endif
            async let loaded: Void = model.reload()
            detail = try? await RoomAPI.detail(roomId)
            await loaded
            if let newest = model.items.first?.id {
                try? await RoomAPI.read(roomId, upTo: newest)
                RoomsRouter.shared.changed()
            }
        }
        .refreshable { await model.reload() }
        .sheet(isPresented: $composing, onDismiss: {
            if let note = composed {
                composed = nil
                model.inserted(note)
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
                    .foregroundStyle(Palette.ink)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
            }
            .buttonStyle(PaperCapsuleStyle(prominent: false))
            .accessibilityIdentifier("room.invite")
        }
        .padding(.vertical, 12)
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
                VStack(alignment: .leading, spacing: 14) {
                    Text("아직 이 방에 글이 없어요.")
                        .typeScale(.note)
                        .foregroundStyle(Palette.ink)
                    Button("초대하기") { inviting = true }
                        .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
            } else {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, note in
                    NoteFeedItem(
                        note: note,
                        onChange: { model.replaced($0) },
                        onDelete: { model.removed($0) },
                        onQuoted: { model.inserted($0) }
                    )
                    .task { await model.loadMoreIfNeeded(current: note) }
                    if index < model.items.count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
                }
            }
        }
    }
}

struct CreateRoomSheet: View {
    let friends: [RoomPerson]
    let onCreated: (RoomDetail) -> Void

    @State private var name = ""
    @State private var creating = false
    @State private var failed: String?
    @State private var created: RoomDetail?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("방 이름", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("createRoom.name")
                } footer: {
                    Text("최대 50명까지 들어올 수 있어요. 방 글은 멤버에게만 보여요.")
                }
                if !friends.isEmpty {
                    Section("만든 뒤 초대할 친구") {
                        ForEach(friends) { friend in
                            HStack(spacing: 10) {
                                AvatarView(author: friend.author, size: 28)
                                Text(friend.displayName ?? friend.username)
                            }
                        }
                    }
                }
                if let failed {
                    Section { Text(failed).foregroundStyle(.red) }
                }
            }
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
                        if creating { ProgressView() } else { Text("만들기") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || creating)
                    .accessibilityIdentifier("createRoom.submit")
                }
            }
            .onAppear { focused = true }
            .sheet(item: $created, onDismiss: {
                if let created { onCreated(created) }
            }) { room in
                RoomInviteSheet(
                    roomId: room.id, roomName: room.name,
                    memberIds: Set(room.members.map(\.id)), preselected: friends)
            }
        }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            created = try await RoomAPI.create(name: name.trimmingCharacters(in: .whitespaces))
        } catch {
            failed = error.localizedDescription
        }
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
