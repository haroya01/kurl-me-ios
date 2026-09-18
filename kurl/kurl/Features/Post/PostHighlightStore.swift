//
//  PostHighlightStore.swift
//  kurl
//

import SwiftUI
import UIKit

/// 한 글의 하이라이트 상태 — 공개 하이라이트를 싣고(본문 문단에 칠하기), 선택→생성(+메모)을 받고,
/// 칠해진 하이라이트 탭→답글 스레드를 연다. 본문(BlockView)이 환경에서 읽어 문단별로 칠하고,
/// 미로그인 생성은 로그인 유도로 넘긴다. 본 글(단독 상세)에서만 주입한다.
@MainActor
@Observable
final class PostHighlightStore {
    let postId: Int64
    private(set) var highlights: [HighlightView] = []
    /// 남들 하이라이트가 많으면 본문이 어지럽다 — 켜면 칠하기를 멈춘다(내 형광펜 생성은 그대로).
    /// 뷰(@AppStorage)가 소유하는 설정을 밀어 넣는다 — 페인트만 접고 데이터는 유지한다.
    var paintHidden = false
    /// 미로그인 사용자가 하이라이트를 시도 — 뷰가 로그인 시트를 띄우도록 신호한다.
    var loginPrompt = false
    /// 탭한 하이라이트 — 뷰가 답글 스레드 시트를 띄운다.
    var threadHighlightId: Int64?
    /// 메모와 함께 하이라이트할 선택 구간 — 뷰가 메모 입력 시트를 띄운다.
    var noteDraft: NoteDraft?
    /// 컬렉션에 연결할 하이라이트 — 스레드 시트가 닫힌 뒤 뷰(PostDetailView)가 ConnectSheet 를 띄운다
    /// (시트 위 시트 대신 present-after-dismiss 로 안정).
    var connectTarget: HighlightView?
    /// 스레드 시트가 "연결"을 예약해 두는 슬롯 — 시트의 onDismiss 가 connectTarget 으로 승격한다.
    /// 고정 지연 핸드오프는 첫 해제(콜드 계층)에서 프레젠테이션을 유실했다.
    var pendingConnect: HighlightView?

    @ObservationIgnored private let isSignedIn: @MainActor () -> Bool
    @ObservationIgnored private let createRequest: @MainActor (Int64, NewHighlight) async throws -> HighlightRef
    @ObservationIgnored private let listRequest: @MainActor (Int64) async throws -> [HighlightView]
    @ObservationIgnored private let deleteRequest: @MainActor (Int64) async throws -> Void
    @ObservationIgnored private var nextOptimisticId: Int64 = -1
    @ObservationIgnored private var mutationVersion = 0
    @ObservationIgnored private var pendingDeletes: Set<Int64> = []

    /// 메모 입력 시트를 구동하는 선택 구간.
    struct NoteDraft: Identifiable {
        let blockOrder: Int
        let startOffset: Int
        let endOffset: Int
        let quote: String
        var id: String { "\(blockOrder)-\(startOffset)-\(endOffset)" }
    }

    init(
        postId: Int64,
        isSignedIn: @escaping @MainActor () -> Bool = { AuthStore.shared.isSignedIn },
        createRequest: @escaping @MainActor (Int64, NewHighlight) async throws -> HighlightRef = {
            try await HighlightsAPI.create(postId: $0, $1)
        },
        listRequest: @escaping @MainActor (Int64) async throws -> [HighlightView] = {
            try await HighlightsAPI.list(postId: $0)
        },
        deleteRequest: @escaping @MainActor (Int64) async throws -> Void = {
            try await HighlightsAPI.delete(id: $0)
        }
    ) {
        self.postId = postId
        self.isSignedIn = isSignedIn
        self.createRequest = createRequest
        self.listRequest = listRequest
        self.deleteRequest = deleteRequest
    }

    func load() async {
        let version = mutationVersion
        // 실패 시 기존 배열 유지 — 빈 배열로 갈면 화면에 칠해진 마크(남들 공개 하이라이트 포함)가 전부 사라진다.
        if let fresh = try? await listRequest(postId), version == mutationVersion {
            highlights = fresh.filter { !pendingDeletes.contains($0.id) } + highlights.filter { $0.id < 0 }
        }
    }

    func highlight(id: Int64) -> HighlightView? { highlights.first { $0.id == id } }

    /// 이 문단(blockOrder)에 칠할 하이라이트 — 저장된 오프셋으로 정밀하게, 메모/답글이 있으면 강조 밑줄.
    /// 다중 블록(endBlockOrder > blockOrder)은 시작 블록 꼬리·중간 블록 전체·끝 블록 머리로 나눠 칠한다
    /// (Int.max = 이 블록 끝까지, 뷰에서 본문 길이로 clamp).
    func marks(forBlock blockOrder: Int) -> [SelectableProseText.Mark] {
        // 표시를 끈 상태면 마크를 하나도 넘기지 않는다 — 본문이 조용해진다. 선택→생성은 여전히 산다.
        guard !paintHidden else { return [] }
        return highlights.compactMap { h in
            let startBO = h.blockOrder ?? -1
            let endBO = h.endBlockOrder ?? startBO
            guard startBO >= 0, blockOrder >= startBO, blockOrder <= endBO else { return nil }
            let hasThread = (h.note?.isEmpty == false) || h.replyCount > 0
            let start: Int
            let end: Int
            let segment: SelectableProseText.Mark.Segment
            if endBO <= startBO {
                start = h.startOffset ?? -1
                end = h.endOffset ?? -1
                segment = .single
            } else if blockOrder == startBO {
                start = h.startOffset ?? -1
                end = Int.max
                segment = .start
            } else if blockOrder == endBO {
                start = 0
                end = h.endOffset ?? -1
                segment = .end
            } else {
                start = 0
                end = Int.max
                segment = .middle
            }
            return SelectableProseText.Mark(
                id: h.id, start: start, end: end, quote: h.quote, hasThread: hasThread, segment: segment)
        }
    }

