//
//  PostDetailView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import UIKit

struct PostDetailView: View {
    @State private var model: PostDetailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    /// 발견 덱이 페이지로 품을 때 true — 같은 화면을 그대로 쓰되, 내비바(제목 스밈·공유)와
    /// 커버의 세이프에어리어 침범은 덱의 것이 아니므로 끄고, 조회 비콘도 덱의 체류
    /// 판정에 맡긴다(여러 장이 lazy 로 살아 있어 load 시점 비콘은 부풀려진다).
    private let embedded: Bool

    init(username: String, slug: String, embedded: Bool = false) {
        self.embedded = embedded
        _model = State(initialValue: PostDetailViewModel(
            username: username, slug: slug, recordsView: !embedded))
    }

    /// 헤더를 지나면 제목이 내비바로 스며들고(아이폰 리딩 앱 문법), 커버가 있으면
    /// 그 동안 내비바 배경을 숨겨 커버가 상단을 다 쓴다.
    @State private var showNavTitle = false
    @State private var replyTo: Comment?

    /// 덱 임베드 전용 — 댓글은 접힌 행으로 시작하고, 본문 끝에서 더 당기면
    /// 같은 작가의 다음 글로 이어진다(가로 = 다른 작가, 세로 = 이 작가 더 보기).
    @State private var commentsExpanded = false

    /// 댓글 입력 = 키보드 위에 붙는 유리 바(채팅 문법). 본문 끝 프롬프트 행이나
    /// 답글 버튼이 이걸 깨운다 — 인라인 입력은 키보드와 위치가 따로 놀았다.
    @State private var composerActive = false
    @State private var nextPost: PostListItem?
    @State private var nextFetched = false
    @State private var showNext = false
    /// 내 글을 볼 때만 뜨는 작가 동작 — 편집(에디터)·분석(이 글 성과).
    @State private var editingOwnPost = false
    @State private var showOwnAnalytics = false
    /// 남의 글 신고(더 보기 메뉴).
    @State private var showReport = false
    /// 손가락이 실제로 당기는 중일 때만 true — 플릭 관성의 바운스가 임계를 넘어도
    /// 다음 글로 튕겨가지 않게 한다.
    @State private var fingerDown = false
    /// 바닥 너머 당김의 진행도(0~1, 임계 90pt) — 큐의 셰브론·제목이 손가락을 따라온다.
    @State private var pullProgress: CGFloat = 0
    /// 읽기 진행도(0~1). 시그니처 = 이 진행을 kurl 3-bar 마크가 왼쪽부터 그려지며 표현한다.
    @State private var readProgress: CGFloat = 0
    /// 끝까지 읽으면 마크가 완성되는 한 번의 모먼트(완독). 위로 다시 올라가면 재무장.
    @State private var readComplete = false

    /// 떠 있는 유리 독 — 글 끝(컴포저·다음 글 큐 영역)에 닿으면 materialize 로 물러나
    /// 입력을 가리지 않는다. 후퇴는 "스크롤 여유가 충분한 글"에만 — 한 화면 남짓 글은
    /// 시작부터 끝이 보여 독이 영영 안 뜨는 회귀가 있었다(여유 120pt 미만이면 항상 유지).
    /// 키보드가 떠 있는 동안(댓글 입력)은 길이와 무관하게 물러난다.
    @State private var endVisible = false
    @State private var scrollable = false
    @State private var keyboardUp = false

    /// 글 끝의 작가 카드·다른 글 — 작가 글 목록은 한 번만 가져와 양쪽(카드·다음 글 큐)이 쓴다.
    @State private var authorPosts: [PostListItem] = []

