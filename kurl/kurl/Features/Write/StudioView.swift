//
//  StudioView.swift
//  kurl
//

import AuthenticationServices
import SwiftUI

/// 글쓰기 탭 = 작가 스튜디오 — 웹 /write 허브 철학의 네이티브 번역.
/// [글 | 시리즈 | 분석] 이 한 지붕: 목록만 있던 허브에서, 시리즈와 분석이 1급으로 승격됐다
/// (분석이 무라벨 차트 아이콘 뒤에 숨어 있던 시절을 끝낸다). 로그아웃 상태는 표면 전체가 게이트.
struct StudioView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var section: StudioSection = .posts
    @State private var phase: LoadState<[MyPost]> = .idle
    @State private var filter: HubFilter = .all
    @State private var seriesList: [MySeries] = []
    @State private var seriesLoaded = false
    @State private var composing = false
    @State private var editing: MyPost?
    @State private var isSigningIn = false
    @State private var showTwoFactorHint = false
    @State private var appleNonce = ""

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    studio
                } else {
                    signedOutGate
                }
            }
            .navigationTitle("글쓰기")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $composing) {
                ComposeView(post: nil) { reloadSoon() }
            }
            .navigationDestination(item: $editing) { post in
                ComposeView(post: post) { reloadSoon() }
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
        .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactorHint) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("내 계정 탭에서 로그인을 완료해 주세요.")
        }
    }

    // MARK: 스튜디오 3분면

    private var studio: some View {
        Group {
            switch section {
            case .posts: postsSection.transition(.opacity)
            case .series: seriesSection.transition(.opacity)
            case .analytics: AnalyticsView(embedded: true).transition(.opacity)
            }
        }
        // 같은 스위처를 쓰는 피드와 같은 문법 — 분면 교체도 한 호흡 크로스페이드.
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: section)
        // 피드와 같은 문법 — 분면 전환은 떠 있는 유리 세그먼트.
        .safeAreaInset(edge: .top) {
            GlassSegmentSwitcher(items: StudioSection.allCases, selection: $section) { $0.label }
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
        // 새 글은 분면과 무관한 스튜디오의 주행동 — 항상 떠 있다.
        .overlay(alignment: .bottomTrailing) {
            GlassFAB(systemImage: "square.and.pencil", label: "새 글") {
                composing = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: 글

    private var postsSection: some View {
        ReadingColumn(spacing: 0) {
            switch phase {
            case .idle, .loading:
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .failed(let message):
                ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                       description: Text(message))
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
            await auth.loadMe()
            await load()
            // 헤더의 시리즈 수 — 없으면 0 으로 두고 글 로드는 막지 않는다.
            if seriesList.isEmpty { seriesList = (try? await WriteAPI.mySeries()) ?? [] }
        }
        .refreshable { await load() }
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
        studioHeader
            .padding(.top, 6)
            .padding(.bottom, 4)

        HStack(alignment: .center) {
            RailHeading("내 글")
            Spacer()
            GlassSegmentSwitcher(items: HubFilter.allCases, selection: $filter) { $0.label }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        Hairline()
        if filtered.isEmpty {
            Text(filter == .draft ? "임시저장한 글이 없습니다." : "발행한 글이 없습니다.")
                .font(.system(size: 14 * unit))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 24)
        }
        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, post in
            Button {
                editing = post
            } label: {
                postRow(post)
            }
            .buttonStyle(RowButtonStyle())
            .modifier(QuietAppear(index: index))
            if index < filtered.count - 1 { Hairline() }
        }
        Color.clear.frame(height: 80) // FAB 가 마지막 행을 가리지 않게.
    }

    /// 스튜디오 정체성 — 아바타·이름·산출물 한 줄. "내 작업실"이라는 감각을 준다.
    private var studioHeader: some View {
        let published = currentPosts.filter { !$0.isDraft && !$0.isScheduled }.count
        let drafts = currentPosts.filter(\.isDraft).count
        return HStack(spacing: 14) {
            if let me = auth.me, let username = me.username {
                AvatarView(
                    author: Author(id: me.id ?? 0, username: username, bio: nil, avatarUrl: me.avatarUrl),
                    size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(username)
                        .font(.system(size: 19 * unit, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 6) {
                        Text("발행 \(published)")
                        Text("·").foregroundStyle(Palette.faint)
                        Text("임시 \(drafts)")
                        if !seriesList.isEmpty {
                            Text("·").foregroundStyle(Palette.faint)
                            Text("시리즈 \(seriesList.count)")
                        }
                    }
                    .font(.system(size: 13 * metaUnit))
                    .foregroundStyle(Palette.secondary)
                    .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 글 한 행 — 상태 점(이브로) + 제목 + 발췌 + 커버 썸네일. 평평한 제목-행을
    /// 콘텐츠가 보이는 도착 행으로(발견 카드와 같은 슬레이트 문법).
    private func postRow(_ post: MyPost) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                statusEyebrow(post)
                Text(post.title)
                    .font(.system(size: 16 * unit, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let excerpt = post.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 13 * unit))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
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
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb, style: .continuous))
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    /// 상태 점 + (발행 외엔) 라벨 + 날짜. 점 색이 상태를 인코딩한다(초록=라이브, 흐림=초안).
    private func statusEyebrow(_ post: MyPost) -> some View {
        let dotColor: Color = post.isDraft ? Palette.faint : (post.isScheduled ? Palette.link : Palette.accentMarker)
        let label: String? = post.isDraft ? String(localized: "임시저장")
            : (post.isScheduled ? String(localized: "예약됨") : nil)
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
        .font(.system(size: 12 * metaUnit, weight: .medium))
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
                    .font(.system(size: 19 * unit, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("마크다운으로 쓰면 웹과 똑같이 발행됩니다.")
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                composing = true
            } label: {
                Text("새 글 쓰기")
                    .font(.system(size: 15 * unit, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 46)
                    .background(GlassTokens.prominentTint, in: Capsule())
            }
            .buttonStyle(.plain)
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

    // MARK: 시리즈

    private var seriesSection: some View {
        ReadingColumn(spacing: 0) {
            RailHeading("내 시리즈")
                .padding(.top, 14)
                .padding(.bottom, 8)
            Hairline()
            if seriesLoaded, seriesList.isEmpty {
                Text("아직 시리즈가 없습니다. 발행 시트에서 글을 시리즈로 묶어 보세요.")
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 24)
            }
            ForEach(Array(seriesList.enumerated()), id: \.element.id) { index, series in
                NavigationLink(value: Route.series(
                    username: auth.me?.username ?? "", slug: series.slug)
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 16 * unit))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 40, height: 40)
                            .background(
                                Palette.accent.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(series.title)
                                .font(.system(size: 15 * unit, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text("\(series.postCount)편")
                                .font(.system(size: 12 * metaUnit))
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
                .modifier(QuietAppear(index: index))
                .disabled((auth.me?.username ?? "").isEmpty)
                if index < seriesList.count - 1 { Hairline() }
            }
        }
        .task {
            await auth.loadMe()
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
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 12)
                Text("마크다운으로 쓰면 웹과 똑같이 발행됩니다.")
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 6)
                // Apple 버튼은 시스템 소유 모양(브랜딩 규정) — 유리 없이 캡슐만 맞춘다.
                SignInWithAppleButton(.continue) { request in
                    appleNonce = AuthStore.prepareAppleRequest(request)
                } onCompletion: { result in
                    finishApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .clipShape(Capsule())
                .padding(.top, 22)

                Button {
                    signInHere()
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn { ProgressView().tint(.white) }
                        Text("Google로 계속하기")
                            .font(.system(size: 15 * unit, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(GlassTokens.prominentTint).interactive(), in: .capsule)
                .disabled(isSigningIn)
                .padding(.top, 10)
            }
        }
    }

    private func signInHere() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            if (try? await auth.signIn()) == .twoFactorRequired {
                showTwoFactorHint = true
            }
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) {
        Task {
            if (try? await auth.completeApple(result, rawNonce: appleNonce)) == .twoFactorRequired {
                showTwoFactorHint = true
            }
        }
    }
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
