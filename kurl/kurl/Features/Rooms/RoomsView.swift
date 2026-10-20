//
//  RoomsView.swift
//  kurl
//

import SwiftUI

struct RoomRoute: Hashable {
    let id: Int64
}

@MainActor
@Observable
final class RoomsRouter {
    static let shared = RoomsRouter()

    var path = NavigationPath()
    var changes = 0

    func open(_ id: Int64) {
        TabRouter.shared.selection = TabRouter.roomsTab
        var next = NavigationPath()
        next.append(RoomRoute(id: id))
        path = next
    }

    func changed() {
        changes += 1
    }
}

extension EnvironmentValues {
    @Entry var insideRoom: Int64? = nil
}

struct RoomsView: View {
    @State private var router = RoomsRouter.shared
    @State private var phase: LoadState<[RoomListItem]> = .idle
    @State private var model = NotesViewModel(source: .rooms)
    @State private var suggested: [RoomPerson] = []
    @State private var invitations: [RoomInvitation] = []
    @State private var answered = 0
    @State private var posted = 0
    @State private var composing = false
    @State private var composed: Note?
    @State private var creating: [RoomPerson]?
    @State private var joining = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle("방")
                .toolbar {
                    if AuthStore.shared.isSignedIn, case .loaded(let rooms) = phase, !rooms.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                composing = true
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .accessibilityLabel(Text("방에 쓰기"))
                            .accessibilityIdentifier("rooms.compose")
                        }
                    }
                }
                .navigationDestination(for: RoomRoute.self) { RoomTimelineView(roomId: $0.id) }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                .task(id: [AuthStore.shared.isSignedIn ? 1 : 0, router.changes]) { await load() }
                .task {
                    #if DEBUG
                    if Config.launchValue(after: "--room-sheet") == "create" { creating = [] }
                    if let id = Config.launchValue(after: "--room").flatMap(Int64.init) {
                        try? await Task.sleep(for: .milliseconds(800))
                        router.open(id)
                    }
                    #endif
                }
                .refreshable { await load() }
                .sheet(item: Binding(
                    get: { creating.map { CreateRoomRequest(friends: $0) } },
                    set: { if $0 == nil { creating = nil } })
                ) { request in
                    CreateRoomSheet(friends: request.friends) { room in
                        creating = nil
                        router.changed()
                        router.open(room.id)
                    }
                }
                .sheet(isPresented: $composing, onDismiss: {
                    if let note = composed {
                        composed = nil
                        model.inserted(note)
                        router.changed()
                    }
                }) {
                    NoteComposeSheet(mode: .new(quote: nil, inReplyToId: nil), suggestedRoom: suggestedRoom) { note in
                        composed = note
                        posted += 1
                    }
                }
                .sheet(isPresented: $joining) { JoinByLinkSheet() }
                .loginPrompt(isPresented: $showLogin, message: "방을 보려면 로그인하세요")
                .sensoryFeedback(.success, trigger: answered)
                .sensoryFeedback(.success, trigger: posted)
        }
        .environment(\.openNoteRoute) { router.path.append($0) }
    }

    private var suggestedRoom: NoteRoom? {
        guard case .loaded(let rooms) = phase, let first = rooms.first else { return nil }
        return NoteRoom(id: first.id, name: first.name)
    }

    @ViewBuilder
    private var content: some View {
        if !AuthStore.shared.isSignedIn {
            FeedPlaceholder(title: "로그인하면 친구들과 만든 방이 여기 모여요.", actionTitle: "로그인") { showLogin = true }
                .padding(.horizontal, Metrics.gutter)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
        } else {
            switch phase {
            case .idle, .loading:
                KurlLoadingMark().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorState(message: message) { Task { await load() } }
                    .padding(.horizontal, Metrics.gutter)
            case .loaded(let rooms):
                page(rooms)
            }
        }
    }

    private func page(_ rooms: [RoomListItem]) -> some View {
        ReadingColumn(spacing: 0, background: Palette.readingBg, gutter: Metrics.noteGutter) {
            RoomRail(
                rooms: rooms,
                suggested: suggested,
                onOpen: { router.open($0) },
                onCreate: { creating = suggested },
                onDismissSuggestion: dismissSuggestions)
                .padding(.horizontal, -Metrics.noteGutter)
                .padding(.top, 4)
                .padding(.bottom, 10)
            ForEach(invitations) { invitation in
                RoomInvitationBanner(invitation: invitation) { accept in
                    Task { await answer(invitation, accept: accept) }
                }
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Hairline().padding(.horizontal, -Metrics.noteGutter)
            if rooms.isEmpty {
                empty
            } else {
                timeline
            }
        }
        .animation(.smooth(duration: 0.3), value: invitations)
        .reservesTabBarSpace()
    }

    @ViewBuilder
    private var timeline: some View {
        switch model.phase {
        case .idle, .loading:
            NoteSkeleton()
        case .failed(let message):
            ErrorState(message: message) { Task { await model.reload() } }
        case .loaded:
            if model.items.isEmpty {
                FeedPlaceholder(title: "아직 방에 올라온 글이 없어요.", actionTitle: "첫 글 쓰기") { composing = true }
                    .padding(.top, 24)
            } else {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, note in
                    NoteFeedItem(
                        note: note,
                        onChange: { model.replaced($0) },
                        onDelete: { model.removed($0) },
                        onQuoted: { model.inserted($0) }
                    )
                    .environment(\.insideRoom, sameRoomAsAbove(index) ? note.room?.id : nil)
                    .modifier(QuietAppear(index: index))
                    .task { await model.loadMoreIfNeeded(current: note) }
                    if index < model.items.count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
                }
            }
        }
    }

    private func sameRoomAsAbove(_ index: Int) -> Bool {
        index > 0 && model.items[index - 1].room?.id == model.items[index].room?.id
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("방을 만들면 친구들 글이 여기 모여요.")
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                Button("방 만들기") { creating = suggested }
                    .buttonStyle(.glassProminent)
                    .tint(GlassTokens.prominentTint)
                    .accessibilityIdentifier("rooms.empty.create")
                Button("초대 링크로 들어가기") { joining = true }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("rooms.empty.join")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private func dismissSuggestions() {
        let ids = suggested.map(\.id)
        withAnimation(.smooth(duration: 0.25)) { suggested = [] }
        Task { try? await RoomAPI.dismissSuggestions(ids) }
    }

    private func load() async {
        guard AuthStore.shared.isSignedIn else { return }
        if case .loaded = phase {} else { phase = .loading }
        do {
            async let rooms = RoomAPI.mine()
            async let suggestions = RoomAPI.suggestions()
            async let received = RoomAPI.invitations()
            async let notes: Void = model.reload()
            phase = .loaded(try await rooms)
            suggested = (try? await suggestions)?.friends ?? []
            invitations = (try? await received) ?? []
            await notes
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func answer(_ invitation: RoomInvitation, accept: Bool) async {
        invitations.removeAll { $0.id == invitation.id }
        do {
            if accept {
                let result = try await RoomAPI.accept(invitation.roomId)
                answered += 1
                if result.joined {
                    router.changed()
                    router.open(invitation.roomId)
                } else {
                    ToastCenter.shared.show(String(localized: "방장이 승인하면 들어가요"))
                }
            } else {
                try await RoomAPI.decline(invitation.roomId)
            }
        } catch {
            ToastCenter.shared.show(String(localized: "초대에 답하지 못했어요"))
            await load()
        }
    }
}

private struct CreateRoomRequest: Identifiable {
    let id = UUID()
    let friends: [RoomPerson]
}

struct RoomRail: View {
    let rooms: [RoomListItem]
    let suggested: [RoomPerson]
    let onOpen: (Int64) -> Void
    let onCreate: () -> Void
    let onDismissSuggestion: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    Button {
                        onOpen(room.id)
                    } label: {
                        RoomBubble(
                            faces: room.faces ?? room.lastNote.map { [$0.author] } ?? [],
                            fallback: room.name,
                            label: room.name,
                            fresh: room.unreadCount > 0)
                    }
                    .buttonStyle(.plain)
                    .modifier(QuietAppear(index: index))
                    .accessibilityLabel(Text(room.unreadCount > 0 ? "\(room.name), 새 글" : "\(room.name)"))
                    .accessibilityIdentifier("rooms.bubble.\(room.id)")
                }
                Button(action: onCreate) {
                    if suggested.isEmpty {
                        RoomBubble(faces: [], fallback: nil, label: String(localized: "새 방"), fresh: false)
                    } else {
                        RoomBubble(
                            faces: suggested, fallback: nil,
                            label: String(localized: "\(suggested[0].displayName ?? suggested[0].username)와 방"),
                            fresh: false, adds: true)
                    }
                }
                .buttonStyle(.plain)
                .modifier(QuietAppear(index: rooms.count))
                .contextMenu {
                    if !suggested.isEmpty {
                        Button("제안 지우기", systemImage: "xmark", action: onDismissSuggestion)
                    }
                }
                .accessibilityIdentifier(suggested.isEmpty ? "rooms.create" : "rooms.suggestion")
            }
            .padding(.horizontal, Metrics.noteGutter)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }
}

