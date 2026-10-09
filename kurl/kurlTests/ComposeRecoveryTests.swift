//
//  ComposeRecoveryTests.swift
//  kurlTests
//
//  새 글 기기 금고와 이탈 플러시 — 새 글끼리 한 슬롯을 나눠 써서 남의 본문을 복구로 내밀거나
//  성공한 플러시가 다른 새 글의 슬롯을 지우던 것, 앞 플러시가 가는 중이면 뒤 플러시를 버리던 것을 못박는다.
//

import XCTest

@testable import kurl

@MainActor
final class ComposeRecoveryTests: XCTestCase {

    override func setUp() async throws {
        ComposeRecoveryStore.wipeAll()
    }

    override func tearDown() async throws {
        ComposeRecoveryStore.wipeAll()
    }

    func testNewDraftsKeepSeparateSlots() {
        let first = UUID(), second = UUID()
        ComposeRecoveryStore.stash(postId: nil, draftKey: first, title: "첫 글", markdown: "A")
        ComposeRecoveryStore.stash(postId: nil, draftKey: second, title: "둘째 글", markdown: "B")
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: first)?.markdown, "A")
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: second)?.markdown, "B")

        ComposeRecoveryStore.clear(postId: nil, draftKey: first)
        XCTAssertNil(ComposeRecoveryStore.peek(postId: nil, draftKey: first))
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: second)?.markdown, "B")
    }

    func testRecoveryOfferSkipsDraftsStillBeingFlushed() {
        let orphan = UUID(), flushing = UUID()
        ComposeRecoveryStore.stash(postId: nil, draftKey: orphan, title: "남은 글", markdown: "orphan")
        ComposeRecoveryStore.stash(postId: nil, draftKey: flushing, title: "나르는 글", markdown: "flushing")

        let offer = ComposeRecoveryStore.latestNewDraft(excluding: [flushing])
        XCTAssertEqual(offer?.key, orphan)
        XCTAssertEqual(offer?.draft.markdown, "orphan")
        XCTAssertNil(ComposeRecoveryStore.latestNewDraft(excluding: [orphan, flushing]))
    }

    func testRecoveryOfferPicksMostRecentNewDraft() {
        let older = UUID(), newer = UUID()
        ComposeRecoveryStore.stash(postId: nil, draftKey: older, title: "", markdown: "older")
        Thread.sleep(forTimeInterval: 0.01)
        ComposeRecoveryStore.stash(postId: nil, draftKey: newer, title: "", markdown: "newer")
        XCTAssertEqual(ComposeRecoveryStore.latestNewDraft(excluding: [])?.key, newer)
    }

    func testPromoteMovesOnlyThatDraft() {
        let promoted = UUID(), other = UUID()
        ComposeRecoveryStore.stash(postId: nil, draftKey: promoted, title: "승격", markdown: "A")
        ComposeRecoveryStore.stash(postId: nil, draftKey: other, title: "그대로", markdown: "B")

        ComposeRecoveryStore.promote(promoted, to: 42)

        let moved = ComposeRecoveryStore.peek(postId: 42, draftKey: UUID())
        XCTAssertEqual(moved?.markdown, "A")
        XCTAssertEqual(moved?.postId, 42)
        XCTAssertNil(ComposeRecoveryStore.peek(postId: nil, draftKey: promoted))
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: other)?.markdown, "B")
    }

    func testLegacySingleNewSlotIsStillOffered() throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComposeRecovery", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("new.json")
        let draft = ComposeRecoveryStore.Draft(postId: nil, title: "옛 슬롯", markdown: "legacy", savedAt: Date())
        try JSONEncoder().encode(draft).write(to: legacy)

        let offer = ComposeRecoveryStore.latestNewDraft(excluding: [])
        XCTAssertEqual(offer?.draft.markdown, "legacy")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        if let key = offer?.key {
            XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: key)?.markdown, "legacy")
        }
    }

    // MARK: 이탈 플러시

    private func payload(_ markdown: String, key: UUID, postId: Int64? = nil) -> DraftFlusher.Payload {
        DraftFlusher.Payload(
            postId: postId, draftKey: key, title: "제목", markdown: markdown,
            savedTitle: "", savedExcerpt: "", savedTags: [], excerpt: "", tags: [],
            savedSeriesId: nil, seriesId: nil)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testFlushWhileAnotherIsInFlightIsQueuedNotDropped() async {
        let server = GatedServer()
        let flusher = DraftFlusher { try await server.save(&$0) }
        let first = UUID(), second = UUID()

        flusher.flush(payload("첫 글", key: first))
        await waitUntil { server.started == 1 }
        flusher.flush(payload("둘째 글", key: second))
        XCTAssertEqual(flusher.pendingDraftKeys, [first, second])

        server.releaseNext()
        await waitUntil { server.started == 2 }
        server.releaseNext()
        await waitUntil { flusher.pendingDraftKeys.isEmpty }

        XCTAssertEqual(server.saved, ["첫 글", "둘째 글"])
        XCTAssertEqual(flusher.completedTick, 2)
    }

    func testSuccessfulFlushClearsOnlyItsOwnSlot() async {
        let server = GatedServer()
        let flusher = DraftFlusher { try await server.save(&$0) }
        let leaving = UUID(), stillOpen = UUID()
        ComposeRecoveryStore.stash(postId: nil, draftKey: leaving, title: "떠난 글", markdown: "leaving")
        ComposeRecoveryStore.stash(postId: nil, draftKey: stillOpen, title: "쓰는 글", markdown: "open")

        flusher.flush(payload("leaving", key: leaving))
        await waitUntil { server.started == 1 }
        server.releaseNext()
        await waitUntil { flusher.pendingDraftKeys.isEmpty }

        XCTAssertNil(ComposeRecoveryStore.peek(postId: 501, draftKey: leaving))
        XCTAssertNil(ComposeRecoveryStore.peek(postId: nil, draftKey: leaving))
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: stillOpen)?.markdown, "open")
    }
}

/// 서버 대역 — 저장 요청을 붙잡아 두었다가 하나씩 풀어 준다. 새 글이면 초안 id 를 매기고 금고 슬롯을 승격한다.
@MainActor
private final class GatedServer {
    private(set) var started = 0
    private(set) var saved: [String] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var nextId: Int64 = 501

    func save(_ payload: inout DraftFlusher.Payload) async throws {
        started += 1
        await withCheckedContinuation { waiting.append($0) }
        if payload.postId == nil {
            payload.postId = nextId
            ComposeRecoveryStore.promote(payload.draftKey, to: nextId)
            nextId += 1
        }
        saved.append(payload.markdown)
    }

    func releaseNext() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }
}
