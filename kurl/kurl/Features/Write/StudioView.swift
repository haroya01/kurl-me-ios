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
    /// 재발화(분석은 스피너부터 다시)하므로, 방문한 분면은 상주시키고 opacity 만 굴린다.
    @State private var visited: Set<StudioSection> = []
    @State private var phase: LoadState<[MyPost]> = .idle
    @State private var filter: HubFilter = .all
    @State private var seriesList: [MySeries] = []
    @State private var seriesLoaded = false
    @State private var composing = false
    @State private var editing: MyPost?
    /// 방금 발행한 글 — 셀레브레이션 "글 보기" 가 에디터를 닫고 여기로 이어 보낸다(라이브 상세).
    @State private var justPublished: PublishedRef?

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    studio
                } else {
                    signedOutGate
                }
            }
            // nav 타이틀 제거 — 세그먼트(글·시리즈·분석)가 곧 이 탭의 헤더다(중복 제거).
            .navigationBarTitleDisplayMode(.inline)
            // 새 글 = 헤더의 prominent 유리 버튼 — 떠다니는 FAB 대신 콘텐츠를 안 가리고
            // 모든 분면에서 늘 같은 자리(컴포즈 툴바의 발행과 같은 .glassProminent 문법).
            .toolbar {
                if auth.isSignedIn {
                    // 글·시리즈·분석 = 헤더(내비바)에. 떠 있는 캡슐로 따로 두지 않고 헤더 하나로 합친다.
                    ToolbarItem(placement: .principal) {
                        GlassSegmentSwitcher(
                            items: StudioSection.allCases, selection: $section, label: { $0.label },
                            bare: true)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            composing = true
                        } label: {
                            Label("새 글", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.glassProminent)
                        .tint(GlassTokens.prominentTint)
                        .accessibilityLabel(Text("새 글 쓰기"))
                    }
                }
            }
            .navigationDestination(isPresented: $composing) {
                ComposeView(post: nil, onSaved: { reloadSoon() }, onOpenPublished: openPublished)
            }
            .navigationDestination(item: $editing) { post in
                ComposeView(post: post, onSaved: { reloadSoon() }, onOpenPublished: openPublished)
            }
            // 발행 직후 "글 보기" — 에디터가 닫히면 그 자리로 라이브 상세를 띄운다(뒤로 = 스튜디오).
            .navigationDestination(item: $justPublished) { ref in
                PostDetailView(username: ref.username, slug: ref.slug)
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
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

    private var studio: some View {
        ZStack {
            ForEach(StudioSection.allCases) { pane in
                if pane == section || visited.contains(pane) {
                    paneView(pane)
                        .opacity(pane == section ? 1 : 0)
                        .allowsHitTesting(pane == section)
                        .accessibilityHidden(pane != section)
                        .transition(.opacity)
                }
            }
        }
        // 분면 교체는 한 호흡 크로스페이드. 세그먼트 자체는 내비바(헤더)에 산다.
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: section)
        .onChange(of: section) { old, new in
            visited.insert(old)
            visited.insert(new)
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
                        .foregroundStyle(Palette.accent)
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
        // 앱으로 돌아오면 목록을 새로고침 — 예약→발행 전환·다른 기기 편집이 묵은 채로 남지 않게.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, auth.isSignedIn { Task { await load() } }
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
                Button {
                    editing = post
                } label: {
                    postRow(post)
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
            }
            Spacer(minLength: 0)
            if let cover = post.ogImageUrl, let url = URL(string: cover) {
                // AsyncImage 는 행이 재생성되면 캐시 히트여도 placeholder 부터 다시 밟는다
                // — 앱 공통 RemoteImage(메모리 캐시)로 첫 프레임부터 완성본.
                RemoteImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
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
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