struct RoomBubble: View {
    let faces: [RoomPerson]
    let fallback: String?
    let label: String
    let fresh: Bool
    var adds = false

    private let size: CGFloat = 64

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .strokeBorder(
                        fresh ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.hairlineStrong),
                        style: StrokeStyle(lineWidth: fresh ? 2.5 : 1, dash: faces.isEmpty && fallback == nil ? [4, 4] : []))
                cluster
                    .frame(width: size - 10, height: size - 10)
                if adds || (faces.isEmpty && fallback == nil) {
                    Image(systemName: "plus")
                        .font(.system(size: adds ? 11 : 20, weight: .semibold))
                        .foregroundStyle(adds ? .white : Palette.secondary)
                        .frame(width: adds ? 22 : nil, height: adds ? 22 : nil)
                        .background { if adds { Circle().fill(Palette.accentFill) } }
                        .overlay { if adds { Circle().stroke(Palette.readingBg, lineWidth: 2) } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: adds ? .bottomTrailing : .center)
                }
            }
            .frame(width: size, height: size)
            Text(label)
                .typeScale(.meta)
                .fontWeight(fresh ? .semibold : .regular)
                .foregroundStyle(fresh ? Palette.ink : Palette.secondary)
                .lineLimit(1)
                .frame(maxWidth: size + 10)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cluster: some View {
        let inner = size - 10
        switch faces.count {
        case 0:
            if let fallback {
                AvatarView(author: Author(id: 0, username: fallback, bio: nil, avatarUrl: nil), size: inner)
            }
        case 1:
            AvatarView(author: faces[0].author, size: inner)
        case 2:
            ZStack {
                AvatarView(author: faces[0].author, size: inner * 0.66)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                AvatarView(author: faces[1].author, size: inner * 0.66)
                    .overlay(Circle().stroke(Palette.readingBg, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        default:
            ZStack {
                AvatarView(author: faces[0].author, size: inner * 0.54)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                AvatarView(author: faces[1].author, size: inner * 0.54)
                    .overlay(Circle().stroke(Palette.readingBg, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                AvatarView(author: faces[2].author, size: inner * 0.54)
                    .overlay(Circle().stroke(Palette.readingBg, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
}

struct RoomInvitationBanner: View {
    let invitation: RoomInvitation
    let onAnswer: (Bool) -> Void

    var body: some View {
        HStack(spacing: 11) {
            AvatarView(author: invitation.inviter.author, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(invitation.roomName)
                    .typeScale(.note)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(detail)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { onAnswer(false) } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("거절"))
            .accessibilityIdentifier("rooms.invitation.decline.\(invitation.roomId)")
            Button { onAnswer(true) } label: {
                Text("들어가기")
                    .typeScale(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
            }
            .buttonStyle(PaperCapsuleStyle(prominent: true))
            .accessibilityIdentifier("rooms.invitation.accept.\(invitation.roomId)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radius))
    }

    private var detail: String {
        let who = invitation.inviter.displayName ?? invitation.inviter.username
        if invitation.approvalRequired {
            return String(localized: "\(who)님의 초대 · 승인 필요")
        }
        return String(localized: "\(who)님의 초대 · \(invitation.memberCount)명")
    }
}

struct AvatarStack: View {
    let people: [RoomPerson]
    var size: CGFloat = 30
    var limit = 3

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(people.prefix(limit)) { person in
                AvatarView(author: person.author, size: size)
                    .overlay(Circle().stroke(Palette.readingBg, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
