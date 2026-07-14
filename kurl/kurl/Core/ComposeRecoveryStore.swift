//
//  ComposeRecoveryStore.swift
//  kurl
//
//  기기 로컬 초안 금고 — 자동저장이 못 미더운 순간(서버 실패·세션 만료·강제 종료·크래시)에도
//  쓰던 본문이 기기에 남는다. 서버 저장이 성공하면 그 슬롯을 지운다(서버가 진실원 — 금고는
//  "서버에 못 실린 변경"만 든다). 글 하나당 한 슬롯(JSON 파일), 새 글은 초안 id 를 얻는 순간
//  new 슬롯을 그 id 로 승격해 이어진다.
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

    private static func fileURL(for postId: Int64?) -> URL {
        directory.appendingPathComponent(postId.map { "post-\($0).json" } ?? "new.json")
    }

    /// 지금 편집 중인 내용을 슬롯에 눕힌다 — 호출측이 디바운스한다(키 입력마다 쓰지 않게).
    static func stash(postId: Int64?, title: String, markdown: String) {
        let draft = Draft(postId: postId, title: title, markdown: markdown, savedAt: Date())
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: postId), options: .atomic)
    }

    /// 슬롯 내용(있으면) — 복구 제안의 재료.
    static func peek(postId: Int64?) -> Draft? {
        guard let data = try? Data(contentsOf: fileURL(for: postId)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    /// 서버 저장 성공 — 금고는 "못 실린 변경"만 들므로 슬롯을 비운다.
    static func clear(postId: Int64?) {
        try? FileManager.default.removeItem(at: fileURL(for: postId))
    }

    /// 새 글이 초안 id 를 얻는 순간 — new 슬롯을 그 id 로 승격(중간에 죽어도 이어지게).
    static func promote(to postId: Int64) {
        guard var draft = peek(postId: nil) else { return }
        draft.postId = postId
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: fileURL(for: postId), options: .atomic)
        }
        clear(postId: nil)
    }
}
