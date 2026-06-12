//
//  AccountView.swift
//  kurl
//

import AuthenticationServices
import SwiftUI

/// 계정 탭 — 조용한 웹로그 톤 그대로. 로그아웃 상태는 한 단락 + 로그인 두 줄(Apple/Google),
/// 로그인 상태는 정체(아바타·이름·이메일)와 로그아웃만. 기능 나열식 설정 화면 금지.
struct AccountView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSigningIn = false
    @State private var appleNonce = ""
    @State private var showTwoFactor = false
    @State private var showNotifications = false
    @State private var unreadCount: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0) {
                Group {
                    if auth.isSignedIn {
                        signedIn
                    } else {
                        signedOut
                    }
                }
                // 정체 패널(유리)이 설 자리 — 옅은 브랜드 안개가 유리 뒤로 흐른다.
                // (ReadingColumn 의 pageBg 안쪽이어야 보인다. 가터를 음수로 물려 전폭.)
                .background(alignment: .top) {
                    BrandMist()
                        .frame(height: 300)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                        .padding(.horizontal, -Metrics.gutter)
                }
            }
            .navigationTitle("내 계정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.brand)
                    .accessibilityLabel("설정")
                }
                if auth.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNotifications = true
                        } label: {
                            Image(systemName: "bell")
                                .overlay(alignment: .topTrailing) {
                                    if unreadCount > 0 {
                                        Circle()
                                            .fill(Palette.accent)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 3, y: -2)
                                    }
                                }
                        }
                        .tint(.brand)
                        .accessibilityLabel("알림")
                    }
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationsView()
            }
            .onChange(of: showNotifications) { _, open in
                // 알림에서 돌아오면 미읽음 점 갱신 — 모두 읽었는데 점이 남지 않게.
                if !open, auth.isSignedIn {
                    Task { unreadCount = (try? await NotificationsAPI.unreadCount()) ?? 0 }
                }
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn {
                    Task { unreadCount = (try? await NotificationsAPI.unreadCount()) ?? 0 }
                } else {
                    unreadCount = 0
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // 며칠 만에 돌아와도 미읽음 점이 그제 상태로 남지 않게.
                if newPhase == .active, auth.isSignedIn {
                    Task { unreadCount = (try? await NotificationsAPI.unreadCount()) ?? unreadCount }
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .task {
                if auth.isSignedIn {
                    unreadCount = (try? await NotificationsAPI.unreadCount()) ?? 0
                }
                if Config.consumeLaunchValue(after: "--open") == "notifications" {
                    showNotifications = true
                }
            }
        }
        .sheet(isPresented: $showTwoFactor) {
            TwoFactorSheet()
        }
        .alert(
            "로그인 실패",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: 로그아웃 상태

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("계정")
                .padding(.top, 28)

            // 환대의 유리 패널 — 안개 위에 뜬 한 장. 본문 타이포는 유리 위 시맨틱.
            VStack(alignment: .leading, spacing: 0) {
                Text("kurl에 로그인")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)

                Text("좋아요와 북마크, 구독, 그리고 글쓰기까지 — 웹과 같은 계정 하나로 이어집니다.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.top, 8)

                // Apple 버튼은 시스템 소유 모양(브랜딩 규정) — 유리를 입히지 않고 캡슐만 맞춘다.
                SignInWithAppleButton(.continue) { request in
                    appleNonce = AuthStore.prepareAppleRequest(request)
                } onCompletion: { result in
                    finishApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .clipShape(Capsule())
                .padding(.top, 24)

                Button {
                    startSignIn()
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView().tint(.white)
                        }
                        Text("Google로 계속하기")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    // 유리 패널 안 주행동 = 솔리드 그린 캡슐 — 유리 위 유리 금지(§1.4).
                    .background(GlassTokens.prominentTint, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .padding(.top, 10)

                Text("로그인은 시스템 브라우저에서 안전하게 진행됩니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.panelRadius))
            .padding(.top, 16)
        }
    }

    private func startSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                if try await auth.signIn() == .twoFactorRequired {
                    showTwoFactor = true
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
                if try await auth.completeApple(result, rawNonce: appleNonce) == .twoFactorRequired {
                    showTwoFactor = true
                }
            } catch AuthError.cancelled {
                // 사용자가 시트를 닫음 — 조용히
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: 로그인 상태

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("계정")
                .padding(.top, 28)

            // 정체 카드 — 안개 위에 뜬 유리 한 장. 탭 = 독자에게 보이는 내 블로그.
            NavigationLink(value: Route.author(username: auth.me?.username ?? "")) {
                HStack(spacing: 12) {
                    AvatarView(
                        author: Author(
                            id: 0,
                            username: auth.me?.username ?? "kurl",
                            bio: nil,
                            avatarUrl: auth.me?.avatarUrl
                        ),
                        size: 52
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(auth.me?.username ?? "kurl")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("내 블로그 보기")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.link)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: GlassTokens.panelRadius))
            .disabled((auth.me?.username ?? "").isEmpty)
            .padding(.top, 16)

            // 서재 — 행동(좋아요·북마크·구독)의 모아 보기.
            RailHeading("서재")
                .padding(.top, 28)
                .padding(.bottom, 4)
            libraryRow("북마크", icon: "bookmark") { BookmarksView() }
            Hairline()
            libraryRow("좋아요한 글", icon: "heart") { LikedPostsView() }
            Hairline()
            libraryRow("구독한 시리즈", icon: "square.stack.3d.up") { SubscribedSeriesView() }

            Hairline()
                .padding(.top, 24)

            Button("로그아웃", role: .destructive) {
                auth.signOut()
            }
            .font(.system(size: 15))
            .padding(.top, 18)
        }
        .task { await auth.loadMe() }
    }

    private func libraryRow(
        _ title: LocalizedStringKey, icon: String, @ViewBuilder destination: @escaping () -> some View
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.accentMarker)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// 2FA 계정의 TOTP 입력. 챌린지는 AuthStore 가 보류 중.
private struct TwoFactorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var useRecovery = false
    @State private var isVerifying = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(useRecovery ? "복구 코드를 입력하세요" : "인증 앱의 6자리 코드를 입력하세요")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.body)
                    .padding(.top, 8)

                TextField(useRecovery ? "복구 코드" : "000000", text: $code)
                    .textContentType(useRecovery ? nil : .oneTimeCode)
                    .keyboardType(useRecovery ? .asciiCapable : .numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .padding(.top, 14)

                if failed {
                    Text("코드가 올바르지 않습니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                Button {
                    verify()
                } label: {
                    Text("확인")
                        .font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 13))
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

#Preview {
    AccountView()
}
