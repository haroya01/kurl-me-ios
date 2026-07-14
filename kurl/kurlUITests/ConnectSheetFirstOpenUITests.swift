//
//  ConnectSheetFirstOpenUITests.swift
//  kurlUITests
//
//  "컬렉션에 연결" 시트가 첫 탭에서 반드시 뜨고 내용까지 로드되는지 — 최초 1회 로딩 실패
//  신고의 재현·회귀 가드. 목 백엔드로 실터치 여정 그대로.
//

import XCTest

final class ConnectSheetFirstOpenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConnectSheetLoadsOnVeryFirstTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        // 글 상세가 서고 독의 "컬렉션에 연결"이 나타날 때까지.
        let connect = app.buttons["컬렉션에 연결"].firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "독의 연결 버튼이 안 보임")

        // 첫 탭 — 시트가 뜨고 컬렉션 목록(제목 "어디에 남길까요?")까지 로드되어야 한다.
        connect.tap()
        let sheetTitle = app.staticTexts["어디에 남길까요?"].firstMatch
        XCTAssertTrue(
            sheetTitle.waitForExistence(timeout: 6),
            "첫 탭에서 연결 시트가 안 떴다 — 최초 1회 로딩 실패 재현")

        // 내용 로드까지 — 목 컬렉션 행 또는 '새 컬렉션 만들기' 행이 보이면 로드 성공.
        let newRow = app.staticTexts["새 컬렉션 만들기"].firstMatch
        XCTAssertTrue(newRow.waitForExistence(timeout: 6), "시트는 떴지만 내용이 로드되지 않음")
    }

    /// 스레드 시트 → "컬렉션에 연결" — 시트가 닫힌 뒤 ConnectSheet 가 첫 시도에 반드시 떠야 한다.
    /// (과거 고정 350ms 지연 핸드오프는 첫 해제가 그보다 느리면 프레젠테이션을 통째로 잃었다.)
    func testThreadToConnectHandoffOnFirstTry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        // 시드 하이라이트(첫 문단 중반) 탭 → 답글 스레드(HighlightNoteReplyUITests 와 동일 좌표).
        let paragraph = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "하이라이트 문단을 못 찾음")
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.16)).tap()
        let sendReply = app.buttons["답글 보내기"]
        if !sendReply.waitForExistence(timeout: 6) {
            paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(sendReply.waitForExistence(timeout: 6), "답글 스레드가 안 열림")
        }

        // 스레드의 "컬렉션에 연결" — 첫 탭 한 번으로 시트 전환이 완주해야 한다.
        // (독의 같은 라벨 버튼이 시트 뒤에 있으니 식별자로 스레드 쪽을 못 박는다.)
        let connect = app.buttons["connectHighlightButton"].firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 6), "스레드의 연결 액션이 안 보임")
        connect.tap()

        let sheetTitle = app.staticTexts["어디에 남길까요?"].firstMatch
        XCTAssertTrue(
            sheetTitle.waitForExistence(timeout: 8),
            "스레드가 닫힌 뒤 연결 시트가 첫 시도에 뜨지 않음")
    }
}
