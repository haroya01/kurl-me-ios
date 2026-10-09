//
//  DraftFlusher.swift
//  kurl
//

import Foundation

/// 편집 화면을 떠나는 순간의 마지막 저장(플러시)을 뷰 수명과 분리해 수행한다.
///
/// ComposeView 는 값 타입 뷰라 뒤로 가기·팝으로 사라지면 그 안에서 띄운
/// `Task { await save(silent:) }` 는 죽어가는 @State 위에서 돌아, 저장이 실패해도
/// 실패 배지·토스트를 띄우지 못한 채 변경이 조용히 사라졌다(초안 자체가 안 만들어지면 전량 유실).
///
/// 이 플러셔는 루트에 사는 싱글턴이라 뷰가 사라져도 살아서 저장을 끝까지 밀고,
/// 실패하면 루트 토스트(ToastHost)로 사용자에게 반드시 알린다 — 조용한 유실 종식.
@MainActor
@Observable
final class DraftFlusher {
    static let shared = DraftFlusher()

    /// 플러시가 서버에 반영을 끝낼 때마다 올라가는 틱 — 스튜디오가 이 값을 관찰해
    /// (뷰 밖에서 만들어진 초안이 목록에 나타나도록) 목록을 새로고침한다.
    private(set) var completedTick = 0

    /// 떠나는 편집에서 넘겨받는, 저장에 필요한 값 스냅샷(뷰 상태 참조 없음).
    struct Payload {
        var postId: Int64?
        /// 새 글의 기기 금고 슬롯 키 — 초안이 생기면 이 슬롯을 id 슬롯으로 승격한다.
        var draftKey: UUID
        var title: String
        var markdown: String
        /// 서버에 이미 반영된 값 — 바뀐 필드만 PATCH 하기 위한 비교 기준.
        var savedTitle: String
        var savedExcerpt: String
        var savedTags: [String]
        var excerpt: String
        var tags: [String]
        var savedSeriesId: Int64?
        var seriesId: Int64?
        /// 편집 화면의 버전 게이트 — 화면에서 가던 쓰기 뒤에 줄 서고, 그 쓰기가 받은 버전을 base 로 쓴다.
        var gate = PostVersionGate()
    }

    /// 차례를 기다리거나 서버로 가는 중인 플러시 — 맨 앞이 지금 보내는 것.
    private var queue: [Payload] = []
    private let perform: @MainActor (inout Payload) async throws -> Void

    init(perform: @escaping @MainActor (inout Payload) async throws -> Void = DraftFlusher.saveToServer) {
        self.perform = perform
    }

    /// 아직 서버에 닿지 않은 새 글의 금고 키 — 새 글 화면이 이 슬롯을 복구 대상으로 오인하지 않게.
    var pendingDraftKeys: Set<UUID> { Set(queue.map(\.draftKey)) }

    /// 편집을 떠날 때 호출 — 넘겨받은 스냅샷으로 저장을 끝까지 수행한다. 앞 플러시가 가는 중이면
    /// 버리지 않고 뒤에 세운다. 성공하면 조용히, 실패하면 루트 토스트로 알리고 '다시 시도'로 재플러시할 수 있게 한다.
    func flush(_ payload: Payload) {
        queue.append(payload)
        guard queue.count == 1 else { return }
        Task { await drain() }
    }

    private func drain() async {
        while var payload = queue.first {
            do {
                try await perform(&payload)
                // 서버에 실렸다 — 기기 금고 슬롯을 비운다(초안을 만들었으면 승격된 id 슬롯).
                ComposeRecoveryStore.clear(postId: payload.postId, draftKey: payload.draftKey)
                // 저장이 끝났음을 알려 스튜디오가 목록을 다시 읽게 한다(뷰 밖 생성분 반영).
                completedTick &+= 1
            } catch is PostEditConflict {
                // 다른 기기가 먼저 고쳤다 — 덮지 않는다. 내 내용은 기기 금고 슬롯에 남아 다시 열면 이어 쓸 수 있다.
                ToastCenter.shared.show(
                    String(localized: "다른 기기에서 이 글을 고쳐서 저장하지 않았어요 — 다시 열면 내가 쓴 내용을 이어 쓸 수 있어요"))
            } catch {
                // 화면은 이미 사라졌다 — 루트에 살아있는 토스트로 반드시 알린다(조용한 유실 금지).
                // '다시 시도'는 이미 만든 초안 id 를 든 스냅샷으로 재플러시한다(초안 중복 생성 방지).
                // 원인이 인증이면 "네트워크 확인" 은 거짓 처방 — 다시 로그인을 말한다.
                let retry = payload
                ToastCenter.shared.show(
                    Self.isAuthFailure(error)
                        ? String(localized: "로그인이 풀려 저장하지 못했어요 — 다시 로그인한 뒤 시도해 주세요")
                        : String(localized: "저장하지 못했어요 — 네트워크를 확인하고 다시 시도해 주세요"),
                    actionLabel: String(localized: "다시 시도")
                ) { [weak self] in
                    self?.flush(retry)
                }
            }
            queue.removeFirst()
        }
    }

    /// 저장 실패가 인증(401·세션 만료) 때문인가 — 컴포즈의 저장 배지와 이 플러시 토스트가 같은 판정을 쓴다.
    static func isAuthFailure(_ error: Error) -> Bool {
        if let api = error as? APIError, api.statusCode == 401 { return true }
        if case AuthError.notSignedIn = error { return true }
        return false
    }

    /// 저장 본체 — save(silent:) 의 성공 경로와 같은 순서(초안 생성 → 본문 교체 → 바뀐 메타 PATCH → 시리즈).
    static func saveToServer(_ p: inout Payload) async throws {
        let id: Int64
        if let existing = p.postId {
            id = existing
        } else {
            let created = try await WriteAPI.createDraft(title: p.title.trimmingCharacters(in: .whitespaces))
            id = created.id
            p.postId = id
            p.gate.adopt(created.contentVersion)
            ComposeRecoveryStore.promote(p.draftKey, to: id)
        }
        let newTitle = p.title.trimmingCharacters(in: .whitespaces)
        _ = try await PostSave.send(
            postId: id, markdown: p.markdown,
            metadata: .init(
                title: newTitle != p.savedTitle ? newTitle : nil,
                excerpt: p.excerpt != p.savedExcerpt ? p.excerpt : nil,
                tags: p.tags != p.savedTags ? p.tags : nil),
            gate: p.gate)
        if p.seriesId != p.savedSeriesId {
            try await WriteAPI.assign(postId: id, from: p.savedSeriesId, to: p.seriesId)
        }
    }
}