    /// 선택 구간을 하이라이트(+선택적 공개 메모) — 미로그인이면 로그인 유도. 로그인 상태면 낙관적으로
    /// 즉시 칠하고 서버 echo 로 진짜 id·attribution 을 채운다. 실패하면 낙관 마크를 걷어내고
    /// 토스트로 알린다(삭제와 같은 문법) — 무음이면 메모까지 소리 없이 유실된다.
    func create(blockOrder: Int, startOffset: Int, endOffset: Int, quote: String, note: String? = nil) {
        guard isSignedIn() else {
            loginPrompt = true
            return
        }
        Task {
            do {
                try await createAndWait(
                    blockOrder: blockOrder, startOffset: startOffset, endOffset: endOffset,
                    quote: quote, note: note)
            } catch {
                ToastCenter.shared.show((error as? HighlightValidationError)?.localizedDescription
                    ?? String(localized: "하이라이트를 저장하지 못했습니다"))
            }
        }
    }

    /// 메모 시트는 이 완료를 기다린 뒤 닫는다. 실패는 호출부에 돌려 입력·재시도를 유지한다.
    func createAndWait(
        blockOrder: Int, startOffset: Int, endOffset: Int, quote: String, note: String? = nil
    ) async throws {
        guard isSignedIn() else { throw AuthError.notSignedIn }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = (trimmed?.isEmpty == false) ? trimmed : nil
        let payload = NewHighlight(
            blockOrder: blockOrder, endBlockOrder: blockOrder, startOffset: startOffset,
            endOffset: endOffset, quote: quote, note: memo)
        try HighlightsAPI.validate(payload)
        // iOS 선택은 블록 단위(문단별 UITextView)라 생성은 늘 단일 블록 — endBlockOrder == blockOrder.
        let optimistic = HighlightView(
            id: nextOptimisticId, author: nil, blockOrder: blockOrder,
            endBlockOrder: blockOrder, startOffset: startOffset, endOffset: endOffset, quote: quote,
            note: memo, replyCount: 0, createdAt: nil)
        nextOptimisticId -= 1
        mutationVersion += 1
        highlights.append(optimistic)
        // 그은 순간 가벼운 촉감 하나 — 좋아요·다음글과 같은 결의 확인(§1.6 조용하지만 살아 있게).
        // 마크가 즉시 칠해지는 그 순간에 맞춰, 형제 인게이지 동작과 동일한 light 무게로.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            let echo = try await createRequest(postId, payload)
            mutationVersion += 1
            // 낙관 항목을 echo 로 교체 — 뒤의 재조회가 실패해도 진짜 id 라 스레드가 동작한다.
            if let idx = highlights.firstIndex(where: { $0.id == optimistic.id }) {
                highlights[idx] = HighlightView(
                    id: echo.id, author: nil, blockOrder: echo.blockOrder,
                    endBlockOrder: echo.endBlockOrder, startOffset: echo.startOffset,
                    endOffset: echo.endOffset, quote: echo.quote, note: echo.note,
                    replyCount: 0, createdAt: echo.createdAt)
            }
            // 저장 완료를 목록 재조회 네트워크에 묶지 않는다. 시트는 이제 안전하게 닫힐 수 있다.
            Task { await load() }
        } catch {
            mutationVersion += 1
            withAnimation(.snappy(duration: 0.25)) {
                highlights.removeAll { $0.id == optimistic.id }
            }
            throw error
        }
    }

    /// 내가 그은 하이라이트 삭제 — 낙관적으로 즉시 본문에서 걷어내(마크가 사라진다) 실패하면 자리째
    /// 되살린다. 성공 여부를 돌려줘 호출부(스레드 시트)가 닫기·토스트를 정한다.
    @discardableResult
    func delete(id: Int64) async -> Bool {
        guard let idx = highlights.firstIndex(where: { $0.id == id }) else { return false }
        let removed = highlights[idx]
        pendingDeletes.insert(id)
        defer { pendingDeletes.remove(id) }
        mutationVersion += 1
        withAnimation(.snappy(duration: 0.25)) {
            highlights.remove(at: idx)
        }
        do {
            try await deleteRequest(id)
            mutationVersion += 1
            return true
        } catch {
            mutationVersion += 1
            // Only restore this item; a concurrent create/refresh owns the rest of the array.
            if !highlights.contains(where: { $0.id == id }) {
                withAnimation(.snappy(duration: 0.25)) {
                    highlights.insert(removed, at: min(idx, highlights.count))
                }
            }
            return false
        }
    }
}

private struct PostHighlightStoreKey: EnvironmentKey {
    static let defaultValue: PostHighlightStore? = nil
}

extension EnvironmentValues {
    /// 본문 문단이 하이라이트를 칠하고 만들 수 있게 — 없으면(임베드) 종전 Text 렌더.
    var postHighlightStore: PostHighlightStore? {
        get { self[PostHighlightStoreKey.self] }
        set { self[PostHighlightStoreKey.self] = newValue }
    }
}
