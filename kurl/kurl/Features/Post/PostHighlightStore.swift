//
//  PostHighlightStore.swift
//  kurl
//

import SwiftUI

/// 한 글의 하이라이트 상태 — 공개 하이라이트를 싣고(본문 문단에 칠하기), 선택→생성(+메모)을 받고,
/// 칠해진 하이라이트 탭→답글 스레드를 연다. 본문(BlockView)이 환경에서 읽어 문단별로 칠하고,
/// 미로그인 생성은 로그인 유도로 넘긴다. 본 글(단독 상세)에서만 주입한다.
@MainActor
@Observable
final class PostHighlightStore {
    let postId: Int64
    private(set) var highlights: [HighlightView] = []
    /// 미로그인 사용자가 하이라이트를 시도 — 뷰가 로그인 시트를 띄우도록 신호한다.
    var loginPrompt = false
    /// 탭한 하이라이트 — 뷰가 답글 스레드 시트를 띄운다.
    var threadHighlightId: Int64?
    /// 메모와 함께 하이라이트할 선택 구간 — 뷰가 메모 입력 시트를 띄운다.
    var noteDraft: NoteDraft?

    /// 메모 입력 시트를 구동하는 선택 구간.
    struct NoteDraft: Identifiable {
        let blockOrder: Int
        let startOffset: Int
        let endOffset: Int
        let quote: String
        var id: String { "\(blockOrder)-\(startOffset)-\(endOffset)" }
    }

    init(postId: Int64) { self.postId = postId }

    func load() async {
        highlights = (try? await HighlightsAPI.list(postId: postId)) ?? []
    }

    func highlight(id: Int64) -> HighlightView? { highlights.first { $0.id == id } }

    /// 이 문단(blockOrder)에 칠할 하이라이트 — 저장된 오프셋으로 정밀하게, 메모/답글이 있으면 강조 밑줄.
    /// 다중 블록(endBlockOrder > blockOrder)은 시작 블록 꼬리·중간 블록 전체·끝 블록 머리로 나눠 칠한다
    /// (Int.max = 이 블록 끝까지, 뷰에서 본문 길이로 clamp).
    func marks(forBlock blockOrder: Int) -> [SelectableProseText.Mark] {
        highlights.compactMap { h in
            let startBO = h.blockOrder ?? -1
            let endBO = h.endBlockOrder ?? startBO
            guard startBO >= 0, blockOrder >= startBO, blockOrder <= endBO else { return nil }
            let hasThread = (h.note?.isEmpty == false) || h.replyCount > 0
            let start: Int
            let end: Int
            if endBO <= startBO {
                start = h.startOffset ?? -1
                end = h.endOffset ?? -1
            } else if blockOrder == startBO {
                start = h.startOffset ?? 0
                end = Int.max
            } else if blockOrder == endBO {
                start = 0
                end = h.endOffset ?? 0
            } else {
                start = 0
                end = Int.max
            }
            return SelectableProseText.Mark(id: h.id, start: start, end: end, quote: h.quote, hasThread: hasThread)
        }
    }

    /// 선택 구간을 하이라이트(+선택적 공개 메모) — 미로그인이면 로그인 유도. 로그인 상태면 낙관적으로
    /// 즉시 칠하고 서버 echo 로 진짜 id·attribution 을 채운다(실패해도 읽기를 끊지 않는다).
    func create(blockOrder: Int, startOffset: Int, endOffset: Int, quote: String, note: String? = nil) {
        guard AuthStore.shared.isSignedIn else {
            loginPrompt = true
            return
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = (trimmed?.isEmpty == false) ? trimmed : nil
        // iOS 선택은 블록 단위(문단별 UITextView)라 생성은 늘 단일 블록 — endBlockOrder == blockOrder.
        let optimistic = HighlightView(
            id: -Int64(highlights.count + 1), author: nil, blockOrder: blockOrder,
            endBlockOrder: blockOrder, startOffset: startOffset, endOffset: endOffset, quote: quote,
            note: memo, replyCount: 0, createdAt: nil)
        highlights.append(optimistic)
        Task {
            _ = try? await HighlightsAPI.create(
                postId: postId,
                NewHighlight(
                    blockOrder: blockOrder, endBlockOrder: blockOrder, startOffset: startOffset,
                    endOffset: endOffset, quote: quote, note: memo))
            await load()
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
