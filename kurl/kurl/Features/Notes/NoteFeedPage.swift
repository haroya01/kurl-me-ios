//
//  NoteFeedPage.swift
//  kurl
//

import SwiftUI

struct NoteFeedPage: View {
    let kind: NoteFeedKind
    let model: NotesViewModel
    var active = true
    var warm = true

    @State private var loadedSignedIn: Bool?
    @State private var position = ScrollPosition(edge: .top)
    @State private var router = TabRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composing = false
    @State private var showLogin = false
    @State private var posted = 0
    @State private var composed: Note?
    @State private var feedChoice = NoteFeedChoice.shared
    @State private var trending = RemoteTrendingModel()

    var body: some View {
        ReadingColumn(
            spacing: 0, background: .clear, tracksTabBar: active, gutter: Metrics.noteGutter, position: $position
        ) {
            Color.clear.frame(height: 8)
            if kind == .federated {
                RemoteTrendingGroup(model: trending)
                if trending.isShown {
                    Hairline().padding(.horizontal, -Metrics.noteGutter)
                    RailHeading("받은 노트")
                        .padding(.top, 20)
                }
            }
            content
        }
        .onChange(of: router.topRequests) {
            guard active, router.topTab == 1 else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { position.scrollTo(edge: .top) }
        }
        .environment(\.noteFilterContext, model.filterContext)
        .task(id: [warm, AuthStore.shared.isSignedIn]) {
            let signedIn = AuthStore.shared.isSignedIn
            guard warm, loadedSignedIn != signedIn else { return }
            loadedSignedIn = signedIn
            await reload()
        }
        .brandRefreshable { await reload() }
        .task(id: active) {
            guard active, let y = Config.consumeLaunchValue(after: "--scroll-y").flatMap(Double.init) else { return }
            try? await Task.sleep(for: .seconds(2))
            position.scrollTo(y: y)
        }
        .onChange(of: NoteFeedPreferences.shared.changes) {
            if kind == .following { refresh() }
        }
        .onChange(of: NoteFeedPreferences.shared.mutes) { refresh() }
        .onChange(of: NoteFeedPreferences.shared.languageChanges) {
            if [.everyone, .federated, .trending].contains(kind) { refresh() }
        }
        .sheet(isPresented: $composing, onDismiss: {
            if let note = composed {
                composed = nil
                model.inserted(note)
                NoteFeedChoice.shared.arrived(note.id)
            }
        }) {
            NoteComposeSheet(mode: .new(quote: nil, inReplyToId: nil)) { note in
                composed = note
                posted += 1
            }
        }
        .onChange(of: feedChoice.arrivingID) { _, id in
            guard active, id != nil else { return }
            Task { @MainActor in
                await Task.yield()
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { position.scrollTo(edge: .top) }
            }
        }
        .loginPrompt(isPresented: $showLogin, message: loginMessage)
        .sensoryFeedback(.success, trigger: posted)
    }

    private func reload() async {
        guard kind == .federated else {
            await model.reload()
            return
        }
        async let notes: Void = model.reload()
        await trending.load()
        await notes
    }

    private func refresh() {
        if warm {
            Task { await model.reload() }
        } else {
            loadedSignedIn = nil
        }
    }

    private func compose() {
        if AuthStore.shared.isSignedIn {
            composing = true
        } else {
            showLogin = true
        }
    }

