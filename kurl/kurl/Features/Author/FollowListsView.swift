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
        var title: String { self == .followers ? "팔로워" : "팔로잉" }
    }

    @State private var tab: FollowTab
    @State private var items: [FollowUser] = []
    @State private var page = 0
    @State private var hasNext = false
    @State private var loading = false
    @State private var loadedOnce = false
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
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if loadedOnce && items.isEmpty {
                ContentUnavailableView {
                    Label(
                        tab == .followers ? "아직 팔로워가 없어요" : "아직 팔로우하는 사람이 없어요",
                        systemImage: "person.2")
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
                        ProgressView().tint(Palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
            }
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tab) { await reload() }
        .loginPrompt(isPresented: $showLoginPrompt, message: "이 작가의 새 글을 피드에서 받기")
    }

    private func row(_ user: FollowUser) -> some View {
        HStack(spacing: 11) {
            AvatarView(author: user.asAuthor, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.system(size: 15, weight: .semibold))
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
        page = 0
        do {
            let res = try await fetch(page: 0)
            items = res.items
            hasNext = res.hasNext
        } catch {
            items = []
            hasNext = false
        }
        loading = false
        loadedOnce = true
    }

    private func loadMore() async {
        guard hasNext, !loading else { return }
        loading = true
        if let res = try? await fetch(page: page + 1) {
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
/// 로딩 전엔 투명(0 깜빡임 방지). FollowButton 과 별개의 공개 status GET 한 번.
struct FollowCountsLink: View {
    let username: String
    @State private var followers: Int64?
    @State private var followingCount: Int64?

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: Route.followers(username: username)) {
                countLabel("팔로워", followers)
            }
            .buttonStyle(.plain)
            Text("·").foregroundStyle(Palette.faint)
            NavigationLink(value: Route.following(username: username)) {
                countLabel("팔로잉", followingCount)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .typeScale(.meta)
        .foregroundStyle(Palette.secondary)
        .opacity(followers == nil ? 0 : 1)
        .animation(.snappy(duration: 0.2), value: followers)
        .task {
            if let status = try? await InteractionsAPI.followStatus(username: username) {
                followers = status.followerCount
                followingCount = status.followingCount
            }
        }
    }

    private func countLabel(_ label: String, _ count: Int64?) -> some View {
        HStack(spacing: 4) {
            Text("\(label) \(count ?? 0)")
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
    let onNeedLogin: () -> Void
    @State private var following: Bool
    @State private var busy = false

    init(username: String, initialFollowing: Bool, onNeedLogin: @escaping () -> Void) {
        self.username = username
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(following ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: !following)
            .disabled(busy)
        }
    }

    private func toggle() {
        guard AuthStore.shared.isSignedIn else {
            onNeedLogin()
            return
        }
        guard !busy else { return }
        busy = true
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
