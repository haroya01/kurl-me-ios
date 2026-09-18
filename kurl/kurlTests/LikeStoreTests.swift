//
//  LikeStoreTests.swift
//  kurlTests
//
//  퀵액션 좋아요의 낙관 카운트 회귀 — 기준값이 살아 있는 동안만 +1 하고, 서버가 새 숫자를
//  들고 오면 그 값을 믿는다(중복 가산 금지). 0→1 등장(하트가 없던 카드)도 고정한다.
//

import XCTest

@testable import kurl

@MainActor
final class LikeStoreTests: XCTestCase {

    override func setUp() async throws {
        LikeStore.shared.reset()
    }

    func testDisplayCountWithoutBumpReturnsServerValue() {
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 5)
    }

    func testBumpAddsOneWhileServerIsStale() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 6)
    }

    func testZeroLikeCardShowsOneAfterBump() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 0)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 0), 1)
    }

    func testFreshServerCountRetiresBump() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        // 내 좋아요가 반영된 새 응답(6) — 그대로 믿고 +1 하지 않는다.
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 6), 6)
        // 그 사이 다른 사람 좋아요까지 실려 와도(9) 서버 값 그대로.
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 9), 9)
    }

    func testBumpIsKeyedPerPost() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "other", server: 5), 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "b", slug: "s", server: 5), 5)
    }

    func testResetClearsBumps() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        LikeStore.shared.reset()
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 5)
    }
}

/// 위젯 딥링크(kurlwidget://…) 라우팅 계약 — 위젯 탭이 분석 분면·서재 탭·저장 글 시트로
/// 정확히 떨어지는지. TabRouter 는 프로세스 공유 싱글턴이라 각 테스트가 상태를 되돌린다.
@MainActor
final class WidgetDeepLinkTests: XCTestCase {

    override func tearDown() {
        TabRouter.shared.pendingStudioSection = nil
        TabRouter.shared.pendingPost = nil
    }

    func testAnalyticsLinkSwitchesToWriteTabAndQueuesSection() {
        WidgetDeepLink.open(URL(string: "kurlwidget://analytics")!)
        XCTAssertEqual(TabRouter.shared.selection, 2, "분석은 글쓰기 탭의 분면")
        XCTAssertEqual(TabRouter.shared.pendingStudioSection, StudioSection.analytics.rawValue)
    }

    func testLibraryLinkSwitchesToAccountTab() {
        WidgetDeepLink.open(URL(string: "kurlwidget://library")!)
        XCTAssertEqual(TabRouter.shared.selection, 4, "서재는 계정 탭에 산다")
    }

    func testPostLinkQueuesSheetRef() {
        WidgetDeepLink.open(URL(string: "kurlwidget://post/hana/slow-reading")!)
        XCTAssertEqual(
            TabRouter.shared.pendingPost,
            WidgetPostRef(username: "hana", slug: "slow-reading"))
    }

    func testMalformedPostLinkIsIgnored() {
        WidgetDeepLink.open(URL(string: "kurlwidget://post/only-one-part")!)
        XCTAssertNil(TabRouter.shared.pendingPost, "재료가 모자라면 조용히 무시 — 404 시트를 띄우지 않는다")
    }

    func testForeignSchemeIsIgnored() {
        let before = TabRouter.shared.selection
        WidgetDeepLink.open(URL(string: "https://blog.kurl.me/@hana/slow-reading")!)
        XCTAssertEqual(TabRouter.shared.selection, before)
        XCTAssertNil(TabRouter.shared.pendingPost)
    }
}

// MARK: Highlight anchors — verified paint range is also the only tappable range

@MainActor
final class HighlightAnchoringTests: XCTestCase {
    private func mark(
        start: Int, end: Int, quote: String,
        segment: SelectableProseText.Mark.Segment = .single
    ) -> SelectableProseText.Mark {
        .init(id: 42, start: start, end: end, quote: quote, hasThread: true, segment: segment)
    }

    func testExactOffsetsDisambiguateRepeatedQuote() {
        let text = "같은 문장 / 같은 문장" as NSString
        let range = text.range(of: "같은 문장", options: .backwards)
        let resolved = SelectableProseText.resolve(
            mark(start: range.location, end: NSMaxRange(range), quote: "같은 문장"), in: text)
        XCTAssertEqual(resolved?.range, range)
    }

