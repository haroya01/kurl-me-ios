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

    // MARK: 자동저장 텍스트 라벨(B5) — 편집 후 "저장 중…" 또는 "저장됨" 텍스트가 배지에 보인다

    func testAutosaveShowsTextLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        let paragraph = openDraftAndFocus(app)
        paragraph.tap()
        app.typeText(" 라벨 테스트.")
        Thread.sleep(forTimeInterval: 0.5)
        // 편집 직후엔 "저장 중…", 왕복 후엔 "저장됨" — 둘 중 하나가 텍스트로 떠야 한다(점선 스피너 단독 아님).
        let saving = app.staticTexts["저장 중…"]
        let saved = app.staticTexts["저장됨"]
        XCTAssertTrue(saving.waitForExistence(timeout: 6) || saved.waitForExistence(timeout: 15),
                      "자동저장 상태가 텍스트 라벨로 안 보임(B5)")
        shot(app, "parity-07-autosave-label")
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

    // MARK: 표 전체 삭제 — 컨트롤 바 "표 삭제" 버튼이 블록을 통째로 지운다

    /// 비텍스트 블록(표)은 캐럿을 못 받아 백스페이스로만(뒤 문단 트릭) 지워졌다 — 표 통째 삭제 수단이
    /// UI 에 없어 사용자가 막혔다(진단). 이제 컨트롤 바 "표 삭제" 버튼으로 블록을 지운다.
    func testTableWholeDeleteButtonRemovesBlock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        _ = openDraftAndFocus(app)

        let tableButton = app.buttons["표"]
        XCTAssertTrue(tableButton.waitForExistence(timeout: 8), "표 버튼 미표시")
        tableButton.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "del-01-table-inserted")

        // 표 삽입 즉시 "표 삭제" 버튼이 컨트롤 바에 있어야(최소 크기와 무관하게 항상 통째 삭제 가능).
        let deleteTable = app.buttons["표 삭제"]
        XCTAssertTrue(deleteTable.waitForExistence(timeout: 6),
                      "표 삽입 후 '표 삭제' 버튼이 없음 — 통째 삭제 수단 부재")
        deleteTable.tap()
        Thread.sleep(forTimeInterval: 0.6)
        shot(app, "del-02-table-deleted")
        // 표가 사라지면 표 컨트롤(+행)도 함께 사라진다 — 실제 블록 삭제의 증거.
        XCTAssertTrue(app.buttons["표 삭제"].waitForNonExistence(timeout: 6),
                      "표 삭제 후에도 컨트롤이 남음 — 실제 삭제가 안 일어남")
    }

    // MARK: 구분선 삭제 — 선택 시 삭제 버튼이 블록을 지운다

    /// 구분선도 비텍스트라 백스페이스로만 지워졌다(진단). 이제 탭해 선택하면 삭제 버튼이 뜨고 지운다.
    func testDividerDeleteButtonRemovesBlock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        _ = openDraftAndFocus(app)

        let dividerButton = app.buttons["구분선"]
        XCTAssertTrue(dividerButton.waitForExistence(timeout: 8), "구분선 삽입 버튼 미표시")
        dividerButton.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "del-03-divider-inserted")

        // 구분선을 탭해 선택 → 삭제 버튼 노출. (툴바 삽입 버튼과 라벨이 겹쳐 식별자로 구분한다.)
        let dividerLine = app.buttons["editor-divider"]
        XCTAssertTrue(dividerLine.waitForExistence(timeout: 6), "삽입된 구분선 요소 미표시")
        dividerLine.tap()
        Thread.sleep(forTimeInterval: 0.4)
        let deleteDivider = app.buttons["구분선 삭제"]
        XCTAssertTrue(deleteDivider.waitForExistence(timeout: 6),
                      "구분선 선택 후 '구분선 삭제' 버튼이 안 뜸")
        deleteDivider.tap()
        Thread.sleep(forTimeInterval: 0.6)
        shot(app, "del-04-divider-deleted")
        XCTAssertTrue(app.buttons["구분선 삭제"].waitForNonExistence(timeout: 6),
                      "구분선 삭제 후에도 삭제 버튼이 남음 — 실제 삭제가 안 일어남")
    }

    // MARK: 볼드 토글 오프 — 굵게를 다시 누르면 마커가 깔끔히 제거된다(재랩·별표 잔존 아님)

    /// 사용자 신고 재현·수정 검증: 볼드 단어에서 굵게를 다시 누르면 `**` 가 사라져 순수 텍스트가 된다.
    /// (예전엔 unwrap 이 없어 재랩(`****…****`)되거나, 수동 마커 삭제 시 짝이 깨져 `*` 가 남았다.)
    func testBoldToggleOffRemovesMarkersCleanly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        _ = openDraftAndFocus(app)

        // 문단 텍스트를 매번 새로 질의(볼드 적용 시 value 가 바뀌어 이전 참조가 stale 이 된다).
        // "포트와 어댑터."(공백 포함) 를 담은 문단 — 원문·마크업 상태 모두 이 접두로 잡힌다.
        func para() -> XCUIElement {
            app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "어댑터")).firstMatch
        }
        let original = (para().value as? String) ?? ""
        para().doubleTap()  // 한 단어 선택(어느 단어인지는 무관 — ** 삽입 여부만 본다)
        Thread.sleep(forTimeInterval: 0.4)
        let bold = app.buttons["굵게"]
        XCTAssertTrue(bold.waitForExistence(timeout: 8), "굵게 버튼 미표시")
        bold.tap()
        Thread.sleep(forTimeInterval: 0.6)
        shot(app, "mk-01-after-bold")
        let afterBold = (para().value as? String) ?? ""
        XCTAssertTrue(afterBold.contains("**"), "굵게 적용 후 raw 에 ** 가 있어야: \(afterBold)")

        // 굵게를 다시 눌러 토글 오프 — 마커가 사라지고 별표가 하나도 안 남아야 한다(핵심 회귀).
        bold.tap()
        Thread.sleep(forTimeInterval: 0.6)
        shot(app, "mk-02-after-toggle-off")
        let afterToggle = (para().value as? String) ?? ""
        XCTAssertFalse(afterToggle.contains("*"),
                       "토글 오프 후에도 별표가 남음(마커 잔존 버그): \(afterToggle)")
        XCTAssertEqual(afterToggle, original, "토글 오프 후 원문으로 정확히 복귀: \(afterToggle)")
    }

    // MARK: 마커 스팬 안 Enter 분할 — 짝을 닫고 다시 열어 리터럴 마커 잔존 없음(실기기 경로)

    /// 볼드 단어 안에 커서를 두고 Enter 를 치면 양쪽 블록이 각각 온전한 `**…**` 짝을 갖는다
    /// (예전엔 `**굵`·`게**` 로 갈려 리터럴 별표가 남았다). 각 블록의 별표 수가 짝수여야 짝이 맞다.
    func testEnterInsideBoldSplitsWithBalancedMarkers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()
        _ = openDraftAndFocus(app)

        func boldedPara() -> XCUIElement {
            app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "**")).firstMatch
        }
        // 한 단어 볼드.
        app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "어댑터")).firstMatch.doubleTap()
        Thread.sleep(forTimeInterval: 0.4)
        let bold = app.buttons["굵게"]
        XCTAssertTrue(bold.waitForExistence(timeout: 8), "굵게 버튼 미표시")
        bold.tap()
        Thread.sleep(forTimeInterval: 0.6)
        let bolded = boldedPara()
        XCTAssertTrue(bolded.waitForExistence(timeout: 6), "볼드 적용 문단 미표시")
        shot(app, "mk-03-bolded-before-enter")

        // 볼드 단어 글자 사이에 커서 — 텍스트뷰 가운데를 탭(단어 내부 근처)해 캐럿을 스팬 안에 둔다.
        bolded.tap()
        Thread.sleep(forTimeInterval: 0.3)
        // Enter(구조 분할).
        bolded.typeText("\n")
        Thread.sleep(forTimeInterval: 0.6)
        shot(app, "mk-04-after-enter")

        // 분할 후 모든 문단 텍스트뷰의 별표 수가 짝수여야(짝이 안 깨짐). 홀수면 리터럴 잔존.
        let allTexts = app.textViews.allElementsBoundByIndex.compactMap { $0.value as? String }
        for t in allTexts where t.contains("*") {
            let stars = t.filter { $0 == "*" }.count
            XCTAssertEqual(stars % 2, 0, "분할 후 별표가 홀수(짝 깨짐): \"\(t)\"")
        }
    }
}
