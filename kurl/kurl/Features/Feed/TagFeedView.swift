//
//  TagFeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

enum TagFeedTab: Hashable {
    case posts, notes

    var label: LocalizedStringKey {
        switch self {
        case .posts: "글"
        case .notes: "노트"
        }
    }

    var key: String {
        switch self {
        case .posts: "posts"
        case .notes: "notes"
        }
    }
}

struct TagFeedView: View {
    let tag: String

    @State private var tab: TagFeedTab
    @State private var notes: NotesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: LoadState<[FeedItem]> = .idle
    @State private var page = 0
    @State private var hasNext = false
    @State private var loadingMore = false
    @State private var showNavTitle = false
    @Namespace private var zoomNS

    init(tag: String, initialTab: TagFeedTab = .posts) {
        self.tag = tag
        _tab = State(initialValue: initialTab)
        _notes = State(initialValue: NotesViewModel(tag: tag))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                // 태그 마스트헤드 — 시리즈 랜딩과 같은 결(eyebrow + 큰 #태그). 로딩부터 떠 있는다.
                masthead
                Section {
                    switch tab {
                    case .posts: postsContent
                    case .notes: notesContent
                    }
                } header: {
                    ContentTabBar(
                        tabs: [TagFeedTab.posts, .notes], selection: $tab, label: \.label,
                        identifier: { "tag.tab.\($0.key)" })
                }
            }
            .padding(.bottom, 16)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.pageBg)
        // 마스트헤드를 지나면 태그 이름이 내비바로 스민다(읽기 앱 문법) — 상단 중복 제거.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 56
        } action: { _, passed in
            withAnimation(.easeInOut(duration: 0.18)) { showNavTitle = passed }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("#\(tag)")
                    .typeScale(.titleSmall)
                    .opacity(showNavTitle ? 1 : 0)
            }
        }
        .toolbarBackground(showNavTitle ? .automatic : .hidden, for: .navigationBar)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .noteTextLinks()
        .task(id: tab) {
            switch tab {
            case .posts: await load()
            case .notes: if case .idle = notes.phase { await notes.reload() }
            }
        }
        .brandRefreshable {
            switch tab {
            case .posts: await reload()
            case .notes: await notes.reload()
            }
        }
    }

    @ViewBuilder
    private var postsContent: some View {
        switch phase {
        case .idle, .loading:
            KurlLoadingMark()
                .frame(maxWidth: .infinity, minHeight: 280)
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await load() } })
                .padding(.top, 60)
        case .loaded(let items):
            if items.isEmpty {
                FeedPlaceholder(
                    title: "글이 없어요",
                    message: "이 태그의 글이 아직 없어요.",
                    actionTitle: "피드에서 읽을 글 찾기",
                    action: { TabRouter.shared.switchTo(0, reduceMotion: reduceMotion) }
                )
                .padding(.top, 48)
            }
            // 태그 피드도 browse 면 — 검색·홈과 같은 카드 문법(웹 §10.1 예외 경계).
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                    BlogCard(item: item, omittingTag: tag)
                }
                .buttonStyle(CardButtonStyle())
                .cardQuickActions(item)
                .modifier(ZoomSource(
                    active: true,
                    id: "tag-\(item.author.username)-\(item.slug)",
                    ns: zoomNS))
                .modifier(QuietAppear(index: index))
                .modifier(CardScrollFade())
                .task {
                    if index >= items.count - 5 { await loadMore() }
                }
            }
            if loadingMore {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        switch notes.phase {
        case .idle, .loading:
            NoteSkeleton()
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await notes.reload() } })
                .padding(.top, 60)
        case .loaded:
            if notes.items.isEmpty {
                FeedPlaceholder(
                    title: "노트가 없어요",
                    message: "이 태그의 노트가 아직 없어요.",
                    actionTitle: "인기 노트 보기",
                    action: {
                        NoteFeedChoice.shared.show(.trending)
                        TabRouter.shared.switchTo(1, reduceMotion: reduceMotion)
                    }
                )
                .padding(.top, 48)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
                            note: note,
                            onChange: { notes.replaced($0) },
                            onDelete: { notes.removed($0) }
                        )
                        .modifier(QuietAppear(index: index))
                        .task { await notes.loadMoreIfNeeded(current: note) }
                        if index < notes.items.count - 1 { Hairline().padding(.horizontal, -Metrics.gutter) }
                    }
                    if notes.isLoadingMore {
                        KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
                .environment(\.noteFilterContext, notes.filterContext)
            }
        }
    }

    /// 태그 머리 — "태그" eyebrow + #태그 디스플레이 제목 + 구독 버튼. 페이지의 단일 히어로.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            RailHeading("태그")
            Text("#\(tag)")
                .typeScale(.display)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // 이 태그의 새 글을 구독함으로 — 웹 태그 페이지의 구독과 같은 동작.
            TagFollowButton(tag: tag)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func load() async {
        if case .loaded = phase { return }
        phase = .loading
        await reload()
    }

    private func reload() async {
        do {
            let result = try await BlogAPI.feed(tag: tag, page: 0, size: 30)
            page = 0
            hasNext = result.hasNext
            phase = .loaded(result.items)
        } catch {
            if case .loaded = phase {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            } else {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    private func loadMore() async {
        guard hasNext, !loadingMore, case .loaded(let current) = phase else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let result = try? await BlogAPI.feed(tag: tag, page: page + 1, size: 30) {
            page += 1
            hasNext = result.hasNext
            phase = .loaded(current + result.items)
        }
    }
}
