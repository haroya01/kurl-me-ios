//
//  V2FormatToolbarUITests.swift
//  kurlUITests
//
//  WriteV2 서식 툴바 — 캔버스 입력 중 선택 서식(볼드·이탤릭·코드·링크)·블록 서식(제목·인용·코드·
//  리스트)·삽입(구분선·사진·표)이 한 유리 바로 뜨는지, 선택 텍스트에 볼드가 적용되는지 실기기(sim)
//  경로로 확인·캡처한다. `--editor v2 --tab write` 로 초안을 열어 캔버스에 진입한다.
//

import XCTest

final class V2FormatToolbarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testFormatToolbarAppearsAndBoldToggles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()

        // 목 초안을 열어 캔버스로.
        let draftRow = app.staticTexts["목 초안 — 헥사고날 정리"]
        XCTAssertTrue(draftRow.waitForExistence(timeout: 15), "스튜디오에 mock 초안이 안 보임")
        draftRow.tap()

        // 문단 블록에 포커스 — 캔버스가 뜨면 툴바가 액세서리로 붙는다.
        let paragraph = app.textViews.containing(
            NSPredicate(format: "value == %@", "포트와 어댑터.")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 12), "문단 블록 렌더 실패")
        paragraph.tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertTrue(app.buttons["composeFormat"].isHittable)
        paragraph.doubleTap()
        app.buttons["composeFormat"].tap()
        let bold = app.buttons["굵게"]
        XCTAssertTrue(bold.waitForExistence(timeout: 5))
        bold.tap()
        let formatted = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "**")).firstMatch
        XCTAssertTrue(formatted.waitForExistence(timeout: 5), "Selected text receives bold formatting through the menu")
        shot("format-toolbar-bold-applied")

        for heading in ["제목 1", "제목 2", "제목 3", "본문"] {
            app.buttons["composeFormat"].tap()
            let choice = app.buttons[heading]
            XCTAssertTrue(choice.waitForExistence(timeout: 4))
            choice.tap()
            XCTAssertEqual(app.buttons["composeFormat"].value as? String, heading)
        }
        shot("format-toolbar-heading-choices")
    }
}
