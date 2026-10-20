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
    @State private var recent: [Note] = []
    @State private var answered = 0
    @State private var pinTaps = 0
    @State private var creating: [RoomPerson]?
    @State private var joining = false
    @State private var showLogin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $router.path) {
            content
                .safeAreaBar(edge: .top) {
                    if AuthStore.shared.isSignedIn {
                        RoomsHeaderBar(onCreate: { creating = suggested }, onJoin: { joining = true })
                    }
                }
                .background(Palette.readingBg)
                .navigationTitle("방")
                .toolbar(.hidden, for: .navigationBar)
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
                .sensoryFeedback(.selection, trigger: pinTaps)
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
                contents(rooms)
            }
        }
    }

    private func contents(_ rooms: [RoomListItem]) -> some View {
        let lively = rooms.filter { $0.pinned == true || RoomBand.isLively($0) }
            .sorted { ($0.pinned == true ? 0 : 1) < ($1.pinned == true ? 0 : 1) }
        let quiet = rooms.filter { !lively.contains($0) }
        return ReadingColumn(spacing: 0, background: Palette.readingBg, gutter: Metrics.noteGutter) {
            if !invitations.isEmpty {
                section("초대받은 방") {
                    ForEach(invitations) { invitation in
                        RoomInvitationLine(invitation: invitation) { accept in
                            Task { await answer(invitation, accept: accept) }
                        }
                        .transition(.opacity)
                    }
                }
            }
            if rooms.isEmpty {
                empty
            }
            ForEach(Array(lively.enumerated()), id: \.element.id) { index, room in
                RoomBlock(
                    room: room,
                    notes: Array(recent.filter { $0.room?.id == room.id }.prefix(2)),
                    onReplace: { replace($0) },
                    onRemove: { id in recent.removeAll { $0.id == id } }
                )
                .contextMenu { pinMenu(room) }
                .modifier(QuietAppear(index: index))
            }
            if !quiet.isEmpty {
                section("조용한 방") {
                    ForEach(Array(quiet.enumerated()), id: \.element.id) { index, room in
                        if index > 0 { Hairline() }
                        NavigationLink(value: RoomRoute(id: room.id)) {
                            QuietRoomLine(room: room)
                        }
                        .buttonStyle(RowButtonStyle())
                        .contextMenu { pinMenu(room) }
                        .accessibilityIdentifier("rooms.row.\(room.id)")
                    }
                }
            }
            if !suggested.isEmpty {
                suggestion.padding(.top, 28)
            }
            if !rooms.isEmpty {
                Button("초대 링크로 들어가기") { joining = true }
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .buttonStyle(.plain)
                    .padding(.top, suggested.isEmpty ? 28 : 18)
                    .accessibilityIdentifier("rooms.join")
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: invitations)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: rooms)
        .reservesTabBarSpace()
    }

    @ViewBuilder
    private func pinMenu(_ room: RoomListItem) -> some View {
        if room.pinned == true {
            Button("고정 풀기", systemImage: "pin.slash") { Task { await pin(room, false) } }
        } else {
            Button("맨 위에 고정", systemImage: "pin") { Task { await pin(room, true) } }
        }
    }

    private func replace(_ note: Note) {
        if let at = recent.firstIndex(where: { $0.id == note.id }) { recent[at] = note }
    }

    private func section<Body: View>(_ title: LocalizedStringKey, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading(title)
                .padding(.top, 22)
                .padding(.bottom, 2)
            body()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("친구들과 방을 만들면, 오늘 거기서 오간 말이 여기 먼저 보여요.")
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .padding(.top, 28)
    }

    private var suggestion: some View {
        HStack(spacing: 10) {
            Button {
                creating = suggested
            } label: {
                HStack(spacing: 10) {
                    AvatarStack(people: suggested, size: 22)
                    Text("\(names(suggested))와 방 만들기")
                        .typeScale(.note)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rooms.suggestion")
            Button {
                let ids = suggested.map(\.id)
                withAnimation(.smooth(duration: 0.25)) { suggested = [] }
                Task { try? await RoomAPI.dismissSuggestions(ids) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.faint)
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
            async let feed = RoomAPI.feed(page: 0, size: 50)
            phase = .loaded(try await rooms)
            recent = (try? await feed)?.items ?? []
            suggested = (try? await suggestions)?.friends ?? []
            invitations = (try? await received) ?? []
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func pin(_ room: RoomListItem, _ pinned: Bool) async {
        guard case .loaded(var rooms) = phase, let at = rooms.firstIndex(where: { $0.id == room.id }) else { return }
        if pinned, rooms.filter({ $0.pinned == true }).count >= RoomBand.maxPinned {
            ToastCenter.shared.show(String(localized: "고정은 \(RoomBand.maxPinned)개까지예요"))
            return
        }
        rooms[at].pinned = pinned
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { phase = .loaded(rooms) }
        pinTaps += 1
        do {
            try await RoomAPI.pin(room.id, pinned)
        } catch {
            ToastCenter.shared.show(String(localized: "고정을 바꾸지 못했어요"))
            await load()
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

struct RoomsHeaderBar: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    @State private var unread = UnreadStore.shared
    @ScaledMetric(relativeTo: .subheadline) private var rawLabelSize: CGFloat = 14

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
            HStack(spacing: 0) {
                Color.clear.frame(width: FeedHeaderMetrics.circle, height: FeedHeaderMetrics.circle)
                Spacer(minLength: FeedHeaderMetrics.gap)
                Menu {
                    Button("새 방 만들기", systemImage: "plus", action: onCreate)
                    Button("초대 링크로 들어가기", systemImage: "link", action: onJoin)
                } label: {
                    HStack(spacing: 6) {
                        Text("방")
                            .font(.system(size: min(rawLabelSize, 16), weight: .semibold))
                        Image(systemName: "plus")
                            .font(.system(size: min(rawLabelSize, 16) - 2, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .contentShape(Capsule())
                }
                .tint(.primary)
                .glassEffect(.regular.interactive(), in: .capsule)
                .shadow(color: Palette.shadow.opacity(0.05), radius: 1.5, y: 1)
                .shadow(color: Palette.shadow.opacity(0.08), radius: 12, y: 5)
                .accessibilityLabel(Text("방 만들기"))
                .accessibilityIdentifier("rooms.create")
                Spacer(minLength: FeedHeaderMetrics.gap)
                InboxBell(count: unread.count)
            }
            .padding(.horizontal, FeedHeaderMetrics.edge)
        }
        .padding(.bottom, 8)
    }
}

struct RoomBand: Identifiable {
    enum Kind { case pinned, today, week, quiet }

    static let maxPinned = 5

    let kind: Kind
    let rooms: [RoomListItem]

    var id: Kind { kind }

    var title: LocalizedStringKey {
        switch kind {
        case .pinned: "고정한 방"
        case .today: "오늘"
        case .week: "이번 주"
        case .quiet: "조용한 방"
        }
    }

    static func isLively(_ room: RoomListItem, now: Date = .now) -> Bool {
        guard room.lastNote != nil, let at = room.lastActivityAt else { return false }
        return now.timeIntervalSince(at) < 7 * 86_400
    }

    static func split(_ rooms: [RoomListItem], now: Date = .now) -> [RoomBand] {
        let calendar = Calendar.current
        var pinned: [RoomListItem] = [], today: [RoomListItem] = [], week: [RoomListItem] = [], quiet: [RoomListItem] = []
        for room in rooms {
            if room.pinned == true {
                pinned.append(room)
                continue
            }
            guard room.lastNote != nil, let at = room.lastActivityAt else {
                quiet.append(room)
                continue
            }
            if calendar.isDate(at, inSameDayAs: now) {
                today.append(room)
            } else if now.timeIntervalSince(at) < 7 * 86_400 {
                week.append(room)
            } else {
                quiet.append(room)
            }
        }
        return [RoomBand(kind: .pinned, rooms: pinned), RoomBand(kind: .today, rooms: today), RoomBand(kind: .week, rooms: week), RoomBand(kind: .quiet, rooms: quiet)]
            .filter { !$0.rooms.isEmpty }
    }
}

struct RoomVoice: View {
    let room: RoomListItem

    private var fresh: Bool { room.unreadCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(room.name)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if fresh {
                    Text("새 글 \(room.unreadCount)")
                        .typeScale(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.link)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if let at = room.lastActivityAt {
                    Text(at.relativeCompact)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
            }
            if let last = room.lastNote {
                Text(last.excerpt ?? "")
                    .typeScale(.noteFocus)
                    .foregroundStyle(fresh ? Palette.ink : Palette.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    AvatarView(author: last.author.author, size: 20)
                    Text(last.author.displayName ?? last.author.username)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    AvatarStack(people: others, size: 18, limit: 4)
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var others: [RoomPerson] {
        (room.faces ?? []).filter { $0.id != room.lastNote?.author.id }
    }
}

struct RoomBlock: View {
    let room: RoomListItem
    let notes: [Note]
    let onReplace: (Note) -> Void
    let onRemove: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: RoomRoute(id: room.id)) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if room.pinned == true {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.faint)
                            .accessibilityLabel(Text("고정"))
                    }
                    Text(room.name)
                        .typeScale(.title)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if room.unreadCount > 0 {
                        Text("새 글 \(room.unreadCount)")
                            .typeScale(.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.link)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    AvatarStack(people: room.faces ?? [], size: 20, limit: 4)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                }
                .padding(.top, 26)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rooms.row.\(room.id)")
            if notes.isEmpty {
                NavigationLink(value: RoomRoute(id: room.id)) {
                    RoomVoice(room: room)
                }
                .buttonStyle(RowButtonStyle())
            } else {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    if index > 0 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
                    NoteFeedItem(note: note, onChange: onReplace, onDelete: onRemove, onQuoted: { _ in })
                        .environment(\.insideRoom, room.id)
                }
                NavigationLink(value: RoomRoute(id: room.id)) {
                    HStack(spacing: 3) {
                        Text("더 보기")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .typeScale(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.secondary)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(room.name) 더 보기"))
            }
            Hairline().padding(.horizontal, -Metrics.noteGutter).padding(.top, 2)
        }
    }
}

struct QuietRoomLine: View {
    let room: RoomListItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(room.name)
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.body)
                .lineLimit(1)
            Text(verbatim: "\(room.memberCount)")
                .typeScale(.meta)
                .foregroundStyle(Palette.faint)
                .monospacedDigit()
            Spacer(minLength: 8)
            Text(room.lastNote == nil ? String(localized: "아직 글 없음") : (room.lastActivityAt?.relativeCompact ?? ""))
                .typeScale(.meta)
                .foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct RoomInvitationLine: View {
    let invitation: RoomInvitation
    let onAnswer: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            AvatarView(author: invitation.inviter.author, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                (Text(invitation.inviter.displayName ?? invitation.inviter.username).fontWeight(.semibold)
                    + Text("님이 ")
                    + Text(invitation.roomName).fontWeight(.semibold)
                    + Text("에 초대했어요"))
                    .typeScale(.note)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Button(invitation.approvalRequired ? "들어가기 요청" : "들어가기") { onAnswer(true) }
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.link)
                        .accessibilityIdentifier("rooms.invitation.accept.\(invitation.roomId)")
                    Button("거절") { onAnswer(false) }
                        .foregroundStyle(Palette.secondary)
                        .accessibilityIdentifier("rooms.invitation.decline.\(invitation.roomId)")
                    Text("멤버 \(invitation.memberCount)명")
                        .foregroundStyle(Palette.faint)
                }
                .typeScale(.meta)
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
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
