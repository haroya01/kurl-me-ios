import SwiftUI

@MainActor
@Observable
final class HomeFeedChoice {
    static let shared = HomeFeedChoice()

    static let key = "home.tab"

    var tab: HomeFeedTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.key) }
    }
    var path = NavigationPath()
    var pendingLogin: HomeFeedTab?
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
        return .forYou
    }

    func select(_ next: HomeFeedTab) {
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

    func signedOut() {
        if tab.requiresAuth { tab = .forYou }
    }

    func revealPosted(_ note: Note) {
        path = NavigationPath()
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
    @State private var choice = HomeFeedChoice.shared
    @State private var preferences = NoteFeedPreferences.shared

    static func shows(tab: HomeFeedTab) -> Bool {
        tab == .following && AuthStore.shared.isSignedIn
    }

    var body: some View {
        if Self.shows(tab: choice.tab) {
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
            get: { choice.tab },
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
