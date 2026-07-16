//
//  FollowListsView.swift
//  kurl
//

import SwiftUI

/// 작가의 팔로워 / 팔로잉 목록 — 한 화면에서 두 탭(유리 세그먼트)으로 오간다. 행 = 작가 행
/// (아바타·핸들·소개) + 행별 팔로우 토글(백엔드 followedByMe 로 시드 — 행마다 status 를 조회하는
/// N+1 회피). 행 탭은 그 작가로. 무한 스크롤(hasNext).
struct FollowListsView: View {
    let username: String

    enum FollowTab: String, Identifiable, CaseIterable {
        case followers, following
        var id: String { rawValue }
        var title: String { self == .followers ? String(localized: "팔로워") : String(localized: "팔로잉") }
    }

    @State private var tab: FollowTab
    @State private var items: [FollowUser] = []
    /// 지금 보이는 items 가 어느 탭 응답인지 — 실패 시 이전 탭 목록을 새 탭에 남겨두지 않기 위한 표식.
    @State private var itemsTab: FollowTab?
    @State private var page = 0
    @State private var hasNext = false
    @State private var loading = false
    @State private var loadedOnce = false
    /// 네트워크 실패 — 빈 200 과 구분해 재시도를 노출한다(빈 상태 위장 방지).
    @State private var failed = false
    /// 세대 토큰 — 탭 전환으로 끼어든 reload 뒤에 도착한 옛 응답을 버린다.
    @State private var epoch = 0
    @State private var showLoginPrompt = false

    init(username: String, tab: FollowTab) {
        self.username = username
        _tab = State(initialValue: tab)
    }

