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
        List {
            if !suggested.isEmpty {
                Section {
                    suggestion
                }
            }
            if rooms.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("아직 들어간 방이 없어요.")
                            .typeScale(.note)
                            .foregroundStyle(Palette.ink)
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
                    .padding(.vertical, 6)
                }
            } else {
                Section {
                    ForEach(rooms) { room in
                        NavigationLink(value: RoomRoute(id: room.id)) {
                            RoomRow(room: room)
                        }
                        .accessibilityIdentifier("rooms.row.\(room.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var suggestion: some View {
        HStack(spacing: 12) {
            Button {
                creating = suggested
            } label: {
                HStack(spacing: 12) {
                    AvatarStack(people: suggested)
                    Text("\(names(suggested))와 방 만들기")
                        .typeScale(.note)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rooms.suggestion")
            Button {
                let ids = suggested.map(\.id)
                suggested = []
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
            phase = .loaded(try await rooms)
            suggested = (try? await suggestions)?.friends ?? []
        } catch {
            phase = .failed(error.localizedDescription)
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(room.name)
                    .typeScale(.note)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let last = room.lastNote {
                    Text("\(last.author.displayName ?? last.author.username): \(last.excerpt ?? "")")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                } else {
                    Text("멤버 \(room.memberCount)명")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let at = room.lastActivityAt {
                    Text(at.relativeCompact)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
                if room.unreadCount > 0 {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(Text("새 글"))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AvatarStack: View {
    let people: [RoomPerson]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(people.prefix(3)) { person in
                AvatarView(author: person.author, size: 30)
                    .overlay(Circle().stroke(Palette.pageBg, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
