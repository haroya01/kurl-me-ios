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

    /// 파일 쓰기·삭제·본문 재디코드·스냅샷 재빌드는 전부 이 직렬 큐를 탄다 — 북마크 글 열람마다
    /// 도는 경로라 메인에서 돌면 히치. 직렬 FIFO 라 "저장 → 스냅샷 → 삭제"가 접수 순서대로
    /// 디스크에 닿는 것까지 보장한다(cachedKeys 만 메인에서 즉시 갱신해 저장됨 점은 바로 켠다).
    private let ioQueue = DispatchQueue(label: "focustime.kurl.offline-io", qos: .utility)

    /// reconcile 처럼 사본을 여러 번 바꾸는 경로에선 위젯 스냅샷 갱신을 잠깐 미루고 끝에 한 번만.
    private var widgetSyncSuspended = false

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
        // 열어 봤다 = 최근 사용 — LRU 의 시계를 감는다(속성 쓰기는 메인 밖에서).
        ioQueue.async {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: url.path)
        }
        return data
    }

    /// 서버 응답 원문 저장 — 상세 화면이 이미 가진 바이트를 재사용하는 경로(추가 네트워크 0).
    func save(raw: Data, username: String, slug: String) {
        cachedKeys.insert("\(username)/\(slug)")
        let url = fileURL(username: username, slug: slug)
        let keys = cachedKeys
        let directory = self.directory
        let needsEviction = cachedKeys.count > Self.capacity
        let syncsWidget = !widgetSyncSuspended
        ioQueue.async {
            try? raw.write(to: url, options: .atomic)
            Self.prefetchImages(from: raw)
            var liveKeys = keys
            if needsEviction {
                let evicted = Self.evictOldest(in: directory)
                if !evicted.isEmpty {
                    liveKeys.subtract(evicted)
                    Task { @MainActor in self.cachedKeys.subtract(evicted) }
                }
            }
            if syncsWidget {
                Self.rebuildWidgetSnapshot(keys: liveKeys, directory: directory)
            }
        }
    }

    func remove(username: String, slug: String) {
        cachedKeys.remove("\(username)/\(slug)")
        let url = fileURL(username: username, slug: slug)
        let keys = cachedKeys
        let directory = self.directory
        let syncsWidget = !widgetSyncSuspended
        ioQueue.async {
            try? FileManager.default.removeItem(at: url)
            if syncsWidget {
                Self.rebuildWidgetSnapshot(keys: keys, directory: directory)
            }
        }
    }

    /// 로그아웃 시 전부 폐기 — 다른 계정이 이 기기의 오프라인 사본을 열지 못하게(프라이버시).
    func removeAll() {
        cachedKeys = []
        let directory = self.directory
        ioQueue.async {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in files { try? FileManager.default.removeItem(at: url) }
            // 로그아웃 = 위젯의 서재도 비운다(다른 계정이 이 기기 홈 화면에서 제목을 못 보게).
            // 큐 뒤에서 지워야 직전에 줄 서 있던 저장의 스냅샷 재빌드가 서재를 되살리지 못한다.
            LibrarySnapshot.clear()
        }
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
        // 여러 사본을 지우고 받는 동안엔 위젯 스냅샷을 미뤘다가(중간 상태 안 새기고) 끝에 한 번.
        widgetSyncSuspended = true
        defer {
            widgetSyncSuspended = false
            syncWidgetSnapshot()
        }
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

    /// 위젯 "서재" 스냅샷을 다시 쓴다 — 오프라인 사본에서 제목·작가만 꺼내 App Group 에 남긴다.
    /// IO 큐 뒤에 줄 세워, 앞서 접수된 쓰기·삭제가 디스크에 닿은 다음의 모습을 찍는다.
    private func syncWidgetSnapshot() {
        guard !widgetSyncSuspended else { return }
        let keys = cachedKeys
        let directory = self.directory
        ioQueue.async {
            Self.rebuildWidgetSnapshot(keys: keys, directory: directory)
        }
    }

    /// 파일 IO·디코드는 메인 밖에서(사본이 120개까지라 열람 hitch 방지), 최근 저장 순으로 정렬.
    private nonisolated static func rebuildWidgetSnapshot(keys: Set<String>, directory: URL) {
        let items: [LibrarySnapshot.Item] = keys.compactMap { key -> LibrarySnapshot.Item? in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let url = directory.appendingPathComponent("\(parts[0])__\(parts[1]).json")
            // 블록·날짜를 건드리지 않는 최소 디코딩 — 서버 날짜 포맷과 무관하고 큰 본문을 통째로 안 판다.
            guard let data = try? Data(contentsOf: url),
                  let probe = try? JSONDecoder().decode(LibraryCardProbe.self, from: data)
            else { return nil }
            let savedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return LibrarySnapshot.Item(
                username: probe.author.username,
                title: probe.post.title,
                slug: probe.post.slug,
                savedAt: savedAt)
        }
        .sorted { $0.savedAt > $1.savedAt }
        LibrarySnapshot.save(items: items, totalCount: keys.count)
    }

    /// 오프라인 사본에서 위젯에 필요한 것만 꺼내는 최소 디코딩(블록·날짜 무시).
    private struct LibraryCardProbe: Decodable {
        struct Author: Decodable { let username: String }
        struct Post: Decodable { let title: String; let slug: String }
        let author: Author
        let post: Post
    }

    private func fileURL(username: String, slug: String) -> URL {
        directory.appendingPathComponent("\(username)__\(slug).json")
    }

    /// 디스크 상한 초과분을 mtime LRU 로 걷는다 — IO 큐 전용. 개수는 디렉토리 실물 기준이라
    /// cachedKeys 반영이 반 박자 늦어도 스스로 맞고, 걷은 키를 돌려준다.
    private nonisolated static func evictOldest(in directory: URL) -> Set<String> {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
            files.count > capacity
        else { return [] }
        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return l < r
        }
        var evicted: Set<String> = []
        for url in sorted.prefix(files.count - capacity) {
            try? FileManager.default.removeItem(at: url)
            let name = url.deletingPathExtension().lastPathComponent
            evicted.insert(name.replacingOccurrences(of: "__", with: "/"))
        }
        return evicted
    }

    /// 커버·본문 이미지 요청을 한 번씩 흘려 URLCache 를 덥힌다 — AsyncImage 가 shared
    /// 세션을 타므로 오프라인에서 캐시 적중하면 그림도 산다(미적중은 플레이스홀더).
    /// 상세 화면이 이미 디코드한 바이트를 또 푸는 경로라 IO 큐 전용(메인에서 부르지 말 것).
    private nonisolated static func prefetchImages(from raw: Data) {
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
