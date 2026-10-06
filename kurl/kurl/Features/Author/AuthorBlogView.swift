//
//  AuthorBlogView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct AuthorBlogView: View {
    let username: String

    @State private var tab: AuthorTab
    @State private var notes: NotesViewModel
    @State private var viewingAvatar: AvatarTarget?
    @State private var reposts: NotesViewModel
    @State private var composingNote = false
    @State private var notesPosted = 0

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// "명함" 버튼 라벨 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var cardLabelSize: CGFloat = 14

    init(username: String, initialTab: AuthorTab = .posts) {
        self.username = username
        _tab = State(initialValue: initialTab)
        _notes = State(initialValue: NotesViewModel(author: username))
        _reposts = State(initialValue: NotesViewModel(repostsBy: username))
    }

    /// 로드된 작가 id — 신고 대상. 내가 아닐 때만 신고를 노출한다.
    private var author: Author? {
        if case .loaded(let view) = phase { return view.author }
        return nil
    }
    private var isOwnAuthor: Bool {
        guard let myId = AuthStore.shared.me?.id, let author else { return false }
        return author.id == myId
    }
    private var tabs: [AuthorTab] {
        var all: [AuthorTab] = [.posts, .notes, .reposts]
        if !series.isEmpty { all.append(.series) }
        if !collections.isEmpty { all.append(.collections) }
        return all
    }
    private var shownTab: AuthorTab { tabs.contains(tab) ? tab : .posts }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                switch phase {
                case .idle, .loading:
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ErrorState(message: message, retry: { Task { await load() } })
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
        .background(Palette.readingBg)
        // 계정 탭 루트로 임베드됐을 때만 탭바 숨김을 몬다 — 환경에 손잡이가 있을 때만
        // 동작하고(스레드식), 작가 프로필로 푸시될 땐 env 가 nil 이라 조용하다(탭 루트 전용).
        .tracksTabBarVisibility()
        // 헤더를 지나면 작가 이름이 내비바로 스민다 — 상단 중복 제거(태그·글 상세와 같은 결).
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, passed in
            withAnimation(.easeInOut(duration: 0.18)) { showNavTitle = passed }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(username)
                    .typeScale(.titleSmall)
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
        .refreshable {
            await load()
            if shownTab == .notes { await notes.reload() }
            if shownTab == .reposts { await reposts.reload() }
        }
        .task(id: shownTab) {
            if shownTab == .notes, case .idle = notes.phase { await notes.reload() }
            if shownTab == .reposts, case .idle = reposts.phase { await reposts.reload() }
        }
        .sheet(isPresented: $composingNote) {
            NoteComposeSheet(mode: .new(quote: nil, inReplyToId: nil)) { note in
                notes.inserted(note)
                notesPosted += 1
            }
        }
        .sensoryFeedback(.success, trigger: notesPosted)
        .fullScreenCover(item: $viewingAvatar) { target in
            AvatarViewer(url: target.url, name: username)
        }
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
            HStack(alignment: .center, spacing: 14) {
                if let avatar = view.author.avatarUrl.flatMap(URL.init(string:)) {
                    Button { viewingAvatar = AvatarTarget(url: avatar) } label: {
                        AvatarView(author: view.author, size: 76)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("프로필 사진 크게 보기")
                    .accessibilityIdentifier("author.avatar")
                } else {
                    AvatarView(author: view.author, size: 76)
                }
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
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))) {
                if isOwnAuthor {
                    FollowCountsLink(username: view.author.username, initialStatus: followStatus)
                } else {
                    FollowButton(username: view.author.username, showCount: false, initialStatus: followStatus)
                    FollowCountsLink(username: view.author.username, initialStatus: followStatus, showsCounts: false)
                }
                Spacer(minLength: 0)
                NavigationLink(value: Route.businessCard(username: username)) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("명함")
                            .font(.system(size: cardLabelSize, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassCapsule(prominent: false)
            }
            .padding(.top, 14)
        }
        .padding(.vertical, 18)

        Section {
            switch shownTab {
            case .posts: postsTab(view)
            case .notes: notesTab
            case .reposts: repostsTab
            case .series: seriesTab
            case .collections: collectionsTab
            }
            Color.clear.frame(height: 40)
        } header: {
            AuthorTabBar(tabs: tabs, selection: $tab)
        }
    }

    @ViewBuilder
    private func postsTab(_ view: PublicPostListView) -> some View {
        if view.posts.isEmpty {
            // 0편 = 빈 공간 대신 자리표 — 내 페이지면 글쓰기로, 남의 페이지면 그냥 안내.
            if isOwnAuthor {
                FeedPlaceholder(
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
                    title: "아직 발행한 글이 없어요",
                    message: "이 작가의 첫 글이 올라오면 여기에서 만나요.",
                    actionTitle: "피드에서 읽을 글 찾기",
                    action: { TabRouter.shared.selection = 0 }
                )
                .padding(.top, 48)
                .padding(.bottom, 8)
            }
        } else {
            // 작가 글 목록 = 카탈로그(작가의 책장) — 카드가 아니라 깔끔한 글 행(PostRow).
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
    }

    @ViewBuilder
    private var notesTab: some View {
        switch notes.phase {
        case .idle, .loading:
            KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 240)
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await notes.reload() } })
                .padding(.top, 48)
        case .loaded:
            if notes.items.isEmpty {
                if isOwnAuthor {
                    FeedPlaceholder(
                        title: "아직 노트가 없어요",
                        message: "제목도 형식도 없이, 지금 떠오른 한 줄을 남기는 자리예요.",
                        actionTitle: "첫 노트 쓰기",
                        prominent: true,
                        action: { composingNote = true }
                    )
                    .padding(.top, 48)
                } else {
                    FeedPlaceholder(
                        title: "아직 노트가 없어요",
                        message: "이 작가의 첫 노트가 올라오면 여기에서 만나요.",
                        actionTitle: "노트 둘러보기",
                        action: { TabRouter.shared.selection = 1 }
                    )
                    .padding(.top, 48)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
                            note: note,
                            onChange: { notes.replaced($0) },
                            onDelete: { notes.removed($0) },
                            onQuoted: isOwnAuthor ? { notes.inserted($0) } : nil
                        )
                        .modifier(QuietAppear(index: index))
                        .task { await notes.loadMoreIfNeeded(current: note) }
                        if index < notes.items.count - 1 { Hairline() }
                    }
                    if notes.isLoadingMore {
                        KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var repostsTab: some View {
        switch reposts.phase {
        case .idle, .loading:
            KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 240)
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await reposts.reload() } })
                .padding(.top, 48)
        case .loaded:
            if reposts.items.isEmpty {
                FeedPlaceholder(
                    title: "아직 리포스트가 없어요",
                    message: isOwnAuthor
                        ? "마음에 든 노트를 리포스트하면 여기에 모여요."
                        : "이 작가가 리포스트한 노트가 여기에 모여요.",
                    actionTitle: "노트 둘러보기",
                    action: { TabRouter.shared.selection = 1 }
                )
                .padding(.top, 48)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(reposts.items.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
                            note: note,
                            onChange: { reposts.replaced($0) },
                            onDelete: { reposts.removed($0) },
                            repostedBy: username
                        )
                        .modifier(QuietAppear(index: index))
                        .task { await reposts.loadMoreIfNeeded(current: note) }
                        if index < reposts.items.count - 1 { Hairline() }
                    }
                    if reposts.isLoadingMore {
                        KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private var seriesTab: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: Route.series(username: username, slug: item.slug)) {
                    catalogRow(title: item.title, detail: Text("\(item.postCount)편"), systemImage: nil)
                }
                .buttonStyle(RowButtonStyle())
                .modifier(QuietAppear(index: index))
                if index < series.count - 1 { Hairline() }
            }
        }
    }

    // 공개 컬렉션 — 상세는 인증 면이라 미로그인 탭은 로그인으로 잇는다(막다른 길 금지).
    private var collectionsTab: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(collections.enumerated()), id: \.element.id) { index, item in
                let row = catalogRow(
                    title: item.title, detail: Text("\(item.count)개"),
                    systemImage: item.kind == .path
                        ? "point.topleft.down.to.point.bottomright.curvepath" : "square.stack")
                Group {
                    if AuthStore.shared.isSignedIn {
                        NavigationLink(value: Route.collection(id: item.id)) { row }
                    } else {
                        Button { showCollectionLogin = true } label: { row }
                    }
                }
                .buttonStyle(RowButtonStyle())
                .modifier(QuietAppear(index: index))
                if index < collections.count - 1 { Hairline() }
            }
        }
    }

    private func catalogRow(title: String, detail: Text, systemImage: String?) -> some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                detail
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 14)
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

