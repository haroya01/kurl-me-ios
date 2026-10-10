//
//  PostVersionGate.swift
//  kurl
//

import Foundation

/// 한 글 편집이 아는 서버 내용 버전 — 다음 저장의 baseVersion. 버전을 올리는 쓰기(본문 PUT·메타 PATCH)는
/// 한 줄로 세운다: 자기 요청 둘이 같은 base 로 겹치면 서버가 하나를 409 로 막는다.
/// 버전을 모르면(nil — 옛 서버) baseVersion 없이 보내 지금처럼 덮는다.
@MainActor
final class PostVersionGate {
    private(set) var version: Int64?
    private var tail: Task<Void, Never>?

    init(version: Int64? = nil) {
        self.version = version
    }

    func adopt(_ version: Int64?) {
        if let version { self.version = version }
    }

    /// 앞선 쓰기가 끝난 뒤 그때의 버전을 base 로 보내고, 응답 버전을 다음 base 로 삼는다.
    func write<T: Sendable>(_ send: @escaping @MainActor (_ base: Int64?) async throws -> (T, Int64?)) async throws -> T {
        let previous = tail
        let task = Task { () async throws -> T in
            await previous?.value
            let (value, next) = try await send(self.version)
            self.adopt(next)
            return value
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

/// iOS 저장 순서(서버 계약): 본문 PUT 다음 메타 PATCH, PATCH 의 base 는 PUT 응답 버전.
enum PostSave {
    struct Metadata: Equatable {
        var title: String?
        var excerpt: String?
        var tags: [String]?

        var isEmpty: Bool { title == nil && excerpt == nil && tags == nil }
    }

    /// 성공하면 서버가 정규화한 본문을 돌려준다. overwrite 는 이 저장의 첫 요청(본문 PUT)에만 싣는다 —
    /// 409 를 받은 저장을 덮어 다시 보내는 자리이고, 요청마다 붙이면 서버 리비전이 그만큼 쌓인다.
    /// 본문 PUT 이 409 면 서버 본문을 다시 읽어, 보낸 본문과 같으면 앞선 저장의 응답만 잃은 것이라 성공으로 친다.
    static func send(
        postId: Int64, markdown: String, metadata: Metadata, gate: PostVersionGate, overwrite: Bool = false
    ) async throws -> String {
        let canonical: String = try await gate.write { base in
            do {
                let saved = try await WriteAPI.replaceMarkdown(
                    postId: postId, markdown: markdown, baseVersion: base, overwrite: overwrite)
                return (saved.markdown, saved.contentVersion)
            } catch is PostEditConflict {
                let current = try await WriteAPI.markdown(postId: postId)
                guard sameBody(current.markdown, markdown) else { throw PostEditConflict() }
                return (current.markdown, current.contentVersion)
            }
        }
        if !metadata.isEmpty {
            let _: MyPost = try await gate.write { base in
                let post = try await WriteAPI.updateMetadata(
                    postId: postId, title: metadata.title, excerpt: metadata.excerpt, tags: metadata.tags,
                    baseVersion: base)
                return (post, post.contentVersion)
            }
        }
        return canonical
    }

    static func cover(postId: Int64, url: String, key: String?, chosen: Bool, gate: PostVersionGate) async throws {
        let _: MyPost = try await gate.write { base in
            let post = try await WriteAPI.updateCover(
                postId: postId, url: url, key: key, chosen: chosen, baseVersion: base)
            return (post, post.contentVersion)
        }
    }

    private static func sameBody(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines) == b.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
