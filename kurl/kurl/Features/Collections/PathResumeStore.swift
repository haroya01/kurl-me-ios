//
//  PathResumeStore.swift
//  kurl
//
//  길(PATH)을 "목록"이 아니라 "이어서 읽어 내려가는 것"으로 만드는 기기 로컬 이어읽기 기억.
//  연결 응답엔 postId 가 없어(username/slug 만) PostReadStore(postId 키)를 그대로 쓸 수 없다 —
//  그래서 길 단위로 "어디까지 걸었나"(가장 멀리 도달한 스텝 index)만 기기에 남긴다. 서버 0.
//  PostReadStore 와 같은 결: 메모리가 단일 진실원, UserDefaults 는 영속 사본, 로그아웃 시 reset.
//

import SwiftUI

/// 길별 이어읽기 위치 — key = collectionId, value = 가장 멀리 도달한 스텝 index(0-based).
/// 스텝을 열 때만 앞으로 나아가고 뒤로는 안 간다(한 번 지나온 길은 지나온 것). @Observable 이라
/// 스텝을 읽고 돌아오면 현재 스텝 강조·진행률·연속성 바가 곧바로 갱신된다.
@MainActor
@Observable
final class PathResumeStore {
    static let shared = PathResumeStore()

    private static let key = "pathResumeFurthest"
    // 단일 진실원 = 메모리. UserDefaults 는 쓸 때만 갱신(되읽지 않음).
    private var furthest: [Int64: Int]

    private init() {
        // UserDefaults 는 [String: Int] 로 저장한다(Int64 키를 문자열로) — plist 사전은 문자열 키만.
        let raw = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int]) ?? [:]
        furthest = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in
            Int64(k).map { ($0, v) }
        })
        // 검증용 시드 — 목 모드에서 현재 스텝 강조·연속성 바를 그려보기 위함(`--seed-path 104:1`).
        // PostReadStore 의 `--seed-read` 와 같은 결. 형식은 `컬렉션id:도달스텝index`.
        if Config.useMocks, let seed = Config.launchValue(after: "--seed-path") {
            for pair in seed.split(separator: ",") {
                let kv = pair.split(separator: ":")
                if kv.count == 2, let cid = Int64(kv[0]), let step = Int(kv[1]) {
                    furthest[cid] = step
                }
            }
        }
    }

    /// 이 길에서 가장 멀리 도달한 스텝 index. 아직 아무 데도 안 걸었으면 nil.
    func furthestStep(collectionId: Int64) -> Int? {
        furthest[collectionId]
    }

    /// 스텝을 열었다 — 그 index 까지 걸은 것으로 표시(뒤로는 안 물러난다).
    func advance(collectionId: Int64, toStep index: Int) {
        guard index >= 0 else { return }
        if let cur = furthest[collectionId], cur >= index { return }
        furthest[collectionId] = index
        persist()
    }

    /// 로그아웃 시 — 이어읽기 위치는 기기 로컬이라 계정 전환 시 비운다(이전 사용자 자취 차단).
    func reset() {
        furthest = [:]
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: furthest.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(raw, forKey: Self.key)
    }
}
