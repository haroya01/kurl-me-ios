import SwiftUI

@Observable
nonisolated final class NoteEngagement {
    enum Outcome: Equatable {
        case done
        case signIn
        case failed(String)
    }

    private(set) var liked: Bool
    private(set) var likeCount: Int64?
    private(set) var reposted: Bool
    private(set) var repostCount: Int64?
    @ObservationIgnored private var noteId: Int64
    @ObservationIgnored private let signedIn: @MainActor () -> Bool
    @ObservationIgnored private let like: (Int64, Bool) async throws -> Int64
    @ObservationIgnored private let repost: (Int64, Bool) async throws -> Int64

    init(
        _ note: Note,
        signedIn: @escaping @MainActor () -> Bool = { AuthStore.shared.isSignedIn },
        like: @escaping (Int64, Bool) async throws -> Int64 = { try await NoteAPI.setLike(id: $0, on: $1).likeCount },
        repost: @escaping (Int64, Bool) async throws -> Int64 = {
            try await NoteAPI.setRepost(id: $0, on: $1).repostCount
        }
    ) {
        noteId = note.id
        liked = note.likedByMe == true
        likeCount = note.likeCount
        reposted = note.repostedByMe == true
        repostCount = note.repostCount
        self.signedIn = signedIn
        self.like = like
        self.repost = repost
    }

    @MainActor func sync(_ note: Note) {
        noteId = note.id
        liked = note.likedByMe == true
        likeCount = note.likeCount
        reposted = note.repostedByMe == true
        repostCount = note.repostCount
    }

    @MainActor func toggleLike() async -> Outcome {
        guard signedIn() else { return .signIn }
        let target = !liked
        let previous = likeCount
        withMotion(Motion.micro) {
            liked = target
            likeCount = max((likeCount ?? 0) + (target ? 1 : -1), 0)
        }
        do {
            let count = try await like(noteId, target)
            withMotion(Motion.micro) { likeCount = count }
            return .done
        } catch {
            liked = !target
            likeCount = previous
            return .failed(String(localized: "좋아요를 반영하지 못했어요"))
        }
    }

    @MainActor func toggleRepost() async -> Outcome {
        guard signedIn() else { return .signIn }
        let target = !reposted
        let previous = repostCount
        withMotion(Motion.micro) {
            reposted = target
            repostCount = max((repostCount ?? 0) + (target ? 1 : -1), 0)
        }
        do {
            let count = try await repost(noteId, target)
            withMotion(Motion.micro) { repostCount = count }
            return .done
        } catch {
            reposted = !target
            repostCount = previous
            return .failed(String(localized: "리포스트하지 못했어요"))
        }
    }
}
