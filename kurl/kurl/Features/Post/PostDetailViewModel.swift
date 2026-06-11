//
//  PostDetailViewModel.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class PostDetailViewModel {
    let username: String
    let slug: String

    private(set) var phase: LoadState<PublicPostDetail> = .idle
    private(set) var comments: [Comment] = []
    /// 보는 사람이 좋아요한 댓글 id — 공개 목록과 별도의 인증 엔드포인트로 hydrate(#538 패턴).
    private(set) var likedCommentIds: Set<Int64> = []
    /// 낙관 카운트 보정(댓글 id → 증감) — 서버 likeCount 는 공개 목록 재로드 때만 갱신되므로.
    private(set) var commentLikeDelta: [Int64: Int64] = [:]
    /// 댓글별 토글 세대 — 비행 중 재로드/연타의 스테일 echo 를 버린다.
    private var commentToggleGen: [Int64: Int] = [:]

    init(username: String, slug: String) {
        self.username = username
        self.slug = slug
    }

    func load() async {
        // 재시도 가능해야 한다 — loaded/loading 만 막고 idle/failed 에선 진입.
        if case .loaded = phase { return }
        if case .loading = phase { return }
        phase = .loading
        do {
            let detail = try await BlogAPI.postDetail(username: username, slug: slug)
            phase = .loaded(detail)
            await BlogAPI.recordView(username: username, slug: slug)
            await loadComments(postId: detail.post.id)
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func loadComments(postId: Int64) async {
        comments = (try? await BlogAPI.comments(postId: postId)) ?? []
        commentLikeDelta = [:]
        commentToggleGen = [:]
        if AuthStore.shared.isSignedIn {
            likedCommentIds = Set((try? await InteractionsAPI.likedCommentIds(postId: postId)) ?? [])
        }
    }

    func displayLikeCount(_ comment: Comment) -> Int64 {
        max(0, (comment.likeCount ?? 0) + (commentLikeDelta[comment.id] ?? 0))
    }

    func toggleCommentLike(_ comment: Comment) async {
        let gen = (commentToggleGen[comment.id] ?? 0) + 1
        commentToggleGen[comment.id] = gen
        let on = !likedCommentIds.contains(comment.id)
        // 낙관 반영
        if on { likedCommentIds.insert(comment.id) } else { likedCommentIds.remove(comment.id) }
        commentLikeDelta[comment.id, default: 0] += on ? 1 : -1
        do {
            let status = try await InteractionsAPI.setCommentLike(commentId: comment.id, on: on)
            guard gen == commentToggleGen[comment.id] else { return }
            // delta 기준은 "현재 배열의 likeCount" — 비행 중 목록이 갈렸어도 이중 반영되지 않게.
            let base = comments.first(where: { $0.id == comment.id })?.likeCount ?? comment.likeCount ?? 0
            commentLikeDelta[comment.id] = status.likeCount - base
            if status.liked { likedCommentIds.insert(comment.id) } else { likedCommentIds.remove(comment.id) }
        } catch {
            guard gen == commentToggleGen[comment.id] else { return }
            if on { likedCommentIds.remove(comment.id) } else { likedCommentIds.insert(comment.id) }
            commentLikeDelta[comment.id, default: 0] += on ? -1 : 1
            ToastCenter.shared.show(String(localized: "좋아요를 반영하지 못했습니다"))
        }
    }

    func deleteComment(_ comment: Comment) async throws {
        try await InteractionsAPI.deleteComment(commentId: comment.id)
        comments.removeAll { $0.id == comment.id || $0.parentId == comment.id }
    }

    /// 댓글 작성 → 공개 목록 재로드(생성 응답 형태에 의존하지 않는다).
    func postComment(body: String, parentId: Int64? = nil) async throws {
        guard case .loaded(let detail) = phase else { return }
        try await InteractionsAPI.createComment(postId: detail.post.id, body: body, parentId: parentId)
        await loadComments(postId: detail.post.id)
    }
}
