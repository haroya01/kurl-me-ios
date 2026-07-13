//
//  StudioView.swift
//  kurl
//

import SwiftUI

/// 글쓰기 탭 = 작가 스튜디오 — 웹 /write 허브 철학의 네이티브 번역.
/// [글 | 시리즈 | 분석] 이 한 지붕: 목록만 있던 허브에서, 시리즈와 분석이 1급으로 승격됐다
/// (분석이 무라벨 차트 아이콘 뒤에 숨어 있던 시절을 끝낸다). 로그아웃 상태는 표면 전체가 게이트.
struct StudioView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var section: StudioSection = .posts
    /// 한 번이라도 방문한 분면 — switch 로 갈아끼우면 뷰가 파괴돼 `.task` 가 전환마다
    /// 재발화(분석은 스피너부터 다시)하므로, 방문한 분면은 상주시켜 로드 상태를 살려둔다.
    @State private var visited: Set<StudioSection> = []
    /// 좌우 스와이프 인터랙티브 — 손가락 따라 분면이 슬라이드된다(현재 분면 오프셋). 인접 분면은
    /// 한 폭 옆에서 따라 들어온다. containerWidth = 스트립 한 칸 폭(전환·오프셋 계산 기준).
    @State private var dragX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var phase: LoadState<[MyPost]> = .idle
    @State private var filter: HubFilter = .all
    @State private var seriesList: [MySeries] = []
    @State private var seriesLoaded = false
    @State private var composing = false
    @State private var editing: MyPost?
    /// 방금 발행한 글 — 셀레브레이션 "글 보기" 가 에디터를 닫고 여기로 이어 보낸다(라이브 상세).
    @State private var justPublished: PublishedRef?
    /// 파괴적 관리(발행취소·삭제) 확인 대상 — 웹 write 관리와 같은 계약. nil 이면 확인창 닫힘.
    @State private var unpublishTarget: MyPost?
    @State private var deleteTarget: MyPost?

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    studio
                } else {
                    signedOutGate
                }
            }
            // 글·시리즈·분석 = 떠 있는 액체 유리 캡슐(내비바 대신) — 분면이 이 밑으로 흐른다.
            // 콘텐츠와 같은 표면에서 좌우로 넘기고, 스위처는 그 위에 뜬 크롬(§1 액체 크롬/종이 본문).
            // 내비바 principal 의 맨몸 세그먼트는 유리 없이 판판했다 — 피드와 같은 떠 있는 유리로 통일.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(auth.isSignedIn ? .hidden : .automatic, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                if auth.isSignedIn {
                    // 좌측 '새 글' 폭만큼의 투명 균형추 — 스위처가 화면 정중앙에 오게(피드의 벨 보정과 같은 수법).
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 44, height: 40)
                        Spacer(minLength: 0)
                        // 스위처와 '새 글'은 한 영역의 유리 둘 — 컨테이너 하나로 묶어 각자 겉돌지 않게(§1.4).
                        GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
                            GlassSegmentSwitcher(
                                items: StudioSection.allCases, selection: $section, label: { $0.label })
                        }
                        Spacer(minLength: 0)
                        // 새 글 = 떠 있는 prominent 유리 버튼(컴포즈 툴바의 발행과 같은 문법).
                        Button {
                            composing = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(GlassTokens.prominentTint).interactive(), in: .circle)
                        .accessibilityLabel(Text("새 글 쓰기"))
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
            }
            // 유리는 뒤에 흐르는 것이 있을 때만 유리다 — 스위처 뒤 옅은 브랜드 안개 한 겹(피드와 동일).
            .background(alignment: .top) {
                if auth.isSignedIn {
                    BrandMist()
                        .frame(height: 220)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            // 푸시된 화면(에디터·상세)은 탭바 숨김을 추적하지 않는다(탭 루트 전용).
            .navigationDestination(isPresented: $composing) {
                ComposeView(post: nil, onSaved: { reloadSoon() }, onOpenPublished: openPublished)
                    .environment(\.tabBarVisibility, nil)
            }
            .navigationDestination(item: $editing) { post in
                ComposeView(post: post, onSaved: { reloadSoon() }, onOpenPublished: openPublished)
                    .environment(\.tabBarVisibility, nil)
            }
            // 발행 직후 "글 보기" — 에디터가 닫히면 그 자리로 라이브 상세를 띄운다(뒤로 = 스튜디오).
            .navigationDestination(item: $justPublished) { ref in
                PostDetailView(username: ref.username, slug: ref.slug)
                    .environment(\.tabBarVisibility, nil)
            }
            .navigationDestination(for: Route.self) {
                RouteView(route: $0).environment(\.tabBarVisibility, nil)
            }
            .onAppear {
                // `--open analytics|compose` — 목/스크린샷 검증용 자동 진입.
                switch Config.consumeLaunchValue(after: "--open") {
                case "analytics": section = .analytics
                case "series": section = .series
                case "compose": composing = true
                default: break
                }
            }
        }
    }

    // MARK: 스튜디오 3분면

    /// 글·시리즈·분석을 좌우로 넘기는 필름스트립. 페이지형 TabView(UIPageViewController) 중첩은
    /// Liquid Glass 가 활성 분면의 스크롤뷰를 못 찾아 콘텐츠가 하단 바 밑으로 흐르지 않고 스크롤
    /// 축소도 안 걸린다(FeedView 가 먼저 부딪힌 함정) — 세 분면을 ZStack 으로 살려두고(스크롤 위치·
    /// 로드 상태 유지) 좌우 스와이프는 제스처로 직접 민다. 떠 있는 유리 스위처와 스와이프는 같은
    /// selection 을 공유해 양방향으로 동기화된다.
    private var studio: some View {
        ZStack {
            ForEach(StudioSection.allCases) { pane in
                if paneRendered(pane) {
                    paneView(pane)
                        // 드래그 중엔 분면 콘텐츠를 비활성화 — 손가락 따라 미끄러질 때 행 탭이
                        // 안 취소되고 글/시리즈로 새던 것을 막는다(FeedView 와 같은 처리).
                        .disabled(dragX != 0 && pane != section)
                        .allowsHitTesting(pane == section)
                        .accessibilityHidden(pane != section)
                        // 활성 분면의 스크롤만 탭바 숨김을 몬다(상주하는 숨은 분면 제외).
                        .tracksTabBarVisibility(pane == section)
                        .offset(x: paneOffset(pane))
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .simultaneousGesture(studioDrag)
        .onChange(of: section) { old, new in
            visited.insert(old)
            visited.insert(new)
        }
    }

    private var sectionIndex: Int { StudioSection.allCases.firstIndex(of: section) ?? 0 }
    private func paneIndex(_ pane: StudioSection) -> Int {
        StudioSection.allCases.firstIndex(of: pane) ?? 0
    }

    /// 어느 분면을 실제로 그릴지 — 현재 분면, 방문해서 상태를 살려둔 분면, 그리고 드래그 중일 때만
    /// 인접 분면(슬라이드로 들어올 자리). 쉼 상태에서 인접 분면을 미리 그리지 않아, 안 본 분면의
    /// `.task`(분석 3콜·시리즈 목록)가 진입 즉시 발화하는 것을 막는다 — 첫 스와이프 때 로드된다.
    private func paneRendered(_ pane: StudioSection) -> Bool {
        if pane == section || visited.contains(pane) { return true }
        return dragX != 0 && abs(paneIndex(pane) - sectionIndex) <= 1
    }

    /// 필름스트립 — 각 분면을 (자기 인덱스 − 선택 인덱스)×폭 + dragX 위치에 둔다. 전환 시
    /// 선택 인덱스와 dragX 를 같은 프레임에 맞바꿔(±폭 상쇄) 시각이 연속이라 점프·깜빡임이 없다.
    private func paneOffset(_ pane: StudioSection) -> CGFloat {
        CGFloat(paneIndex(pane) - sectionIndex) * containerWidth + dragX
    }

    /// 좌우 스와이프 — 수직 스크롤(ReadingColumn)과 공존하도록 수평 우세일 때만 잡는다.
    /// 끝 분면에서 더 끌면 고무줄 저항. 스위처 pill 은 selection 이 바뀌면 자체 애니메이션으로
    /// 활주하므로(withAnimation 래핑 금지 — 스냅 버그) 여기선 dragX 만 굴린다.
    private var studioDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !reduceMotion,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                var dx = value.translation.width
                let all = StudioSection.allCases
                let i = all.firstIndex(of: section) ?? 0
                let atEdge = (i == 0 && dx > 0) || (i == all.count - 1 && dx < 0)
                if atEdge { dx *= 0.28 }
                dragX = dx
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let vx = value.velocity.width
                let all = StudioSection.allCases
                let i = all.firstIndex(of: section) ?? 0
                // 빠른 플릭(속도) 또는 의도적 끌기(거리+방향비) 둘 다 받는다.
                let horizontal = abs(dx) > abs(dy)
                let flick = abs(vx) > 260 && abs(dx) > 20
                let deliberate = abs(dx) > 48 && abs(dx) > abs(dy) * 1.2
                let canGo = dx < 0 ? i < all.count - 1 : i > 0
                guard horizontal, flick || deliberate, canGo else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { dragX = 0 }
                    return
                }
                let newSection = all[dx < 0 ? i + 1 : i - 1]
                if reduceMotion {
                    section = newSection
                    dragX = 0
                    return
                }
                // 선택을 곧바로 바꾸고(→ 스위처 pill 활주·햅틱 즉시) dragX 를 ±폭만큼 보정해 한
                // 프레임에 같이 적용 — 인덱스 변화와 상쇄돼 시각은 연속. 이어 dragX 를 0 으로
                // 애니메이트해 새 분면을 중앙에 안착시킨다.
                section = newSection
                dragX += dx < 0 ? containerWidth : -containerWidth
                withAnimation(.snappy(duration: 0.28)) { dragX = 0 }
            }
    }

    @ViewBuilder
    private func paneView(_ pane: StudioSection) -> some View {
        switch pane {
        case .posts: postsSection
        case .series: seriesSection
        case .analytics: AnalyticsView(embedded: true, onCompose: { composing = true })
        }
    }

    // MARK: 글

    private var postsSection: some View {
        ReadingColumn(spacing: 0) {
            switch phase {
            case .idle, .loading:
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .failed(let message):
                ContentUnavailableView {
                    Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            case .loaded(let posts):
                if posts.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .task {
            if auth.me == nil { await auth.loadMe() } // 빈 상태 인사("…님의 첫 글")용.
            await load()
        }
        .refreshable { await load() }
        // 이탈 시 마지막 저장(DraftFlusher)은 뷰 밖에서 끝나 onSaved 를 못 부른다 — 플러시가
        // 서버 반영을 끝낸 틱을 관찰해, 새로 만들어진 초안이 목록에 나타나게 새로고침한다.
        .onChange(of: DraftFlusher.shared.completedTick) { if auth.isSignedIn { Task { await load() } } }
        // 앱으로 돌아오면 목록을 새로고침 — 예약→발행 전환·다른 기기 편집이 묵은 채로 남지 않게.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, auth.isSignedIn { Task { await load() } }
        }
        // 발행 취소 — 되돌릴 수 있는 동작이라 담담한 확인. 성공 시 목록을 다시 읽어 상태(비공개)를 제자리 반영.
        .alert(
            "이 글의 발행을 취소할까요?",
            isPresented: Binding(get: { unpublishTarget != nil },
                                 set: { if !$0 { unpublishTarget = nil } })
        ) {
            Button("발행 취소", role: .destructive) {
                if let post = unpublishTarget { Task { await unpublish(post) } }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("글은 남지만 공개 주소가 닫혀 아무도 볼 수 없게 돼요. 언제든 다시 발행할 수 있어요.")
        }
        // 삭제 — 되돌릴 수 없는 동작이라 결과를 또렷이 알린다.
        .alert(
            "이 글을 삭제할까요?",
            isPresented: Binding(get: { deleteTarget != nil },
                                 set: { if !$0 { deleteTarget = nil } })
        ) {
            Button("삭제", role: .destructive) {
                if let post = deleteTarget { Task { await deletePost(post) } }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("글과 그 안의 내용이 영구히 지워져요. 되돌릴 수 없어요.")
        }
    }

    /// 글이 쌓이면 초안 찾기가 스크롤 사냥이 된다 — 임시/발행 한 번에 거르는 칩.
    private var filtered: [MyPost] {
        switch filter {
        case .all: return currentPosts
        case .draft: return currentPosts.filter(\.isDraft)
        case .published: return currentPosts.filter { !$0.isDraft }
        }
    }

    private var currentPosts: [MyPost] {
        if case .loaded(let posts) = phase { return posts }
        return []
    }

    @ViewBuilder
    private var list: some View {
        // 정체성 헤더(아바타·이름)·"내 글" 라벨·nav 타이틀을 걷어냈다 — 세그먼트가 곧 헤더다.
        // 필터만 슬림하게 한 줄, 그 아래 바로 콘텐츠.
        HStack {
            Spacer(minLength: 0)
            GlassSegmentSwitcher(items: HubFilter.allCases, selection: $filter) { $0.label }
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
        if filtered.isEmpty {
            Text(filter == .draft ? "아직 임시저장한 글이 없어요" : "아직 발행한 글이 없어요")
                .typeScale(.lede)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 24)
        }
        LazyVStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, post in
                // 행 탭 = 편집(에디터). 관리(발행취소·삭제)는 우측 ⋯ 메뉴로 — 웹 write 관리와 같은
                // 계약이라, 글을 내리거나 지우려고 웹으로 건너갈 필요가 없다(감사 갭 ④).
                Button {
                    editing = post
                } label: {
                    HStack(alignment: .top, spacing: 4) {
                        postRow(post)
                        ownerMenu(post)
                    }
                }
                .buttonStyle(RowButtonStyle())
                if index < filtered.count - 1 { Hairline() }
            }
        }
        Color.clear.frame(height: 40) // 탭바 최소화 여백.
    }

    /// 내 글 행 — 상태 eyebrow + 제목 + 발췌 + 커버 썸네일. 카탈로그(내 책장)라
    /// 카드가 아니라 깔끔한 글 행(3원칙 표준). 상태는 사진 위가 아니라 종이 위
    /// eyebrow 로 둬 초안/예약/발행이 또렷하다.
    private func postRow(_ post: MyPost) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                statusEyebrow(post)
                Text(post.title)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let excerpt = post.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 태그가 붙은 글은 종이 위 #태그 한 줄로 — 캡슐 없이 글자만(MutedChip, §10).
                // 카탈로그에서 주제를 훑게 하는 조용한 정보 밀도(있을 때만, 최대 3개).
                if let tags = post.tags, !tags.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            MutedChip(text: "#\(tag)")
                        }
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
            if let cover = post.ogImageUrl, let url = URL(string: cover) {
                // AsyncImage 는 행이 재생성되면 캐시 히트여도 placeholder 부터 다시 밟는다
                // — 앱 공통 RemoteImage(메모리 캐시)로 첫 프레임부터 완성본.
                RemoteImage(url: url) { phase in
                    if case .success(let image) = phase {
                        // 채움 이미지는 프레임 밖으로 넘친다 — 클립은 그림만 자르고 히트는 못 잘라, 이웃 카드 탭을 먹는다.
                        image.resizable().scaledToFill().allowsHitTesting(false)
                    } else {
                        Rectangle().fill(Palette.hairline)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb, style: .continuous))
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    /// 행 우측 ⋯ 관리 메뉴 — 편집(행 탭)과 겹치지 않게 자체 히트 영역을 갖는다.
    /// 발행취소는 라이브(발행) 글에만(초안·예약·이미 비공개엔 의미 없음), 삭제는 어느 상태든.
    /// 파괴적 액션이라 SeriesDetail·CommentRow 와 같은 .alert 확인 관용구를 거친다.
    private func ownerMenu(_ post: MyPost) -> some View {
        Menu {
            if post.isPublished {
                Button(role: .destructive) {
                    unpublishTarget = post
                } label: {
                    Label("발행 취소", systemImage: "eye.slash")
                }
            }
            Button(role: .destructive) {
                deleteTarget = post
            } label: {
                Label("삭제", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15 * metaUnit, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .tint(.brand)
        .accessibilityLabel(Text("\(post.title) 관리"))
    }

    /// 상태 점 + (발행 외엔) 라벨 + 날짜. 점 색이 상태를 인코딩한다(초록=라이브, 흐림=초안).
    private func statusEyebrow(_ post: MyPost) -> some View {
        let dotColor: Color =
            post.isDraft ? Palette.faint
            : post.isScheduled ? Palette.link
            : post.isUnpublished ? Palette.secondary
            : Palette.accentMarker
        let label: String? =
            post.isDraft ? String(localized: "임시저장")
            : post.isScheduled ? String(localized: "예약됨")
            : post.isUnpublished ? String(localized: "비공개")
            : nil
        return HStack(spacing: 5) {
            Circle().fill(dotColor).frame(width: 5, height: 5)
            if let label {
                Text(label).foregroundStyle(dotColor)
                Text("·").foregroundStyle(Palette.faint)
            }
            if let date = post.publishedAt ?? post.scheduledAt ?? post.updatedAt {
                Text(date.relativeShort).foregroundStyle(Palette.secondary)
            }
        }
        .typeScale(.meta)
    }

    /// 빈 상태 — 막다른 길 금지(AGENTS 폴리시). 인사 + 또렷한 시작 버튼.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 26))
                .foregroundStyle(Palette.accent)
                .frame(width: 68, height: 68)
                .background(Palette.accent.opacity(0.10), in: Circle())
            VStack(spacing: 6) {
                Text(auth.me?.username.map { "\($0) 님의 첫 글" } ?? "첫 글을 시작하세요")
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                Text("도구 막대로 제목·이미지·표를 넣어 웹과 똑같이 발행돼요.")
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                composing = true
            } label: {
                Text("새 글 쓰기")
                    .font(.system(size: 15 * unit, weight: .semibold))
                    .padding(.horizontal, 24)
                    .frame(height: 46)
            }
            // 툴바의 ‘새 글’·컴포즈의 발행과 같은 prominent 유리 문법(종이 위 그린 유리 캡슐).
            .buttonStyle(.glassProminent)
            .tint(GlassTokens.prominentTint)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    private func load() async {
        if case .idle = phase { phase = .loading }
        do {
            phase = .loaded(try await WriteAPI.myPosts())
        } catch {
            // 보이던 목록을 에러 화면으로 대체하지 않는다 — 비었을 때만 실패 표시.
            if case .loaded(let posts) = phase, !posts.isEmpty { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func reloadSoon() {
        Task { await load() }
    }

    /// 발행 취소 후 목록을 다시 읽어 상태(비공개)를 제자리 반영 — 실패는 화면을 갈아엎지 않고 토스트로.
    private func unpublish(_ post: MyPost) async {
        do {
            try await WriteAPI.unpublish(postId: post.id)
            ToastCenter.shared.show(String(localized: "발행을 취소했어요"))
            await load()
        } catch {
            ToastCenter.shared.show(String(localized: "발행을 취소하지 못했습니다"))
        }
    }

    /// 삭제 후 목록에서 그 글을 즉시 걷어낸다(서버 재확인 겸 load) — 실패는 토스트로 알리고 목록 유지.
    private func deletePost(_ post: MyPost) async {
        do {
            try await WriteAPI.deletePost(postId: post.id)
            ToastCenter.shared.show(String(localized: "글을 삭제했어요"))
            await load()
        } catch {
            ToastCenter.shared.show(String(localized: "글을 삭제하지 못했습니다"))
        }
    }

    /// 에디터가 "글 보기"로 닫혔다 — 목록을 새로고침하고, 에디터 pop 직후 라이브 상세를 띄운다.
    private func openPublished(slug: String) {
        guard let username = auth.me?.username else { return }
        reloadSoon()
        // 에디터 pop 애니메이션과 겹치지 않게 한 박자 뒤 푸시(뒤로 = 스튜디오).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            justPublished = PublishedRef(username: username, slug: slug)
        }
    }

    // MARK: 시리즈

    private var seriesSection: some View {
        ReadingColumn(spacing: 0) {
            RailHeading("내 시리즈")
                .padding(.top, 14)
                .padding(.bottom, 8)
            Hairline()
            if seriesLoaded, seriesList.isEmpty {
                Text("아직 시리즈가 없어요. 발행 시트에서 글을 시리즈로 묶어 보세요.")
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 24)
            }
            ForEach(Array(seriesList.enumerated()), id: \.element.id) { index, series in
                NavigationLink(value: Route.series(
                    username: auth.me?.username ?? "", slug: series.slug)
                ) {
                    HStack(spacing: 12) {
                        KurlMark(drawn: [true, true, true])
                            .frame(width: 20 * unit, height: 12 * unit)
                            .frame(width: 40, height: 40)
                            .background(
                                Palette.accent.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: Metrics.radiusThumb, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(series.title)
                                .typeScale(.titleSmall)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text("\(series.postCount)편")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12 * metaUnit, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
                .disabled((auth.me?.username ?? "").isEmpty)
                if index < seriesList.count - 1 { Hairline() }
            }
        }
        .task {
            if auth.me == nil { await auth.loadMe() } // 행 링크의 username 용.
            seriesList = (try? await WriteAPI.mySeries()) ?? []
            seriesLoaded = true
        }
        .refreshable {
            seriesList = (try? await WriteAPI.mySeries()) ?? seriesList
        }
    }

    // MARK: 로그인 게이트

    private var signedOutGate: some View {
        ReadingColumn(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                RailHeading("글쓰기")
                    .padding(.top, 28)
                Text("로그인하고 글을 쓰세요")
                    .typeScale(.featured)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 12)
                Text("마크다운으로 쓰면 웹과 똑같이 발행됩니다.")
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 6)
                // Apple/Google 버튼 한 쌍은 공유 컴포넌트 — 계정 탭·웰컴·로그인 시트와 같은 출처.
                AuthProviderButtons()
                    .padding(.top, 22)
            }
        }
    }
}

/// 발행 직후 "글 보기"로 띄울 라이브 글 참조 — navigationDestination(item:) 키.
struct PublishedRef: Hashable, Identifiable {
    let username: String
    let slug: String
    var id: String { "\(username)/\(slug)" }
}

/// 스튜디오 3분면 — 웹 /write 의 글·시리즈·분석을 그대로 옮긴 구도.
enum StudioSection: String, CaseIterable, Identifiable {
    case posts
    case series
    case analytics

    var id: String { rawValue }

    var label: String {
        switch self {
        case .posts: return String(localized: "글")
        case .series: return String(localized: "시리즈")
        case .analytics: return String(localized: "분석")
        }
    }
}

/// 내 글 허브의 상태 필터 — 예약 글은 발행 쪽 양동이로(발행 흐름에 들어간 글).
enum HubFilter: String, CaseIterable, Identifiable {
    case all
    case draft
    case published

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "전체")
        case .draft: return String(localized: "임시")
        case .published: return String(localized: "발행")
        }
    }
}
