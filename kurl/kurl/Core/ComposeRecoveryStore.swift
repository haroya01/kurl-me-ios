//
//  ComposeRecoveryStore.swift
//  kurl
//
//  기기 로컬 초안 금고 — 자동저장이 못 미더운 순간(서버 실패·세션 만료·강제 종료·크래시)에도
//  쓰던 본문이 기기에 남는다. 서버 저장이 성공하면 그 슬롯을 지운다(서버가 진실원 — 금고는
//  "서버에 못 실린 변경"만 든다). 글 하나당 한 슬롯(JSON 파일), 새 글은 편집 세션마다 고유 키 슬롯을
//  쓰다가 초안 id 를 얻는 순간 그 id 슬롯으로 승격해 이어진다.
//

import Foundation

@MainActor
enum ComposeRecoveryStore {
    struct Draft: Codable, Equatable {
        var postId: Int64?
        var title: String
        var markdown: String
        var savedAt: Date
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ComposeRecovery", isDirectory: true)
    }

    private static let newPrefix = "new-"

    private static func fileURL(for postId: Int64?, draftKey: UUID) -> URL {
        directory.appendingPathComponent(postId.map { "post-\($0).json" } ?? "\(newPrefix)\(draftKey.uuidString).json")
    }

    /// 지금 편집 중인 내용을 슬롯에 눕힌다 — 호출측이 디바운스한다(키 입력마다 쓰지 않게).
    static func stash(postId: Int64?, draftKey: UUID, title: String, markdown: String) {
        let draft = Draft(postId: postId, title: title, markdown: markdown, savedAt: Date())
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: postId, draftKey: draftKey), options: .atomic)
    }

    /// 슬롯 내용(있으면) — 복구 제안의 재료.
    static func peek(postId: Int64?, draftKey: UUID) -> Draft? {
        read(fileURL(for: postId, draftKey: draftKey))
    }

    private static func read(_ url: URL) -> Draft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    /// 서버 저장 성공 — 금고는 "못 실린 변경"만 들므로 슬롯을 비운다.
    static func clear(postId: Int64?, draftKey: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: postId, draftKey: draftKey))
    }

    /// 다른 기기 편집과 충돌해 서버 최신본을 불러올 때 밀려난 내 내용 — 이후 편집이 덮는 글 슬롯과 따로 둔다.
    private static func conflictURL(_ postId: Int64) -> URL {
        directory.appendingPathComponent("conflict-post-\(postId).json")
    }

    static func stashConflict(postId: Int64, title: String, markdown: String) {
        let draft = Draft(postId: postId, title: title, markdown: markdown, savedAt: Date())
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: conflictURL(postId), options: .atomic)
    }

    static func peekConflict(postId: Int64) -> Draft? {
        read(conflictURL(postId))
    }

    static func clearConflict(postId: Int64) {
        try? FileManager.default.removeItem(at: conflictURL(postId))
    }

    /// 새 글을 열 때 복구를 제안할 슬롯 — 아직 서버로 가는 중인(claimed) 새 글은 빼고 가장 최근 것.
    static func latestNewDraft(excluding claimed: Set<UUID>) -> (key: UUID, draft: Draft)? {
        let fm = FileManager.default
        let legacy = directory.appendingPathComponent("new.json")
        if fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: fileURL(for: nil, draftKey: UUID()))
        }
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .compactMap { name -> (key: UUID, draft: Draft)? in
                guard name.hasPrefix(newPrefix), name.hasSuffix(".json"),
                      let key = UUID(uuidString: String(name.dropFirst(newPrefix.count).dropLast(5))),
                      !claimed.contains(key),
                      let draft = read(directory.appendingPathComponent(name))
                else { return nil }
                return (key, draft)
            }
            .max { $0.draft.savedAt < $1.draft.savedAt }
    }

    /// 금고 전체를 비운다 — 슬롯이 파일이라 앱 재실행·다른 UITest 사이에도 남는다. 컴포즈 계열
    /// UITest 가 앞선 테스트의 잔여 슬롯(→ 복구 다이얼로그)에 오염되지 않게 setUp 에서 초기화하는 용도
    /// (`--reset-recovery`). 운영엔 호출부가 없다.
    static func wipeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 새 글이 초안 id 를 얻는 순간 — 그 글의 새 글 슬롯을 id 슬롯으로 승격(중간에 죽어도 이어지게).
    static func promote(_ draftKey: UUID, to postId: Int64) {
        guard var draft = peek(postId: nil, draftKey: draftKey) else { return }
        draft.postId = postId
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: fileURL(for: postId, draftKey: draftKey), options: .atomic)
        }
        clear(postId: nil, draftKey: draftKey)
    }
}
