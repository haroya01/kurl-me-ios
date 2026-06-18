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
            // 시스템 버튼엔 스피너를 못 얹으니, 진행 중엔 흐리고 입력을 막아 이중탭을 가둔다(Google 경로와 동일 상태).
            SignInWithAppleButton(.continue) { request in
                appleNonce = AuthStore.prepareAppleRequest(request)
            } onCompletion: { result in
                finishApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(Capsule())
            .disabled(isSigningIn)
            .opacity(isSigningIn ? 0.6 : 1)

            // Google 버튼도 브랜딩 규정 — 중립 면 + 4색 "G" 로고 + 정해진 문구(초록 캡슐 X).
            Button {
                startSignIn()
            } label: {
                HStack(spacing: 10) {
                    if isSigningIn {
                        ProgressView().controlSize(.small).tint(googleText)
                    } else {
                        GoogleGLogo().frame(width: 18, height: 18)
                    }
                    Text("Google로 계속하기")
                        .font(.system(size: 15 * unit, weight: .medium))
                        .foregroundStyle(googleText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(googleBg, in: Capsule())
                .overlay(Capsule().strokeBorder(googleBorder, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
            .accessibilityLabel(Text("Google로 계속하기"))
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
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
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

    // Google 브랜딩 색 — 라이트=흰 면/짙은 글자, 다크=짙은 면/옅은 글자(공식 light/dark 변형).
    private var googleBg: Color {
        colorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.078) : .white
    }
    private var googleText: Color {
        colorScheme == .dark ? Color(white: 0.9) : Color(red: 0.12, green: 0.12, blue: 0.12)
    }
    private var googleBorder: Color {
        colorScheme == .dark ? Color(white: 0.32) : Color(red: 0.855, green: 0.863, blue: 0.878)
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
    @State private var errorText: String?

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

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13 * unit))
                        .foregroundStyle(Palette.danger)
                        .padding(.top, 8)
                }

                Button {
                    verify()
                } label: {
                    Group {
                        if isVerifying {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Text("확인")
                                .font(.system(size: 15 * unit, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
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
                    errorText = nil
                }
                .font(.system(size: 13 * unit))
                .foregroundStyle(Palette.link)
                .padding(.top, 14)
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
        // 키보드가 올라오면 .medium 이 답답해지니 .large 로 늘릴 수 있게 둔다.
        .presentationDetents([.medium, .large])
        // 검증 중 드래그로 시트가 닫혀 무음 중단되는 것을 막는다 — 취소는 명시적 "취소" 버튼으로만.
        .interactiveDismissDisabled(isVerifying)
    }

    private func verify() {
        guard !isVerifying else { return }
        isVerifying = true
        errorText = nil
        Task {
            defer { isVerifying = false }
            do {
                try await AuthStore.shared.completeTwoFactor(code: code, recovery: useRecovery)
                dismiss()
            } catch {
                // 코드 거절(4xx)과 일시 장애(네트워크·서버)를 갈라 보여준다 — 둘 다 "코드 오류"로 묻지 않는다.
                if let status = (error as? APIError)?.statusCode, (400...422).contains(status) {
                    errorText = useRecovery
                        ? String(localized: "복구 코드가 올바르지 않습니다.")
                        : String(localized: "코드가 올바르지 않습니다.")
                } else {
                    errorText = (error as? APIError)?.localizedDescription
                        ?? String(localized: "확인하지 못했습니다. 잠시 후 다시 시도해 주세요.")
                }
            }
        }
    }
}

/// Google 4색 "G" 마크 — 공식 에셋이 없어 가이드라인 색으로 직접 그린다(필요하면 공식 PNG 로 교체 가능).
/// 링은 4색 호 + 파란 가로 크로스바, 우상단이 입(mouth)으로 열린다.
struct GoogleGLogo: View {
    private static let blue = Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
    private static let green = Color(red: 52 / 255, green: 168 / 255, blue: 83 / 255)
    private static let yellow = Color(red: 251 / 255, green: 188 / 255, blue: 5 / 255)
    private static let red = Color(red: 234 / 255, green: 67 / 255, blue: 53 / 255)

    var body: some View {
        Canvas { ctx, size in
            let w = min(size.width, size.height)
            let lw = w * 0.235
            let radius = (w - lw) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            func seg(_ from: Double, _ to: Double, _ color: Color) {
                var p = Path()
                p.addArc(
                    center: c, radius: radius,
                    startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
            }
            // 0°=3시, 90°=6시, 180°=9시, 270°=12시 (화면에서 시계방향). 우상단(310°~350°)은 입으로 비운다.
            seg(234, 310, Self.red)      // 위
            seg(-10, 40, Self.blue)      // 오른쪽(크로스바 쪽)
            seg(40, 140, Self.green)     // 아래
            seg(140, 234, Self.yellow)   // 왼쪽

            // 파란 가로 크로스바 — 가운데에서 오른쪽 링까지.
            let bar = CGRect(x: c.x, y: c.y - lw / 2, width: radius + lw / 2, height: lw)
            ctx.fill(Path(bar), with: .color(Self.blue))
        }
        .accessibilityHidden(true)
    }
}
