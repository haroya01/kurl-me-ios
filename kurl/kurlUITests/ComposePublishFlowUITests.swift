//
//  ComposePublishFlowUITests.swift
//  kurlUITests
//

import XCTest

/// 발행 시트 — 이 앱 최대의 순간(초안 → 발행)까지의 마지막 한 박자. 지금까지 스니펫 바만
/// 가드했고 발행 자체는 어떤 테스트도 실제로 눌러보지 않았다. 대표 태그 규칙(1개 필수)·중복 제거·
/// 대표 승격·발행 성공 모먼트(앱 유일의 안정 식별자 viewPublishedPost)를 실기기 경로로 확인한다.
final class ComposePublishFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 컴포즈를 열고 제목·본문을 채워 '발행'이 살아나는 상태로 만든다(canSave 충족).
    private func launchComposeReady() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--focus", "editor"]
        app.launch()
        XCTAssertTrue(app.buttons["굵게"].waitForExistence(timeout: 12), "스니펫 바 안 뜸")

        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "제목 필드 없음")
        title.tap()
        title.typeText("QA 발행 테스트 제목")

        let editor = app.textViews.firstMatch
        editor.tap()
        editor.typeText("본문이 있어야 발행 버튼이 살아난다.")
        return app
    }

    /// 키보드를 내리고 발행 버튼을 눌러 발행 시트를 연다.
    private func openPublishSheet(_ app: XCUIApplication) {
        if app.buttons["키보드 내리기"].exists { app.buttons["키보드 내리기"].tap() }
        let publish = app.buttons["발행"]
        XCTAssertTrue(publish.waitForExistence(timeout: 4), "발행 버튼 없음(제목·본문 미충족?)")
        publish.tap()
        XCTAssertTrue(app.navigationBars["발행 준비"].waitForExistence(timeout: 5), "발행 시트가 안 뜸")
    }

    private func addTag(_ app: XCUIApplication, _ tag: String) {
        let field = app.textFields["태그 입력 후 추가 (쉼표로 여러 개)"]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "태그 입력 필드 없음")
        field.tap()
        field.typeText(tag)
        app.buttons["태그 추가"].tap()
    }

    /// 대표 태그(1개)가 없으면 발행이 막히고 이유가 한 줄로 뜬다 — 태그를 넣으면 풀리고,
    /// 발행하면 성공 모먼트의 '글 보기'(viewPublishedPost)가 뜬다.
    func testPublishRequiresTagThenCelebrates() throws {
        let app = launchComposeReady()
        openPublishSheet(app)

        let blockReason = app.staticTexts["대표 태그를 1개 이상 정하면 발행할 수 있어요."]
        XCTAssertTrue(blockReason.waitForExistence(timeout: 4), "태그 없이도 발행 차단 사유가 안 뜸")

        addTag(app, "개발")
        XCTAssertTrue(blockReason.waitForNonExistence(timeout: 4), "대표 태그를 넣어도 차단 사유가 안 사라짐")

        app.buttons["지금 발행"].tap()
        let viewPublished = app.buttons["viewPublishedPost"]
        XCTAssertTrue(viewPublished.waitForExistence(timeout: 10), "발행 성공 모먼트(글 보기)가 안 뜸")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "publish-celebration"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 같은 태그를 두 번 넣어도 하나만 남고(대소문자 무시 중복 제거), ✕ 로 지우면 칩이 사라진다.
    func testTagFieldDeduplicatesAndDeletes() throws {
        let app = launchComposeReady()
        openPublishSheet(app)

        addTag(app, "개발")
        XCTAssertTrue(app.buttons["대표 태그 개발"].waitForExistence(timeout: 3), "첫 태그가 대표 칩으로 안 생김")

        addTag(app, "개발")
        Thread.sleep(forTimeInterval: 0.4)
        let dupDeletes = app.buttons.matching(NSPredicate(format: "label == %@", "개발 삭제"))
        XCTAssertEqual(dupDeletes.count, 1, "중복 태그가 칩으로 또 생김")

        app.buttons["개발 삭제"].tap()
        XCTAssertTrue(app.buttons["대표 태그 개발"].waitForNonExistence(timeout: 3), "삭제해도 대표 칩이 남음")
    }

    /// 둘째 태그를 탭하면 대표(첫 자리)로 올라오고, 옛 대표는 일반 칩으로 내려간다.
    func testTagPromoteToPrimary() throws {
        let app = launchComposeReady()
        openPublishSheet(app)

        addTag(app, "개발")
        addTag(app, "회고")
        XCTAssertTrue(app.buttons["대표 태그 개발"].waitForExistence(timeout: 3), "첫 태그가 대표가 아님")

        let promoteHoego = app.buttons["회고 — 대표로 지정"]
        XCTAssertTrue(promoteHoego.waitForExistence(timeout: 3), "둘째 태그의 대표 지정 칩이 없음")
        promoteHoego.tap()

        XCTAssertTrue(app.buttons["대표 태그 회고"].waitForExistence(timeout: 3), "탭해도 대표로 안 바뀜")
        XCTAssertTrue(app.buttons["개발 — 대표로 지정"].waitForExistence(timeout: 3), "옛 대표(개발)가 일반으로 안 내려감")
    }
}