    /// 리더 소셜 하이라이트 — 본 글(단독)에서만. 본문 문단이 환경에서 읽어 칠하고 만든다.
    /// 임베드(덱)는 만들지 않아 종전 렌더 그대로다.
    @State private var highlights: PostHighlightStore?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                switch model.phase {
                case .idle, .loading:
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { Task { await model.load() } }
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(.top, 80)
                case .loaded(let detail):
                    // 커버 헤더 없음 — 제목이 항상 맨 위(커버·무커버 글 제목 위치 일관).
                    // 커버 이미지가 의미 있으면 작가가 본문에 넣고, 발견 카드엔 그대로 남는다.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content(detail)
                    }
                    .frame(maxWidth: Metrics.readingColumn)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Metrics.gutter)
                    // 본문 문단이 선택→하이라이트 + 공개 하이라이트 페인트를 띄울 수 있게.
                    .environment(\.postHighlightStore, highlights)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // 제목이 내비바로 스밀 때까지(showNavTitle) 상단 엣지 효과를 끈다 — 투명 헤더 위
        // 제목이 깔끔히 떠 있게. 덱(임베드)은 항상 끈다.
        .scrollEdgeEffectHidden(embedded || !showNavTitle, for: .top)
        .background(Palette.readingBg.ignoresSafeArea())
        // 스크롤 여유가 충분한지 — 독 후퇴 판정의 전제(짧은 글은 독이 유일한 인게이지 표면).
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height > geometry.containerSize.height + 120
        } action: { _, isScrollable in
            scrollable = isScrollable
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in keyboardUp = true }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in keyboardUp = false }
        .onChange(of: model.comments) {
            // 답글 대상이 삭제/소실되면 답글 모드를 푼다 — 영구 실패 루프 방지.
            if let target = replyTo, !model.comments.contains(where: { $0.id == target.id }) {
                replyTo = nil
            }
        }
        .onChange(of: replyTo) { _, target in
            if target != nil { composerActive = true }
        }
        // 키보드 위에 붙는 유리 댓글 바 — safeAreaInset 이 키보드를 따라 위치를 보장한다.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if composerActive {
                GlassCommentBar(model: model, replyTo: $replyTo) {
                    composerActive = false
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: composerActive)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 110
        } action: { _, passed in
            guard !embedded else { return }
            withAnimation(.easeInOut(duration: 0.18)) { showNavTitle = passed }
        }
        // 임베드 전용: 바닥까지 남은 거리. 가까워지면 다음 글을 미리 찾고,
        // 바닥을 지나 90pt 이상 당기면 다음 글로 넘어간다.
        // 본문이 화면보다 짧으면 스크롤(러버밴드)이 없어 당김이 불가능 — 0 을 돌려
        // 프리페치는 즉시 일어나게 하고, 이동은 큐 탭에 맡긴다.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            guard geometry.containerSize.height > 0,
                  geometry.contentSize.height > geometry.containerSize.height
            else { return 0 }
            return geometry.contentSize.height
                - (geometry.contentOffset.y + geometry.containerSize.height)
        } action: { _, remaining in
            guard embedded else { return }
            if remaining < 600, !nextFetched {
                nextFetched = true
                Task { await loadAuthorContext() }
            }
            pullProgress = remaining < 0 ? min(1, -remaining / 90) : 0
            if remaining < -90, fingerDown, nextPost != nil, !showNext {
                showNext = true
            }
        }
        // 읽기 진행도 — 본문을 얼마나 내려왔는지 0~1 로(덱·단독 공통).
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let total = geometry.contentSize.height - geometry.containerSize.height
            guard total > 1 else { return 0 }
            let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
            return min(1, max(0, scrolled / total))
        } action: { _, progress in
            readProgress = progress
            // 완독 모먼트 — 거의 끝(0.985)에 닿으면 마크 완성 한 번. 0.9 아래로 되돌아가면 재무장.
            if progress >= 0.985, !readComplete {
                readComplete = true
            } else if progress < 0.9, readComplete {
                readComplete = false
            }
        }
        .onScrollPhaseChange { _, newPhase in
            if embedded { fingerDown = newPhase == .interacting }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: showNext)
        .navigationDestination(isPresented: $showNext) {
            if let nextPost {
                // 당겨서 명시적으로 넘어간 글 — 정상 상세(자체 비콘 포함)로 푸시.
                PostDetailView(username: model.username, slug: nextPost.slug)
            }
        }
        .navigationDestination(isPresented: $editingOwnPost) {
            if case .loaded(let detail) = model.phase {
                ComposeView(post: myPost(from: detail), onSaved: {})
            }
        }
        .navigationDestination(isPresented: $showOwnAnalytics) {
            if case .loaded(let detail) = model.phase {
                PostAnalyticsView(post: topPost(from: detail))
            }
        }
        .toolbar {
            // 임베드 시 내비바는 호스트(발견)의 것 — 여러 장이 동시에 살아 있어
            // principal/공유를 끼우면 서로 싸운다.
            if !embedded {
                // 헤딩 2개 이상이면 목차 — 탭하면 그 자리로 스크롤(웹 post-toc 의 네이티브 번역).
                if headings.count >= 2 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(headings, id: \.id) { h in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(h.id, anchor: UnitPoint(x: 0, y: 0.08))
                                    }
                                } label: {
                                    Text(String(repeating: "   ", count: h.level - 1) + h.title)
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .tint(.brand)
                        .accessibilityLabel("목차")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(loadedTitle)
                        .font(.system(size: 16 * unit, weight: .semibold))
                        .lineLimit(1)
                        .opacity(showNavTitle ? 1 : 0)
                }
                ToolbarItem(placement: .primaryAction) {
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("공유"))
                    }
                }
                // 내 글이면 — 읽으면서 바로 편집·분석으로 갈 수 있게 작가 동작을 같이 노출.
                if isOwnPost {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showOwnAnalytics = true } label: {
                            Image(systemName: "chart.bar")
                        }
                        .tint(.brand)
                        .accessibilityLabel("이 글 분석")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { editingOwnPost = true } label: {
                            Image(systemName: "pencil")
                        }
                        .tint(.brand)
                        .accessibilityLabel("이 글 편집")
                    }
                } else if loadedPostId != nil {
                    // 남의 글이면 — 더 보기 메뉴에 신고(UGC 신고 경로).
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) { showReport = true } label: {
                                Label("신고", systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .tint(.brand)
                        .accessibilityLabel("더 보기")
                    }
                }
            }
        }
        .reportDialog(isPresented: $showReport, subjectType: "POST", subjectId: loadedPostId ?? 0)
        // 스크롤로 제목이 스밀 때까지는 내비바 배경을 숨긴다 — 커버 유무와 무관하게.
        // (무커버 글 진입 때 .automatic 의 반투명 내비바가 상단에 "투명한 박스"로 떴던 것 제거.)
        .toolbarBackground(
            !embedded && !showNavTitle ? .hidden : .automatic, for: .navigationBar)
        // 뒤로가기 = 셰브론-온리 유리 원판 — "< 피드" 텍스트 꼬리 제거(스와이프 백 유지).
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            // 단독·덱 임베드 공통의 단일 인게이지 문법 — 임베드별 인라인 줄을 두지 않는다.
            // 덱에선 장마다 제 페이지 안에 떠서 페이지와 함께 밀려 나간다.
            if case .loaded(let detail) = model.phase, !keyboardUp,
               !(endVisible && scrollable) {
                EngagementDock(
                    postId: detail.post.id, initialLikeCount: detail.post.likeCount,
                    offlineRef: (username: detail.author.username, slug: detail.post.slug),
                    connectTarget: (title: detail.post.title, postId: detail.post.id)
                )
                .padding(.trailing, 14)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        // 읽기 진행 = 상단 가는 막대(내비바 아래 한 줄). 왼쪽부터 그린으로 찬다 — 떠 있는
        // 마크 캡슐이 거슬린다는 피드백으로 조용한 띠로 되돌렸다.
        // 덱: 장 상단부터. 단독: 제목이 내비바로 스민 뒤(showNavTitle). 충분히 긴 글에만.
        .overlay(alignment: .top) {
            if scrollable, embedded || showNavTitle {
                GeometryReader { geo in
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: geo.size.width * min(1, max(0, readProgress)), height: 3)
                }
                .frame(height: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        // 완독 = 결과 햅틱 한 번(.success). trigger 닫힘(되돌아감)엔 울리지 않게 완료에만.
        .sensoryFeedback(trigger: readComplete) { _, done in done ? .success : nil }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: endVisible)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: keyboardUp)
        .task {
            await model.load()
            // 덱은 lazy 페이지가 많아 바닥 근접 때만(loadMore 경로), 단독은 곧장 작가 컨텍스트.
            if !embedded { await loadAuthorContext() }
        }
        // 완독 = 읽음. 긴 글은 끝까지 내려간 순간(readComplete) 찍는다 — '열기'가 아니라 '다 읽기'.
        .onChange(of: readComplete) { _, done in
            guard done, !embedded, let id = loadedPostId else { return }
            PostReadStore.shared.markRead(id)
        }
        // 짧은 글(스크롤 없음)은 완독 판정이 안 잡힌다 — 전체가 한 화면이라 잠깐 체류하면 읽음.
        // 긴 글은 여기서 안 찍고(레이아웃 후 scrollable=true) readComplete 경로에 맡긴다.
        .task(id: loadedPostId) {
            guard !embedded, let id = loadedPostId else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, !scrollable else { return }
            PostReadStore.shared.markRead(id)
        }
        // 리더 하이라이트 — 본 글일 때만 store 를 세우고 공개 하이라이트를 싣는다.
        .task(id: loadedPostId) {
            guard !embedded, let id = loadedPostId else {
                highlights = nil
                return
            }
            let store = PostHighlightStore(postId: id)
            highlights = store
            await store.load()
        }
        // 읽기 기록 비콘 — 로그인 독자가 글을 열면 계정에 기록(기기를 넘어 이어진다). 익명은 기록 없음.
        .task(id: loadedPostId) {
            guard !embedded, let id = loadedPostId, AuthStore.shared.isSignedIn else { return }
            await ReadingHistoryAPI.record(postId: id)
        }
        // 미로그인 사용자가 하이라이트를 시도하면 — 댓글·팔로우와 같은 공용 로그인 시트.
        .loginPrompt(
            isPresented: Binding(
                get: { highlights?.loginPrompt ?? false },
                set: { highlights?.loginPrompt = $0 }),
            message: "하이라이트는 kurl 계정에 저장됩니다.")
        }
    }

    private var loadedTitle: String {
        if case .loaded(let detail) = model.phase { return detail.post.title }
        return ""
    }

    /// 로드된 글의 id — 읽음 기록(완독·짧은 글 체류)의 키. 로딩 중엔 nil 이라 안 찍힌다.
    private var loadedPostId: Int64? {
        if case .loaded(let detail) = model.phase { return detail.post.id }
        return nil
    }

    /// 본문 헤딩(H1~H3) 목차 — 텍스트·앵커 id(블록 id)·들여쓰기 레벨.
    private var headings: [(id: Int, title: String, level: Int)] {
        guard case .loaded(let detail) = model.phase else { return [] }
        return detail.blocks.compactMap { block in
            let level: Int
            switch block.kind {
            case .h1: level = 1
            case .h2: level = 2
            case .h3: level = 3
            default: return nil
            }
            let text = (block.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (id: block.id, title: text, level: level)
        }
    }

    /// 로그인한 내가 이 글의 작가인가 — 편집·분석 동작은 이때만.
    private var isOwnPost: Bool {
        guard let myId = AuthStore.shared.me?.id,
              case .loaded(let detail) = model.phase else { return false }
        return detail.author.id == myId
    }

    /// 공개 상세 → 에디터용 MyPost. 본문(markdown)은 에디터가 id 로 다시 받는다.
    private func myPost(from detail: PublicPostDetail) -> MyPost {
        MyPost(
            id: detail.post.id, slug: detail.post.slug, title: detail.post.title,
            status: "PUBLISHED", publishedAt: detail.post.publishedAt, scheduledAt: nil,
            updatedAt: detail.post.lastEditedAt, tags: detail.post.tags,
            excerpt: detail.post.excerpt, ogImageUrl: detail.post.ogImageUrl, seriesId: nil)
    }

    /// 공개 상세 → 분석용 TopPostView. 수치는 분석 화면이 id 로 다시 받는다.
    private func topPost(from detail: PublicPostDetail) -> TopPostView {
        TopPostView(
            postId: detail.post.id, slug: detail.post.slug, title: detail.post.title,
            viewCount: 0, likeCount: detail.post.likeCount, followsGained: 0)
    }

    /// 네이티브 공유 시트용 공개 URL — 웹과 같은 주소.
    private var shareURL: URL? {
        guard case .loaded(let detail) = model.phase else { return nil }
        return URL(
            string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/p/\(detail.author.username)/\(detail.post.slug)")
    }

    // 읽기 흐름 우선: 커버 → 제목 → 작가 한 줄 → 본문. 태그와 좋아요는 다 읽은 뒤
    // 자연스럽게 만나도록 본문 끝으로 — 헤더에 끼어 있던 인터랙션 바가 진입을 막지 않는다.
    @ViewBuilder
    private func content(_ detail: PublicPostDetail) -> some View {
        header(detail)
        if model.isOfflineCopy {
            // 기기 사본 렌더 중 — 조용한 한 줄. 댓글·좋아요가 비어 있는 이유까지 여기서 설명된다.
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11 * metaUnit, weight: .semibold))
                Text("오프라인 사본 — 연결되면 최신으로 갱신됩니다")
                    .font(.system(size: 12 * metaUnit, weight: .medium))
            }
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.hairline, in: Capsule())
            .padding(.top, 14)
        }
        // 시리즈 글은 본문 전에 "여정의 몇 번째"부터 세운다 — 웹 SeriesNav 와 같은 자리.
        if let nav = detail.series {
            SeriesBanner(nav: nav, username: detail.author.username, currentSlug: detail.post.slug)
                .padding(.top, 22)
        }
        VStack(alignment: .leading, spacing: 2) {
            // 첫 문단은 lead — 독자를 글 안으로 들이는 한 호흡 큰 도입(에디토리얼 문법).
            let leadIndex = detail.blocks.firstIndex { $0.kind == .paragraph }
            ForEach(Array(detail.blocks.enumerated()), id: \.offset) { index, block in
                BlockView(block: block, isLead: index == leadIndex)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 목차가 이 블록으로 점프할 수 있게 앵커 — 헤딩만 쓰지만 전부 달아도 무해.
                    .id(block.id)
            }
        }
        .padding(.top, 20)

        if !detail.post.tags.isEmpty {
            FlowTags(tags: detail.post.tags)
                .padding(.top, 26)
        }
        // 완독 직후의 연결 — 다음 편 카드(시리즈) → 작가 카드 → 댓글 순.
        if let nav = detail.series {
            SeriesNextCard(nav: nav, username: detail.author.username)
        }
        authorCard(detail.author)
        comments(authorId: detail.author.id)
        if embedded, let next = nextPost {
            nextPostCue(next)
        }
        Color.clear.frame(height: 56)
            .onScrollVisibilityChange(threshold: 0.2) { visible in
                endVisible = visible
            }
    }

    /// 본문 끝의 조용한 신호 — 더 당기면 이 작가의 다음 글로 이어진다.
    /// 탭해도 간다: 짧은 글은 러버밴드가 없어 당김이 성립하지 않는다.
    private func nextPostCue(_ next: PostListItem) -> some View {
        Button {
            showNext = true
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 16 * unit, weight: .semibold))
                    .foregroundStyle(pullProgress > 0.97 ? Palette.link : Palette.faint)
                    .rotationEffect(.degrees(reduceMotion ? 0 : 180 * pullProgress))
                Text("계속 당기면 다음 글")
                    .font(.system(size: 12 * metaUnit))
                    .foregroundStyle(Palette.secondary)
                Text(next.title)
                    .font(.system(size: 14 * unit, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .opacity(0.6 + 0.4 * pullProgress)
                    .offset(y: reduceMotion ? 0 : 5 * (1 - pullProgress))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("다음 글 — \(next.title)")
    }

    /// 작가 글 목록 1회 로드 — 글 끝 작가 카드(다른 글)와 덱의 다음 글 큐가 함께 쓴다.
    private func loadAuthorContext() async {
        guard authorPosts.isEmpty,
              let list = try? await BlogAPI.authorPosts(username: model.username)
        else { return }
        authorPosts = list.posts
        if let idx = list.posts.firstIndex(where: { $0.slug == model.slug }),
           idx + 1 < list.posts.count {
            nextPost = list.posts[idx + 1]
        }
    }

    private var otherPosts: [PostListItem] {
        Array(authorPosts.filter { $0.slug != model.slug }.prefix(6))
    }

    /// 글 끝의 작가 카드 — 완독 직후가 팔로우 전환의 최적 순간. 글이 막다른 길로 끝나지 않게.
    private func authorCard(_ author: Author) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Hairline()
            NavigationLink(value: Route.author(username: author.username)) {
                HStack(spacing: 12) {
                    AvatarView(author: author, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(author.username)
                            .font(.system(size: 16 * unit, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        if let bio = author.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 13 * unit))
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12 * metaUnit, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            FollowButton(username: author.username)

            if !otherPosts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // 헤딩 + "전체 보기" — 일부만 추리므로 작가 블로그로 이어지는 문을 같은 줄에 둔다.
                    HStack(alignment: .firstTextBaseline) {
                        RailHeading("이 작가의 다른 글")
                        Spacer(minLength: 8)
                        NavigationLink(value: Route.author(username: author.username)) {
                            HStack(spacing: 2) {
                                Text("전체 보기")
                                    .font(.system(size: 13 * metaUnit, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10 * metaUnit, weight: .semibold))
                            }
                            .foregroundStyle(Palette.link)
                            .expandTapTarget(8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(author.username)님의 글 전체 보기")
                    }
                    // 평평한 목록 대신 커버 카드 가로 레일 — 작가 시리즈 레일과 같은 책장 문법.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(otherPosts) { post in
                                NavigationLink(
                                    value: Route.post(username: author.username, slug: post.slug)
                                ) {
                                    otherPostCard(post)
                                }
                                .buttonStyle(CardButtonStyle())
                                .modifier(CardScrollFade(axis: .horizontal))
                            }
                        }
                        .padding(.vertical, 4) // 카드 그림자가 레일 가장자리에서 잘리지 않게.
                    }
                    .scrollClipDisabled()
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
    }

    private func header(_ detail: PublicPostDetail) -> some View {
        // 제목 위 카테고리 eyebrow(대표 태그)가 내비바 아래 띠를 매거진 머릿글처럼 채운다.
        let kicker = detail.post.tags.first
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: kicker != nil ? 6 : 14)

            if let kicker {
                // 카테고리 eyebrow = 조용한 매거진 머릿글. 초록은 주액션(팔로우)·데이터 전용이므로
                // 여기선 muted — 대문자 트래킹으로 위계를 세우고 색은 빼는 절제(§10 색 규율).
                NavigationLink(value: Route.tag(kicker)) {
                    Text(kicker.uppercased())
                        .font(.system(size: 12 * metaUnit, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Palette.secondary)
                        .expandTapTarget(6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 9)
            }

            Text(detail.post.title)
                .typeScale(.display)
                .lineSpacing(6)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            NavigationLink(value: Route.author(username: detail.author.username)) {
                HStack(spacing: 9) {
                    AvatarView(author: detail.author, size: 28)
                    Text(detail.author.username)
                        .font(.system(size: 14 * unit, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if let date = detail.post.publishedAt {
                        Text("·").foregroundStyle(Palette.faint)
                        Text(date.mediumDate)
                            .font(.system(size: 13 * unit))
                            .foregroundStyle(Palette.secondary)
                    }
                    // 탭 가능한 행이라는 신호 — 어포던스 없는 링크는 없는 링크다.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * metaUnit, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            // 읽는 시간 — 글 입구에서 "얼마나 걸릴지" 한 호흡(에디토리얼 마스트헤드 메타).
            if let minutes = readingMinutes(detail.blocks) {
                HStack(spacing: 5) {
                    Image(systemName: "book")
                        .font(.system(size: 11 * metaUnit, weight: .medium))
                    Text("\(minutes)분 읽기")
                        .font(.system(size: 12 * metaUnit, weight: .medium))
                }
                .foregroundStyle(Palette.faint)
                .padding(.top, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("읽는 시간 약 \(minutes)분"))
            }

            Hairline().padding(.top, 18)
        }
    }

    /// 본문 글자 수로 읽는 시간 추정 — 한국어 ≈ 분당 500자, 최소 1분. 본문 없으면 nil.
    private func readingMinutes(_ blocks: [PostBlock]) -> Int? {
        let chars = blocks.reduce(0) { $0 + ($1.content?.count ?? 0) }
        guard chars > 0 else { return nil }
        return max(1, Int((Double(chars) / 500.0).rounded()))
    }

    /// 다른 글 한 장 — 커버(없으면 종이 플레이스홀더) + 제목 + 메타. 카드 문법(20곡률·
    /// 다층 그림자·다크 보더)은 발견 카드와 같은 토큰을 쓴다.
    private func otherPostCard(_ post: PostListItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let cover = post.ogImageUrl, let url = URL(string: cover) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            otherPostCover(post)
                        }
                    }
                } else {
                    otherPostCover(post)
                }
            }
            .frame(width: 220, height: 118)
            .clipped()

            VStack(alignment: .leading, spacing: 7) {
                Text(post.title)
                    .font(.system(size: 15 * unit, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let date = post.publishedAt {
                        Text(date.relativeShort)
                    }
                    if post.likeCount > 0 {
                        Text("·").foregroundStyle(Palette.faint)
                        HStack(spacing: 3) {
                            Image(systemName: "heart")
                            Text("\(post.likeCount)").monospacedDigit()
                        }
                    }
                }
                .font(.system(size: 12 * metaUnit))
                .foregroundStyle(Palette.secondary)
            }
            .padding(13)
            .frame(width: 220, alignment: .leading)
        }
        .frame(width: 220, height: 214, alignment: .top)
        .background(Palette.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
        .overlay {
            // 라이트는 그림자로 서고(보더=상자 느낌), 다크는 그림자가 죽어 보더 유지(발견 카드 규칙).
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
        }
        .cardShadow()
    }

    /// 커버 없는 글의 플레이스홀더 — 색 없이 흰 타일 + 옅은 회색 kurl 마크 워터마크.
    /// 태그가 있으면 좌상단에 작은 칩으로(맥락).
    private func otherPostCover(_ post: PostListItem) -> some View {
        ZStack {
            Color(uiColor: .systemBackground)
            KurlMark(drawn: [true, true, true], tint: Palette.hairlineStrong)
                .frame(width: 60, height: 36)
        }
        .overlay(alignment: .bottom) { Hairline() }
        .overlay(alignment: .topLeading) {
            if let tag = post.tags.first {
                Text("#\(tag)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }

    private func comments(authorId: Int64) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Hairline()
            // 덱에서는 접힌 행으로 — 읽기 흐름과 "당겨서 다음 글" 동작을 댓글이
            // 길게 끊지 않는다. 탭하면 그 자리에서 펼친다.
            if embedded, !commentsExpanded {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { commentsExpanded = true }
                } label: {
                    HStack(spacing: 8) {
                        RailHeading("댓글 \(model.comments.count)")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12 * metaUnit, weight: .semibold))
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("댓글 \(model.comments.count) 펼치기")
            } else {
                RailHeading("댓글 \(model.comments.count)")
                // 대화는 가벼운 행으로 — 스레드 사이만 헤어라인으로 나눈다(박스 카드 ❌).
                let threads = model.comments.filter { $0.parentId == nil }
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, parent in
                    CommentThread(
                        model: model,
                        comment: parent,
                        replies: model.comments.filter { $0.parentId == parent.id },
                        replyTo: $replyTo,
                        postAuthorId: authorId)
                    if index < threads.count - 1 { Hairline() }
                }
                // 본문 끝의 조용한 프롬프트 — 탭하면 유리 바가 키보드와 함께 떠오른다.
                Button {
                    composerActive = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 13 * unit))
                            .foregroundStyle(Palette.secondary)
                        Text("댓글을 남겨보세요")
                            .font(.system(size: 14 * unit))
                            .foregroundStyle(Palette.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("댓글을 남겨보세요")
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 16)
    }
}

/// 댓글 한 줄 — 좋아요(#538)·답글·내 댓글 삭제. 미로그인 인터랙션은 컴포저와 같은 로그인 유도.
/// 글 상세와 발견 덱의 댓글 시트가 공유한다.
struct CommentRow: View {
    let model: PostDetailViewModel
    let comment: Comment
    @Binding var replyTo: Comment?
    /// 글쓴이 표시용 — 댓글 작성자가 글 작가면 "작가" 칩이 붙는다.
    var postAuthorId: Int64?

    @State private var confirmDelete = false
    @State private var showReport = false
    @State private var likeTaps = 0
    @State private var deleteFailed = false
    @ScaledMetric(relativeTo: .subheadline) private var bodySize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var likedByMe: Bool { model.likedCommentIds.contains(comment.id) }
    private var isMine: Bool {
        guard let myId = AuthStore.shared.me?.id else { return false }
        return comment.author.id == myId
    }

    /// 답글은 한 단 작은 아바타로 — 들여쓰기와 함께 "이 사람 밑"임이 읽힌다.
    private var avatarSize: CGFloat { comment.parentId == nil ? 32 : 26 }

    var body: some View {
        // 2열 — 왼쪽 아바타, 오른쪽에 이름·본문·액션이 한 기둥으로 정렬된다.
        // (본문을 32pt 행잉 인덴트로 띄우던 옛 레이아웃은 한글에서 폭만 깎고 떠 보였다.)
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: Route.author(username: comment.author.username)) {
                AvatarView(author: comment.author, size: avatarSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(comment.author.username)님의 블로그"))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    NavigationLink(value: Route.author(username: comment.author.username)) {
                        Text(comment.author.username)
                            .font(.system(size: 14 * unit, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(.plain)
                    if let postAuthorId, comment.author.id == postAuthorId {
                        Text("작가")
                            .font(.system(size: 10 * metaUnit, weight: .semibold))
                            .foregroundStyle(Palette.link)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.chipBg, in: Capsule())
                    }
                    if let date = comment.createdAt {
                        Text(date.relativeShort)
                            .font(.system(size: 12 * metaUnit))
                            .foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                    if isMine {
                        Button {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12 * metaUnit))
                                .foregroundStyle(Palette.secondary)
                                .expandTapTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("댓글 삭제")
                    } else {
                        // 남의 댓글 — 더 보기 메뉴에 신고(subjectType=COMMENT).
                        Menu {
                            Button(role: .destructive) { showReport = true } label: {
                                Label("신고", systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12 * metaUnit))
                                .foregroundStyle(Palette.secondary)
                                .expandTapTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("댓글 더 보기")
                    }
                }
                Text(comment.body)
                    .font(.system(size: bodySize))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                HStack(spacing: 16) {
                    Button {
                        guard AuthStore.shared.isSignedIn else { return }
                        likeTaps += 1
                        Task { await model.toggleCommentLike(comment) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: likedByMe ? "heart.fill" : "heart")
                                .font(.system(size: 11 * metaUnit))
                                .symbolEffect(.bounce, value: reduceMotion ? false : likedByMe)
                            if model.displayLikeCount(comment) > 0 {
                                Text("\(model.displayLikeCount(comment))")
                                    .font(.system(size: 12 * metaUnit).monospacedDigit())
                                    .contentTransition(.numericText())
                            }
                        }
                        .foregroundStyle(likedByMe ? Palette.link : Palette.secondary)
                        .expandTapTarget()
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .light), trigger: likeTaps)
                    .accessibilityLabel(Text("댓글 좋아요"))
                    .accessibilityValue(Text("\(model.displayLikeCount(comment))"))
                    .accessibilityAddTraits(likedByMe ? [.isSelected] : [])
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: likedByMe)

                    // 답글은 최상위 댓글에만 — 1단 깊이 유지.
                    if comment.parentId == nil {
                        Button {
                            replyTo = comment
                        } label: {
                            Text("답글")
                                .font(.system(size: 12 * metaUnit, weight: .medium))
                                .foregroundStyle(Palette.secondary)
                                .expandTapTarget()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 1)
            }
        }
        .confirmationDialog("이 댓글을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                Task {
                    do { try await model.deleteComment(comment) }
                    catch { deleteFailed = true }
                }
            }
        }
        .alert("삭제하지 못했습니다", isPresented: $deleteFailed) {
            Button("확인", role: .cancel) {}
        }
        .reportDialog(isPresented: $showReport, subjectType: "COMMENT", subjectId: comment.id)
    }
}

