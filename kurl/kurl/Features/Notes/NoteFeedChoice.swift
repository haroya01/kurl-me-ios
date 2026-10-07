//
//  NoteFeedChoice.swift
//  kurl
//

import Observation
import SwiftUI

enum NoteFeedKind: String, CaseIterable, Identifiable {
    case everyone
    case following
    case trending
    case bookmarks
    case direct
    case list

    var id: String { rawValue }

    static let pickable: [NoteFeedKind] = [.everyone, .following, .trending, .bookmarks, .direct]

    var title: LocalizedStringKey {
        switch self {
        case .everyone: "노트"
        case .following: "팔로잉"
        case .trending: "인기"
        case .bookmarks: "북마크한 노트"
        case .direct: "개인 멘션"
        case .list: "리스트"
        }
    }

    var menuLabel: LocalizedStringKey {
        switch self {
        case .everyone: "모든 노트"
        case .following: "팔로잉"
        case .trending: "인기"
        case .bookmarks: "북마크한 노트"
        case .direct: "개인 멘션"
        case .list: "리스트"
        }
    }

    var symbol: String {
        switch self {
        case .everyone: "text.bubble"
        case .following: "person.2"
        case .trending: "flame"
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
        didSet { persist() }
    }
    private(set) var listId: Int64?
    private(set) var listTitle: String?

    var selectionKey: String { kind == .list ? "list:\(listId ?? 0)" : kind.rawValue }

    var title: Text {
        if kind == .list { return Text(verbatim: listTitle ?? "") }
        return Text(kind.title)
    }

    private init() {
        let saved = Config.useMocks ? nil : UserDefaults.standard.string(forKey: Self.key)
        if let saved, saved.hasPrefix("list:"), let id = Int64(saved.dropFirst(5)) {
            listId = id
            kind = .list
        } else {
            kind = saved.flatMap(NoteFeedKind.init) ?? .everyone
        }
    }

    func show(_ list: NoteListSummary) {
        listId = list.id
        listTitle = list.title
        if kind == .list { persist() } else { kind = .list }
    }

    func reconcile(with lists: [NoteListSummary]) {
        guard kind == .list else { return }
        if let current = lists.first(where: { $0.id == listId }) {
            listTitle = current.title
        } else {
            kind = .everyone
        }
    }

    private func persist() {
        UserDefaults.standard.set(selectionKey, forKey: Self.key)
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
            NoteFeedChoice.shared.reconcile(with: loaded)
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
        NoteFeedChoice.shared.reconcile(with: lists)
    }

    func delete(_ list: NoteListSummary) async throws {
        try await NoteAPI.deleteList(id: list.id)
        lists.removeAll { $0.id == list.id }
        NoteFeedChoice.shared.reconcile(with: lists)
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

struct NoteFeedPicker: View {
    @Bindable var choice = NoteFeedChoice.shared
    private var preferences = NoteFeedPreferences.shared
    private var lists = NoteListsStore.shared

    var body: some View {
        Picker("노트 피드", selection: $choice.kind) {
            ForEach(NoteFeedKind.pickable) { kind in
                Label(kind.menuLabel, systemImage: kind.symbol).tag(kind)
            }
        }
        .pickerStyle(.inline)
        if choice.kind == .following, AuthStore.shared.isSignedIn {
            Section {
                Toggle(isOn: Binding(
                    get: { preferences.showReposts },
                    set: { on in Task { await preferences.setShowReposts(on) } }
                )) {
                    Label("리포스트 보기", systemImage: "arrow.2.squarepath")
                }
            }
        }
        if AuthStore.shared.isSignedIn {
            Section("리스트") {
                ForEach(lists.lists) { list in
                    Button {
                        choice.show(list)
                    } label: {
                        Label(
                            list.title,
                            systemImage: choice.kind == .list && choice.listId == list.id
                                ? "checkmark" : "list.bullet")
                    }
                }
                Button {
                    lists.managing = true
                } label: {
                    Label("리스트 관리", systemImage: "slider.horizontal.3")
                }
            }
            Section {
                Button {
                    ScheduledNotesStore.shared.showing = true
                } label: {
                    Label("예약한 노트", systemImage: "clock")
                }
            }
        }
    }
}
