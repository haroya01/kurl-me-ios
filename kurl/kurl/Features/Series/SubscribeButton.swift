//
//  SubscribeButton.swift
//  kurl
//

import SwiftUI

/// 시리즈 구독 버튼 — FollowButton 과 같은 문법(채움=accent-700, 구독 중=muted 외곽선).
/// 새 글이 올라오면 알림으로 이어지는 구독이라 라벨은 "구독"으로.
struct SubscribeButton: View {
    @State private var model: SubscribeModel
    @State private var showLoginPrompt = false
    @State private var showTwoFactorHint = false

    init(seriesId: Int64) {
        _model = State(initialValue: SubscribeModel(seriesId: seriesId))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggle()
            } label: {
                Text(model.subscribed ? "구독 중" : "구독")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.subscribed ? Palette.body : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background {
                        if model.subscribed {
                            Capsule().strokeBorder(Palette.hairlineStrong, lineWidth: 1)
                        } else {
                            Capsule().fill(Palette.accentFill)
                        }
                    }
            }
            .buttonStyle(.plain)
            .animation(.snappy(duration: 0.2), value: model.subscribed)

            if let count = model.subscriberCount, count > 0 {
                Text("구독자 \(count)")
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
            Text("구독하면 시리즈에 새 글이 올라올 때 알 수 있어요.")
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
final class SubscribeModel {
    private(set) var subscribed = false
    /// 햅틱 트리거 — hydrate 가 아닌 사용자 토글에만 증가.
    private(set) var userToggleCount = 0
    private(set) var subscriberCount: Int64?

    private let seriesId: Int64

    init(seriesId: Int64) {
        self.seriesId = seriesId
    }

    /// 구독 표면은 전부 인증 — 비로그인은 hydrate 생략(버튼은 "구독" 기본값).
    func hydrate() async {
        guard AuthStore.shared.isSignedIn else { return }
        let gen = userToggleCount
        if let status = try? await InteractionsAPI.subscriptionStatus(seriesId: seriesId), gen == userToggleCount {
            subscribed = status.subscribed
            subscriberCount = status.subscriberCount
        }
    }

    func toggle() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !subscribed
        subscribed = target
        if let count = subscriberCount {
            subscriberCount = max(0, count + (target ? 1 : -1))
        }
        do {
            let status = try await InteractionsAPI.setSubscription(seriesId: seriesId, on: target)
            guard gen == userToggleCount else { return }
            subscribed = status.subscribed
            subscriberCount = status.subscriberCount
        } catch {
            guard gen == userToggleCount else { return }
            await hydrate()
            throw error
        }
    }
}
