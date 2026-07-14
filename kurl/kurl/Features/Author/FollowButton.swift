//
//  FollowButton.swift
//  kurl
//

import SwiftUI

/// 작가 페이지의 팔로우 버튼 + 팔로워 수 — 유리 캡슐 문법: 팔로우 전 = 그린(700) 유리,
/// 팔로잉 상태는 맑은 유리로 가라앉는다. 토글은 낙관, 실패 시 서버 상태로 복귀.
struct FollowButton: View {
    @State private var model: FollowModel
    @State private var showLoginPrompt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 옆에 "팔로워 N"을 붙일지 — 작가 헤더처럼 탭 가능한 카운트 행이 따로 있으면 끈다.
    private let showCount: Bool
    /// 본인 작가 페이지/내 글에선 self-follow 가 무의미 — 버튼을 숨긴다.
    private let username: String

    /// 호출측이 작가 로드 때 이미 받아 둔 follow status — 같은 GET 을 또 치지 않도록 시드.
    init(username: String, showCount: Bool = true, initialStatus: InteractionsAPI.FollowStatus? = nil) {
        _model = State(initialValue: FollowModel(username: username, seed: initialStatus))
        self.showCount = showCount
        self.username = username
    }

    var body: some View {
        if AuthStore.shared.me?.username == username {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            // 캡슐 높이 ~33pt → expandTap 으로 탭 영역만 44pt(시각 크기 유지).
            ToggleCapsuleButton(
                isOn: model.following, on: "팔로잉", off: "팔로우", expandTap: 6
            ) {
                toggle()
            }

            if showCount, !model.hideFollowerCount, let count = model.followerCount {
                Text("팔로워 \(count)")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: count)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task { await model.hydrateIfNeeded() }
        .loginPrompt(isPresented: $showLoginPrompt, message: "이 큐레이터가 엮는 길을 따라 읽기") {
            await model.hydrate()
        }
    }

    private func toggle() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        Task {
            do { try await model.toggle() }
            catch { ToastCenter.shared.show(String(localized: "팔로우를 반영하지 못했습니다")) }
        }
    }
}

@MainActor
@Observable
final class FollowModel {
    private(set) var following = false
    /// 햅틱 트리거 — hydrate 가 아닌 사용자 토글에만 증가.
    private(set) var userToggleCount = 0
    private(set) var followerCount: Int64?
    /// 작가가 팔로워 수를 숨겼는지 — 카운트를 서버가 내려도 이 플래그가 켜지면 감춘다.
    private(set) var hideFollowerCount = false
    /// 호출측이 시드를 줬는지 — 줬다면 등장 시 같은 GET 을 또 치지 않는다.
    private var seeded: Bool

    private let username: String

    init(username: String, seed: InteractionsAPI.FollowStatus? = nil) {
        self.username = username
        self.seeded = seed != nil
        if let seed {
            following = seed.following
            followerCount = seed.followerCount
            hideFollowerCount = seed.hideFollowerCount
        }
    }

    /// 시드를 받았으면 첫 hydrate 를 건너뛴다(작가 페이지가 이미 한 번 받아 둠).
    func hydrateIfNeeded() async {
        if seeded { return }
        await hydrate()
    }

    /// 비로그인도 팔로워 수는 공개 — following 만 로그인 상태에서 의미.
    func hydrate() async {
        let gen = userToggleCount
        if let status = try? await InteractionsAPI.followStatus(username: username), gen == userToggleCount {
            following = status.following
            followerCount = status.followerCount
            hideFollowerCount = status.hideFollowerCount
        }
    }

    func toggle() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !following
        following = target
        if let count = followerCount {
            followerCount = count + (target ? 1 : -1)
        }
        do {
            let status = try await InteractionsAPI.setFollow(username: username, on: target)
            guard gen == userToggleCount else { return }
            following = status.following
            followerCount = status.followerCount
            hideFollowerCount = status.hideFollowerCount
        } catch {
            guard gen == userToggleCount else { return }
            await hydrate()
            throw error
        }
    }
}
