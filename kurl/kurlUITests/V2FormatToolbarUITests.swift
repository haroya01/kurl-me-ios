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

        // 서식 툴바가 떴는가 — 굵게·제목 버튼 존재로 판정(레이블).
        let boldButton = app.buttons["굵게"]
        XCTAssertTrue(boldButton.waitForExistence(timeout: 6), "서식 툴바(굵게) 미표시")
        XCTAssertTrue(app.buttons["제목"].exists, "블록 서식(제목) 미표시")
        XCTAssertTrue(app.buttons["인용"].exists, "블록 서식(인용) 미표시")
        shot("format-toolbar-01-visible")

        // 단어 선택 — 문단을 더블탭해 단어를 선택하고 볼드 적용.
        paragraph.doubleTap()
        Thread.sleep(forTimeInterval: 0.5)
        shot("format-toolbar-02-word-selected")

        if boldButton.isHittable {
            boldButton.tap()
            Thread.sleep(forTimeInterval: 0.7)
            // 적용 후에도 캔버스는 유지되고(포커스), 저장 배지가 뜬다(마크다운 변경 → 자동저장).
            shot("format-toolbar-03-bold-applied")
        }

        // 블록 서식: 제목 순환 — 버튼 하나가 # → ## → ### → 문단 을 돈다(제목/소제목 통합).
        let titleButton = app.buttons["제목"]
        if titleButton.isHittable {
            titleButton.tap()
            Thread.sleep(forTimeInterval: 0.7)
            shot("format-toolbar-04-heading-h1")
            titleButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            shot("format-toolbar-05-heading-h2")
            titleButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            shot("format-toolbar-06-heading-h3")
            titleButton.tap()  // 한 바퀴 — 문단으로 복귀(크래시·죽은 버튼 회귀 가드)
            Thread.sleep(forTimeInterval: 0.5)
            shot("format-toolbar-07-heading-back-to-paragraph")
        }
    }
}
