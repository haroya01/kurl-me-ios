//
//  LoginPrompt.swift
//  kurl
//

import SwiftUI

extension View {
    /// 인게이지 버튼(팔로우·구독·태그 구독·좋아요/북마크 독) 공용 로그인 유도 — 같은 알럿 한 쌍
    /// (로그인 + 2FA 힌트)과 Apple/Google 사인인 핸들러가 네 곳에 똑같이 복제돼 있던 것을 한 자리로.
    /// 면마다 다른 건 안내 문구뿐이고, 로그인되면 `onSignedIn`(보통 `model.hydrate()`)을 부른다.
    func loginPrompt(
        isPresented: Binding<Bool>,
        message: LocalizedStringKey,
        onSignedIn: @escaping () async -> Void = {}
    ) -> some View {
        modifier(LoginPromptModifier(isPresented: isPresented, message: message, onSignedIn: onSignedIn))
    }
}

private struct LoginPromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: LocalizedStringKey
    let onSignedIn: () async -> Void

    /// 2FA 힌트는 이 모디파이어가 소유 — 호출측은 신경 쓰지 않는다.
    @State private var showTwoFactor = false

    func body(content: Content) -> some View {
        content
            .alert("로그인이 필요합니다", isPresented: $isPresented) {
                Button("Apple로 로그인") { authenticate(apple: true) }
                Button("Google로 로그인") { authenticate(apple: false) }
                Button("취소", role: .cancel) {}
            } message: {
                Text(message)
            }
            .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactor) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("내 계정 탭에서 로그인을 완료해 주세요.")
            }
    }

    private func authenticate(apple: Bool) {
        Task {
            // 2FA 계정은 TOTP 입력 UI 가 계정 탭에 있어 여기서 끝까지 못 간다 — 안내만.
            let outcome = apple
                ? try? await AuthStore.shared.signInWithApple()
                : try? await AuthStore.shared.signIn()
            if outcome == .twoFactorRequired {
                showTwoFactor = true
            } else if AuthStore.shared.isSignedIn {
                await onSignedIn()
            }
        }
    }
}
