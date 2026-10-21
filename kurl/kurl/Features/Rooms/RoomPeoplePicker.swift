//
//  RoomPeoplePicker.swift
//  kurl
//

import SwiftUI

struct RoomCandidate: Hashable, Identifiable {
    let id: Int64
    let username: String
    let displayName: String?
    let avatarUrl: String?

    var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? username }
    var author: Author {
        Author(id: id, username: username, bio: nil, avatarUrl: avatarUrl, displayName: displayName)
    }
}

extension RoomCandidate {
    init(_ person: RoomPerson) {
        self.init(id: person.id, username: person.username, displayName: person.displayName, avatarUrl: person.avatarUrl)
    }
}

struct RoomPeoplePicker: View {
    @Binding var picked: [RoomCandidate]
    let query: String
    var memberIds: Set<Int64> = []
    var invited: Set<Int64> = []

    enum Source: String, CaseIterable, Identifiable {
        case following, followers
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .following ? "팔로잉" : "팔로워" }
    }

    @State private var source: Source = .following
    @State private var lists: [Source: [RoomCandidate]] = [:]
    @State private var matches: [RoomCandidate] = []
    @State private var searching = false

    var body: some View {
        if !picked.isEmpty {
            pickedStrip
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if PeopleAPI.isSearchable(query) {
            rows(matches, empty: searching ? nil : "찾는 사람이 없어요")
                .task(id: query) { await search() }
        } else {
            ContentTabBar(
                tabs: Source.allCases, selection: $source, label: \.title,
                identifier: { "roomInvite.tab.\($0.rawValue)" },
                background: Palette.readingBg)
                .padding(.bottom, 4)
            Group {
                if let list = lists[source] {
                    rows(list, empty: source == .following ? "아직 팔로우하는 사람이 없어요" : "아직 팔로워가 없어요")
                } else {
                    KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .task(id: source) { await loadList(source) }
        }
    }

    private var pickedStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(picked) { person in
                    Button {
                        toggle(person)
                    } label: {
                        VStack(spacing: 5) {
                            AvatarView(author: person.author, size: 44)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Palette.secondary)
                                        .offset(x: 4, y: -2)
                                }
                            Text(person.name)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .frame(maxWidth: 56)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(person.name) 빼기"))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func rows(_ people: [RoomCandidate], empty: LocalizedStringKey?) -> some View {
        if people.isEmpty {
            if let empty {
                FeedPlaceholder(title: empty).padding(.top, 20)
            } else {
                KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 120)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    row(person)
                        .modifier(QuietAppear(index: index))
                    if index < people.count - 1 { Hairline() }
                }
            }
        }
    }

    private func row(_ person: RoomCandidate) -> some View {
        let member = memberIds.contains(person.id)
        let waiting = invited.contains(person.id)
        let chosen = picked.contains { $0.id == person.id }
        return Button {
            toggle(person)
        } label: {
            HStack(spacing: 11) {
                AvatarView(author: person.author, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if person.name != person.username {
                        Text(verbatim: "@\(person.username)")
                            .typeScale(.lede)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if member || waiting {
                    Text(member ? "멤버" : "초대함")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                } else {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(chosen ? Palette.accent : Palette.faint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(member || waiting)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("roomInvite.person.\(person.username)")
    }

    private func toggle(_ person: RoomCandidate) {
        if let at = picked.firstIndex(where: { $0.id == person.id }) {
            picked.remove(at: at)
        } else if picked.count < 20 {
            picked.append(person)
        }
    }

    private func loadList(_ source: Source) async {
        guard lists[source] == nil, let me = AuthStore.shared.me?.username else { return }
        let page = source == .following
            ? try? await FollowListsAPI.following(username: me, size: 50)
            : try? await FollowListsAPI.followers(username: me, size: 50)
        lists[source] = (page?.items ?? []).map {
            RoomCandidate(id: $0.id, username: $0.username, displayName: nil, avatarUrl: $0.avatarUrl)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--room-pick"), picked.isEmpty {
            picked = Array((lists[source] ?? []).filter { !memberIds.contains($0.id) && !invited.contains($0.id) }.prefix(3))
        }
        #endif
    }

    private func search() async {
        guard PeopleAPI.isSearchable(query) else {
            matches = []
            searching = false
            return
        }
        searching = true
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }
        let page = try? await PeopleAPI.search(query)
        guard !Task.isCancelled else { return }
        matches = (page?.items ?? []).compactMap { match in
            match.userId.map {
                RoomCandidate(id: $0, username: match.username, displayName: match.displayName, avatarUrl: match.avatarUrl)
            }
        }
        searching = false
    }
}