    var body: some View {
        ReadingColumn(spacing: 0) {
            GlassSegmentSwitcher(items: FollowTab.allCases, selection: $tab, label: { $0.title })
                .padding(.top, 8)
                .padding(.bottom, 8)

            if loading && items.isEmpty {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed {
                ErrorState(retry: { Task { await reload() } })
                    .padding(.top, 56)
            } else if loadedOnce && items.isEmpty {
                ContentUnavailableView {
                    Label(
                        tab == .followers ? "아직 팔로워가 없어요" : "아직 팔로우하는 사람이 없어요",
                        systemImage: "person.2")
                } actions: {
                    // 내 팔로잉 0 = 콜드스타트의 한복판 — 유일하게 CTA 없던 빈 면이었다.
                    // 사람을 찾을 경로(발견 탭)를 형제 빈 면들과 같은 문법으로 내민다.
                    if tab == .following, AuthStore.shared.me?.username == username {
                        Button("발견에서 작가 찾기") { TabRouter.shared.selection = 1 }
                            .foregroundStyle(Palette.link)
                    }
                }
                .padding(.top, 56)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, user in
                        NavigationLink(value: Route.author(username: user.username)) {
                            row(user)
                        }
                        .buttonStyle(RowButtonStyle())
                        .modifier(QuietAppear(index: index))
                        .task {
                            if index == items.count - 1 { await loadMore() }
                        }
                        if index < items.count - 1 { Hairline() }
                    }
                    if hasNext {
                        KurlLoadingMark()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
            }
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tab) { await reload() }
        .refreshable { await reload() }
        .loginPrompt(isPresented: $showLoginPrompt, message: "이 작가의 새 글을 피드에서 받기") {
            // 로그인 후 followedByMe 시드가 stale — 목록을 다시 받아 행 토글을 새로 시드.
            await reload()
        }
    }

    private func row(_ user: FollowUser) -> some View {
        HStack(spacing: 11) {
            AvatarView(author: user.asAuthor, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            RowFollowToggle(
                username: user.username,
                initialFollowing: user.followedByMe,
                onNeedLogin: { showLoginPrompt = true })
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func reload() async {
        loading = true
        failed = false
        epoch += 1
        let myEpoch = epoch
        do {
            let res = try await fetch(page: 0)
            guard myEpoch == epoch else { return }
            items = res.items
            itemsTab = tab
            page = 0
            hasNext = res.hasNext
        } catch {
            // 탭 전환의 .task(id:) 취소 — 새 탭 reload 가 화면을 맡으니 상태를 건드리지 않는다
            // (여기서 비우면 다음 응답까지 빈 상태 문구가 깜빡인다). URLSession 취소는
            // APIError.transport 로 감싸여 올라오므로 오류 타입 대신 Task.isCancelled 로 판별.
            if Task.isCancelled || error is CancellationError { return }
            guard myEpoch == epoch else { return }
            // 같은 탭의 재조회(당겨서 새로고침·로그인 후) 실패면 보이던 목록을 보존하고,
            // 그 외엔 빈 상태로 위장하는 대신 재시도를 노출한다.
            if itemsTab != tab || items.isEmpty {
                items = []
                itemsTab = nil
                hasNext = false
                failed = true
            }
        }
        loading = false
        loadedOnce = true
    }

    private func loadMore() async {
        guard hasNext, !loading else { return }
        loading = true
        let myEpoch = epoch
        let res = try? await fetch(page: page + 1)
        // reload 가 끼어들었으면 옛 세대 응답 — 목록도 loading 도 건드리지 않고 버린다
        // (다른 탭 행이 이어붙거나 page 를 되감는 오염 방지).
        guard myEpoch == epoch else { return }
        if let res {
            items += res.items
            page = res.page
            hasNext = res.hasNext
        }
        loading = false
    }

    private func fetch(page: Int) async throws -> FollowListPage {
        tab == .followers
            ? try await FollowListsAPI.followers(username: username, page: page)
            : try await FollowListsAPI.following(username: username, page: page)
    }
}

/// 탭 가능한 "팔로워 N · 팔로잉 N" — 작가 헤더에 들어가 각 숫자가 해당 목록으로 민다.
/// 숫자 GET 이 실패해도 목록 진입로는 살아 있어야 한다(유일한 문) — 그래서 링크는 항상
/// tappable, 실패 땐 숫자 자리에 "—" 플레이스홀더 + 재시도. FollowButton 과 별개의 공개 status GET.
struct FollowCountsLink: View {
    let username: String
    /// 호출측이 작가 로드 때 이미 받아 둔 수 — 같은 status GET 을 또 치지 않도록 시드.
    var initialStatus: InteractionsAPI.FollowStatus?
    @State private var followers: Int64?
    @State private var followingCount: Int64?
    /// 작가가 팔로워 수를 숨겼는지 — 켜지면 숫자 없이 라벨만(목록 진입로는 유지).
    @State private var hidden = false
    @State private var failed = false

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: Route.followers(username: username)) {
                countLabel(String(localized: "팔로워"), followers)
            }
            .buttonStyle(.plain)
            Text("·").foregroundStyle(Palette.faint)
            NavigationLink(value: Route.following(username: username)) {
                countLabel(String(localized: "팔로잉"), followingCount)
            }
            .buttonStyle(.plain)
            if failed, !hidden {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.link)
                        .expandTapTarget(8)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
        // 로딩 첫 프레임만 숨겨 0→실제값 깜빡임을 막고(실패 땐 플레이스홀더로 보여 줌), 링크 탭은 죽이지 않는다.
        // 숨김이면 첫 프레임부터 라벨만 보여야 하므로 감추지 않는다.
        .opacity(!hidden && followers == nil && !failed ? 0 : 1)
        .animation(.snappy(duration: 0.2), value: followers)
        .task {
            // 시드를 받았으면 그 값으로 그리고 GET 을 건너뛴다(작가 페이지가 이미 한 번 받아 둠).
            if let seed = initialStatus {
                hidden = seed.hideFollowerCount
                followers = seed.followerCount
                followingCount = seed.followingCount
            } else {
                await load()
            }
        }
    }

    private func load() async {
        failed = false
        do {
            let status = try await InteractionsAPI.followStatus(username: username)
            hidden = status.hideFollowerCount
            followers = status.followerCount
            followingCount = status.followingCount
        } catch {
            // 숫자만 못 받았을 뿐 — 링크는 살려 두고, 숫자 자리엔 플레이스홀더 + 재시도.
            if followers == nil { failed = true }
        }
    }

    private func countLabel(_ label: String, _ count: Int64?) -> some View {
        HStack(spacing: 4) {
            // 숨김이면 숫자 없이 라벨만(목록 링크는 살아 있다). 미로딩은 "—" 플레이스홀더.
            Text(hidden ? label : (count.map { "\(label) \($0)" } ?? "\(label) —"))
                .contentTransition(.numericText())
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.faint)
        }
        .contentShape(Rectangle())
    }
}

/// 행별 팔로우 토글 — 목록 행마다. 상태는 백엔드 followedByMe 로 시드(행마다 status 조회 X).
/// 내 행이면 숨기고, 비로그인 탭은 공용 로그인 시트로 올린다. 낙관, 실패 시 되돌리고 토스트.
private struct RowFollowToggle: View {
    let username: String
    /// State(initialValue:) 는 행 identity(user.id) 첫 생성에만 먹는다 — reload 가 items 를
    /// 갈아끼워도 기존 행은 재시드되지 않으므로 onChange 재동기화용으로 시드를 들고 있는다.
    let initialFollowing: Bool
    let onNeedLogin: () -> Void
    @State private var following: Bool
    @State private var busy = false
    /// 햅틱 트리거 — 되돌림이 아닌 사용자 토글에만 증가(헤더 FollowButton 과 같은 어휘).
    @State private var userToggleCount = 0
    /// 행 팔로우 알약 라벨(헤더보다 한 급 작은 13) — 사다리 미스매치라 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 13

    init(username: String, initialFollowing: Bool, onNeedLogin: @escaping () -> Void) {
        self.username = username
        self.initialFollowing = initialFollowing
        self.onNeedLogin = onNeedLogin
        _following = State(initialValue: initialFollowing)
    }

    var body: some View {
        if AuthStore.shared.me?.username == username {
            EmptyView()
        } else {
            Button {
                toggle()
            } label: {
                Text(following ? "팔로잉" : "팔로우")
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(following ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .contentShape(Capsule())
                    .expandTapTarget(8)  // 캡슐 높이 ~25pt → 탭 영역만 44pt 로(시각 크기 유지)
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: !following)
            .disabled(busy)
            .sensoryFeedback(.impact(weight: .light), trigger: userToggleCount)
            .onChange(of: initialFollowing) { _, seed in
                // 재조회(로그인 후 등)가 새 followedByMe 를 내려주면 재동기화 —
                // 단 낙관 토글 비행 중엔 setFollow 응답이 최종 진실이라 덮지 않는다.
                guard !busy else { return }
                following = seed
            }
        }
    }

    private func toggle() {
        guard AuthStore.shared.isSignedIn else {
            onNeedLogin()
            return
        }
        guard !busy else { return }
        busy = true
        userToggleCount += 1
        let target = !following
        following = target
        Task {
            defer { busy = false }
            do {
                let status = try await InteractionsAPI.setFollow(username: username, on: target)
                following = status.following
            } catch {
                following = !target
                ToastCenter.shared.show(String(localized: "팔로우를 반영하지 못했습니다"))
            }
        }
    }
}
