//
//  EngagementBar.swift
//  kurl
//

import SwiftUI

/// 글 상세의 좋아요·북마크 줄 — 헤더 바로 아래 한 줄, 조용한 고스트 아이콘.
/// 토글은 낙관(즉시 반영 → 실패 시 서버 응답/원상태로 복귀), 활성 색은 그린 한 가닥.
/// 로그아웃 상태에서 누르면 그 자리에서 로그인 시트를 띄운다 — 글을 떠나지 않는다.
struct EngagementBar: View {
    @State private var model: EngagementModel
    @State private var showLoginPrompt = false
    @State private var showTwoFactorHint = false

    init(postId: Int64, initialLikeCount: Int64) {
        _model = State(initialValue: EngagementModel(postId: postId, likeCount: initialLikeCount))
    }

    var body: some View {
        HStack(spacing: 18) {
            Button {
                interact { try await model.toggleLike() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.liked ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .symbolEffect(.bounce, value: model.liked)
                    if model.likeCount > 0 {
                        Text("\(model.likeCount)")
                            .font(.system(size: 14, weight: .medium))
                            .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(model.liked ? Palette.accent : Palette.secondary)
            }
            .buttonStyle(.plain)
            .animation(.snappy(duration: 0.2), value: model.liked)
            .animation(.snappy(duration: 0.2), value: model.likeCount)

            Button {
                interact { try await model.toggleBookmark() }
            } label: {
                Image(systemName: model.bookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15))
                    .symbolEffect(.bounce, value: model.bookmarked)
                    .foregroundStyle(model.bookmarked ? Palette.accent : Palette.secondary)
            }
            .buttonStyle(.plain)
            .animation(.snappy(duration: 0.2), value: model.bookmarked)

            Spacer()
        }
        .padding(.vertical, 10)
        .sensoryFeedback(.impact(weight: .light), trigger: model.liked)
        .sensoryFeedback(.impact(weight: .light), trigger: model.bookmarked)
        .task { await model.hydrate() }
        .alert("로그인이 필요합니다", isPresented: $showLoginPrompt) {
            Button("로그인") { signInHere() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("좋아요와 북마크는 kurl 계정으로 이어집니다.")
        }
        .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactorHint) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("내 계정 탭에서 로그인을 완료해 주세요.")
        }
    }

    private func interact(_ action: @escaping () async throws -> Void) {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        Task { try? await action() }
    }

    private func signInHere() {
        Task {
            // 2FA 계정은 TOTP 입력 UI 가 계정 탭에 있어 여기서 끝까지 못 간다 — 안내만.
            if (try? await AuthStore.shared.signIn()) == .twoFactorRequired {
                showTwoFactorHint = true
            } else if AuthStore.shared.isSignedIn {
                await model.hydrate()
            }
        }
    }
}

@MainActor
@Observable
final class EngagementModel {
    private(set) var liked = false
    private(set) var likeCount: Int64
    private(set) var bookmarked = false

    private let postId: Int64

    init(postId: Int64, likeCount: Int64) {
        self.postId = postId
        self.likeCount = likeCount
    }

    /// 로그인 상태일 때만 내 상태(liked/bookmarked)를 서버에서 가져온다.
    func hydrate() async {
        guard AuthStore.shared.isSignedIn else { return }
        if let like = try? await InteractionsAPI.likeStatus(postId: postId) {
            liked = like.liked
            likeCount = like.likeCount
        }
        if let bookmark = try? await InteractionsAPI.bookmarkStatus(postId: postId) {
            bookmarked = bookmark.bookmarked
        }
    }

    func toggleLike() async throws {
        let target = !liked
        liked = target
        likeCount += target ? 1 : -1
        do {
            let status = try await InteractionsAPI.setLike(postId: postId, on: target)
            liked = status.liked
            likeCount = status.likeCount
        } catch {
            liked = !target
            likeCount += target ? -1 : 1
            throw error
        }
    }

    func toggleBookmark() async throws {
        let target = !bookmarked
        bookmarked = target
        do {
            bookmarked = try await InteractionsAPI.setBookmark(postId: postId, on: target).bookmarked
        } catch {
            bookmarked = !target
            throw error
        }
    }
}
