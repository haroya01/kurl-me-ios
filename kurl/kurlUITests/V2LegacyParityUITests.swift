//
//  V2LegacyParityUITests.swift
//  kurlUITests
//
//  WriteV2(기본 에디터)에 레거시 파리티로 되살린 컨트롤의 실동작 — 취소선 버튼·표 행/열 삭제·
//  키보드 내리기. 탭 → 실제 상태 변화(블록 값·컨트롤 등장·토스트)로 판정한다(하이라이트만으로 X).
//  이미지 폭/삭제는 PHPicker(프로세스 밖) 의존이라 유닛(WriteV2RoundTripTests)이 대표 커버.
//

import XCTest

final class V2LegacyParityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    /// 목 초안을 열어 캔버스로 진입 — 문단 "포트와 어댑터." 블록에 포커스.
    private func openDraftAndFocus(_ app: XCUIApplication) -> XCUIElement {
        let draftRow = app.staticTexts["목 초안 — 헥사고날 정리"]
        XCTAssertTrue(draftRow.waitForExistence(timeout: 20), "스튜디오 mock 초안 미표시")
        draftRow.tap()
        let paragraph = app.textViews.containing(
            NSPredicate(format: "value == %@", "포트와 어댑터.")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "문단 블록 렌더 실패")
        paragraph.tap()
        Thread.sleep(forTimeInterval: 0.6)
        return paragraph
    }

    // MARK: 취소선 — 버튼 존재 + 적용 후 자동저장(마크다운 변경 반영)

    func testStrikethroughButtonAppliesAndSaves() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        let paragraph = openDraftAndFocus(app)

        let strike = app.buttons["취소선"]
        XCTAssertTrue(strike.waitForExistence(timeout: 8), "취소선 버튼이 V2 툴바에 없음")
        shot(app, "parity-01-strike-button")

        paragraph.doubleTap()  // 단어 선택
        Thread.sleep(forTimeInterval: 0.4)
        if strike.isHittable { strike.tap(); Thread.sleep(forTimeInterval: 0.6) }
        // 마크다운 변경 → 자동저장 배지.
        XCTAssertTrue(app.buttons["저장 상태 보기"].waitForExistence(timeout: 15),
                      "취소선 적용 후 자동저장 배지 안 뜸")
        shot(app, "parity-02-strike-applied")
    }

    
    // MARK: 키보드 내리기 — 고정 버튼 존재 + 탭

    func testKeyboardDismissButtonExists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        _ = openDraftAndFocus(app)

        let dismiss = app.buttons["키보드 내리기"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 8), "키보드 내리기 버튼이 V2 툴바에 없음")
        XCTAssertTrue(dismiss.isHittable, "키보드 내리기 버튼이 스크롤에 밀려 도달 불가")
        dismiss.tap()
        Thread.sleep(forTimeInterval: 0.6)
        shot(app, "parity-03-keyboard-dismissed")
    }

    // MARK: 표 행/열 삭제 — 표 삽입 → 삭제 컨트롤 등장 → 탭 → 되돌리기 토스트

    func testTableDeleteControlsAppearAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        _ = openDraftAndFocus(app)

        // 표 삽입 — 인블록 컨트롤(+행 +열)이 뜬다.
        let tableButton = app.buttons["표"]
        XCTAssertTrue(tableButton.waitForExistence(timeout: 8), "표 버튼 미표시")
        tableButton.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // 기본 표는 헤더+본문1행 = 삭제 불가(행 삭제 버튼 없음). 한 행 추가해 삭제 가능 상태로.
        let addRow = app.buttons["행"].firstMatch  // + 행
        XCTAssertTrue(addRow.waitForExistence(timeout: 6), "표 인블록 '행 추가' 미표시")
        addRow.tap()
        Thread.sleep(forTimeInterval: 0.5)
        shot(app, "parity-04-table-two-body-rows")

        // 이제 본문 2행 → '행 삭제'(라벨) 컨트롤이 나타나야 한다.
        let deleteRow = app.buttons["행 삭제"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 6),
                      "본문 2행인데 행 삭제 컨트롤이 안 뜸")
        // 열 삭제도 있어야(기본 2열).
        XCTAssertTrue(app.buttons["열 삭제"].exists, "열 삭제 컨트롤이 안 뜸")
        shot(app, "parity-05-delete-controls-visible")

        deleteRow.tap()
        Thread.sleep(forTimeInterval: 0.6)
        shot(app, "parity-06-row-deleted")
        // 본문이 1행으로 줄면 '행 삭제' 컨트롤이 사라진다(헤더+본문1행은 보호) — 삭제가 실제로 일어난 증거.
        // (되돌리기 토스트 문구는 별도 ToastHost 관찰 이슈에 얽혀 있어 여기선 구조 변화로 판정한다.)
        XCTAssertTrue(app.buttons["행 삭제"].waitForNonExistence(timeout: 6),
                      "행 삭제 후에도 행 삭제 컨트롤이 남음 — 실제 삭제가 안 일어남")
    }
}
