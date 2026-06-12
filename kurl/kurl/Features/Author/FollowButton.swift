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
    @State private var showTwoFactorHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .foregroundStyle(model.following ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: !model.following)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.following)

            if let count = model.followerCount {
                Text("팔로워 \(count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: count)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task { await model.hydrate() }
        .alert("로그인이 필요합니다", isPresented: $showLoginPrompt) {
            Button("Apple로 로그인") { appleHere() }
            Button("Google로 로그인") { signInHere() }
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
        Task {
            do { try await model.toggle() }
            catch { ToastCenter.shared.show(String(localized: "팔로우를 반영하지 못했습니다")) }
        }
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

    private func appleHere() {
        Task {
            if (try? await AuthStore.shared.signInWithApple()) == .twoFactorRequired {
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
