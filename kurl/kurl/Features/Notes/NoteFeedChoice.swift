//
//  NoteFeedChoice.swift
//  kurl
//

import Observation
import SwiftUI

enum NoteFeedKind: String, CaseIterable, Identifiable {
    case everyone
    case trending
    case following
    case federated
    case bookmarks
    case direct
    case list

    var id: String { rawValue }

    static let tabs: [NoteFeedKind] = [.everyone, .trending, .following]
    static let more: [NoteFeedKind] = [.federated, .bookmarks, .direct]

    var title: LocalizedStringKey {
        switch self {
        case .everyone: "최신"
        case .trending: "인기"
        case .following: "팔로잉"
        case .federated: "다른 서버"
        case .bookmarks: "북마크한 노트"
        case .direct: "개인 멘션"
        case .list: "리스트"
        }
    }

    var label: String {
        switch self {
        case .everyone: String(localized: "최신")
        case .trending: String(localized: "인기")
        case .following: String(localized: "팔로잉")
        case .federated: String(localized: "다른 서버")
        case .bookmarks: String(localized: "북마크한 노트")
        case .direct: String(localized: "개인 멘션")
        case .list: String(localized: "리스트")
        }
    }

    var symbol: String {
        switch self {
        case .everyone: "text.bubble"
        case .trending: "flame"
        case .following: "person.2"
        case .federated: "globe"
        case .bookmarks: "bookmark"
        case .direct: "at"
        case .list: "list.bullet"
        }
    }
}

@MainActor
@Observable
final class NoteFeedChoice {
    static let shared = NoteFeedChoice()

    private static let key = "notes.feed"

    var kind: NoteFeedKind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: Self.key) }
    }
    var path = NavigationPath()
    private(set) var posted: Note?

    private init() {
        let launched = Config.launchValue(after: "--notes-feed").flatMap(NoteFeedKind.init)
        let saved = Config.useMocks ? nil : UserDefaults.standard.string(forKey: Self.key).flatMap(NoteFeedKind.init)
        kind = [launched, saved].compactMap { $0 }.first { NoteFeedKind.tabs.contains($0) } ?? .everyone
    }

    func show(_ tab: NoteFeedKind) {
        path = NavigationPath()
        kind = tab
    }

    func open(_ route: Route) {
        path.append(route)
    }

    func didPost(_ note: Note) {
        posted = note
    }
}

@MainActor
@Observable
final class NoteListsStore {
    static let shared = NoteListsStore()

    private(set) var lists: [NoteListSummary] = []
    var managing = false

    private init() {}

    func reload() async {
        guard AuthStore.shared.isSignedIn else {
            if !lists.isEmpty { lists = [] }
            return
        }
        if let loaded = try? await NoteAPI.lists() {
            lists = loaded
        }
    }

    @discardableResult
    func create(_ title: String) async throws -> NoteListSummary {
        let created = try await NoteAPI.createList(title: title)
        lists.append(created)
        return created
    }

    func rename(_ list: NoteListSummary, to title: String) async throws {
        let renamed = try await NoteAPI.renameList(id: list.id, title: title)
        if let index = lists.firstIndex(where: { $0.id == list.id }) { lists[index] = renamed }
    }

    func delete(_ list: NoteListSummary) async throws {
        try await NoteAPI.deleteList(id: list.id)
        lists.removeAll { $0.id == list.id }
    }

    func memberCountChanged(_ listId: Int64, by delta: Int64) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index].memberCount = max(0, lists[index].memberCount + delta)
        }
    }
}

@MainActor
@Observable
final class NoteFeedPreferences {
    static let shared = NoteFeedPreferences()

    private(set) var showReposts = true
    private(set) var languages: [String] = []
    private(set) var languageChanges = 0
    private(set) var changes = 0
    private(set) var mutes = 0
    private var loadedFor: Int64?

    private init() {}

    func hydrateIfNeeded() async {
        guard let me = AuthStore.shared.me?.id else {
            loadedFor = nil
            if !showReposts { showReposts = true }
            if !languages.isEmpty { languages = [] }
            return
        }
        guard loadedFor != me else { return }
        if let preferences = try? await NoteAPI.feedPreferences() {
            showReposts = preferences.showReposts ?? true
            languages = preferences.languages ?? []
            loadedFor = me
        }
    }

    func followingFeedChanged() {
        changes += 1
    }

    func mutesChanged() {
        mutes += 1
    }

    func setShowReposts(_ on: Bool) async {
        let before = showReposts
        showReposts = on
        do {
            showReposts = try await NoteAPI.setShowReposts(on).showReposts ?? on
            changes += 1
        } catch {
            showReposts = before
            ToastCenter.shared.show(String(localized: "설정을 바꾸지 못했어요"))
        }
    }
}

extension NoteFeedPreferences {
    func setLanguages(_ codes: [String]) async {
        let before = languages
        languages = codes
        do {
            languages = try await NoteAPI.setLanguages(codes).languages ?? codes
            languageChanges += 1
        } catch {
            languages = before
            ToastCenter.shared.show(String(localized: "설정을 바꾸지 못했어요"))
        }
    }
}

struct NoteFeedTabMenu: View {
    @State private var choice = NoteFeedChoice.shared

    var body: some View {
        Picker("노트 피드", selection: $choice.kind) {
            ForEach(NoteFeedKind.tabs) { kind in
                Label(kind.title, systemImage: kind.symbol).tag(kind)
            }
        }
        .pickerStyle(.inline)
        NoteFeedMenu()
    }
}

struct NoteFeedMenu: View {
    @State private var choice = NoteFeedChoice.shared
    @State private var preferences = NoteFeedPreferences.shared
    @State private var lists = NoteListsStore.shared

    var body: some View {
        Section {
            ForEach(NoteFeedKind.more) { kind in
                Button {
                    choice.open(.noteFeed(kind))
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        }
        Section("리스트") {
            ForEach(lists.lists) { list in
                Button {
                    choice.open(.noteList(id: list.id, title: list.title))
                } label: {
                    Label(list.title, systemImage: NoteFeedKind.list.symbol)
                }
            }
            Button {
                lists.managing = true
            } label: {
                Label("리스트 관리", systemImage: "slider.horizontal.3")
            }
        }
        Section {
            if choice.kind == .following {
                Toggle(isOn: Binding(
                    get: { preferences.showReposts },
                    set: { on in Task { await preferences.setShowReposts(on) } }
                )) {
                    Label("리포스트 보기", systemImage: "arrow.2.squarepath")
                }
            }
            Button {
                ScheduledNotesStore.shared.showing = true
            } label: {
                Label("예약한 노트", systemImage: "clock")
            }
        }
    }
}
