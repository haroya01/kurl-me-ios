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
        case .everyone: "clock"
        case .trending: "flame"
        case .following: "person.2"
        case .federated: "globe"
        case .bookmarks: "bookmark"
        case .direct: "at"
        case .list: "list.bullet"
        }
    }
}

enum NoteMoreFeed: Hashable {
    case kind(NoteFeedKind)
    case list(Int64)

    var kind: NoteFeedKind {
        switch self {
        case .kind(let kind): kind
        case .list: .list
        }
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
