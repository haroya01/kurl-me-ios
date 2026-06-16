//
//  PostHighlightStore.swift
//  kurl
//

import SwiftUI

/// 한 글의 하이라이트 상태 — 공개 하이라이트를 싣고(본문 문단에 칠하기), 선택→생성을 받는다.
/// 본문(BlockView)이 환경에서 읽어 문단별 인용을 칠하고, 미로그인 생성은 로그인 유도로 넘긴다.
/// 본 글(단독 상세)에서만 주입한다 — 발견 덱 임베드는 가볍게 종전 렌더 그대로.
@MainActor
@Observable
final class PostHighlightStore {
    let postId: Int64
    private(set) var highlights: [HighlightView] = []
    /// 미로그인 사용자가 하이라이트를 시도 — 뷰가 로그인 시트를 띄우도록 신호한다.
    var loginPrompt = false

    init(postId: Int64) { self.postId = postId }

    func load() async {
        highlights = (try? await HighlightsAPI.list(postId: postId)) ?? []
    }

    /// 이 문단(blockOrder)에 칠할 하이라이트 — 저장된 오프셋(startOffset/endOffset)을 그대로 넘겨
    /// 정밀하게 칠하게 한다. 오프셋이 없으면 -1 로 인용 폴백을 태운다.
    func marks(forBlock blockOrder: Int) -> [SelectableProseText.Mark] {
        highlights.compactMap { h in
            guard h.blockOrder == blockOrder else { return nil }
            return SelectableProseText.Mark(
                start: h.startOffset ?? -1, end: h.endOffset ?? -1, quote: h.quote)
        }
    }

    /// 선택 구간을 하이라이트 — 미로그인이면 로그인 유도. 로그인 상태면 낙관적으로 즉시 칠하고
    /// 서버 echo 로 진짜 id·attribution 을 채운다(실패해도 읽기를 끊지 않는다).
    func create(blockOrder: Int, startOffset: Int, endOffset: Int, quote: String) {
        guard AuthStore.shared.isSignedIn else {
            loginPrompt = true
            return
        }
        let optimistic = HighlightView(
            id: -Int64(highlights.count + 1), author: nil, blockOrder: blockOrder,
            startOffset: startOffset, endOffset: endOffset, quote: quote, createdAt: nil)
        highlights.append(optimistic)
        Task {
            _ = try? await HighlightsAPI.create(
                postId: postId,
                NewHighlight(
                    blockOrder: blockOrder, startOffset: startOffset,
                    endOffset: endOffset, quote: quote))
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
