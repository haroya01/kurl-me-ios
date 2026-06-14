//
//  AuthProviderButtons.swift
//  kurl
//

import AuthenticationServices
import SwiftUI

/// Apple + Google 로그인 버튼 한 쌍 — 계정 탭·글쓰기 게이트·웰컴·로그인 시트가 공유하는 단일 출처.
/// 이 묶음(공식 Apple 버튼 + 그린 캡슐 Google + 2FA 시트 + 실패 알럿)이 네 곳에 복제돼 있던 것을
/// 한 자리로. 2FA 가 걸리면 TwoFactorSheet 를 여기서 직접 띄워 끝까지 간다(면마다 따로 처리 X).
/// 로그인이 끝나면 `onSignedIn`(보통 시트 닫기·hydrate)을 부른다.
struct AuthProviderButtons: View {
    var onSignedIn: () async -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var isSigningIn = false
    @State private var appleNonce = ""
    @State private var showTwoFactor = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            // Apple 버튼은 시스템 소유 모양(브랜딩 규정) — 유리를 입히지 않고 캡슐만 맞춘다.
            SignInWithAppleButton(.continue) { request in
                appleNonce = AuthStore.prepareAppleRequest(request)
            } onCompletion: { result in
                finishApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(Capsule())

            Button {
                startSignIn()
            } label: {
                HStack(spacing: 8) {
                    if isSigningIn { ProgressView().tint(.white) }
                    Text("Google로 계속하기")
                        .font(.system(size: 15 * unit, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                // 솔리드 그린 캡슐 — 유리 위 유리 금지(§1.4). 어느 표면에 얹혀도 같은 주행동.
                .background(GlassTokens.prominentTint, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
        }
        .sheet(isPresented: $showTwoFactor, onDismiss: { Task { await notifyIfSignedIn() } }) {
            TwoFactorSheet()
        }
        .alert(
            "로그인 실패",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                if try await AuthStore.shared.signIn() == .twoFactorRequired {
                    showTwoFactor = true
                } else {
                    await notifyIfSignedIn()
                }
            } catch AuthError.cancelled {
                // 사용자가 시트를 닫음 — 조용히
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) {
        Task {
            do {
                if try await AuthStore.shared.completeApple(result, rawNonce: appleNonce)
                    == .twoFactorRequired {
                    showTwoFactor = true
                } else {
                    await notifyIfSignedIn()
                }
            } catch AuthError.cancelled {
                // 사용자가 시트를 닫음 — 조용히
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 직접 로그인 성공·2FA 시트 완료 후 한 군데서만 통지 — 로그인됐을 때만.
    private func notifyIfSignedIn() async {
        guard AuthStore.shared.isSignedIn else { return }
        await onSignedIn()
    }
}

/// 2FA 계정의 TOTP 입력. 챌린지는 AuthStore 가 보류 중.
struct TwoFactorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var code = ""
    @State private var useRecovery = false
    @State private var isVerifying = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(useRecovery ? "복구 코드를 입력하세요" : "인증 앱의 6자리 코드를 입력하세요")
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(Palette.body)
                    .padding(.top, 8)

                TextField(useRecovery ? "복구 코드" : "000000", text: $code)
                    .textContentType(useRecovery ? nil : .oneTimeCode)
                    .keyboardType(useRecovery ? .asciiCapable : .numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 22 * unit, weight: .medium, design: .monospaced))
                    .padding(.top, 14)

                if failed {
                    Text("코드가 올바르지 않습니다.")
                        .font(.system(size: 13 * unit))
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                Button {
                    verify()
                } label: {
                    Text("확인")
                        .font(.system(size: 15 * unit, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(GlassTokens.prominentTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(code.isEmpty || isVerifying)
                .padding(.top, 20)

                Button(useRecovery ? "인증 앱 코드 사용" : "복구 코드 사용") {
                    useRecovery.toggle()
                    code = ""
                    failed = false
                }
                .font(.system(size: 13 * unit))
                .foregroundStyle(Palette.link)
                .padding(.top, 14)

                Spacer()
            }
            .padding(.horizontal, Metrics.gutter)
            .navigationTitle("2단계 인증")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func verify() {
        guard !isVerifying else { return }
        isVerifying = true
        failed = false
        Task {
            defer { isVerifying = false }
            do {
                try await AuthStore.shared.completeTwoFactor(code: code, recovery: useRecovery)
                dismiss()
            } catch {
                failed = true
            }
        }
    }
}