/// 댓글 한 묶음(원댓글 + 답글) — 대화는 가벼운 행으로(박스 카드 ❌, 조용한 웹로그 표준).
/// 답글은 부모 아바타 중심선에서 내려오는 연결 스파인 + 들여쓰기로 "이 사람 밑"임이 읽힌다.
private struct CommentThread: View {
    let model: PostDetailViewModel
    let comment: Comment
    let replies: [Comment]
    @Binding var replyTo: Comment?
    var postAuthorId: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommentRow(
                model: model, comment: comment, replyTo: $replyTo, postAuthorId: postAuthorId)
            if !replies.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.hairlineStrong)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(replies) { reply in
                            CommentRow(
                                model: model, comment: reply, replyTo: $replyTo,
                                postAuthorId: postAuthorId)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.leading, 15)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 키보드 위에 붙는 유리 댓글 바 — 입력은 떠 있는 크롬이므로 유리(AGENTS §1).
/// safeAreaInset(.bottom) 이 키보드를 따라가 위치는 시스템이 보장한다.
/// 유리 위 주행동(보내기)은 솔리드 그린 원(§1.4 유리 중첩 금지).
struct GlassCommentBar: View {
    let model: PostDetailViewModel
    @Binding var replyTo: Comment?
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var body_ = ""
    @State private var sending = false
    @State private var sendFailed = false
    @State private var showLoginPrompt = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTo {
                HStack(spacing: 6) {
                    Text("\(replyTo.author.username)님에게 답글")
                        .font(.system(size: 12 * metaUnit))
                        .foregroundStyle(Palette.link)
                    Button {
                        self.replyTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13 * unit))
                            .foregroundStyle(.secondary)
                            .expandTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("답글 취소")
                }
            }
            if sendFailed {
                Text("전송하지 못했습니다 — 다시 시도해 주세요.")
                    .font(.system(size: 12 * metaUnit))
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    replyTo == nil ? "댓글을 남겨보세요" : "답글을 남겨보세요",
                    text: $body_, axis: .vertical
                )
                .font(.system(size: 15 * unit))
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { if canSend { send() } }

                Button {
                    send()
                } label: {
                    if sending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 34 * unit, height: 34 * unit)
                            .background(GlassTokens.prominentTint, in: Circle())
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15 * unit, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34 * unit, height: 34 * unit)
                            .background(
                                canSend ? GlassTokens.prominentTint : Color.secondary.opacity(0.45),
                                in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend || sending)
                .accessibilityLabel("댓글 보내기")
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .onAppear { focused = true }
        .onChange(of: focused) { _, isFocused in
            // 키보드를 내렸고 쓰던 글도 없으면 바도 물러난다(초안이 있으면 남아서 지킨다).
            if !isFocused, !sending,
               body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                replyTo = nil
                onDone()
            }
        }
        .loginPrompt(isPresented: $showLoginPrompt, message: "이 글에 생각을 남겨보세요")
    }

    private var canSend: Bool {
        !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        guard !sending else { return }
        sendFailed = false
        sending = true
        Task {
            defer { sending = false }
            do {
                try await model.postComment(
                    body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
                    parentId: replyTo?.id)
                body_ = ""
                replyTo = nil
                focused = false
                sendFailed = false
                onDone()
            } catch {
                sendFailed = true // 입력은 보존 — 실패를 보이게.
            }
        }
    }

}

/// 시그니처 — 읽기 진행을 kurl 3-bar 마크가 그려지며 표현한다. 옅은 트랙(미독) 위로 그린
/// 마크가 왼쪽부터 채워지고(progress), 완독하면(complete) 한 번 톡 튄다. 밋밋한 진행 띠를
/// 태그 줄바꿈 래핑 — muted 칩.
struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    NavigationLink(value: Route.tag(tag)) { MutedChip(text: tag) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 피드 카드 → 글 상세로 넘기는 가벼운 커버 힌트. 카드가 화면에 뜰 때 자기 커버를
/// 기억해 두면, 그 글로 들어갈 때 상세가 로딩 첫 프레임부터 커버를 깔아 zoom 전환이
/// 빈 막(반투명 내비바)이 아니라 사진으로 착지한다.
@MainActor
enum PostPeek {
    private static var covers: [String: String] = [:]

    static func remember(username: String, slug: String, cover: String?) {
        guard let cover, !cover.isEmpty else { return }
        covers["\(username)/\(slug)"] = cover
    }

    static func cover(username: String, slug: String) -> String? {
        covers["\(username)/\(slug)"]
    }
}