enum AuthorTab: Hashable {
    case posts, notes, reposts, series, collections

    var label: LocalizedStringKey {
        switch self {
        case .posts: "글"
        case .notes: "노트"
        case .reposts: "리포스트"
        case .series: "시리즈"
        case .collections: "컬렉션"
        }
    }

    var key: String {
        switch self {
        case .posts: "posts"
        case .notes: "notes"
        case .reposts: "reposts"
        case .series: "series"
        case .collections: "collections"
        }
    }
}

private struct AvatarTarget: Identifiable {
    let url: URL
    var id: URL { url }
}

/// 프로필 사진 크게 보기 — 어두운 막 위 큰 원(웹과 같은 문법). 바깥을 누르거나 닫기로 닫는다.
private struct AvatarViewer: View {
    let url: URL
    let name: String
    @State private var appeared = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width * 0.8, 360)
            ZStack {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                RemoteImage(url: url, maxPixel: 720) { phase in
                    Palette.hairline.overlay {
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipShape(Circle())
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
                .accessibilityElement()
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(Text(name))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, Metrics.gutter)
            .padding(.top, 8)
            .accessibilityLabel(Text("닫기"))
            .accessibilityIdentifier("author.avatar.close")
        }
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { appeared = true }
        }
    }
}

private struct AuthorTabBar: View {
    let tabs: [AuthorTab]
    @Binding var selection: AuthorTab
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.label)
                        .typeScale(.body)
                        .fontWeight(selection == tab ? .semibold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selection == tab ? Palette.ink : Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if selection == tab {
                                Capsule()
                                    .fill(Palette.ink)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("author.tab.\(tab.key)")
            }
        }
        .background(alignment: .bottom) { Hairline() }
        .background(Palette.readingBg)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selection)
    }
}
