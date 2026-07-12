//
//  AuthorBlogView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct AuthorBlogView: View {
    let username: String

    @State private var phase: LoadState<PublicPostListView> = .idle
    @State private var series: [SeriesListItem] = []
    /// 이 작가가 공개로 엮은 컬렉션(길) — 큐레이션을 프로필 표면으로. 미로그인도 목록은 본다.
    @State private var collections: [CollectionSummary] = []
    /// 미로그인이 컬렉션을 누르면 — 상세는 인증 면이라 로그인으로 잇는다(막다른 길 금지).
    @State private var showCollectionLogin = false
    /// 작가 로드 때 한 번 받아 두는 follow status — 헤더의 팔로우 버튼·카운트 링크가 공유한다(중복 GET 제거).
    @State private var followStatus: InteractionsAPI.FollowStatus?
    @State private var showNavTitle = false
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var navUnit: CGFloat = 1
    /// "명함" 버튼 라벨 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var cardLabelSize: CGFloat = 14

    /// 로드된 작가 id — 신고 대상. 내가 아닐 때만 신고를 노출한다.
    private var author: Author? {
        if case .loaded(let view) = phase { return view.author }
        return nil
    }
    private var isOwnAuthor: Bool {
        guard let myId = AuthStore.shared.me?.id, let author else { return false }
        return author.id == myId
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch phase {
                case .idle, .loading:
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { Task { await load() } }
                            .foregroundStyle(Palette.link)
                    }
                    .padding(.top, 80)
                case .loaded(let view):
                    content(view)
                }
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.pageBg)
        // 헤더를 지나면 작가 이름이 내비바로 스민다 — 상단 중복 제거(태그·글 상세와 같은 결).
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, passed in
            withAnimation(.easeInOut(duration: 0.18)) { showNavTitle = passed }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(username)
                    .font(.system(size: 16 * navUnit, weight: .semibold))
                    .opacity(showNavTitle ? 1 : 0)
            }
            if let author, !isOwnAuthor {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
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
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.brand)
                    .accessibilityLabel("더 보기")
                    .id(author.id)
                }
            }
        }
        .loginPrompt(isPresented: $showCollectionLogin, message: "컬렉션을 열려면 로그인하세요")
        .reportDialog(isPresented: $showReport, subjectType: "USER", subjectId: author?.id ?? 0)
        .blockDialog(
            isPresented: $showBlockConfirm,
            username: author?.username ?? "", userId: author?.id ?? 0)
        .toolbarBackground(showNavTitle ? .automatic : .hidden, for: .navigationBar)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            await BlockStore.shared.hydrateIfNeeded()
        }
        .refreshable { await load() }
        // 계정 탭은 상주 임베드라 세션 내내 살아 있다 — 앱 복귀 때 내 블로그를 조용히
        // 갱신해 발행·프로필 수정이 묵지 않게(남의 페이지는 당겨서 새로고침으로 충분).
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, case .loaded = phase,
               AuthStore.shared.me?.username == username {
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func content(_ view: PublicPostListView) -> some View {
        // 정체 헤더 = 작가 랜딩 마스트헤드(태그·시리즈와 같은 family — eyebrow + 히어로).
        VStack(alignment: .leading, spacing: 0) {
            RailHeading(isOwnAuthor ? "내 블로그" : "작가")
                .padding(.top, 8)
                .padding(.bottom, 14)
            HStack(alignment: .center, spacing: 14) {
                AvatarView(author: view.author, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(view.author.username)
                        .typeScale(.name)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        Text("글 \(view.posts.count)")
                        if !series.isEmpty {
                            Text("·").foregroundStyle(Palette.faint)
                            Text("시리즈 \(series.count)")
                        }
                    }
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            if let bio = view.author.bio, !bio.isEmpty {
                Text(bio)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 12)
            }
            // 탭 가능한 "팔로워 N · 팔로잉 N" — 각각 해당 목록으로(Medium 문법).
            FollowCountsLink(username: view.author.username, initialStatus: followStatus)
                .padding(.top, 12)
            HStack(spacing: 10) {
                // 내 블로그면 팔로우 자리는 비운다 — 정체는 위 eyebrow("내 블로그")가 이미 말한다.
                // 남의 블로그일 때만 팔로우가 서고, 명함은 양쪽 모두 같은 정체의 다른 얼굴로 오른쪽에.
                if !isOwnAuthor {
                    FollowButton(username: view.author.username, showCount: false, initialStatus: followStatus)
                }
                Spacer(minLength: 0)
                // 명함(u/ — 링크 모음·소셜)으로 가는 문 — 블로그와 같은 정체의 다른 얼굴.
                // 시트 대신 스택 푸시 — 앱 안 화면에 얹혀 뒤로가 자연스럽고 블로그로 되건너기 쉽다.
                NavigationLink(value: Route.businessCard(username: username)) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("명함")
                            .font(.system(size: cardLabelSize, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // 중성 보조 캡슐 — 투명도 감소 시 Palette.cardBg 솔리드로 떨어진다(§1.7).
                .glassCapsule(prominent: false)
            }
            .padding(.top, 14)
        }
        .padding(.vertical, 18)

        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                RailHeading("시리즈")
                // 세로 행 대신 가로 레일 — 시리즈가 프로필의 책장처럼 읽히게.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(series) { item in
                            NavigationLink(
                                value: Route.series(username: username, slug: item.slug)
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    KurlMark(drawn: [true, true, true])
                                        .frame(width: 18, height: 11)
                                    Text(item.title)
                                        .typeScale(.titleSmall)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.7)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Text("\(item.postCount)편")
                                        .typeScale(.meta)
                                        .foregroundStyle(Palette.secondary)
                                }
                                .padding(13)
                                .frame(width: 148, height: 108, alignment: .topLeading)
                                // 회색 박스 → 흰 종이 카드(보더) — 다른 카드와 같은 문법.
                                .background(
                                    Palette.cardBg,
                                    in: RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous)
                                        .strokeBorder(Palette.cardBorder, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(CardButtonStyle())
                            .modifier(CardScrollFade(axis: .horizontal))
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }

        if !collections.isEmpty {
            collectionsRail
                .padding(.bottom, 18)
        }

        RailHeading("글").padding(.bottom, 4)
        if view.posts.isEmpty {
            // 0편 = 헤딩 아래 빈 공간 대신 자리표 — 내 페이지면 글쓰기로, 남의 페이지면 그냥 안내.
            if isOwnAuthor {
                FeedPlaceholder(
                    eyebrow: "내 블로그",
                    title: "아직 발행한 글이 없어요",
                    message: "첫 글을 발행하면 여기 카탈로그로 쌓입니다.",
                    actionTitle: "글쓰기",
                    prominent: true,
                    action: { TabRouter.shared.selection = 2 }
                )
                .padding(.top, 48)
                .padding(.bottom, 8)
            } else {
                FeedPlaceholder(
                    eyebrow: "작가",
                    title: "아직 발행한 글이 없어요",
                    message: "이 작가의 첫 글이 올라오면 여기에서 만나요.",
                    actionTitle: "발견에서 읽을 글 찾기",
                    action: { TabRouter.shared.selection = 1 }
                )
                .padding(.top, 48)
                .padding(.bottom, 8)
            }
        } else {
            // 작가 글 목록 = 카탈로그(작가의 책장) — 카드가 아니라 깔끔한 글 행(PostRow).
            // 발견·검색·태그만 카드, 읽기·카탈로그 면은 행(3원칙 표준).
            LazyVStack(spacing: 0) {
                ForEach(Array(view.posts.enumerated()), id: \.element.id) { index, post in
                    NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                        PostRow(item: post)
                    }
                    .buttonStyle(RowButtonStyle())
                    .modifier(QuietAppear(index: index))
                    if index < view.posts.count - 1 { Hairline() }
                }
            }
        }
        Color.clear.frame(height: 40)
    }

    // 공개 컬렉션 레일 — 시리즈 레일과 같은 문법(가로 책장). 큐레이션(엮은 길)을 프로필 표면으로.
    // 상세는 인증 면이라 미로그인 탭은 로그인으로 잇는다(막다른 길 금지).
    private var collectionsRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            RailHeading("컬렉션")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(collections) { item in
                        if AuthStore.shared.isSignedIn {
                            NavigationLink(value: Route.collection(id: item.id)) {
                                collectionCard(item)
                            }
                            .buttonStyle(CardButtonStyle())
                            .modifier(CardScrollFade(axis: .horizontal))
                        } else {
                            Button { showCollectionLogin = true } label: {
                                collectionCard(item)
                            }
                            .buttonStyle(CardButtonStyle())
                            .modifier(CardScrollFade(axis: .horizontal))
                        }
                    }
                }
            }
        }
    }

    private func collectionCard(_ item: CollectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: item.kind == .path ? "point.topleft.down.to.point.bottomright.curvepath"
                : "square.stack")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Text(item.title)
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text("\(item.count)개")
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
        }
        .padding(13)
        .frame(width: 148, height: 108, alignment: .topLeading)
        .background(
            Palette.cardBg,
            in: RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func load() async {
        // 이미 로드된 화면은 유지한 채 조용히 다시 받는다 — 당겨서 새로고침·재방문·복귀.
        if case .loaded = phase {} else { phase = .loading }
        do {
            // 글·시리즈를 병렬로 받아 한 호흡에 반영 — 시리즈 레일이 뒤늦게 끼어들며
            // 글 목록을 밀어내지 않고, 첫 페인트도 직렬 왕복만큼 빨라진다.
            async let viewReq = BlogAPI.authorPosts(username: username)
            async let seriesReq = BlogAPI.authorSeries(username: username)
            // 공개 컬렉션도 같은 호흡에 — 실패해도(없거나 오류) 조용히 빈 채로 두고 나머지를 그린다.
            async let collectionsReq = CollectionsAPI.publicByUsername(username)
            // 본인 페이지는 팔로우 표면이 안 떠 status 가 필요 없다 — 그 외에만 한 번 받아 두 컴포넌트에 시드.
            if AuthStore.shared.me?.username != username {
                async let statusReq = InteractionsAPI.followStatus(username: username)
                followStatus = try? await statusReq
            }
            let view = try await viewReq
            series = (try? await seriesReq)?.series ?? series
            collections = (try? await collectionsReq) ?? collections
            phase = .loaded(view)
        } catch {
            // 보이던 화면을 에러로 대체하지 않는다 — 비었을 때만 실패 표시.
            if case .loaded = phase { return }
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
