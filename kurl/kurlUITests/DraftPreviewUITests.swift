//
//  DraftPreviewUITests.swift
//  kurlUITests
//
//  초안(미발행) 네이티브 미리보기 — ⋯ 메뉴의 "미리보기"가 인앱 사파리(웹)가 아니라 리더(BlockView)로
//  지금 문서를 발행 후 모습으로 띄우는지 실기기(sim) 경로로 확인하고 캡처한다. 블록 종류가 두루 든
//  목 초안(9003)을 연다. simctl 은 탭/키보드를 못 넣으니 XCUITest 가 유일한 실동작 경로다.
//

import XCTest

final class DraftPreviewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testDraftPreviewIsNativeReadingView() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()

        // 블록 종류가 두루 든 목 초안을 연다.
        let draftRow = app.staticTexts["목 초안 — 미리보기 데모"]
        XCTAssertTrue(draftRow.waitForExistence(timeout: 15), "스튜디오에 미리보기 데모 초안이 안 보임")
        draftRow.tap()

        // 편집 화면 로드 대기 — 제목 블록이 렌더될 때까지.
        let heading = app.textViews.containing(
            NSPredicate(format: "value == %@", "종이 위의 초안")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 12), "초안 편집 로드 실패")
        Thread.sleep(forTimeInterval: 0.5)

        // ⋯ 메뉴 → 미리보기. 툴바 오버플로 메뉴 버튼을 찾아 연다.
        // (SF Symbol ellipsis 메뉴 — 접근성 라벨이 불안정하니 primaryAction 영역의 메뉴 버튼을 훑는다.)
        openOverflowMenu(app)
        let previewButton = app.buttons["미리보기"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 6), "⋯ 메뉴에 미리보기 없음")
        previewButton.tap()

        // 네이티브 미리보기가 떴는가 — 웹뷰(SafariView)가 아니라 리더. 네비 제목 "미리보기" + 닫기 버튼.
        let previewNav = app.navigationBars["미리보기"]
        let closeButton = app.buttons["닫기"]
        let appeared = previewNav.waitForExistence(timeout: 8) || closeButton.waitForExistence(timeout: 4)
        XCTAssertTrue(appeared, "네이티브 미리보기 시트 미표시")
        // 웹뷰가 아님을 방증 — 본문이 네이티브 텍스트로 렌더되어 제목 텍스트가 존재.
        let previewTitle = app.staticTexts["종이 위의 초안"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 6), "미리보기 본문(네이티브)이 안 보임")
        Thread.sleep(forTimeInterval: 0.8)
        shot("draft-preview-01-native-top")   // 제목 마스트헤드 + 읽는 시간 + lead 문단·인용

        // 스크롤해 아래 블록(구분선·리스트·코드)을 캡처.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        shot("draft-preview-02-list-code")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        shot("draft-preview-03-code-block")
    }

    /// 툴바 오버플로(⋯) 메뉴를 연다 — 라벨이 불안정하니 여러 후보를 시도한다.
    private func openOverflowMenu(_ app: XCUIApplication) {
        let candidates = ["More", "더 보기", "ellipsis"]
        for id in candidates {
            let button = app.buttons[id]
            if button.waitForExistence(timeout: 2), button.isHittable {
                button.tap()
                return
            }
        }
        // 폴백 — 내비바 안 마지막 버튼(주 액션 영역의 ⋯ 핀)을 누른다.
        let navBar = app.navigationBars.firstMatch
        let buttons = navBar.buttons
        if buttons.count > 0 {
            buttons.element(boundBy: buttons.count - 1).tap()
        }
    }
}
