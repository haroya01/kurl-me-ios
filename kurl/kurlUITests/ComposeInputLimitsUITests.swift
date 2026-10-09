//
//  ComposeInputLimitsUITests.swift
//  kurlUITests
//
//  글 입력 한도 실동작 — 제목 200·소개글 500(UTF-16)에서 입력이 멈추고 한도 근처에서 글자 수가 보이며,
//  태그는 10개에서 입력이 닫히고 사유가 보인다(서버가 400 을 내거나 조용히 자르기 전에 입력 단계에서).
//

import XCTest

final class ComposeInputLimitsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchCompose() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--mocks", "--reset-recovery", "--tab", "write", "--open", "compose", "--focus", "editor",
            "--editor", "legacy",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["굵게"].waitForExistence(timeout: 12), "스니펫 바 안 뜸")
        return app
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testTitleStopsAtServerLimitAndShowsCount() throws {
        let app = launchCompose()
        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "제목 필드 없음")
        title.tap()
        title.typeText(String(repeating: "a", count: 185))
        XCTAssertTrue(app.staticTexts["15자 남음"].waitForExistence(timeout: 3), "한도 근처 글자 수가 안 보임")
        title.typeText(String(repeating: "b", count: 20))

        let value = title.value as? String ?? ""
        XCTAssertEqual(value.count, 200, "제목이 200자에서 멈추지 않음")
        XCTAssertTrue(app.staticTexts["200자까지 쓸 수 있어요"].waitForExistence(timeout: 3))
        shot("title-limit")
    }

    func testExcerptStopsAtServerLimitAndTagsStopAtTen() throws {
        let app = launchCompose()
        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "제목 필드 없음")
        title.tap()
        title.typeText("한도 테스트")
        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("본문")
        if app.buttons["키보드 내리기"].exists { app.buttons["키보드 내리기"].tap() }
        app.buttons["발행"].tap()
        XCTAssertTrue(app.navigationBars["발행 준비"].waitForExistence(timeout: 5), "발행 시트가 안 뜸")

        let tagField = app.textFields["태그 입력 후 추가 (쉼표로 여러 개)"]
        XCTAssertTrue(tagField.waitForExistence(timeout: 3), "태그 입력 필드 없음")
        for n in 1...10 {
            tagField.tap()
            tagField.typeText("t\(n)\n")
            let chip = n == 1 ? app.buttons["대표 태그 t1"] : app.buttons["t\(n) — 대표로 지정"]
            XCTAssertTrue(chip.waitForExistence(timeout: 3), "태그 t\(n) 칩이 안 생김")
        }
        XCTAssertTrue(app.staticTexts["태그는 10개까지 달 수 있어요"].waitForExistence(timeout: 3), "태그 한도 사유가 안 보임")
        XCTAssertTrue(app.staticTexts["10/10"].exists)
        XCTAssertFalse(tagField.isEnabled, "10개를 채워도 태그 입력이 열려 있음")
        shot("tag-limit")

        let excerpt = app.textFields["소개글 — 카드와 검색에 보이는 한 단락"]
        XCTAssertTrue(excerpt.waitForExistence(timeout: 3), "소개글 필드 없음")
        excerpt.tap()
        excerpt.typeText(String(repeating: "c", count: 505))
        let typed = app.textFields.element(matching: NSPredicate(format: "value BEGINSWITH 'ccc'"))
        let value = typed.value as? String ?? ""
        XCTAssertEqual(value.count, 500, "소개글이 500자에서 멈추지 않음")
        XCTAssertTrue(app.staticTexts["500자까지 쓸 수 있어요"].waitForExistence(timeout: 3))
        shot("excerpt-limit")
    }
}
