//
//  SubscribeButton.swift
//  kurl
//

import SwiftUI

/// 시리즈 구독 버튼 — FollowButton 과 같은 유리 캡슐 문법(구독 전=그린 유리, 구독 중=맑은 유리).
/// 새 글이 올라오면 알림으로 이어지는 구독이라 라벨은 "구독"으로.
struct SubscribeButton: View {
    @State private var model: SubscribeModel
    @State private var showLoginPrompt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .foregroundStyle(model.subscribed ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: !model.subscribed)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.subscribed)

            if let count = model.subscriberCount, count > 0 {
                Text("구독자 \(count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: count)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task { await model.hydrate() }
        .loginPrompt(isPresented: $showLoginPrompt, message: "시리즈 새 글을 놓치지 않게") {
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
            catch { ToastCenter.shared.show(String(localized: "구독을 반영하지 못했습니다")) }
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
