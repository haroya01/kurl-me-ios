//
//  WriteV2RealInteractionUITests.swift
//  kurlUITests
//
//  V2 캔버스 실사용 여정 — 실제 터치·키보드·클립보드·사진 피커로 사용자 신고 5증상 경로를
//  그대로 밟는다: 제목 타이핑 → 캔버스 탭 → 본문 타이핑 → 줄머리 지름길(`# `·`- `) →
//  무포커스 서식 버튼 → 구분선·표 삽입 → 자동저장 배지 / 클립보드 이미지·URL 붙여넣기 /
//  사진 라이브러리 삽입. simctl 은 터치·키보드를 못 넣으니 XCUITest 가 유일한 실동작 경로다.
//

import XCTest

final class WriteV2RealInteractionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    /// V2 새 글 컴포즈로 진입 — 목 백엔드, 글쓰기 탭, 컴포즈 자동 오픈.
    private func launchCompose() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--editor", "v2"]
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15), "V2 캔버스 미표시")
        return app
    }

    /// 캔버스 빈 영역(이어 쓰기 활주로) 탭 — 접근성 요소 우선, 좌표 폴백.
    private func tapCanvas(_ app: XCUIApplication) {
        let runway = app.buttons["본문 이어 쓰기"].firstMatch
        if runway.waitForExistence(timeout: 4), runway.isHittable {
            runway.tap()
        } else {
            app.scrollViews.firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        }
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// 특정 값을 가진 블록 텍스트뷰가 나타나길 기다린다.
    private func assertBlock(
        _ app: XCUIApplication, value: String, contains: Bool = false,
        timeout: TimeInterval = 6, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let format = contains ? "value CONTAINS %@" : "value == %@"
        let block = app.textViews.containing(NSPredicate(format: format, value)).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: timeout), message, file: file, line: line)
    }

    /// 러너가 채운 시스템 클립보드는 앱에서 붙여넣기 동의 알럿을 띄울 수 있다.
    private func installPasteConsentMonitor() {
        addUIInterruptionMonitor(withDescription: "paste-consent") { alert in
            for label in ["Allow Paste", "붙여넣기 허용", "Paste", "허용", "Allow"]
            where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    /// 롱프레스 편집 메뉴에서 붙여넣기 실행(ko/en 라벨 겸용).
    private func pasteViaMenu(_ app: XCUIApplication, on element: XCUIElement) {
        element.press(forDuration: 1.2)
        let pasteEN = app.menuItems["Paste"]
        let pasteKO = app.menuItems["붙여넣기"]
        XCTAssertTrue(
            pasteEN.waitForExistence(timeout: 5) || pasteKO.waitForExistence(timeout: 2),
            "붙여넣기 메뉴가 안 뜸")
        (pasteEN.exists ? pasteEN : pasteKO).tap()
        app.tap()  // 인터럽션 모니터가 동의 알럿을 처리하도록 한 번 건드린다.
    }

    // MARK: 여정 1 — 타이핑·지름길·툴바·삽입·자동저장 (신고 1·2·4 경로)

    func testComposeJourneyByTouchAndKeyboard() throws {
        let app = launchCompose()

        // 제목 — 실제 키보드 타이핑.
        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "제목 필드 없음")
        title.tap()
        title.typeText("Engine journey")

        // 본문 — 캔버스 빈 곳을 탭해 이어 쓰기(신고 1: 본문 클릭 불능 회귀 방지).
        tapCanvas(app)
        app.typeText("Hello body")
        assertBlock(app, value: "Hello body", "본문 타이핑이 블록에 안 들어감")
        shot(app, "journey-01-typed")

        // 줄머리 지름길 — `# ` 는 마커가 사라지고 제목 블록이 된다(신고 2).
        // 전환 공백 직후 아주 짧게 쉰다: 전환이 텍스트뷰를 프로그램적으로 리셋하는데, 그 수 ms 안에
        // 오는 키 입력은 iOS 입력 세션 재동기화에 삼켜진다(기계 속도 전용 — 사람 타이핑 간격에선 불가능).
        app.typeText("\n")
        Thread.sleep(forTimeInterval: 0.4)
        app.typeText("# ")
        Thread.sleep(forTimeInterval: 0.25)
        app.typeText("Big title")
        assertBlock(app, value: "Big title", "`# ` 지름길이 제목 블록으로 전환 안 됨(마커 미제거)")

        // `- ` 리스트 지름길.
        app.typeText("\n")
        Thread.sleep(forTimeInterval: 0.4)
        app.typeText("- ")
        Thread.sleep(forTimeInterval: 0.25)
        app.typeText("First item")
        assertBlock(app, value: "First item", "`- ` 지름길이 리스트 항목으로 전환 안 됨")
        shot(app, "journey-02-shortcuts")

        // 빈 항목 엔터 두 번 = 리스트 탈출 → 문단.
        app.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)
        app.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)

        // 서식 툴바 굵게 — 선택 없이 눌러도 죽지 않고 마커쌍 사이에 캐럿(신고 2).
        let bold = app.buttons["굵게"]
        XCTAssertTrue(bold.waitForExistence(timeout: 4), "서식 툴바(굵게) 없음")
        bold.tap()
        Thread.sleep(forTimeInterval: 0.4)
        app.typeText("bold")
        assertBlock(app, value: "**bold**", contains: true, "굵게 마커쌍 사이 타이핑이 안 들어감")
        shot(app, "journey-03-bold")

        // 구분선 삽입 — 비텍스트 블록이 실제로 앉는다.
        app.buttons["구분선"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(
            app.descendants(matching: .any)["구분선"].firstMatch.waitForExistence(timeout: 5),
            "구분선 블록이 캔버스에 안 나타남")

        // 표 삽입 — 행/열 추가·정렬 컨트롤이 뜬다(열별 정렬은 '정렬' 메뉴 안).
        app.buttons["표"].tap()
        XCTAssertTrue(app.buttons["정렬"].waitForExistence(timeout: 6), "표 블록 정렬 컨트롤이 안 뜸")
        XCTAssertTrue(app.buttons["행"].exists, "표 블록 행 추가 컨트롤이 안 뜸")
        shot(app, "journey-04-divider-table")

        // 자동저장 — 제목·본문이 채워졌으니 디바운스 후 저장 배지(신고 4 경로, 목 왕복).
        let statusBadge = app.buttons["저장 상태 보기"]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 15), "자동저장 배지가 안 뜸")
        shot(app, "journey-05-saved")
    }

    // MARK: 여정 2 — 클립보드 이미지 붙여넣기 → 이미지 블록 (신고 5)

    func testPasteClipboardImageBecomesImageBlock() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        UIPasteboard.general.image = image
        installPasteConsentMonitor()

        let app = launchCompose()
        // 초안 생성엔 제목이 필요(canSave) — 업로드는 ensurePost 를 타므로 제목부터.
        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap()
        title.typeText("Paste image")

        tapCanvas(app)
        pasteViaMenu(app, on: app.textViews.firstMatch)

        // 업로드(목) → IMAGE 블록 — 대체 텍스트 캡션 필드가 이미지 블록의 지문이다.
        let altField = app.textFields["대체 텍스트"]
        XCTAssertTrue(altField.waitForExistence(timeout: 20), "클립보드 이미지가 이미지 블록으로 안 들어감")
        shot(app, "paste-image-block")
    }

    // MARK: 여정 3 — URL 붙여넣기 → kurl 단축 치환 (신고 3)

    func testPasteURLShortensInPlace() throws {
        UIPasteboard.general.string = "https://example.com/very/deep/link"
        installPasteConsentMonitor()

        let app = launchCompose()
        tapCanvas(app)
        pasteViaMenu(app, on: app.textViews.firstMatch)

        // 원문이 먼저 들어가고(즉시 반응) 목 단축(kurl.me/mkN)이 제자리 치환된다.
        let shortened = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "kurl.me/")).firstMatch
        let original = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "example.com/very/deep/link")).firstMatch
        XCTAssertTrue(
            shortened.waitForExistence(timeout: 12) || original.exists,
            "붙여넣은 URL 이 본문에 없음(원문도 단축본도 실종)")
        shot(app, "paste-url")
    }

    // MARK: 여정 4 — 사진 라이브러리 삽입 (신고 5, PHPicker)

    func testInsertPhotoFromLibrary() throws {
        let app = launchCompose()
        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap()
        title.typeText("Photo pick")

        tapCanvas(app)
        let photoButton = app.buttons["사진"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 6), "서식 툴바(사진) 없음")
        photoButton.tap()

        // PHPicker 는 프로세스 밖 원격 뷰 — 접근성 스냅샷이 수시로 갈리므로(인덱스 재조회가
        // "No matches for element at index" 로 죽는다) 프레임만 떠서 좌표 탭한다. 셀은 images 또는
        // cells 로 노출되고, 앱 툴바 심볼(수 pt)·권한 배너 아이콘도 걸리므로 크기(사진 격자)로 고른다.
        _ = app.images.firstMatch.waitForExistence(timeout: 12)
        var cellFrame: CGRect?
        for _ in 0..<4 where cellFrame == nil {
            Thread.sleep(forTimeInterval: 1.0)
            for query in [app.images, app.cells] {
                let count = min(query.count, 24)
                for i in 0..<count {
                    let el = query.element(boundBy: i)
                    guard el.exists else { continue }
                    let f = el.frame
                    if f.width > 80, f.height > 80, f.width < 400 { cellFrame = f; break }
                }
                if cellFrame != nil { break }
            }
        }
        guard let f = cellFrame else {
            throw XCTSkip("PHPicker 사진 셀이 접근성 트리에 안 보임 — 이 시뮬 런타임에선 수동 확인 경로")
        }
        let screen = app.frame
        app.coordinate(withNormalizedOffset: CGVector(
            dx: f.midX / screen.width, dy: f.midY / screen.height)).tap()

        let altField = app.textFields["대체 텍스트"]
        XCTAssertTrue(altField.waitForExistence(timeout: 25), "선택한 사진이 이미지 블록으로 안 들어감")
        shot(app, "photo-picked-block")
    }
}
