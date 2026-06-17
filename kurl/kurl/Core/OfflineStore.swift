//
//  OfflineStore.swift
//  kurl
//

import Foundation
import Observation

/// 오프라인 읽기 저장소 — "북마크 = 기기에 보장"의 단일 소유자.
/// 본문은 서버 응답 원문(JSON)을 그대로 보관해 온라인과 같은 디코더·렌더러 경로를 탄다.
/// 이미지는 URLCache 베스트에포트(저장 시 프리페치로 덥혀 둠) — 글은 확정, 그림은 최선.
@MainActor
@Observable
final class OfflineStore {
    static let shared = OfflineStore()

    /// "username/slug" — 서재 행의 저장됨 점은 이 집합 하나로 그린다.
    private(set) var cachedKeys: Set<String> = []

    /// 디스크 상한 — 넘치면 오래 안 연 사본부터(mtime LRU) 걷는다.
    private static let capacity = 120

    private let directory: URL

    private init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("offline-posts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        cachedKeys = Set(
            files.filter { $0.hasSuffix(".json") }
                .map { String($0.dropLast(5)).replacingOccurrences(of: "__", with: "/") })
    }

    func contains(username: String, slug: String) -> Bool {
        cachedKeys.contains("\(username)/\(slug)")
    }

    func data(username: String, slug: String) -> Data? {
        let url = fileURL(username: username, slug: slug)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 열어 봤다 = 최근 사용 — LRU 의 시계를 감는다.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// 서버 응답 원문 저장 — 상세 화면이 이미 가진 바이트를 재사용하는 경로(추가 네트워크 0).
    func save(raw: Data, username: String, slug: String) {
        try? raw.write(to: fileURL(username: username, slug: slug), options: .atomic)
        cachedKeys.insert("\(username)/\(slug)")
        prefetchImages(from: raw)
        evictIfNeeded()
    }

    func remove(username: String, slug: String) {
        try? FileManager.default.removeItem(at: fileURL(username: username, slug: slug))
        cachedKeys.remove("\(username)/\(slug)")
    }

    /// 로그아웃 시 전부 폐기 — 다른 계정이 이 기기의 오프라인 사본을 열지 못하게(프라이버시).
    func removeAll() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files { try? FileManager.default.removeItem(at: url) }
        cachedKeys = []
    }

    /// 없으면 받아서 저장 — 카드 컨텍스트 메뉴·구독함 프리페치·서재 reconcile 의 공용 경로.
    func download(username: String, slug: String) async {
        guard !contains(username: username, slug: slug) else { return }
        guard let raw = try? await BlogAPI.postDetailData(username: username, slug: slug) else {
            return
        }
        save(raw: raw, username: username, slug: slug)
    }

    /// 서재 동기화 — 서버 북마크 목록이 진실. 빠진 사본은 받고, 풀린 북마크의 사본은 지운다.
    /// (웹에서 북마크한 글도 앱을 열면 기기로 따라온다.)
    func reconcile(bookmarks: [(username: String, slug: String)]) async {
        let wanted = Set(bookmarks.map { "\($0.username)/\($0.slug)" })
        for key in cachedKeys.subtracting(wanted) {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 { remove(username: parts[0], slug: parts[1]) }
        }
        for bookmark in bookmarks.prefix(50) {
            await download(username: bookmark.username, slug: bookmark.slug)
        }
    }

    // MARK: 내부

    private func fileURL(username: String, slug: String) -> URL {
        directory.appendingPathComponent("\(username)__\(slug).json")
    }

    private func evictIfNeeded() {
        guard cachedKeys.count > Self.capacity,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return l < r
        }
        for url in sorted.prefix(max(0, cachedKeys.count - Self.capacity)) {
            try? FileManager.default.removeItem(at: url)
            let name = url.deletingPathExtension().lastPathComponent
            cachedKeys.remove(name.replacingOccurrences(of: "__", with: "/"))
        }
    }

    /// 커버·본문 이미지 요청을 한 번씩 흘려 URLCache 를 덥힌다 — AsyncImage 가 shared
    /// 세션을 타므로 오프라인에서 캐시 적중하면 그림도 산다(미적중은 플레이스홀더).
    private func prefetchImages(from raw: Data) {
        guard let detail = try? JSONDecoder.blog.decode(PublicPostDetail.self, from: raw) else {
            return
        }
        var urls: [URL] = []
        if let cover = detail.post.ogImageUrl, let url = URL(string: cover) { urls.append(url) }
        for block in detail.blocks where block.kind == .image {
            // IMAGE content = {"url":...,"caption":...} 또는 맨 URL 문자열(BlockRenderer 와 동일 규칙).
            guard let content = block.content else { continue }
            let urlString: String
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                urlString = json["url"] as? String ?? ""
            } else {
                urlString = content
            }
            if let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in urls {
                _ = try? await URLSession.shared.data(from: url)
            }
        }
    }
}

#if DEBUG
/// `--seed-offline` — 네트워크 없이도 오프라인 폴백을 결정적으로 검증하기 위한 픽스처 주입.
enum OfflineSeed {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--seed-offline") else { return }
        let fixture = """
            {"author":{"id":1,"username":"offline-fixture","bio":null,"avatarUrl":null},
             "post":{"id":424242,"slug":"offline-post","title":"오프라인 사본 검증 글","excerpt":null,
                     "ogImageUrl":null,"languageTag":"ko","tags":[],"likeCount":0,
                     "publishedAt":"2026-06-01T00:00:00Z","lastEditedAt":null,"pinned":false},
             "blocks":[{"type":"PARAGRAPH","content":"비행기 모드에서도 이 본문이 보이면 성공.","blockOrder":1}],
             "series":null}
            """
        OfflineStore.shared.save(
            raw: Data(fixture.utf8), username: "offline-fixture", slug: "offline-post")
    }
}
#endif
