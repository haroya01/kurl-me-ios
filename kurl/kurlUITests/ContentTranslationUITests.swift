//
//  ContentTranslationUITests.swift
//  kurlUITests
//
//  외국어 노트·글은 그 자리에서 번역문으로 바뀌고 원문으로 돌아간다. 목 모드는 가짜 번역기가
//  "[ko] " 를 붙인다(시뮬레이터엔 실제 번역 모델이 없다). 기기 언어는 한국어 하나로 고정한다.
//

import XCTest

final class ContentTranslationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        return app
    }

    func testAForeignNoteTranslatesInPlaceAndGoesBack() throws {
        let app = launch(["--mocks", "--tab", "notes"])
        let body = app.buttons["note.body.9510"]
        for _ in 0..<6 where !(body.exists && body.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(body.waitForExistence(timeout: 12), "영어 노트(9510)가 피드에 없음")
        XCTAssertFalse(body.label.contains("[ko]"))

        let translate = app.buttons["note.translate.9510"]
        XCTAssertTrue(translate.waitForExistence(timeout: 6), "외국어 노트에 번역 보기가 없음")
        translate.tap()
        let original = app.buttons["note.original.9510"]
        XCTAssertTrue(original.waitForExistence(timeout: 6), "번역 뒤 원문 보기가 없음")
        XCTAssertTrue(body.label.contains("[ko] Hexagonal ports"), "본문이 번역문으로 바뀌지 않음: \(body.label)")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '영어에서 번역됨'")).firstMatch.exists,
            "어느 언어에서 번역됐는지 안 보임")
        shot("note-translated")

        original.tap()
        XCTAssertTrue(translate.waitForExistence(timeout: 4), "원문 보기 뒤 번역 보기로 돌아오지 않음")
        XCTAssertFalse(body.label.contains("[ko]"), "원문 보기를 눌렀는데 번역문이 남음")

        translate.tap()
        XCTAssertTrue(original.waitForExistence(timeout: 1), "한 번 번역한 노트를 다시 번역하는 데 시간이 걸린다(기억 안 됨)")
    }

    func testAFailedTranslationSaysSoAndKeepsTheOriginal() throws {
        let app = launch(["--mocks", "--tab", "notes", "--translation-fails"])
        let body = app.buttons["note.body.9510"]
        for _ in 0..<6 where !(body.exists && body.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(body.waitForExistence(timeout: 12), "영어 노트(9510)가 피드에 없음")
        let translate = app.buttons["note.translate.9510"]
        XCTAssertTrue(translate.waitForExistence(timeout: 6), "외국어 노트에 번역 보기가 없음")
        translate.tap()
        XCTAssertTrue(app.staticTexts["번역하지 못했어요"].waitForExistence(timeout: 6), "번역이 실패해도 알리지 않음")
        shot("note-translation-failed")
        XCTAssertTrue(translate.waitForExistence(timeout: 4), "실패한 뒤 번역 보기로 돌아오지 않음")
        XCTAssertFalse(app.buttons["note.original.9510"].exists, "실패했는데 원문 보기가 남음")
        XCTAssertFalse(body.label.contains("[ko]"), "실패했는데 본문이 바뀜")
    }

    func testANoteInTheDeviceLanguageHasNoTranslateButton() throws {
        let app = launch(["--mocks", "--tab", "notes"])
        XCTAssertTrue(app.buttons["note.body.9501"].waitForExistence(timeout: 12), "한국어 노트(9501)가 피드에 없음")
        XCTAssertFalse(app.buttons["note.translate.9501"].exists, "한국어 기기에서 한국어 노트에 번역 보기가 있음")
    }

    func testAForeignPostTranslatesItsTextBlocksOnly() throws {
        let app = launch(["--mocks", "--post", "honggildong/kyoukai-wo-hiku"])
        let banner = app.descendants(matching: .any)["post.translation"]
        XCTAssertTrue(banner.waitForExistence(timeout: 12), "일본어 글에 번역 배너가 없음")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '일본어로 쓴 글이에요'")).firstMatch.exists,
            "배너가 원문 언어를 말하지 않음")
        shot("post-banner")

        app.buttons["post.translate"].tap()
        let translatedTitle = app.staticTexts["[ko] 境界を先に引く"]
        XCTAssertTrue(translatedTitle.waitForExistence(timeout: 6), "제목이 번역문으로 바뀌지 않음")
        XCTAssertTrue(app.buttons["post.original"].exists, "번역 뒤 원문 보기가 없음")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'protocol PostStore'")).firstMatch.exists,
            "코드 블록이 사라졌다")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '[ko] protocol'")).firstMatch.exists,
            "코드 블록까지 번역했다")
        XCTAssertTrue(app.staticTexts["[ko] 層"].exists, "표 셀이 번역문 그대로 보이지 않음")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '\\\\['")).firstMatch.exists,
            "번역문에 이스케이프 역슬래시가 새어 나왔다")
        shot("post-translated")

        app.buttons["post.original"].tap()
        XCTAssertTrue(app.staticTexts["境界を先に引く"].waitForExistence(timeout: 4), "원문 보기로 제목이 돌아오지 않음")
        XCTAssertTrue(app.buttons["post.translate"].exists, "원문 보기 뒤 번역 보기로 돌아오지 않음")
    }

    func testAPostInTheDeviceLanguageHasNoBanner() throws {
        let app = launch(["--mocks", "--post", "honggildong/hexagonal-after-3-months"])
        XCTAssertTrue(app.buttons["좋아요"].waitForExistence(timeout: 12), "글 상세가 열리지 않음")
        XCTAssertFalse(app.descendants(matching: .any)["post.translation"].exists, "한국어 글에 번역 배너가 있음")
    }
}
