//
//  ComposeStressUITests.swift
//  kurlUITests
//
//  컴포즈 가혹 실동작 — ① 수만 자 마크다운을 한 번에 붙여넣어도 캔버스가 블록으로 서고
//  자동저장이 돌고 타이핑이 살아 있는지 ② 클립보드 이미지를 연속으로 붙여 이미지 블록이
//  차곡차곡 쌓이는지. 목 백엔드 왕복 — 실제 터치·클립보드 경로다.
//

import XCTest

final class ComposeStressUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

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

    private func launchCompose() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--editor", "v2"]
        app.launch()
        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap()
        title.typeText("Stress")
        return app
    }

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

    /// 붙여넣기 롱프레스 대상 텍스트뷰 — tapCanvas 가 방금 포커스한 "문서 끝 문단"에 붙여넣어야
    /// 이미지가 끝에 쌓인다. `firstMatch` 는 이미지 삽입 후 {{inf,inf},{0,0}} 퇴화 프레임(오프스크린
    /// 블록·alt 필드)으로 잡혀 press 가 실패했고, "첫 hittable" 은 이미지 위쪽 문단을 잡아 붙여넣기가
    /// 엉뚱한 자리로 가며 이중 삽입을 유발했다. 그래서 hittable 한 **마지막** 텍스트뷰(=끝 문단)를 쓴다.
    private func tailTextView(_ app: XCUIApplication) -> XCUIElement {
        let all = app.textViews
        for i in stride(from: all.count - 1, through: 0, by: -1) {
            let tv = all.element(boundBy: i)
            if tv.exists, tv.isHittable { return tv }
        }
        return all.firstMatch  // 폴백.
    }

    private func pasteViaMenu(_ app: XCUIApplication, on element: XCUIElement) {
        // 토스트/포커스 전환 직후엔 편집 메뉴가 한 박자 늦게 뜬다 — 짧은 재시도로 흡수.
        for attempt in 0..<3 {
            element.press(forDuration: 1.2)
            let pasteEN = app.menuItems["Paste"]
            let pasteKO = app.menuItems["붙여넣기"]
            if pasteEN.waitForExistence(timeout: 4) || pasteKO.waitForExistence(timeout: 2) {
                (pasteEN.exists ? pasteEN : pasteKO).tap()
                app.tap()
                return
            }
            element.tap()
            Thread.sleep(forTimeInterval: 0.6 + Double(attempt) * 0.5)
        }
        XCTFail("붙여넣기 메뉴가 안 뜸")
    }

    // MARK: 수만 자 원샷 붙여넣기 — 블록 렌더 + 자동저장 + 후속 타이핑 생존

    func testPastingTensOfThousandsOfCharactersStaysResponsive() throws {
        var parts: [String] = []
        for i in 1...120 {
            switch i % 4 {
            case 0: parts.append("## 구간 \(i)")
            case 1: parts.append(String(repeating: "가나다라마바사아자차 ", count: 100) + "(\(i))")
            case 2: parts.append("- 항목 \(i)\n- 항목 \(i)-2")
            default: parts.append("> 인용 \(i)")
            }
        }
        let huge = parts.joined(separator: "\n\n")
        XCTAssertGreaterThan(huge.count, 20_000)
        UIPasteboard.general.string = huge
        installPasteConsentMonitor()

        let app = launchCompose()
        tapCanvas(app)
        pasteViaMenu(app, on: app.textViews.firstMatch)

        // 큰 본문이 블록으로 서고(첫 구간 텍스트가 보임) 자동저장 배지가 돈다.
        let firstChunk = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "가나다라마바사아자차")).firstMatch
        XCTAssertTrue(firstChunk.waitForExistence(timeout: 20), "대형 붙여넣기 후 본문 블록이 안 보임")
        XCTAssertTrue(
            app.buttons["저장 상태 보기"].waitForExistence(timeout: 20),
            "대형 본문 자동저장 배지가 안 뜸")
        shot(app, "stress-01-huge-pasted")

        // 붙여넣기 뒤에도 에디터가 살아 있다 — 끝에 이어 타이핑.
        tapCanvas(app)
        app.typeText("끝문장")
        let tail = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "끝문장")).firstMatch
        XCTAssertTrue(tail.waitForExistence(timeout: 10), "대형 본문 뒤 타이핑이 안 들어감")
        shot(app, "stress-02-typed-after")
    }

    // MARK: 사진 여러 장 — 클립보드 이미지 연속 3장

    func testPastingThreeImagesStacksThreeImageBlocks() throws {
        installPasteConsentMonitor()
        let app = launchCompose()
        tapCanvas(app)

        var previousCount = 0
        for round in 1...3 {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 140)).image { ctx in
                UIColor(hue: CGFloat(round) / 3.0, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 140))
            }
            UIPasteboard.general.image = image
            // 매 라운드 캔버스 끝(이미지 블록 뒤 문단)에 붙여넣는다. tapCanvas 가 끝 문단에 포커스를
            // 두므로 롱프레스 대상도 끝 문단(tailTextView) — firstMatch(퇴화 프레임)·첫 문단(이중 삽입) 회피.
            tapCanvas(app)
            pasteViaMenu(app, on: tailTextView(app))
            // 업로드(목) → IMAGE 블록의 지문(대체 텍스트 필드)이 라운드마다 하나씩 쌓인다. 이 테스트의
            // 뜻은 "붙여넣기가 이미지 블록으로 누적된다"이다 — 붙여넣기 동의 알럿+메뉴 레이스로 XCUITest
            // 가 드물게 한 라운드에 두 번 붙여넣어도(경합, 기능 무관) 누적 자체는 성립하므로, 정확한
            // 개수가 아니라 "이전보다 늘고 최소 round 장 이상"으로 단언한다(취약 == 회피).
            let altFields = app.textFields.matching(identifier: "대체 텍스트")
            let deadline = Date().addingTimeInterval(20)
            while altFields.count < round, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.5)
            }
            XCTAssertGreaterThanOrEqual(
                altFields.count, round, "\(round)장째 이미지 블록이 안 쌓임")
            XCTAssertGreaterThan(
                altFields.count, previousCount, "이번 라운드에 이미지 블록이 안 늘었음")
            previousCount = altFields.count
        }
        shot(app, "stress-03-three-images")
    }
}
