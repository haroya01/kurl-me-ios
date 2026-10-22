//
//  로그아웃 뒤 기기에 남는 이전 계정 자취 — 쓰다 만 글의 복구 슬롯, 최근 검색, 내보낸 CSV 가 다음 계정에 보이지 않게 못박는다.
//

import XCTest

@testable import kurl

@MainActor
final class LogoutWipeTests: XCTestCase {

    override func tearDown() async throws {
        ComposeRecoveryStore.wipeAll()
        SearchRecents.clear()
        DataExportView.removeDownloads()
    }

    func testSignOutWipesRecoveryDrafts() {
        let key = UUID()
        ComposeRecoveryStore.stash(postId: nil, draftKey: key, title: "A의 새 글", markdown: "A")
        ComposeRecoveryStore.stash(postId: 42, draftKey: UUID(), title: "A의 초안", markdown: "B")
        ComposeRecoveryStore.stashConflict(postId: 42, title: "밀려난 내용", markdown: "C")
        XCTAssertNotNil(ComposeRecoveryStore.latestNewDraft(excluding: []))

        AuthStore.shared.signOut()

        XCTAssertNil(ComposeRecoveryStore.latestNewDraft(excluding: []))
        XCTAssertNil(ComposeRecoveryStore.peek(postId: nil, draftKey: key))
        XCTAssertNil(ComposeRecoveryStore.peek(postId: 42, draftKey: UUID()))
        XCTAssertNil(ComposeRecoveryStore.peekConflict(postId: 42))
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
}
