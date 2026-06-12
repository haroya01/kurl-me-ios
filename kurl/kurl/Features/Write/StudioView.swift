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
            case .posts: postsSection
            case .series: seriesSection
            case .analytics: AnalyticsView(embedded: true)
            }
        }
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
        .task { await load() }
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
        HStack(alignment: .center) {
            RailHeading("내 글")
            Spacer()
            GlassSegmentSwitcher(items: HubFilter.allCases, selection: $filter) { $0.label }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        Hairline()
        if filtered.isEmpty {
            Text(filter == .draft ? "임시저장한 글이 없습니다." : "발행한 글이 없습니다.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 24)
        }
        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, post in
            Button {
                editing = post
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let date = post.publishedAt ?? post.updatedAt {
                            Text(date.relativeShort)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    if post.isDraft {
                        Text("임시저장")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.chipBg, in: Capsule())
                    } else if post.isScheduled {
                        Text("예약됨")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.link)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.chipBg, in: Capsule())
                    }
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            if index < filtered.count - 1 { Hairline() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailHeading("내 글")
                .padding(.top, 24)
            Text("아직 글이 없습니다. 오른쪽 아래 버튼으로 첫 글을 시작하세요.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
        }
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
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 24)
            }
            ForEach(Array(seriesList.enumerated()), id: \.element.id) { index, series in
                NavigationLink(value: Route.series(
                    username: auth.me?.username ?? "", slug: series.slug)
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.accentMarker)
                        Text(series.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(series.postCount)편")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.faint)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 12)
                Text("마크다운으로 쓰면 웹과 똑같이 발행됩니다.")
                    .font(.system(size: 15))
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
                            .font(.system(size: 15, weight: .semibold))
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
