//
//  로그아웃 뒤 기기에 남는 이전 계정 자취 — 쓰다 만 글은 주인에게만 복구로 뜨고, 최근 검색·내보낸 CSV 는
//  다음 계정에 보이지 않으며, 저장 실패의 '다시 시도'와 줄 선 플러시가 다른 계정에 초안을 만들지 않게 못박는다.
//

import XCTest

@testable import kurl

@MainActor
final class LogoutWipeTests: XCTestCase {
    private static var flushers: [DraftFlusher] = []
    private var owner: Int64? = 7

    override func setUp() async throws {
        owner = 7
        ComposeRecoveryStore.currentOwner = { [unowned self] in self.owner }
        ComposeRecoveryStore.wipeAll()
    }

    override func tearDown() async throws {
        ComposeRecoveryStore.wipeAll()
        ComposeRecoveryStore.currentOwner = { AuthStore.shared.accountId }
        SearchRecents.clear()
        DataExportView.removeDownloads()
    }

    private func stashAll() -> UUID {
        let key = UUID()
        ComposeRecoveryStore.stash(postId: nil, draftKey: key, title: "새 글", markdown: "A")
        ComposeRecoveryStore.stash(postId: 42, draftKey: UUID(), title: "초안", markdown: "B")
        ComposeRecoveryStore.stashConflict(postId: 42, title: "밀려난 내용", markdown: "C")
        return key
    }

    private func assertVaultEmpty(_ key: UUID, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(ComposeRecoveryStore.latestNewDraft(excluding: []), file: file, line: line)
        XCTAssertNil(ComposeRecoveryStore.peek(postId: nil, draftKey: key), file: file, line: line)
        XCTAssertNil(ComposeRecoveryStore.peek(postId: 42, draftKey: UUID()), file: file, line: line)
        XCTAssertNil(ComposeRecoveryStore.peekConflict(postId: 42), file: file, line: line)
    }

