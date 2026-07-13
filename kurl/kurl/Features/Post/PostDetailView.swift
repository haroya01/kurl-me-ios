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
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    /// 발견 덱이 페이지로 품을 때 true — 같은 화면을 그대로 쓰되, 내비바(제목 스밈·공유)와
    /// 커버의 세이프에어리어 침범은 덱의 것이 아니므로 끄고, 조회 비콘도 덱의 체류
    /// 판정에 맡긴다(여러 장이 lazy 로 살아 있어 load 시점 비콘은 부풀려진다).
    private let embedded: Bool
    /// 발견 딥링크 — 이 구절이 든 블록으로 스크롤해 잠깐 강조한다(없으면 평소대로 위에서부터 읽기).
    private let focusQuote: String?

    init(username: String, slug: String, embedded: Bool = false, focusQuote: String? = nil) {
        self.embedded = embedded
        self.focusQuote = focusQuote
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
    /// 내 글 파괴적 관리(발행취소·삭제) — 웹 write 관리와 같은 계약. 읽던 자리에서 바로 처리한다(감사 갭 ④).
    @State private var showUnpublishConfirm = false
    @State private var showDeleteConfirm = false
    /// 남의 글 신고·작가 차단(더 보기 메뉴).
    @State private var showReport = false
    @State private var showBlockConfirm = false
    /// 손가락이 실제로 당기는 중일 때만 true — 플릭 관성의 바운스가 임계를 넘어도
    /// 다음 글로 튕겨가지 않게 한다.
    @State private var fingerDown = false
    /// 스크롤 진행(읽기·당김) — 매 프레임 갱신되는 값이라 @State 로 두면 상세 body 전체가
    /// 프레임마다 재평가된다(블록 트리 재구성·목차 재순회). 진행을 그리는 잎 뷰만 구독하도록
    /// @Observable 참조로 분리해 부모 무효화를 끊는다.
    @State private var scrollProgress = ScrollProgress()
    /// 끝까지 읽으면 마크가 완성되는 한 번의 모먼트(완독). 위로 다시 올라가면 재무장.
    @State private var readComplete = false

    /// 본문 파생값(목차·읽는 시간) — body 재평가마다 전 블록을 다시 순회하지 않게
    /// 로드 시 1회 계산해 둔다(오프라인 사본 → 온라인 갱신 포함).
    @State private var headings: [(id: Int, title: String, level: Int)] = []
    @State private var readingMinutes: Int?

    /// 하이라이트가 "탭하면 대화"라는 걸 처음 한 번만 알려주는 코치(§10 조용히, 5초 후 사라짐).
    @State private var showHighlightCoach = false
    private static let highlightCoachKey = "seenHighlightTapCoach"

    /// 발견 딥링크 도착 시 그 블록을 잠깐 강조했다 사라지는 플래시. didFocus = 1회만.
    @State private var flashBlockId: Int?
    @State private var didFocus = false

    /// 떠 있는 유리 독 — 글 끝(컴포저·다음 글 큐 영역)에 닿으면 materialize 로 물러나
    /// 입력을 가리지 않는다. 후퇴는 "스크롤 여유가 충분한 글"에만 — 한 화면 남짓 글은
    /// 시작부터 끝이 보여 독이 영영 안 뜨는 회귀가 있었다(여유 120pt 미만이면 항상 유지).
    /// 키보드가 떠 있는 동안(댓글 입력)은 길이와 무관하게 물러난다.
    @State private var endVisible = false
    @State private var scrollable = false
    /// 끝맺음 감지선에 처음 닿았을 때의 읽기 진행도 — 이 아래로 되돌아 올라오면 독이 다시 뜬다.
    /// (감지선을 지나쳐 위로 사라져도 물러난 상태를 유지하기 위한 래치 기준점.)
    @State private var bodyEndProgress: CGFloat?
    @State private var keyboardUp = false

    /// 글 끝의 작가 카드·다른 글 — 작가 글 목록은 한 번만 가져와 양쪽(카드·다음 글 큐)이 쓴다.
    @State private var authorPosts: [PostListItem] = []

    /// 리더 소셜 하이라이트 — 본 글(단독)에서만. 본문 문단이 환경에서 읽어 칠하고 만든다.
    /// 임베드(덱)는 만들지 않아 종전 렌더 그대로다.
    @State private var highlights: PostHighlightStore?

    /// 하이라이트 표시/숨기기 — 남들 형광펜이 많으면 어지럽다는 독자를 위해. 기기 전역 취향이라
    /// 글마다 다시 정하지 않게 @AppStorage 로 영속하고, 로드 시 스토어에 밀어 넣는다(기본 = 표시).
    @AppStorage("hideOthersHighlights") private var hideHighlights = false

    /// 읽기 기록 비콘을 이미 보낸 글 id — pop-back 으로 task 가 재시작돼도 재전송하지 않는다.
    @State private var recordedHistoryId: Int64?

    // 상세 body 는 모디파이어 사슬이 길어 하나의 식으로는 타입 검사 예산을 넘는다 —
    // ScrollView + 스크롤/툴바 계열을 scrollBody 로 잘라 불투명 경계(some View)를 만들고,
    // 나머지(시트·태스크·오버레이)는 body 에서 이어 붙여 두 개의 작은 식으로 나눈다.
    @ViewBuilder
    private func scrollBody(_ proxy: ScrollViewProxy) -> some View {
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
                            .foregroundStyle(Palette.link)
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
        // 컴포저 밖(본문)을 탭하면 키보드를 내린다 — 빈 컴포저는 그대로 닫히고(초안이 있으면
        // 바는 남아 지킨다). 탭만 잡는 simultaneous 라 스크롤·보내기·첨부 탭은 그대로.
        .simultaneousGesture(
            composerActive ? TapGesture().onEnded { dismissComposerEditing() } : nil)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // 제목이 내비바로 스밀 때까지(showNavTitle) 상단 엣지 효과를 끈다 — 투명 헤더 위
        // 제목이 깔끔히 떠 있게. 덱(임베드)은 항상 끈다.
        .scrollEdgeEffectHidden(embedded || !showNavTitle, for: .top)
        .background(Palette.readingBg.ignoresSafeArea())
        // 스크롤 여유가 충분한지 — 독 후퇴 판정의 전제(짧은 글은 독이 유일한 인게이지 표면).
        // 한 번 스크롤 가능으로 판정되면 유지한다(글 길이는 스크롤로 줄지 않는데, 바닥에 닿으면
        // contentSize↔containerSize 관계가 잠깐 뒤집혀 false 로 흘러 끝맺음 위 독이 되살아났다).
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height > geometry.containerSize.height + 120
        } action: { _, isScrollable in
            if isScrollable { scrollable = true }
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
        // 목차·읽는 시간 재계산 — 오프라인 사본 → 온라인 갱신은 글 id 가 그대로라
        // (isOfflineCopy 만 바뀐다) 두 트리거를 함께 둔다.
        .onChange(of: loadedPostId) { refreshDerivedContent() }
        .onChange(of: model.isOfflineCopy) { refreshDerivedContent() }
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
            // 같은 값(평소엔 0) 재대입도 @Observable 은 통지한다 — 일반 스크롤 내내
            // 큐가 헛되이 다시 그려지지 않게 변할 때만 쓴다.
            let pull = remaining < 0 ? min(1, -remaining / 90) : 0
            if scrollProgress.pull != pull { scrollProgress.pull = pull }
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
            scrollProgress.read = progress
            // 완독 모먼트 — 거의 끝(0.985)에 닿으면 마크 완성 한 번. 0.9 아래로 되돌아가면 재무장.
            if progress >= 0.985, !readComplete {
                readComplete = true
            } else if progress < 0.9, readComplete {
                readComplete = false
            }
            // 독 래치 해제 — 끝맺음에 닿았던 지점보다 본문 위로 되돌아 오면 독을 다시 띄운다.
            if let end = bodyEndProgress, progress < end - 0.02, endVisible {
                endVisible = false
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
        .toolbar { detailToolbar(proxy) }
    }

    var body: some View {
        ScrollViewReader { proxy in
        scrollBody(proxy)
        .reportDialog(isPresented: $showReport, subjectType: "POST", subjectId: loadedPostId ?? 0)
        .blockDialog(
            isPresented: $showBlockConfirm,
            username: loadedAuthor?.username ?? "", userId: loadedAuthor?.id ?? 0)
        // 발행 취소 — 되돌릴 수 있는 동작이라 담담한 확인. 성공하면 이 화면은 공개 상태를 벗어나므로
        // 읽던 자리를 닫고 스튜디오로 돌아간다(비공개 글엔 공개 URL 이 없다).
        .alert("이 글의 발행을 취소할까요?", isPresented: $showUnpublishConfirm) {
            Button("발행 취소", role: .destructive) { Task { await unpublishOwnPost() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("글은 남지만 공개 주소가 닫혀 아무도 볼 수 없게 돼요. 언제든 다시 발행할 수 있어요.")
        }
        // 삭제 — 되돌릴 수 없는 동작. 성공하면 이 상세는 더 존재하지 않으므로 뒤로 돌아간다.
        .alert("이 글을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) { Task { await deleteOwnPost() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("글과 그 안의 내용이 영구히 지워져요. 되돌릴 수 없어요.")
        }
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
            // 컴포저가 깨어나는 즉시 물러난다 — keyboardUp(키보드 알림)은 한 박자 늦어 잠깐 겹쳤다.
            // 숨김은 opacity 로만 — hierarchy 에서 빼면 독의 @State 모델이 새로 만들어져
            // 숨김↔표시 사이클마다 hydrate GET 2건이 재발사되고 좋아요가 잠깐 꺼져 깜빡였다.
            if case .loaded(let detail) = model.phase {
                let dockHidden = keyboardUp || composerActive || (endVisible && scrollable)
                // 목차를 상단 크롬에서 내려 독 바로 위에 얹는다 — 항해 보조와 인게이지를 한 손
                // 닿는 자리에 모은다. 목차·독은 성격이 다른 독립 컨트롤이라 spacing 12 로 띄워
                // 각자 제 유리로 읽히게 하고(독 내부 문법과 동일), 후퇴는 독과 함께 한다.
                VStack(spacing: 12) {
                    if headings.count >= 2 { tocButton(proxy) }
                    EngagementDock(
                        postId: detail.post.id, initialLikeCount: detail.post.likeCount,
                        offlineRef: (username: detail.author.username, slug: detail.post.slug),
                        connectTarget: (title: detail.post.title, postId: detail.post.id)
                    )
                }
                .padding(.trailing, 14)
                .padding(.bottom, 10)
                .opacity(dockHidden ? 0 : 1)
                .allowsHitTesting(!dockHidden)
                .accessibilityHidden(dockHidden)
            }
        }
        // 읽기 진행 = 상단 가는 막대(내비바 아래 한 줄). 왼쪽부터 그린으로 찬다 — 떠 있는
        // 마크 캡슐이 거슬린다는 피드백으로 조용한 띠로 되돌렸다.
        // 덱: 장 상단부터. 단독: 제목이 내비바로 스민 뒤(showNavTitle). 충분히 긴 글에만.
        .overlay(alignment: .top) {
            if scrollable, embedded || showNavTitle {
                ReadProgressBar(progress: scrollProgress)
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
            // 푸시로 가려졌다 pop 되면 id 그대로여도 task 가 재시작된다 — 이미 세운 store 를
            // 새로 만들면 칠이 지워졌다 재로드까지 깜빡이므로 그대로 둔다.
            guard highlights?.postId != id else { return }
            let store = PostHighlightStore(postId: id)
            store.paintHidden = hideHighlights
            highlights = store
            await store.load()
            maybeShowHighlightCoach(store)
        }
        // 표시/숨기기 토글 — 켜고 끄면 곧바로 본문 칠이 걷히거나 돌아온다(스토어가 @Observable).
        .onChange(of: hideHighlights) { _, hidden in
            highlights?.paintHidden = hidden
        }
        // 읽기 기록 비콘 — 로그인 독자가 글을 열면 계정에 기록(기기를 넘어 이어진다). 익명은 기록 없음.
        // 가드 = pop-back task 재시작마다 재전송하지 않게(didFocus 와 같은 1회 패턴).
        .task(id: loadedPostId) {
            guard !embedded, let id = loadedPostId, AuthStore.shared.isSignedIn,
                  recordedHistoryId != id else { return }
            recordedHistoryId = id
            await ReadingHistoryAPI.record(postId: id)
        }
        // 발견 피드의 하이라이트 카드로 들어오면 — 그 구절이 든 블록으로 스크롤 + 잠깐 강조(1회).
        .task(id: loadedPostId) { await focusOnQuoteIfNeeded(proxy) }
        // 미로그인 사용자가 하이라이트를 시도하면 — 댓글·팔로우와 같은 공용 로그인 시트.
        .loginPrompt(
            isPresented: Binding(
                get: { highlights?.loginPrompt ?? false },
                set: { highlights?.loginPrompt = $0 }),
            message: "하이라이트는 kurl 계정에 저장됩니다.")
        // 칠해진 하이라이트 탭 → 답글 스레드.
        .sheet(isPresented: Binding(
            get: { highlights?.threadHighlightId != nil },
            set: { if !$0 { highlights?.threadHighlightId = nil } })) {
            if let store = highlights, let id = store.threadHighlightId, let hl = store.highlight(id: id) {
                HighlightThreadSheet(highlight: hl, store: store)
            }
        }
        // 스레드에서 "컬렉션에 연결" → 닫힌 뒤 여기서 ConnectSheet(왜 한 줄)로 그래프에 잇는다.
        .sheet(isPresented: Binding(
            get: { highlights?.connectTarget != nil },
            set: { if !$0 { highlights?.connectTarget = nil } })) {
            if let hl = highlights?.connectTarget {
                ConnectSheet(
                    targetKind: "하이라이트", targetTitle: hl.quote,
                    blockType: .highlight, refId: hl.id)
            }
        }
        // 선택→"메모" → 여백 노트와 함께 하이라이트 생성.
        .sheet(item: Binding(
            get: { highlights?.noteDraft },
            set: { highlights?.noteDraft = $0 })) { draft in
            HighlightNoteComposerSheet(draft: draft) { note in
                highlights?.create(
                    blockOrder: draft.blockOrder, startOffset: draft.startOffset,
                    endOffset: draft.endOffset, quote: draft.quote, note: note)
            }
        }
        .overlay(alignment: .bottom) {
            if showHighlightCoach { highlightCoach }
        }
        }
    }

    /// 상세 내비바 — 제목 + 우측 단일 ⋯ 메뉴(공유·작가 동작/편집·분석·관리·남의 글 차단·신고).
    /// 항해 보조인 목차는 크롬을 비우고 하단 독 위로 내려 인게이지와 한자리에 모았다(§1 유리 크롬).
    /// 임베드(덱)는 호스트 내비바를 쓰므로 비운다.
    @ToolbarContentBuilder
    private func detailToolbar(_ proxy: ScrollViewProxy) -> some ToolbarContent {
        // 임베드 시 내비바는 호스트(발견)의 것 — 여러 장이 동시에 살아 있어
        // principal/공유를 끼우면 서로 싸운다.
        if !embedded {
            ToolbarItem(placement: .principal) {
                Text(loadedTitle)
                    .font(.system(size: 16 * unit, weight: .semibold))
                    .lineLimit(1)
                    .opacity(showNavTitle ? 1 : 0)
            }
            // 나열하던 공유·분석·편집·관리를 단일 ⋯ 하나로 접는다 — 읽기 화면 크롬을 조용히
            // 비우고(§10), 액션은 한 번의 탭 뒤에 둔다. 조건부 노출은 그대로: 편집·분석 = 내 글만,
            // 신고 = 남의 글만, 공유 = 모두. 파괴적 동작(발행취소·삭제·차단·신고)은 시트/알림으로
            // 되묻는다(메뉴에서 바로 지워지지 않게).
            ToolbarItem(placement: .primaryAction) {
                if isOwnPost {
                    Menu {
                        shareMenuItem
                        highlightToggleItem
                        Button { showOwnAnalytics = true } label: {
                            Label("이 글 분석", systemImage: "chart.bar")
                        }
                        Button { editingOwnPost = true } label: {
                            Label("이 글 편집", systemImage: "pencil")
                        }
                        Section {
                            Button(role: .destructive) { showUnpublishConfirm = true } label: {
                                Label("발행 취소", systemImage: "eye.slash")
                            }
                            Button(role: .destructive) { showDeleteConfirm = true } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.brand)
                    // 관리(발행취소·삭제)를 품는 메뉴 — 접근성 라벨은 관리 진입로로 유지한다.
                    .accessibilityLabel("이 글 관리")
                } else if loadedPostId != nil, let author = loadedAuthor {
                    // 남의 글이면 — 공유 + 차단·신고(작가 프로필과 같은 문법). 차단을 여기 두어
                    // 거슬리는 글을 만난 자리에서 바로 처리하게 한다.
                    Menu {
                        shareMenuItem
                        highlightToggleItem
                        Section {
                            if BlockStore.shared.isBlocked(id: author.id) {
                                Button {
                                    Task {
                                        try? await BlockStore.shared.unblock(
                                            id: author.id, username: author.username)
                                        ToastCenter.shared.show(String(localized: "차단을 해제했어요"))
                                    }
                                } label: {
                                    Label("차단 해제", systemImage: "hand.raised.slash")
                                }
                            } else {
                                Button(role: .destructive) { showBlockConfirm = true } label: {
                                    Label("차단", systemImage: "hand.raised")
                                }
                            }
                            Button(role: .destructive) { showReport = true } label: {
                                Label("신고", systemImage: "flag")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.brand)
                    .accessibilityLabel("더 보기")
                } else {
                    // 작가 정보가 아직 없을 때(로딩 중 등)엔 공유만이라도 손에 남긴다.
                    Menu {
                        shareMenuItem
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.brand)
                    .accessibilityLabel("더 보기")
                }
            }
        }
    }

    /// ⋯ 메뉴 안의 공유 항목 — 모두에게 뜬다(공유 URL 이 준비됐을 때). 네이티브 공유 시트를 연다.
    /// 제목·아이콘을 미리보기로 직접 얹어, 시스템이 URL 을 원격 조회할 때까지 빈 카드로 있던
    /// 지연을 없앤다(§ 공유 시 제목·마크가 즉시 뜬다).
    @ViewBuilder
    private var shareMenuItem: some View {
        if let shareURL {
            // 제목 + 앱 마크를 미리보기로 직접 얹는다 — 커버가 있어도 원격 이미지는 비동기라
            // 늦게 뜨므로, 즉시 그릴 수 있는 번들 아이콘으로 첫 화면을 채운다.
            ShareLink(
                item: shareURL,
                preview: SharePreview(loadedTitle, icon: Image("LaunchMark"))
            ) {
                Label("공유", systemImage: "square.and.arrow.up")
            }
        }
    }

    /// ⋯ 메뉴 안의 하이라이트 표시 토글 — 칠할 하이라이트가 있을 때만 뜬다. 숨기면 본문의 형광펜이
    /// 걷히고(내 형광펜 생성은 그대로), 다시 켜면 돌아온다. 기기 전역 취향이라 @AppStorage 로 영속.
    @ViewBuilder
    private var highlightToggleItem: some View {
        if let store = highlights, !store.highlights.isEmpty {
            Button {
                hideHighlights.toggle()
            } label: {
                Label(
                    hideHighlights ? "하이라이트 표시" : "하이라이트 숨기기",
                    systemImage: hideHighlights ? "eye" : "eye.slash")
            }
        }
    }

    /// 목차 — 독 위에 얹힌 유리 원판. 탭하면 헤딩을 펼쳐 그 자리로 스크롤한다(웹 post-toc 의
    /// 네이티브 번역). 독의 좋아요·북마크와 같은 유리 문법(52 원판·시맨틱 심볼·materialize)이라
    /// 크롬으로 한 덩이로 읽히되, 성격이 다른 항해 컨트롤이라 12pt 떨어져 제 유리로 산다.
    private func tocButton(_ proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(headings, id: \.id) { h in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo(h.id, anchor: UnitPoint(x: 0, y: 0.08))
                    }
                } label: {
                    // 들여쓰기는 비분리 공백 — 메뉴가 선행 일반 공백을 트리밍해 레벨이 뭉개졌다.
                    Text(String(repeating: "\u{00A0}\u{00A0}\u{00A0}", count: h.level - 1) + h.title)
                }
            }
        } label: {
            // 유리 위 심볼은 시맨틱 스타일(§1.2) — vibrancy 가 가독을 만든다. 52 원판은 독과 같은 키.
            Image(systemName: "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCapsule(prominent: false)
        .accessibilityLabel(Text("목차"))
    }

    /// 첫 1회 — 하이라이트가 "탭하면 대화·메모"라는 걸 조용히 알려준다. 탭하거나 5초 지나면 사라진다.
    private var highlightCoach: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text("밑줄 친 문장을 탭하면 메모·대화가 열려요")
                .typeScale(.meta)
                .foregroundStyle(Palette.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.bottom, 40)
        .padding(.horizontal, Metrics.gutter)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onTapGesture { withAnimation(reduceMotion ? nil : .snappy) { showHighlightCoach = false } }
        .task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(reduceMotion ? nil : .snappy) { showHighlightCoach = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

    /// 로드된 글의 작가 — 남의 글일 때 차단 대상.
    private var loadedAuthor: Author? {
        if case .loaded(let detail) = model.phase { return detail.author }
        return nil
    }

    /// 발견 딥링크 — 구절이 든 블록으로 스크롤하고 잠깐 강조했다 사라진다. 공개 하이라이트는 이미
    /// 그 자리에 그린으로 칠해져 있어, 도착하면 그 문장에 바로 안착한다. 한 글에 한 번만.
    private func focusOnQuoteIfNeeded(_ proxy: ScrollViewProxy) async {
        guard !didFocus, let quote = focusQuote, !quote.isEmpty,
              case .loaded(let detail) = model.phase else { return }
        let needle = String(quote.prefix(16))
        guard let block = detail.blocks.first(where: { ($0.content ?? "").contains(needle) })
        else { return }
        didFocus = true
        try? await Task.sleep(for: .milliseconds(420))  // 레이아웃·하이라이트 페인트 후
        // reduce-motion = 스크롤·플래시 모두 즉시(스밈·페이드 없이) — 도착은 하되 움직임은 끈다.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
            proxy.scrollTo(block.id, anchor: UnitPoint(x: 0, y: 0.18))
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { flashBlockId = block.id }
        try? await Task.sleep(for: .milliseconds(1300))
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.7)) { flashBlockId = nil }
    }

    /// 대화가 달린 하이라이트가 있는 글에서, 처음 한 번만 "탭하면 열려요" 코치(§10 조용히).
    /// `--force-coach`(목 전용) = 플래그 무시하고 매번 — UI 테스트 결정성 진입로.
    private func maybeShowHighlightCoach(_ store: PostHighlightStore) {
        let forceCoach = Config.useMocks
            && ProcessInfo.processInfo.arguments.contains("--force-coach")
        let hasThreaded = store.highlights.contains {
            ($0.note?.isEmpty == false) || $0.replyCount > 0
        }
        guard !embedded, hasThreaded,
              forceCoach || !UserDefaults.standard.bool(forKey: Self.highlightCoachKey)
        else { return }
        if !forceCoach { UserDefaults.standard.set(true, forKey: Self.highlightCoachKey) }
        withAnimation(reduceMotion ? nil : .snappy) { showHighlightCoach = true }
    }

    /// 본문 파생값(목차·읽는 시간) 1회 계산 — 로드/오프라인 갱신 시점에만 전 블록을 순회한다.
    private func refreshDerivedContent() {
        guard case .loaded(let detail) = model.phase else {
            headings = []
            readingMinutes = nil
            return
        }
        headings = Self.extractHeadings(detail.blocks)
        readingMinutes = Self.estimateReadingMinutes(detail.blocks)
    }

    /// 본문 헤딩(H1~H3) 목차 — 텍스트·앵커 id(블록 id)·들여쓰기 레벨.
    private static func extractHeadings(_ blocks: [PostBlock]) -> [(id: Int, title: String, level: Int)] {
        blocks.compactMap { block in
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

    /// 발행 취소 — 라이브 글을 비공개로 내린다. 이 상세는 공개 URL 을 잃으므로 뒤로 돌아간다.
    /// 실패는 화면을 닫지 않고 토스트로만 알린다(읽던 자리 유지).
    private func unpublishOwnPost() async {
        guard let id = loadedPostId else { return }
        do {
            try await WriteAPI.unpublish(postId: id)
            ToastCenter.shared.show(String(localized: "발행을 취소했어요"))
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "발행을 취소하지 못했습니다"))
        }
    }

    /// 글 영구 삭제 — 성공하면 이 상세가 더 없으므로 뒤로 돌아간다. 실패는 토스트로만.
    private func deleteOwnPost() async {
        guard let id = loadedPostId else { return }
        do {
            try await WriteAPI.deletePost(postId: id)
            ToastCenter.shared.show(String(localized: "글을 삭제했어요"))
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "글을 삭제하지 못했습니다"))
        }
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

    /// 본문 탭 시 키보드 사임 — GlassCommentBar 의 focus 변화가 이어받아 빈 컴포저를 닫는다.
    private func dismissComposerEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // 읽기 흐름 우선: 제목 → 작가 한 줄 → 본문(커버 헤더 없음 — 제목이 항상 맨 위).
    // 태그와 좋아요는 다 읽은 뒤 자연스럽게 만나도록 본문 끝으로 — 헤더에 끼어 있던
    // 인터랙션 바가 진입을 막지 않는다.
    @ViewBuilder
    private func content(_ detail: PublicPostDetail) -> some View {
        header(detail)
        if model.isOfflineCopy {
            // 기기 사본 렌더 중 — 조용한 한 줄. 댓글·좋아요가 비어 있는 이유까지 여기서 설명된다.
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11 * metaUnit, weight: .semibold))
                Text("오프라인 사본 — 연결되면 최신으로 갱신됩니다")
                    .typeScale(.footnote)
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
                    // 딥링크 도착 시 잠깐 강조(그린 워시) — 그 문장이 "여기야" 신호.
                    .background(
                        flashBlockId == block.id ? Palette.highlightFlash : Color.clear,
                        in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
                    // 목차가 이 블록으로 점프할 수 있게 앵커 — 헤딩만 쓰지만 전부 달아도 무해.
                    .id(block.id)
            }
        }
        .padding(.top, 20)

        if !ContentValidity.renderableTags(detail.post.tags).isEmpty {
            FlowTags(tags: detail.post.tags)
                .padding(.top, 26)
        }
        // 완독 직후의 연결 — 다음 편 카드(시리즈) → 작가 카드 → 댓글 순.
        if let nav = detail.series {
            SeriesNextCard(nav: nav, username: detail.author.username)
        }
        // 본문이 끝나고 '끝맺음'(레일·작가 카드·댓글)이 시작되는 감지선. 뷰포트에 들면 독이 물러난다 —
        // 떠 있는 독이 그 아래 요소를 가리지 않게(§ 표면 매핑: "글 끝에선 후퇴"). 한 번 닿으면 그 지점의
        // 읽기 진행도를 기록해 두고, 감지선을 지나쳐 위로 사라져도(끝맺음을 계속 보는 동안) 물러난
        // 채로 둔다 — 예전엔 감지선을 지나치는 순간 독이 되살아나 댓글·레일을 덮었다. 본문으로
        // 되돌아 그 진행도 아래로 올라오면 다시 뜬다. 짧은 글은 scrollable 가드가 막아 독을 유지한다.
        Color.clear.frame(height: 1)
            .onScrollVisibilityChange(threshold: 0.1) { visible in
                if visible {
                    endVisible = true
                    if bodyEndProgress == nil { bodyEndProgress = scrollProgress.read }
                }
            }
        // 글 = 엣지가 보이는 노드 — 다 읽은 뒤, 이 글이 놓인 길 · 이어진 것 · 이은 사람으로 나간다.
        // 엣지가 하나도 없으면 그려지지 않고(막다른 길 방지는 아래 태그 기반 작가 레일이 맡는다),
        // 덱 임베드는 여러 장이 lazy 로 살아 있어 켜지 않는다(본 글에서만).
        if !embedded {
            PostEdges(postId: detail.post.id, authorUsername: detail.author.username)
                .padding(.top, 10)
        }
        authorCard(detail.author)
        comments(authorId: detail.author.id)
        if embedded, let next = nextPost {
            NextPostCue(next: next, progress: scrollProgress) { showNext = true }
        }
        // 바닥 여백 — 단독 글엔 떠 있는 독(바닥 원판 52 + 아래 10)만큼 자리를 비워 둔다.
        // 짧은 글(스크롤 없음)은 독이 물러날 계기(endVisible)가 없어 하단 댓글 프롬프트·작가
        // 카드 위에 영영 겹쳤다 — 이 여백이 마지막 인터랙션을 독 위로 올린다. 스크롤되는 글은
        // 끝에서 독이 후퇴하므로 이 여백이 남아돌 뿐 해가 없다(scrollable 에 의존하지 않아
        // 여백↔scrollable 되먹임 진동도 없다). 덱 임베드는 페이지마다 독이 함께 밀려 나가 제외.
        Color.clear.frame(height: embedded ? 56 : 78)
    }

    /// 작가 글 목록 1회 로드 — 글 끝 작가 카드(다른 글)와 덱의 다음 글 큐가 함께 쓴다.
    /// isEmpty 가드는 뷰 인스턴스 로컬이라 작가 레일로 같은 작가 글을 이어 읽으면
    /// 푸시되는 상세마다 전체 목록을 재요청했다 — 세션 캐시로 상세끼리 공유한다.
    private func loadAuthorContext() async {
        guard authorPosts.isEmpty else { return }
        if let cached = AuthorPostsCache.get(model.username) {
            applyAuthorPosts(cached)
            return
        }
        guard let list = try? await BlogAPI.authorPosts(username: model.username) else {
            // 실패 시 프리페치 플래그를 되돌려 다시 바닥에 닿을 때 재시도되게 —
            // 안 그러면 한 번 삐끗한 장에서 다음 글 큐가 영영 안 뜬다.
            nextFetched = false
            return
        }
        AuthorPostsCache.set(model.username, posts: list.posts)
        applyAuthorPosts(list.posts)
    }

    private func applyAuthorPosts(_ posts: [PostListItem]) {
        authorPosts = posts
        if let idx = posts.firstIndex(where: { $0.slug == model.slug }),
           idx + 1 < posts.count {
            nextPost = posts[idx + 1]
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
                            .typeScale(.titleSmall)
                            .foregroundStyle(Palette.ink)
                        if let bio = author.bio, !bio.isEmpty {
                            Text(bio)
                                .typeScale(.lede)
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
        let kicker = ContentValidity.renderableTags(detail.post.tags).first
        return VStack(alignment: .leading, spacing: 0) {
            // 단독 뷰의 내비바는 배경 없이 유리 캡슐만 떠 있어서, 제목이 6pt 에서 시작하면
            // 캡슐과 뭉개져 보인다. 캡슐 아래로 한 호흡 내려 시작(덱 임베드는 칸이 좁아 유지).
            Color.clear.frame(height: embedded ? (kicker != nil ? 6 : 14) : (kicker != nil ? 24 : 28))

            if let kicker {
                // 카테고리 eyebrow = 조용한 매거진 머릿글. 초록은 주액션(팔로우)·데이터 전용이므로
                // 여기선 muted — 대문자 트래킹으로 위계를 세우고 색은 빼는 절제(§10 색 규율).
                NavigationLink(value: Route.tag(kicker)) {
                    Text(kicker.uppercased())
                        .typeScale(.eyebrow)
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
                        .typeScale(.meta)
                        .foregroundStyle(Palette.ink)
                    if let date = detail.post.publishedAt {
                        Text("·").foregroundStyle(Palette.faint)
                        Text(date.mediumDate)
                            .typeScale(.meta)
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
            if let minutes = readingMinutes {
                HStack(spacing: 5) {
                    Image(systemName: "book")
                        .font(.system(size: 11 * metaUnit, weight: .medium))
                    Text("\(minutes)분 읽기")
                        .typeScale(.footnote)
                }
                .foregroundStyle(Palette.secondary)
                .padding(.top, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("읽는 시간 약 \(minutes)분"))
            }

            Hairline().padding(.top, 18)
        }
    }

    /// 본문 글자 수로 읽는 시간 추정 — 한국어 ≈ 분당 500자, 최소 1분. 본문 없으면 nil.
    /// 산문(문단·헤딩·인용)만 센다 — 코드·리스트·임베드·표의 content 는 JSON 직렬화라
    /// 글자 수가 부풀어 읽는 시간이 엉뚱해진다.
    private static func estimateReadingMinutes(_ blocks: [PostBlock]) -> Int? {
        let prose: Set<BlockKind> = [.paragraph, .h1, .h2, .h3, .quote]
        let chars = blocks.reduce(0) { sum, block in
            prose.contains(block.kind) ? sum + (block.content?.count ?? 0) : sum
        }
        guard chars > 0 else { return nil }
        return max(1, Int((Double(chars) / 500.0).rounded()))
    }

    /// 다른 글 한 장 — 커버(없으면 종이 플레이스홀더) + 제목 + 메타. 카드 문법(20곡률·
    /// 다층 그림자·다크 보더)은 발견 카드와 같은 토큰을 쓴다.
    private func otherPostCard(_ post: PostListItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let cover = post.ogImageUrl, let url = URL(string: cover) {
                    RemoteImage(url: url) { phase in
                        if case .success(let image) = phase {
                            // 채움 이미지는 프레임 밖으로 넘친다 — 클립은 그림만 자르고 히트는 못 잘라, 이웃 카드 탭을 먹는다.
                            image.resizable().scaledToFill().allowsHitTesting(false)
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
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
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
                .typeScale(.meta)
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
                    .typeScale(.footnote)
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
                        RailHeading(model.commentsFailed ? "댓글" : "댓글 \(model.comments.count)")
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
                RailHeading(model.commentsFailed ? "댓글" : "댓글 \(model.comments.count)")
                if model.commentsFailed {
                    Button {
                        Task { await model.reloadComments() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12 * metaUnit, weight: .semibold))
                            Text("댓글을 불러오지 못했습니다 — 다시 시도")
                                .typeScale(.footnote)
                        }
                        .foregroundStyle(Palette.secondary)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // 대화는 가벼운 행으로 — 스레드 사이만 헤어라인으로 나눈다(박스 카드 ❌).
                // 차단한 작가의 댓글·답글은 숨긴다(App Store 1.2 — 차단 = 그 사용자 콘텐츠 안 보임).
                let threads = model.comments.filter {
                    $0.parentId == nil && !BlockStore.shared.isBlocked($0.author.username)
                }
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, parent in
                    CommentThread(
                        model: model,
                        comment: parent,
                        replies: model.comments.filter {
                            $0.parentId == parent.id
                                && !BlockStore.shared.isBlocked($0.author.username)
                        },
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
                    .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl))
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

/// 스크롤 진행(읽기 0~1 · 바닥 너머 당김 0~1)의 전용 저장소. 매 프레임 갱신되는 값이라
/// @Observable 로 두어 이 값을 읽는 잎 뷰(진행 막대·다음 글 큐)만 다시 그려지고,
/// 상세 body 전체는 프레임 단위 무효화에서 벗어난다.
@MainActor
@Observable
private final class ScrollProgress {
    /// 읽기 진행도(0~1) — 상단 가는 막대가 왼쪽부터 그린으로 찬다.
    var read: CGFloat = 0
    /// 바닥 너머 당김의 진행도(0~1, 임계 90pt) — 큐의 셰브론·제목이 손가락을 따라온다.
    var pull: CGFloat = 0
}

/// 읽기 진행 막대(내비바 아래 한 줄) — 매 프레임 값은 이 잎 뷰만 구독한다.
private struct ReadProgressBar: View {
    let progress: ScrollProgress

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Palette.accent)
                .frame(width: geo.size.width * min(1, max(0, progress.read)), height: 3)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 본문 끝의 조용한 신호 — 더 당기면 이 작가의 다음 글로 이어진다.
/// 탭해도 간다: 짧은 글은 러버밴드가 없어 당김이 성립하지 않는다.
private struct NextPostCue: View {
    let next: PostListItem
    let progress: ScrollProgress
    let onAdvance: () -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            onAdvance()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 16 * unit, weight: .semibold))
                    .foregroundStyle(progress.pull > 0.97 ? Palette.link : Palette.faint)
                    .rotationEffect(.degrees(reduceMotion ? 0 : 180 * progress.pull))
                Text("계속 당기면 다음 글")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                Text(next.title)
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .opacity(0.6 + 0.4 * progress.pull)
                    .offset(y: reduceMotion ? 0 : 5 * (1 - progress.pull))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("다음 글 — \(next.title)")
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
    @State private var showBlockConfirm = false
    @State private var likeTaps = 0
    @State private var deleteFailed = false
    @State private var showLoginPrompt = false
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
                            .typeScale(.meta)
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
                            .typeScale(.meta)
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
                        // 남의 댓글 — 더 보기 메뉴에 차단·신고(글·작가 프로필과 같은 문법).
                        Menu {
                            if BlockStore.shared.isBlocked(id: comment.author.id) {
                                Button {
                                    Task {
                                        try? await BlockStore.shared.unblock(
                                            id: comment.author.id, username: comment.author.username)
                                        ToastCenter.shared.show(String(localized: "차단을 해제했어요"))
                                    }
                                } label: {
                                    Label("차단 해제", systemImage: "hand.raised.slash")
                                }
                            } else {
                                Button(role: .destructive) { showBlockConfirm = true } label: {
                                    Label("차단", systemImage: "hand.raised")
                                }
                            }
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
                    .typeScale(.body)
                    .foregroundStyle(Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                HStack(spacing: 16) {
                    Button {
                        // 미로그인은 침묵 대신 로그인 유도 — 컴포저·하이라이트와 같은 공용 시트.
                        guard AuthStore.shared.isSignedIn else {
                            showLoginPrompt = true
                            return
                        }
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
        // 알럿(중앙 모달) — confirmationDialog 은 regular width·세로 모두 부리 팝오버로 새어 나갔다.
        .alert("이 댓글을 삭제할까요?", isPresented: $confirmDelete) {
            Button("삭제", role: .destructive) {
                Task {
                    do { try await model.deleteComment(comment) }
                    catch { deleteFailed = true }
                }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("삭제하지 못했습니다", isPresented: $deleteFailed) {
            Button("확인", role: .cancel) {}
        }
        .reportDialog(isPresented: $showReport, subjectType: "COMMENT", subjectId: comment.id)
        .blockDialog(
            isPresented: $showBlockConfirm,
            username: comment.author.username, userId: comment.author.id)
        .loginPrompt(isPresented: $showLoginPrompt, message: "이 댓글에 공감하려면 로그인하세요")
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
                    .foregroundStyle(Palette.danger)
            }
            // 한 줄일 때 입력칸이 보내기 버튼(34pt)보다 낮게 깔려 위에 빈 띠가 생기던 것 —
            // 가운데 정렬로 입력칸이 버튼과 나란히 올라와 키보드 바로 위에 딱 붙는다.
            HStack(alignment: .center, spacing: 10) {
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
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.panelRadius))
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

/// 태그 줄바꿈 래핑 — muted 칩.
struct FlowTags: View {
    let tags: [String]

    var body: some View {
        // 불완전 자모·한 글자 부스러기 태그는 글 끝 태그 줄에서도 거른다.
        let renderable = ContentValidity.renderableTags(tags)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(renderable, id: \.self) { tag in
                    NavigationLink(value: Route.tag(tag)) { MutedChip(text: "#\(tag)") }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 작가 글 목록의 세션 캐시 — 작가 레일로 같은 작가의 글을 이어 읽을 때, 푸시되는
/// 상세마다 전체 목록 GET 이 반복되지 않게 상세끼리 공유한다. TTL 이 지나면 다시
/// 받아 새 글·삭제를 따라간다.
@MainActor
enum AuthorPostsCache {
    private static var entries: [String: (posts: [PostListItem], at: Date)] = [:]
    private static let ttl: TimeInterval = 300

    static func get(_ username: String) -> [PostListItem]? {
        guard let entry = entries[username], Date().timeIntervalSince(entry.at) < ttl
        else { return nil }
        return entry.posts
    }

    static func set(_ username: String, posts: [PostListItem]) {
        entries = entries.filter { Date().timeIntervalSince($0.value.at) < ttl }
        entries[username] = (posts, Date())
    }
}
