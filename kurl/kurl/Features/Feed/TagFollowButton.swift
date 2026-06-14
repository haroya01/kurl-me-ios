//
//  TagFollowButton.swift
//  kurl
//

import SwiftUI

/// 태그 구독 버튼 — 시리즈 구독과 같은 유리 캡슐 문법(구독 전=그린 유리, 구독 중=맑은 유리).
/// 구독한 태그의 새 글은 구독함 피드로 흘러든다(웹 tag-prefs parity).
struct TagFollowButton: View {
    @State private var model: TagFollowModel
    @State private var showLoginPrompt = false
    @State private var showTwoFactorHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tag: String) {
        _model = State(initialValue: TagFollowModel(tag: tag))
    }

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.following ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.following ? "구독 중" : "구독")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(model.following ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(prominent: !model.following)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.following)
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task { await model.hydrate() }
        .accessibilityLabel(Text("태그 구독"))
        .accessibilityAddTraits(model.following ? [.isSelected] : [])
        .alert("로그인이 필요합니다", isPresented: $showLoginPrompt) {
            Button("Apple로 로그인") { appleHere() }
            Button("Google로 로그인") { signInHere() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("태그를 구독하면 그 태그의 새 글이 구독함에 모여요.")
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
            catch { ToastCenter.shared.show(String(localized: "구독을 반영하지 못했습니다")) }
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
final class TagFollowModel {
    private(set) var following = false
    /// 햅틱 트리거 — hydrate 가 아닌 사용자 토글에만 증가.
    private(set) var userToggleCount = 0

    private let tag: String

    init(tag: String) {
        self.tag = tag
    }

    private func isThis(_ t: String) -> Bool { t.caseInsensitiveCompare(tag) == .orderedSame }

    /// 구독 표면은 인증 — 비로그인은 hydrate 생략(버튼은 "구독" 기본값).
    func hydrate() async {
        guard AuthStore.shared.isSignedIn else { return }
        let gen = userToggleCount
        if let prefs = try? await InteractionsAPI.tagPrefs(), gen == userToggleCount {
            following = prefs.followed.contains(where: isThis)
        }
    }

    func toggle() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !following
        following = target
        do {
            let prefs = try await InteractionsAPI.setTagFollow(tag: tag, on: target)
            guard gen == userToggleCount else { return }
            following = prefs.followed.contains(where: isThis)
        } catch {
            guard gen == userToggleCount else { return }
            following = !target
            throw error
        }
    }
}