    func testShiftedUniqueQuoteRepairsBothPaintAndTapRangeInUTF16() throws {
        let text = "새 문장 👩🏽‍💻 다음에 중요한 구절이 있다" as NSString
        let target = text.range(of: "중요한 구절")
        let resolved = try XCTUnwrap(SelectableProseText.resolve(
            mark(start: 0, end: 6, quote: "중요한 구절"), in: text))
        XCTAssertEqual(resolved.range, target)
        XCTAssertTrue(NSLocationInRange(target.location, resolved.range))
        XCTAssertFalse(NSLocationInRange(0, resolved.range), "old offsets must not open the thread")
    }

    func testAmbiguousOrMissingQuoteFailsClosed() {
        XCTAssertNil(SelectableProseText.resolve(
            mark(start: 0, end: 1, quote: "반복"), in: "앞 반복 뒤 반복" as NSString))
        XCTAssertNil(SelectableProseText.resolve(
            mark(start: 0, end: 2, quote: "삭제된 문장"), in: "수정한 문장" as NSString))
        XCTAssertNil(SelectableProseText.resolve(
            mark(start: 0, end: 2, quote: ""), in: "수정한 문장" as NSString))
    }

    func testMultiBlockQuoteValidatesEachSegmentWithoutFullQuoteEquality() {
        let quote = "첫 문단 끝.\n\n중간 문단.\n마지막 시작."
        let first = "앞 내용. 첫 문단 끝." as NSString
        let start = first.range(of: "첫 문단 끝.").location
        XCTAssertEqual(SelectableProseText.resolve(
            mark(start: start, end: Int.max, quote: quote, segment: .start), in: first)?.range,
            NSRange(location: start, length: first.length - start))
        let middle = "중간 문단." as NSString
        XCTAssertEqual(SelectableProseText.resolve(
            mark(start: 0, end: Int.max, quote: quote, segment: .middle), in: middle)?.range,
            NSRange(location: 0, length: middle.length))
        let last = "마지막 시작. 뒤 내용." as NSString
        let length = ("마지막 시작." as NSString).length
        XCTAssertEqual(SelectableProseText.resolve(
            mark(start: 0, end: length, quote: quote, segment: .end), in: last)?.range,
            NSRange(location: 0, length: length))
    }

    func testChangedMultiBlockBoundaryDoesNotGuessAReplacement() {
        XCTAssertNil(SelectableProseText.resolve(
            mark(start: 0, end: Int.max, quote: "원래 꼬리. 다음 문단.", segment: .start),
            in: "새로 바꾼 꼬리." as NSString))
        XCTAssertNil(SelectableProseText.resolve(
            mark(start: 0, end: 4, quote: "첫 문단. 원래 머리.", segment: .end),
            in: "수정된 머리. 원래 머리." as NSString))
    }

    func testStorePreservesMultiBlockRoles() async {
        let highlight = HighlightView(
            id: 1, author: nil, blockOrder: 2, endBlockOrder: 4, startOffset: 3, endOffset: 5,
            quote: "first middle last", note: "a note", replyCount: 0, createdAt: nil)
        let store = PostHighlightStore(postId: 1, listRequest: { _ in [highlight] })
        await store.load()
        XCTAssertEqual(store.marks(forBlock: 2).first?.segment, .start)
        XCTAssertEqual(store.marks(forBlock: 3).first?.segment, .middle)
        XCTAssertEqual(store.marks(forBlock: 4).first?.segment, .end)
        XCTAssertTrue(store.marks(forBlock: 1).isEmpty)
        store.paintHidden = true
        XCTAssertTrue(store.marks(forBlock: 2).isEmpty)
    }

    func testSourceJumpMatchesWholeQuoteAcrossFormattingAndBlocks() {
        let blocks = [(id: 1, raw: "같은 도입이 있지만 다른 결론."),
                      (id: 2, raw: "같은 도입이 있지만 **저장한 결론**."),
                      (id: 3, raw: "다음 문단의 시작.")]
        XCTAssertEqual(SelectableProseText.sourceBlockID(
            for: "같은 도입이 있지만 저장한 결론.\n다음 문단의 시작.", blocks: blocks), 2)
    }

