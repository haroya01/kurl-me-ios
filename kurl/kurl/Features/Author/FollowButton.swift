//
//  FollowButton.swift
//  kurl
//

import SwiftUI

/// 작가 페이지의 팔로우 버튼 + 팔로워 수 — 그린 실 규칙: 채움(팔로우 전) = accent-700,
/// 팔로잉 상태는 muted 외곽선으로 가라앉는다. 토글은 낙관, 실패 시 서버 상태로 복귀.
struct FollowButton: View {
    @State private var model: FollowModel
    @State private var showLoginPrompt = false
    @State private var showTwoFactorHint = false

    init(username: String) {
        _model = State(initialValue: FollowModel(username: username))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggle()
            } label: {
                Text(model.following ? "팔로잉" : "팔로우")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.following ? Palette.body : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background {
                        if model.following {
                            Capsule().strokeBorder(Palette.hairlineStrong, lineWidth: 1)
                        } else {
                            Capsule().fill(Palette.accentFill)
                        }
                    }
            }
            .buttonStyle(.plain)
            .animation(.snappy(duration: 0.2), value: model.following)

            if let count = model.followerCount {
                Text("팔로워 \(count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: count)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task { await model.hydrate() }
        .alert("로그인이 필요합니다", isPresented: $showLoginPrompt) {
            Button("로그인") { signInHere() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("팔로우하면 새 글을 피드에서 받아볼 수 있어요.")
        }
        .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactorHint) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("내 계정 탭에서 로그인을 완료해 주세요.")
        }
    }

    private func toggle() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        Task { try? await model.toggle() }
    }

    private func signInHere() {
        Task {
            if (try? await AuthStore.shared.signIn()) == .twoFactorRequired {
                showTwoFactorHint = true
            } else if AuthStore.shared.isSignedIn {
                await model.hydrate()
            }
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

    private let username: String

    init(username: String) {
        self.username = username
    }

    /// 비로그인도 팔로워 수는 공개 — following 만 로그인 상태에서 의미.
    func hydrate() async {
        let gen = userToggleCount
        if let status = try? await InteractionsAPI.followStatus(username: username), gen == userToggleCount {
            following = status.following
            followerCount = status.followerCount
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
        } catch {
            guard gen == userToggleCount else { return }
            await hydrate()
            throw error
        }
    }
}
