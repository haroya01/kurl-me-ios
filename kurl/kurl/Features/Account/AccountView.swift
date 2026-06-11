//
//  AccountView.swift
//  kurl
//

import SwiftUI

/// 계정 탭 — 조용한 웹로그 톤 그대로. 로그아웃 상태는 한 단락 + 버튼 하나,
/// 로그인 상태는 정체(아바타·이름·이메일)와 로그아웃만. 기능 나열식 설정 화면 금지.
struct AccountView: View {
    private var auth: AuthStore { .shared }

    @State private var isSigningIn = false
    @State private var showTwoFactor = false
    @State private var showNotifications = false
    @State private var unreadCount: Int64 = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0) {
                if auth.isSignedIn {
                    signedIn
                } else {
                    signedOut
                }
            }
            .navigationTitle("내 계정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

            Text("kurl에 로그인")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 14)

            Text("좋아요와 북마크, 구독, 그리고 글쓰기까지 — 웹과 같은 계정 하나로 이어집니다.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(4)
                .padding(.top, 8)

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
                .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
            .padding(.top, 24)

            Text("로그인은 시스템 브라우저에서 안전하게 진행됩니다.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 10)
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

    // MARK: 로그인 상태

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("계정")
                .padding(.top, 28)

            HStack(spacing: 12) {
                AvatarView(
                    author: Author(
                        id: 0,
                        username: auth.me?.username ?? "kurl",
                        bio: nil,
                        avatarUrl: auth.me?.avatarUrl
                    ),
                    size: 44
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.me?.username ?? "kurl")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(auth.me?.email ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
            }
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
                        .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 12))
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
