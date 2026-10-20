//
//  HomeFeedChoice.swift
//  kurl
//

import SwiftUI

@MainActor
@Observable
final class HomeFeedChoice {
    static let shared = HomeFeedChoice()

    static let key = "home.tab"

    var tab: HomeFeedTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.key) }
    }
    private(set) var more: FeedSource?
    var path = NavigationPath()
    var pendingLogin: HomeFeedTab?
    var pendingMoreLogin: FeedSource?
    private(set) var posted: Note?
    private(set) var arrivingID: Int64?

    private init() {
        tab = Self.initialTab(
            launched: Config.launchValue(after: "--feed") ?? Config.launchValue(after: "--notes-feed"),
            defaults: Config.useMocks ? nil : .standard,
            signedIn: AuthStore.shared.isSignedIn)
    }

    static func initialTab(launched: String?, defaults: UserDefaults?, signedIn: Bool) -> HomeFeedTab {
        let saved = [defaults?.string(forKey: key), defaults?.string(forKey: "feed.tab"), defaults?.string(forKey: "notes.feed")]
        for value in [launched] + (signedIn ? saved : []) {
            if let value, let tab = HomeFeedTab(stored: value) { return tab }
        }
        return .latest
    }

    func select(_ next: HomeFeedTab) {
        more = nil
        tab = next
    }

    func show(_ next: HomeFeedTab) {
        path = NavigationPath()
        guard !next.requiresAuth || AuthStore.shared.isSignedIn else {
            pendingLogin = next
            return
        }
        select(next)
    }

    func open(_ next: HomeFeedTab) {
        TabRouter.shared.selection = TabRouter.homeTab
        show(next)
    }

    func show(_ feed: FeedSource) {
        guard AuthStore.shared.isSignedIn else {
            pendingMoreLogin = feed
            return
        }
        path = NavigationPath()
        more = feed
    }

    func leaveMore() {
        guard more != nil, let last = HomeFeedTab.allCases.last else { return }
        select(last)
    }

    func signedOut() {
        if tab.requiresAuth { tab = .latest }
        more = nil
    }

    func revealPosted(_ note: Note) {
        path = NavigationPath()
        if more != nil || tab == .trending { select(.latest) }
        posted = note
        arrived(note.id)
    }

    func arrived(_ id: Int64) {
        arrivingID = id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.arrivingID == id { self?.arrivingID = nil }
        }
    }
}

struct HomeMoreMenu: View {
    static let feeds: [FeedSource] = [.forYou]

    @State private var choice = HomeFeedChoice.shared
    @State private var preferences = NoteFeedPreferences.shared

    var body: some View {
        Picker(selection: Binding<FeedSource?>(
            get: { choice.more },
            set: { if let feed = $0 { choice.show(feed) } }
        )) {
            ForEach(Self.feeds) { feed in
                Label(feed.label, systemImage: feed.symbol).tag(Optional(feed))
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.inline)
        if AuthStore.shared.isSignedIn, choice.more == nil, choice.tab == .following {
            Section("보기") {
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

struct HomeTabMenu: View {
    @State private var choice = HomeFeedChoice.shared

    var body: some View {
        Picker("피드", selection: Binding<HomeFeedTab?>(
            get: { choice.more == nil ? choice.tab : nil },
            set: { if let tab = $0 { choice.show(tab) } }
        )) {
            ForEach(HomeFeedTab.allCases) { tab in
                Label(tab.label, systemImage: tab.symbol).tag(Optional(tab))
            }
        }
        .pickerStyle(.inline)
        HomeMoreMenu()
    }
}
