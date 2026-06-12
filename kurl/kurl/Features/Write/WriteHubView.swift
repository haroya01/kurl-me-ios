//
//  WriteHubView.swift
//  kurl
//

import AuthenticationServices
import SwiftUI

/// 글쓰기 탭 — 웹 /write 허브의 축소판: 내 글 목록(임시저장/발행 상태) + 새 글.
/// 로그아웃 상태는 이 표면 전체가 로그인 게이트.
struct WriteHubView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: LoadState<[MyPost]> = .idle
    @State private var composing = false
    @State private var editing: MyPost?
    @State private var showAnalytics = false
    @State private var isSigningIn = false
    @State private var showTwoFactorHint = false
    @State private var appleNonce = ""

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    hub
                } else {
                    signedOutGate
                }
            }
            .navigationTitle("글쓰기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if auth.isSignedIn {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showAnalytics = true
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                        .tint(.brand)
                        .accessibilityLabel("분석")
                    }
                }
            }
            // 새 글 = 떠 있는 유리 FAB — 글쓰기 탭의 주행동을 엄지 아래로.
            .overlay(alignment: .bottomTrailing) {
                if auth.isSignedIn {
                    GlassFAB(systemImage: "square.and.pencil", label: "새 글") {
                        composing = true
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationDestination(isPresented: $showAnalytics) {
                AnalyticsView()
            }
            .navigationDestination(isPresented: $composing) {
                ComposeView(post: nil) { reloadSoon() }
            }
            .navigationDestination(item: $editing) { post in
                ComposeView(post: post) { reloadSoon() }
            }
            .onAppear {
                // `--open analytics|compose` — 목/스크린샷 검증용 자동 진입.
                switch Config.consumeLaunchValue(after: "--open") {
                case "analytics": showAnalytics = true
                case "compose": composing = true
                default: break
                }
            }
        }
        .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactorHint) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("내 계정 탭에서 로그인을 완료해 주세요.")
        }
    }

    // MARK: 내 글 목록

    private var hub: some View {
        ReadingColumn(spacing: 0) {
            switch phase {
            case .idle, .loading:
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .failed(let message):
                ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                       description: Text(message))
                    .padding(.top, 60)
            case .loaded(let posts):
                if posts.isEmpty {
                    emptyState
                } else {
                    list(posts)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func list(_ posts: [MyPost]) -> some View {
        RailHeading("내 글")
            .padding(.top, 24)
            .padding(.bottom, 6)
        Hairline()
        ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
            Button {
                editing = post
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let date = post.publishedAt ?? post.updatedAt {
                            Text(date.relativeShort)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer()
                    if post.isDraft {
                        Text("임시저장")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.chipBg, in: Capsule())
                    } else if post.isScheduled {
                        Text("예약됨")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.link)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.chipBg, in: Capsule())
                    }
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            if index < posts.count - 1 { Hairline() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailHeading("내 글")
                .padding(.top, 24)
            Text("아직 글이 없습니다. 오른쪽 위 버튼으로 첫 글을 시작하세요.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
        }
    }

    private func load() async {
        if case .idle = phase { phase = .loading }
        do {
            phase = .loaded(try await WriteAPI.myPosts())
        } catch {
            // 보이던 목록을 에러 화면으로 대체하지 않는다 — 비었을 때만 실패 표시.
            if case .loaded(let posts) = phase, !posts.isEmpty { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func reloadSoon() {
        Task { await load() }
    }

    // MARK: 로그인 게이트

    private var signedOutGate: some View {
        ReadingColumn(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                RailHeading("글쓰기")
                    .padding(.top, 28)
                Text("로그인하고 글을 쓰세요")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 12)
                Text("마크다운으로 쓰면 웹과 똑같이 발행됩니다.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 6)
                // Apple 버튼은 시스템 소유 모양(브랜딩 규정) — 유리 없이 캡슐만 맞춘다.
                SignInWithAppleButton(.continue) { request in
                    appleNonce = AuthStore.prepareAppleRequest(request)
                } onCompletion: { result in
                    finishApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .clipShape(Capsule())
                .padding(.top, 22)

                Button {
                    signInHere()
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn { ProgressView().tint(.white) }
                        Text("Google로 계속하기")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(GlassTokens.prominentTint).interactive(), in: .capsule)
                .disabled(isSigningIn)
                .padding(.top, 10)
            }
        }
    }

    private func signInHere() {
        guard !isSigningIn else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            if (try? await auth.signIn()) == .twoFactorRequired {
                showTwoFactorHint = true
            }
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) {
        Task {
            if (try? await auth.completeApple(result, rawNonce: appleNonce)) == .twoFactorRequired {
                showTwoFactorHint = true
            }
        }
    }
}
