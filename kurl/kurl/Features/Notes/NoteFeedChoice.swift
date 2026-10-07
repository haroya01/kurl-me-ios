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

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .everyone: "노트"
        case .following: "팔로잉"
        case .trending: "인기"
        case .bookmarks: "북마크한 노트"
        case .direct: "개인 멘션"
        }
    }

    var menuLabel: LocalizedStringKey {
        switch self {
        case .everyone: "모든 노트"
        case .following: "팔로잉"
        case .trending: "인기"
        case .bookmarks: "북마크한 노트"
        case .direct: "개인 멘션"
        }
    }

    var symbol: String {
        switch self {
        case .everyone: "text.bubble"
        case .following: "person.2"
        case .trending: "flame"
        case .bookmarks: "bookmark"
        case .direct: "at"
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

    private init() {
        let saved = Config.useMocks ? nil : UserDefaults.standard.string(forKey: Self.key)
        kind = saved.flatMap(NoteFeedKind.init) ?? .everyone
    }
}

@MainActor
@Observable
final class NoteFeedPreferences {
    static let shared = NoteFeedPreferences()

    private(set) var showReposts = true
    private(set) var changes = 0
    private var loadedFor: Int64?

    private init() {}

    func hydrateIfNeeded() async {
        guard let me = AuthStore.shared.me?.id else {
            loadedFor = nil
            if !showReposts { showReposts = true }
            return
        }
        guard loadedFor != me else { return }
        if let preferences = try? await NoteAPI.feedPreferences() {
            showReposts = preferences.showReposts
            loadedFor = me
        }
    }

    func followingFeedChanged() {
        changes += 1
    }

    func setShowReposts(_ on: Bool) async {
        let before = showReposts
        showReposts = on
        do {
            showReposts = try await NoteAPI.setShowReposts(on).showReposts
            changes += 1
        } catch {
            showReposts = before
            ToastCenter.shared.show(String(localized: "설정을 바꾸지 못했어요"))
        }
    }
}

struct NoteFeedPicker: View {
    @Bindable var choice = NoteFeedChoice.shared
    private var preferences = NoteFeedPreferences.shared

    var body: some View {
        Picker("노트 피드", selection: $choice.kind) {
            ForEach(NoteFeedKind.allCases) { kind in
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
    }
}
