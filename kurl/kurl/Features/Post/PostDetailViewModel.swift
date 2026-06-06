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

    init(username: String, slug: String) {
        self.username = username
        self.slug = slug
    }

    func load() async {
        guard case .idle = phase else { return }
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
    }
}
