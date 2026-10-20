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
    @State private var suggested: [RoomPerson] = []
    @State private var invitations: [RoomInvitation] = []
    @State private var answered = 0
    @State private var creating: [RoomPerson]?
    @State private var joining = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .navigationTitle("방")
                .toolbar {
                    if AuthStore.shared.isSignedIn {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                creating = []
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(Text("방 만들기"))
                            .accessibilityIdentifier("rooms.create")
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
                .sheet(isPresented: $joining) { JoinByLinkSheet() }
                .loginPrompt(isPresented: $showLogin, message: "방을 보려면 로그인하세요")
                .sensoryFeedback(.success, trigger: answered)
        }
        .environment(\.openNoteRoute) { router.path.append($0) }
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
                list(rooms)
            }
        }
    }

    private func list(_ rooms: [RoomListItem]) -> some View {
        ReadingColumn(spacing: 0, background: Palette.readingBg) {
            if !invitations.isEmpty {
                RailHeading("받은 초대")
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                ForEach(invitations) { invitation in
                    RoomInvitationRow(invitation: invitation) { accept in
                        Task { await answer(invitation, accept: accept) }
                    }
                    Hairline()
                }
                Color.clear.frame(height: 14)
            }
            if !suggested.isEmpty {
                suggestion
                Hairline()
            }
            if rooms.isEmpty {
                empty
            } else {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    NavigationLink(value: RoomRoute(id: room.id)) {
                        RoomRow(room: room)
                    }
                    .buttonStyle(RowButtonStyle())
                    .modifier(QuietAppear(index: index))
                    .accessibilityIdentifier("rooms.row.\(room.id)")
                    if index < rooms.count - 1 { Hairline() }
                }
            }
        }
        .reservesTabBarSpace()
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("아직 들어간 방이 없어요.")
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                Button("방 만들기") { creating = [] }
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

    private var suggestion: some View {
        HStack(spacing: 12) {
            Button {
                creating = suggested
            } label: {
                HStack(spacing: 11) {
                    AvatarStack(people: suggested, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(names(suggested))와 방 만들기")
                            .typeScale(.titleSmall)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text("서로 팔로우하는 친구예요")
                            .typeScale(.lede)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityIdentifier("rooms.suggestion")
            Button {
                let ids = suggested.map(\.id)
                withAnimation(.smooth(duration: 0.25)) { suggested = [] }
                Task { try? await RoomAPI.dismissSuggestions(ids) }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("제안 지우기"))
        }
    }

    private func names(_ people: [RoomPerson]) -> String {
        people.prefix(2).map { $0.displayName ?? $0.username }.joined(separator: ", ")
    }

    private func load() async {
        guard AuthStore.shared.isSignedIn else { return }
        if case .loaded = phase {} else { phase = .loading }
        do {
            async let rooms = RoomAPI.mine()
            async let suggestions = RoomAPI.suggestions()
            async let received = RoomAPI.invitations()
            phase = .loaded(try await rooms)
            suggested = (try? await suggestions)?.friends ?? []
            invitations = (try? await received) ?? []
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

extension RoomsView {
    fileprivate func answer(_ invitation: RoomInvitation, accept: Bool) async {
        withAnimation(.smooth(duration: 0.25)) {
            invitations.removeAll { $0.id == invitation.id }
        }
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

struct RoomRow: View {
    let room: RoomListItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            face
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(room.name)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(verbatim: "\(room.memberCount)")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                        .monospacedDigit()
                        .accessibilityLabel(Text("멤버 \(room.memberCount)명"))
                    Spacer(minLength: 8)
                    if let at = room.lastActivityAt {
                        Text(at.relativeCompact)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    line
                        .typeScale(.lede)
                        .foregroundStyle(room.unreadCount > 0 ? Palette.ink : Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if room.unreadCount > 0 {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel(Text("새 글"))
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var face: some View {
        if let author = room.lastNote?.author {
            AvatarView(author: author.author, size: 44)
        } else {
            AvatarView(author: Author(id: room.id, username: room.name, bio: nil, avatarUrl: nil), size: 44)
        }
    }

    private var line: Text {
        if let last = room.lastNote {
            return Text("\(last.author.displayName ?? last.author.username)  ").fontWeight(.semibold)
                + Text(last.excerpt ?? "")
        }
        return Text("아직 글이 없어요")
    }
}

struct RoomInvitationRow: View {
    let invitation: RoomInvitation
    let onAnswer: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            AvatarView(author: invitation.inviter.author, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(invitation.roomName)
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(detail)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Button { onAnswer(true) } label: { capsule("들어가기", prominent: true) }
                        .buttonStyle(PaperCapsuleStyle(prominent: true))
                        .accessibilityIdentifier("rooms.invitation.accept.\(invitation.roomId)")
                    Button { onAnswer(false) } label: { capsule("거절", prominent: false) }
                        .buttonStyle(PaperCapsuleStyle(prominent: false))
                        .accessibilityIdentifier("rooms.invitation.decline.\(invitation.roomId)")
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func capsule(_ title: LocalizedStringKey, prominent: Bool) -> some View {
        Text(title)
            .typeScale(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(prominent ? .white : Palette.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Capsule())
    }

    private var detail: String {
        let who = invitation.inviter.displayName ?? invitation.inviter.username
        let base = String(localized: "\(who)님이 초대했어요 · 멤버 \(invitation.memberCount)명")
        guard invitation.approvalRequired else { return base }
        return base + "\n" + String(localized: "방장이 승인하면 들어가요")
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