    func testAmbiguousSourceQuoteDoesNotJumpToTheFirstParagraph() {
        XCTAssertNil(SelectableProseText.sourceBlockID(
            for: "같은 문장", blocks: [(id: 1, raw: "같은 문장"), (id: 2, raw: "같은 문장")]))
    }
}

// MARK: Highlight memo submission — failure retains input, success alone permits dismissal

@MainActor
final class HighlightSubmissionTests: XCTestCase {
    func testMemoLimitUsesUTF16AndKeepsOverflowForCorrection() async {
        let submission = HighlightNoteSubmission()
        submission.text = String(repeating: "😀", count: 250)
        XCTAssertEqual(submission.noteLength, 500)
        XCTAssertTrue(submission.canSave)
        submission.text += "가"
        XCTAssertFalse(submission.canSave)
        let success = await submission.save { _ in XCTFail("oversized memo reached the network") }
        XCTAssertFalse(success)
        XCTAssertEqual(submission.noteLength, 501)
        XCTAssertNotNil(submission.errorMessage)
    }

    func testQuoteLimitPreventsServerTruncationAtUTF16Boundary() {
        let atLimit = NewHighlight(blockOrder: 0, endBlockOrder: 0, startOffset: 0, endOffset: 1000,
            quote: String(repeating: "😀", count: 500), note: nil)
        XCTAssertNoThrow(try HighlightsAPI.validate(atLimit))
        let tooLong = NewHighlight(blockOrder: 0, endBlockOrder: 0, startOffset: 0, endOffset: 1002,
            quote: String(repeating: "😀", count: 501), note: nil)
        XCTAssertThrowsError(try HighlightsAPI.validate(tooLong))
    }

