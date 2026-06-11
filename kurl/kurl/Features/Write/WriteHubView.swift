//
//  WriteHubView.swift
//  kurl
//

import SwiftUI

/// 글쓰기 탭 — 웹 /write 허브의 축소판: 내 글 목록(임시저장/발행 상태) + 새 글.
/// 로그아웃 상태는 이 표면 전체가 로그인 게이트.
struct WriteHubView: View {
    private var auth: AuthStore { .shared }

    @State private var phase: LoadState<[MyPost]> = .idle
    @State private var composing = false
    @State private var editing: MyPost?
    @State private var isSigningIn = false
    @State private var showTwoFactorHint = false

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
                        NavigationLink {
                            AnalyticsView()
                        } label: {
                            Image(systemName: "chart.bar")
                        }
                        .tint(.brand)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            composing = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .tint(.brand)
                    }
                }
            }
            .navigationDestination(isPresented: $composing) {
                ComposeView(post: nil) { reloadSoon() }
            }
            .navigationDestination(item: $editing) { post in
                ComposeView(post: post) { reloadSoon() }
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
                    .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .padding(.top, 22)
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
}