    func testSameUserIsOfferedDraftsAfterSessionExpiry() {
        let key = stashAll()

        AuthStore.shared.forgetSession()

        XCTAssertEqual(ComposeRecoveryStore.latestNewDraft(excluding: [])?.draft.markdown, "A")
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: key)?.markdown, "A")
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: 42, draftKey: UUID())?.markdown, "B")
        XCTAssertEqual(ComposeRecoveryStore.peekConflict(postId: 42)?.markdown, "C")
    }

    func testOtherUserIsNotOfferedAndSlotsAreRemoved() {
        let key = stashAll()
        AuthStore.shared.forgetSession()

        owner = 8
        assertVaultEmpty(key)

        owner = 7
        assertVaultEmpty(key)
    }

    func testUnknownUserHidesSlotsWithoutRemovingThem() {
        let key = stashAll()

        owner = nil
        assertVaultEmpty(key)
        ComposeRecoveryStore.stash(postId: nil, draftKey: key, title: "새 글", markdown: "끊긴 사이")

        owner = 7
        XCTAssertEqual(ComposeRecoveryStore.peek(postId: nil, draftKey: key)?.markdown, "A")
    }

    func testSignOutWipesRecoveryDrafts() {
        let key = stashAll()

        AuthStore.shared.signOut()

        assertVaultEmpty(key)
    }

    func testSignOutClearsRecentSearches() {
        SearchRecents.save(["kurl", "swift"])
        XCTAssertEqual(SearchRecents.load(), ["kurl", "swift"])

        AuthStore.shared.signOut()

        XCTAssertEqual(SearchRecents.load(), [])
    }

    func testSignOutRemovesExportedFiles() throws {
        let url = DataExportView.downloadURL(.following)
        try Data("Account address\n".utf8).write(to: url)

        AuthStore.shared.signOut()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: 저장 실패의 '다시 시도'

    private func failingFlusher(_ attempts: @escaping () -> Void) -> DraftFlusher {
        let flusher = DraftFlusher { _ in
            attempts()
            throw URLError(.notConnectedToInternet)
        }
        Self.flushers.append(flusher)
        return flusher
    }

    private func payload() -> DraftFlusher.Payload {
        DraftFlusher.Payload(
            postId: nil, draftKey: UUID(), title: "제목", markdown: "본문",
            savedTitle: "", savedExcerpt: "", savedTags: [], excerpt: "", tags: [],
            savedSeriesId: nil, seriesId: nil)
    }

    private func flushAndFail(_ flusher: DraftFlusher) async {
        flusher.flush(payload())
        let deadline = Date().addingTimeInterval(3)
        while ToastCenter.shared.actionLabel == nil || !flusher.pendingDraftKeys.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(ToastCenter.shared.actionLabel)
    }

    func testRetryByTheSameUserFlushesAgain() async {
        var attempts = 0
        let flusher = failingFlusher { attempts += 1 }
        await flushAndFail(flusher)

        ToastCenter.shared.runAction()
        let deadline = Date().addingTimeInterval(3)
        while attempts < 2, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(attempts, 2)
        ToastCenter.shared.dismissActionToast()
    }

    func testRetryAfterSwitchingAccountsDoesNothing() async {
        var attempts = 0
        let flusher = failingFlusher { attempts += 1 }
        await flushAndFail(flusher)

        owner = 8
        ToastCenter.shared.runAction()
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(flusher.pendingDraftKeys.isEmpty)
        XCTAssertNil(ToastCenter.shared.actionLabel)
    }

    func testSignOutDismissesRetryToast() async {
        let flusher = failingFlusher {}
        await flushAndFail(flusher)

        AuthStore.shared.signOut()

        XCTAssertNil(ToastCenter.shared.message)
        XCTAssertNil(ToastCenter.shared.actionLabel)
    }

    // MARK: 대기 중인 플러시의 주인

    private func recorder(gated: Bool = false) -> FlushRecorder {
        let recorder = FlushRecorder(gated: gated)
        Self.flushers.append(recorder.flusher)
        return recorder
    }

    private func payload(_ markdown: String) -> DraftFlusher.Payload {
        var payload = payload()
        payload.markdown = markdown
        return payload
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    func testQueuedFlushIsHeldForItsOwnerWhileAnotherUserIsSignedIn() async {
        let recorder = recorder()
        let flusher = recorder.flusher
        flusher.flush(payload("A의 글"))
        owner = 8
        await settle()

        XCTAssertEqual(recorder.sent, [])
        XCTAssertEqual(flusher.pendingDraftKeys.count, 1)

        flusher.flush(payload("B의 글"))
        await waitUntil { recorder.sent == ["B의 글"] }
        flusher.resumeHeld()
        await settle()
        XCTAssertEqual(recorder.sent, ["B의 글"])

        owner = 7
        flusher.resumeHeld()
        await waitUntil { recorder.sent.count == 2 }
        XCTAssertEqual(recorder.sent, ["B의 글", "A의 글"])
        XCTAssertTrue(flusher.pendingDraftKeys.isEmpty)
    }

    func testQueuedFlushResumesWhenItsOwnerSignsBackInAfterExpiry() async {
        let recorder = recorder()
        let flusher = recorder.flusher
        flusher.flush(payload("A의 글"))
        owner = nil
        await settle()
        XCTAssertEqual(recorder.sent, [])

        owner = 7
        flusher.resumeHeld()
        await waitUntil { !recorder.sent.isEmpty }

        XCTAssertEqual(recorder.sent, ["A의 글"])
        XCTAssertTrue(flusher.pendingDraftKeys.isEmpty)
    }

    func testDiscardDropsQueuedAndHeldFlushes() async {
        let held = recorder()
        held.flusher.flush(payload("보류된 글"))
        owner = nil
        await settle()
        held.flusher.discardQueued()
        XCTAssertTrue(held.flusher.pendingDraftKeys.isEmpty)
        owner = 7
        held.flusher.resumeHeld()
        await settle()
        XCTAssertEqual(held.sent, [])

        let gated = recorder(gated: true)
        gated.flusher.flush(payload("가는 중"))
        await waitUntil { gated.waiting == 1 }
        gated.flusher.flush(payload("줄 선 글"))
        gated.flusher.discardQueued()
        gated.releaseAll()
        await waitUntil { gated.flusher.pendingDraftKeys.isEmpty }
        await settle()

        XCTAssertEqual(gated.sent, ["가는 중"])
    }
}

@MainActor
private final class FlushRecorder {
    private(set) var sent: [String] = []
    private var gates: [CheckedContinuation<Void, Never>] = []
    private let gated: Bool
    private(set) lazy var flusher = DraftFlusher { payload in
        if self.gated { await withCheckedContinuation { self.gates.append($0) } }
        self.sent.append(payload.markdown)
    }

    var waiting: Int { gates.count }

    init(gated: Bool) {
        self.gated = gated
    }

    func releaseAll() {
        let pending = gates
        gates = []
        pending.forEach { $0.resume() }
    }
}