    func testFailedMemoSurvivesAndRetryUsesTheSameText() async {
        let submission = HighlightNoteSubmission()
        submission.text = "  내 생각을 잃지 않도록  "
        let failed = await submission.save { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertFalse(failed)
        XCTAssertEqual(submission.text, "  내 생각을 잃지 않도록  ")
        XCTAssertNotNil(submission.errorMessage)
        XCTAssertFalse(submission.busy)
        var sent: String?
        let saved = await submission.save { sent = $0 }
        XCTAssertTrue(saved)
        XCTAssertEqual(sent, "내 생각을 잃지 않도록")
        XCTAssertNil(submission.errorMessage)
    }

    func testPendingMemoCannotStartASecondSave() async {
        let submission = HighlightNoteSubmission()
        submission.text = "한 번만 저장"
        let started = expectation(description: "save started")
        var resume: CheckedContinuation<Void, Never>?
        let first = Task {
            await submission.save { _ in
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(submission.busy)
        let second = await submission.save { _ in XCTFail("duplicate save") }
        XCTAssertFalse(second)
        XCTAssertEqual(submission.text, "한 번만 저장")
        resume?.resume()
        let success = await first.value
        XCTAssertTrue(success)
        XCTAssertFalse(submission.busy)
    }

    func testStoreRollsBackFailedCreateAndPropagatesFailureToMemo() async {
        let store = PostHighlightStore(
            postId: 5, isSignedIn: { true },
            createRequest: { _, _ in throw URLError(.timedOut) }, listRequest: { _ in [] })
        let submission = HighlightNoteSubmission()
        submission.text = "계속 남아야 할 메모"
        let success = await submission.save { note in
            try await store.createAndWait(blockOrder: 0, startOffset: 0, endOffset: 2, quote: "구절", note: note)
        }
        XCTAssertFalse(success)
        XCTAssertTrue(store.highlights.isEmpty)
        XCTAssertEqual(submission.text, "계속 남아야 할 메모")
    }

    func testStoreKeepsSuccessfulEchoEvenIfRefreshFails() async throws {
        let store = PostHighlightStore(
            postId: 5, isSignedIn: { true },
            createRequest: { _, payload in
                HighlightRef(id: 77, blockOrder: payload.blockOrder, endBlockOrder: payload.endBlockOrder,
                    startOffset: payload.startOffset, endOffset: payload.endOffset, quote: payload.quote,
                    note: payload.note, createdAt: nil)
            }, listRequest: { _ in throw URLError(.notConnectedToInternet) })
        try await store.createAndWait(blockOrder: 0, startOffset: 0, endOffset: 2, quote: "구절", note: "내 메모")
        await store.load()
        XCTAssertEqual(store.highlights.map(\.id), [77])
        XCTAssertEqual(store.highlights.first?.note, "내 메모")
    }

    func testFailedDeleteRestoresOnlyThatItemAndKeepsConcurrentCreation() async throws {
        let original = HighlightView(id: 1, author: nil, blockOrder: 0, endBlockOrder: 0,
            startOffset: 0, endOffset: 2, quote: "이전", note: nil, replyCount: 0, createdAt: nil)
        var server = [original]
        let started = expectation(description: "delete pending")
        var finishDelete: CheckedContinuation<Void, Error>?
        let store = PostHighlightStore(
            postId: 1, isSignedIn: { true }, createRequest: { _, payload in
                server.append(HighlightView(id: 2, author: nil, blockOrder: 0, endBlockOrder: 0,
                    startOffset: 0, endOffset: 2, quote: payload.quote, note: nil, replyCount: 0, createdAt: nil))
                return HighlightRef(id: 2, blockOrder: 0, endBlockOrder: 0, startOffset: 0,
                    endOffset: 2, quote: payload.quote, note: nil, createdAt: nil)
            }, listRequest: { _ in server }, deleteRequest: { _ in
                try await withCheckedThrowingContinuation { continuation in
                    finishDelete = continuation
                    started.fulfill()
                }
            })
        await store.load()
        let deletion = Task { await store.delete(id: 1) }
        await fulfillment(of: [started], timeout: 2)
        try await store.createAndWait(blockOrder: 0, startOffset: 0, endOffset: 2, quote: "신규")
        await store.load()
        XCTAssertEqual(store.highlights.map(\.id), [2], "refresh must not resurrect a pending deletion")
        finishDelete?.resume(throwing: URLError(.timedOut))
        let deleted = await deletion.value
        XCTAssertFalse(deleted)
        XCTAssertEqual(store.highlights.map(\.id), [1, 2])
    }

    func testOldReadCannotEraseAConfirmedCreation() async throws {
        let started = expectation(description: "old read pending")
        var finishRead: CheckedContinuation<[HighlightView], Error>?
        var calls = 0
        let store = PostHighlightStore(
            postId: 1, isSignedIn: { true }, createRequest: { _, payload in
                HighlightRef(id: 2, blockOrder: 0, endBlockOrder: 0, startOffset: 0,
                    endOffset: 2, quote: payload.quote, note: nil, createdAt: nil)
            }, listRequest: { _ in
                calls += 1
                guard calls == 1 else { throw URLError(.notConnectedToInternet) }
                return try await withCheckedThrowingContinuation { continuation in
                    finishRead = continuation
                    started.fulfill()
                }
            })
        let read = Task { await store.load() }
        await fulfillment(of: [started], timeout: 2)
        try await store.createAndWait(blockOrder: 0, startOffset: 0, endOffset: 2, quote: "신규")
        finishRead?.resume(returning: [])
        await read.value
        XCTAssertEqual(store.highlights.map(\.id), [2])
    }
}

// MARK: Highlight library — older API payloads remain readable; existing public notes are searchable

@MainActor
final class HighlightLibraryTests: XCTestCase {
    func testDecodeOldResponseWithoutNote() throws {
        let data = Data(#"{"id":1,"quote":"문장","postUsername":"a","postSlug":"b","postTitle":"글"}"#.utf8)
        let item = try JSONDecoder().decode(MyHighlightView.self, from: data)
        XCTAssertNil(item.note)
        XCTAssertTrue(item.matches("문장"))
    }

    func testFindsNoteWithoutChangingQuote() throws {
        let data = Data(#"{"id":1,"quote":"문장","note":"다시 읽으며 떠오른 설계","postUsername":"a","postSlug":"b","postTitle":"글"}"#.utf8)
        let item = try JSONDecoder().decode(MyHighlightView.self, from: data)
        XCTAssertTrue(item.matches(" 설계 "))
        XCTAssertTrue(item.matches("글"))
        XCTAssertFalse(item.matches("없는 내용"))
        XCTAssertEqual(item.quote, "문장")
    }
}
