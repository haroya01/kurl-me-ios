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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30
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
    /// 손가락이 실제로 당기는 중일 때만 true — 플릭 관성의 바운스가 임계를 넘어도
    /// 다음 글로 튕겨가지 않게 한다.
    @State private var fingerDown = false
    /// 바닥 너머 당김의 진행도(0~1, 임계 90pt) — 큐의 셰브론·제목이 손가락을 따라온다.
    @State private var pullProgress: CGFloat = 0

    /// 떠 있는 유리 독 — 글 끝(컴포저·다음 글 큐 영역)에 닿으면 materialize 로 물러나
    /// 입력을 가리지 않는다. 후퇴는 "스크롤 여유가 충분한 글"에만 — 한 화면 남짓 글은
    /// 시작부터 끝이 보여 독이 영영 안 뜨는 회귀가 있었다(여유 120pt 미만이면 항상 유지).
    /// 키보드가 떠 있는 동안(댓글 입력)은 길이와 무관하게 물러난다.
    @State private var endVisible = false
    @State private var scrollable = false
    @State private var keyboardUp = false

    /// 글 끝의 작가 카드·다른 글 — 작가 글 목록은 한 번만 가져와 양쪽(카드·다음 글 큐)이 쓴다.
    @State private var authorPosts: [PostListItem] = []

    var body: some View {
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
                    // 커버는 엣지-투-엣지(컬럼 밖) — 본문 컬럼만 읽기 폭으로 좁힌다.
                    if let urlString = detail.post.ogImageUrl, let url = URL(string: urlString) {
                        StretchyCover(url: url, height: coverHeight)
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content(detail)
                    }
                    .frame(maxWidth: Metrics.readingColumn)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Metrics.gutter)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .ignoresSafeArea(edges: hasCover && !embedded ? .top : [])
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
            geometry.contentOffset.y + geometry.contentInsets.top > (hasCover ? coverHeight : 110)
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
        .toolbar {
            // 임베드 시 내비바는 호스트(발견)의 것 — 여러 장이 동시에 살아 있어
            // principal/공유를 끼우면 서로 싸운다.
            if !embedded {
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
                    }
                }
            }
        }
        .toolbarBackground(
            !embedded && hasCover && !showNavTitle ? .hidden : .automatic, for: .navigationBar)
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
                    offlineRef: (username: detail.author.username, slug: detail.post.slug)
                )
                .padding(.trailing, 14)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: endVisible)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: keyboardUp)
        .task {
            await model.load()
            // 덱은 lazy 페이지가 많아 바닥 근접 때만(loadMore 경로), 단독은 곧장 작가 컨텍스트.
            if !embedded { await loadAuthorContext() }
        }
    }

    /// 가로(compact 높이)에선 커버가 화면을 다 먹지 않게 낮춘다.
    private var coverHeight: CGFloat { verticalSizeClass == .compact ? 180 : 300 }

    private var hasCover: Bool {
        if case .loaded(let detail) = model.phase { return detail.post.ogImageUrl != nil }
        return false
    }

    private var loadedTitle: String {
        if case .loaded(let detail) = model.phase { return detail.post.title }
        return ""
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
            ForEach(Array(detail.blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        Array(authorPosts.filter { $0.slug != model.slug }.prefix(3))
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
                VStack(alignment: .leading, spacing: 0) {
                    // 헤딩 + "전체 보기" — 3편만 추리므로 작가 블로그로 이어지는 문을 같은 줄에 둔다.
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
                    .padding(.bottom, 6)
                    ForEach(Array(otherPosts.enumerated()), id: \.element.id) { index, post in
                        NavigationLink(
                            value: Route.post(username: author.username, slug: post.slug)
                        ) {
                            otherPostRow(post)
                        }
                        .buttonStyle(RowButtonStyle())
                        if index < otherPosts.count - 1 { Hairline() }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
    }

    private func header(_ detail: PublicPostDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: detail.post.ogImageUrl != nil ? 22 : 18)

            Text(detail.post.title)
                .font(.system(size: titleSize, weight: .bold))
                .tracking(-0.4)
                .lineSpacing(3)
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

            Hairline().padding(.top, 18)
        }
    }

    /// 다른 글 한 행 — 제목 한 줄짜리 텍스트 행이었던 것을 발췌·메타가 있는 도착 행 문법
    /// (구독함과 동일 계열)으로. 썸네일은 있을 때만 — 없는 글이 비뚤어 보이지 않게 trailing.
    private func otherPostRow(_ post: PostListItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.system(size: 15 * unit, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let excerpt = post.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 13 * unit))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let date = post.publishedAt {
                        Text(date.relativeShort)
                    }
                    if post.likeCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart")
                            Text("\(post.likeCount)").monospacedDigit()
                        }
                    }
                }
                .font(.system(size: 12 * metaUnit))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 1)
            }
            Spacer(minLength: 0)
            if let cover = post.ogImageUrl, let url = URL(string: cover) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Palette.hairline)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb, style: .continuous))
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
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
                ForEach(model.comments) { comment in
                    CommentRow(
                        model: model, comment: comment, replyTo: $replyTo,
                        postAuthorId: authorId
                    )
                    .padding(.leading, comment.parentId != nil ? 30 : 0)
                    // 답글의 소속을 눈으로 — 들여쓰기만으로는 스레드가 안 읽힌다.
                    // 스파인은 부모 아바타(32) 중심선(15) 자리에 내린다.
                    .overlay(alignment: .leading) {
                        if comment.parentId != nil {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Palette.hairlineStrong)
                                .frame(width: 2)
                                .padding(.vertical, 4)
                                .offset(x: 15)
                        }
                    }
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
    @State private var showTwoFactorHint = false
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
        .alert("로그인이 필요합니다", isPresented: $showLoginPrompt) {
            Button("Apple로 로그인") { appleHere() }
            Button("Google로 로그인") { signInHere() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("댓글은 kurl 계정으로 남겨집니다.")
        }
        .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactorHint) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("내 계정 탭에서 로그인을 완료해 주세요.")
        }
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

    private func signInHere() {
        Task {
            if (try? await AuthStore.shared.signIn()) == .twoFactorRequired {
                showTwoFactorHint = true
            }
        }
    }

    private func appleHere() {
        Task {
            if (try? await AuthStore.shared.signInWithApple()) == .twoFactorRequired {
                showTwoFactorHint = true
            }
        }
    }
}

/// 엣지-투-엣지 커버 — 당겨 내리면 늘어나는 네이티브 stretchy 헤더.
/// 카드 zoom 전환의 도착점이기도 하다.
private struct StretchyCover: View {
    let url: URL
    var height: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .scrollView).minY
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Palette.hairline)
            }
            .saturation(0.85)
            .overlay(Palette.coverVeil)
            .frame(width: geo.size.width, height: geo.size.height + max(0, minY))
            .clipped()
            .offset(y: min(0, -minY))
            .accessibilityHidden(true)
        }
        .frame(height: height)
    }
}

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
