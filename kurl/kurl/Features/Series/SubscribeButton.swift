//
//  SubscribeButton.swift
//  kurl
//

import SwiftUI

/// 시리즈 구독 버튼 — FollowButton 과 같은 유리 캡슐 문법(구독 전=그린 유리, 구독 중=맑은 유리).
/// 새 글이 올라오면 알림으로 이어지는 구독이라 라벨은 "구독"으로.
struct SubscribeButton: View {
    /// 화면에서의 무게 — primary 는 구독 전 그린 유리(기본), secondary 는 다른 그린 주행동
    /// (예: 시리즈 상세의 '이어 읽기') 옆에서 색을 다투지 않게 늘 맑은 유리로 가라앉는다.
    enum Emphasis { case primary, secondary }

    @State private var model: SubscribeModel
    @State private var showLoginPrompt = false
    private let emphasis: Emphasis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(seriesId: Int64, emphasis: Emphasis = .primary) {
        _model = State(initialValue: SubscribeModel(seriesId: seriesId))
        self.emphasis = emphasis
    }

    /// 그린 채움 유리는 primary + 구독 전에만. secondary 는 맑은 유리로 가라앉는다.
    private var prominent: Bool { emphasis == .primary && !model.subscribed }

    /// 유리 위 라벨색 — 그린 채움엔 흰 글자, 맑은 유리엔 시맨틱/그린 텍스트(§1.2·§1.3).
    private var labelStyle: AnyShapeStyle {
        switch (emphasis, model.subscribed) {
        case (.primary, false): return AnyShapeStyle(.white)
        case (.primary, true): return AnyShapeStyle(.primary)
        case (.secondary, false): return AnyShapeStyle(Palette.link)
        case (.secondary, true): return AnyShapeStyle(.secondary)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 캡슐 시각 높이 ~30pt → expandTap 으로 탭 영역만 44pt(시각 크기 유지).
            ToggleCapsuleButton(
                isOn: model.subscribed, on: "구독 중", off: "구독",
                prominent: prominent, labelStyle: labelStyle, expandTap: 12
            ) {
                toggle()
            }

            if let count = model.subscriberCount, count > 0 {
                Text("구독자 \(count)")
                    .typeScale(.meta)
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
