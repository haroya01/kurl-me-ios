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

    var body: some View {
        ReadingColumn(
            spacing: 0, background: .clear, tracksTabBar: active, gutter: Metrics.noteGutter, position: $position
        ) {
            Color.clear.frame(height: 8)
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
            await model.reload()
        }
        .brandRefreshable { await model.reload() }
        .onChange(of: NoteFeedPreferences.shared.changes) {
            if kind == .following { refresh() }
        }
        .onChange(of: NoteFeedPreferences.shared.mutes) { refresh() }
        .onChange(of: NoteFeedPreferences.shared.languageChanges) {
            if [.everyone, .federated, .trending].contains(kind) { refresh() }
        }
        .sheet(isPresented: $composing) {
            NoteComposeSheet(mode: .new(quote: nil, inReplyToId: nil)) { note in
                model.inserted(note)
                posted += 1
            }
        }
        .loginPrompt(isPresented: $showLogin, message: loginMessage)
        .sensoryFeedback(.success, trigger: posted)
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
        case .following: "로그인하고 팔로잉 피드 보기"
        case .everyone, .trending: "로그인하고 노트 쓰기"
        default: "로그인하고 노트 보기"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let gate = gate, !AuthStore.shared.isSignedIn {
            FeedPlaceholder(
                title: gate.title,
                message: gate.message,
                actionTitle: "로그인",
                prominent: true,
                action: { showLogin = true }
            )
            .padding(.top, 56)
        } else {
            feed
        }
    }

    private var gate: (title: LocalizedStringKey, message: LocalizedStringKey)? {
        switch kind {
        case .everyone, .trending: nil
        case .following:
            ("팔로우한 사람의 노트만 모아 봐요", "로그인하면 블로그와 노트에서 팔로우한 사람의 노트가 여기 모여요.")
        case .federated:
            ("다른 서버의 노트", "로그인하면 이 서버가 받은 마스토돈 같은 다른 서버의 공개 노트를 볼 수 있어요.")
        case .bookmarks:
            ("나만 보는 북마크", "로그인하면 북마크한 노트를 여기서 다시 볼 수 있어요.")
        case .direct:
            ("나에게 온 개인 멘션", "로그인하면 멘션한 사람만 보는 노트가 여기 모여요.")
        case .list:
            ("리스트", "로그인하면 리스트에 담은 사람의 노트를 볼 수 있어요.")
        }
    }

    @ViewBuilder
    private var emptyFeed: some View {
        switch kind {
        case .everyone:
            FeedPlaceholder(
                title: "아직 노트가 없어요",
                message: "제목도 형식도 없이, 지금 떠오른 한 줄을 남기는 자리예요.",
                actionTitle: "첫 노트 쓰기",
                prominent: true,
                action: compose
            )
        case .federated:
            FeedPlaceholder(
                title: "아직 받은 다른 서버 노트가 없어요",
                message: "검색에 @아이디@서버를 적어 다른 서버 계정을 팔로우하면, 그 노트가 여기와 팔로잉에 와요.",
                actionTitle: "최신 노트 보기",
                prominent: true,
                action: { NoteFeedChoice.shared.show(.everyone) }
            )
        case .following:
            FeedPlaceholder(
                title: "팔로우한 사람의 노트가 여기 모여요",
                message: "블로그에서 팔로우한 사람도 함께 보여요. 인기 노트에서 시작해 보세요.",
                actionTitle: "인기 노트 보기",
                prominent: true,
                action: { NoteFeedChoice.shared.show(.trending) }
            )
        case .bookmarks:
            FeedPlaceholder(
                title: "북마크한 노트가 없어요",
                message: "노트의 … 메뉴나 상세의 북마크로 모아 둘 수 있어요. 북마크는 나만 봐요.",
                actionTitle: "인기 노트 보기",
                prominent: true,
                action: { NoteFeedChoice.shared.show(.trending) }
            )
        case .list:
            FeedPlaceholder(
                title: "이 리스트에 아직 노트가 없어요",
                message: "프로필의 … 메뉴에서 \"리스트에 추가\"로 사람을 담으면 그 사람들의 노트가 여기 모여요.",
                actionTitle: "리스트 관리",
                prominent: true,
                action: { NoteListsStore.shared.managing = true }
            )
        case .direct:
            FeedPlaceholder(
                title: "개인 멘션이 없어요",
                message: "공개 범위를 \"멘션한 사람만\"으로 정한 노트가 여기 모여요. 나와 멘션된 회원만 봐요.",
                actionTitle: "노트 쓰기",
                prominent: true,
                action: compose
            )
        case .trending:
            FeedPlaceholder(
                title: "이번 주에 쓴 노트가 아직 없어요",
                message: "일주일 안에 쓴 노트 중 반응을 많이 받은 노트가 먼저 올라와요.",
                actionTitle: "첫 노트 쓰기",
                prominent: true,
                action: compose
            )
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
                emptyFeed.padding(.top, 56)
            } else {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, note in
                    NoteFeedItem(
                        note: note,
                        onChange: { model.replaced($0) },
                        onDelete: { model.removed($0) },
                        onQuoted: { model.inserted($0) },
                        repostedBy: note.repostedBy?.username
                    )
                    .modifier(QuietAppear(index: index))
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

struct NoteFeedScreen: View {
    let kind: NoteFeedKind
    private let listId: Int64?
    private let listTitle: String?
    @State private var model: NotesViewModel
    @State private var lists = NoteListsStore.shared

    init(kind: NoteFeedKind) {
        self.kind = kind
        listId = nil
        listTitle = nil
        _model = State(initialValue: NotesViewModel(feed: kind))
    }

    init(listId: Int64, title: String) {
        kind = .list
        self.listId = listId
        listTitle = title
        _model = State(initialValue: NotesViewModel(list: listId))
    }

    var body: some View {
        NoteFeedPage(kind: kind, model: model)
            .background(Palette.readingBg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
    }

    private var title: Text {
        guard let listId else { return Text(kind.title) }
        return Text(verbatim: lists.lists.first { $0.id == listId }?.title ?? listTitle ?? "")
    }
}