    private var loginMessage: LocalizedStringKey {
        switch kind {
        case .following: "팔로잉 피드를 보려면 로그인하세요"
        case .everyone, .trending: "노트를 쓰려면 로그인하세요"
        default: "노트를 보려면 로그인하세요"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let gate = gate, !AuthStore.shared.isSignedIn {
            FeedPlaceholder(
                title: gate,
                actionTitle: "로그인",
                action: { showLogin = true }
            )
            .padding(.top, 24)
        } else {
            feed
        }
    }

    private var gate: LocalizedStringKey? {
        switch kind {
        case .everyone, .trending: nil
        case .following: "로그인하면 블로그와 노트에서 팔로우한 사람의 노트가 여기 모여요."
        case .federated: "로그인하면 이 서버가 받은 마스토돈 같은 다른 서버의 공개 노트를 볼 수 있어요."
        case .bookmarks: "로그인하면 북마크한 노트를 여기서 다시 볼 수 있어요."
        case .direct: "로그인하면 멘션한 사람만 보는 노트가 여기 모여요."
        case .list: "로그인하면 리스트에 담은 사람의 노트를 볼 수 있어요."
        }
    }

    @ViewBuilder
    private var emptyFeed: some View {
        switch kind {
        case .everyone:
            FeedPlaceholder(title: "아직 노트가 없어요", actionTitle: "첫 노트 쓰기", action: compose)
        case .federated:
            FeedPlaceholder(
                title: "아직 받은 다른 서버 노트가 없어요",
                actionTitle: "최신 노트 보기",
                action: { NoteFeedChoice.shared.show(.everyone) }
            )
        case .following:
            FeedPlaceholder(
                title: "팔로우한 사람의 노트가 아직 없어요",
                actionTitle: "인기 노트 보기",
                action: { NoteFeedChoice.shared.show(.trending) }
            )
        case .bookmarks:
            FeedPlaceholder(
                title: "북마크한 노트가 없어요",
                actionTitle: "인기 노트 보기",
                action: { NoteFeedChoice.shared.show(.trending) }
            )
        case .list:
            FeedPlaceholder(
                title: "이 리스트에 아직 노트가 없어요",
                actionTitle: "리스트 관리",
                action: { NoteListsStore.shared.managing = true }
            )
        case .direct:
            FeedPlaceholder(title: "개인 멘션이 없어요", actionTitle: "노트 쓰기", action: compose)
        case .trending:
            FeedPlaceholder(title: "이번 주에 쓴 노트가 아직 없어요", actionTitle: "첫 노트 쓰기", action: compose)
        }
    }

    @ViewBuilder
    private var feed: some View {
        switch model.phase {
        case .idle, .loading:
            NoteSkeleton()
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await model.reload() } })
        case .loaded:
            if model.items.isEmpty {
                emptyFeed.padding(.top, 24)
            } else {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, note in
                    NoteFeedItem(
                        note: note,
                        onChange: { model.replaced($0) },
                        onDelete: { model.removed($0) },
                        onQuoted: { model.inserted($0) },
                        repostedBy: note.repostedBy?.username
                    )
                    .modifier(QuietAppear(index: note.id == feedChoice.arrivingID ? .max : index))
                    .modifier(NoteArrival(active: note.id == feedChoice.arrivingID))
                    .task { await model.loadMoreIfNeeded(current: note) }
                    if index < model.items.count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
                }
                if model.isLoadingMore {
                    KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                }
            }
        }
    }
}

struct NoteMoreFeedPage: View {
    let feed: NoteMoreFeed
    @State private var model: NotesViewModel

    init(feed: NoteMoreFeed) {
        self.feed = feed
        switch feed {
        case .kind(let kind): _model = State(initialValue: NotesViewModel(feed: kind))
        case .list(let id): _model = State(initialValue: NotesViewModel(list: id))
        }
    }

    var body: some View {
        NoteFeedPage(kind: feed.kind, model: model)
    }
}

struct NoteArrival: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = true
    @State private var washed = true

    func body(content: Content) -> some View {
        content
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : -16)
            .background {
                Palette.rowHighlight
                    .opacity(washed ? 0 : 1)
                    .padding(.horizontal, -Metrics.noteGutter)
            }
            .onAppear {
                guard active else { return }
                washed = false
                settled = reduceMotion
                withAnimation(.smooth(duration: 0.45)) { settled = true }
                withAnimation(.smooth(duration: 1.2)) { washed = true }
            }
    }
}
