//
//  WriteV2IntegrationUITests.swift
//  kurlUITests
//

import XCTest

/// WriteV2(WYSIWYG 블록 에디터)를 `--editor v2` 플래그로 켠 실제 글쓰기 경로 검증.
/// 플래그 OFF 는 기존 Compose* 테스트가 커버(현행 MarkdownTextView 회귀 0). 여기선 ON 경로만:
///  1) 기존 글을 열면 서버 마크다운이 블록으로 파싱·렌더된다(제목 마커 `#` 없이 최종 모습).
///  2) 편집(캔버스 이어쓰기) → 저장 → 저장됨 배지(마크다운 계약으로 왕복 저장, mock 백엔드 PUT/GET).
/// simctl 은 키보드를 못 넣으니 XCUITest 가 유일한 실동작 경로다. 기존 글 로드를 쓰는 이유는
/// 타이핑 없이 파싱→렌더를 결정적으로 검증하고(줄머리 지름길의 IME 타이밍에 의존하지 않는다),
/// 이어 편집·저장으로 직렬화 왕복까지 덮기 위함이다.
final class WriteV2IntegrationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testWriteV2LoadsRendersEditsAndSaves() throws {
        let app = XCUIApplication()
        // --editor v2 = WriteV2 옵트인. 스튜디오 목록에서 기존 초안을 탭해 편집으로 진입한다.
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()

        // mock 초안 "목 초안 — 헥사고날 정리"(markdown: `# 헥사고날\n\n포트와 어댑터.`)를 연다.
        let draftRow = app.staticTexts["목 초안 — 헥사고날 정리"]
        XCTAssertTrue(draftRow.waitForExistence(timeout: 15), "스튜디오에 mock 초안이 안 보임")
        draftRow.tap()

        // 1) 로드→파싱→렌더: 제목 블록이 마커(`#`) 없이 "헥사고날"로, 문단이 "포트와 어댑터."로 렌더.
        let heading = app.textViews.containing(
            NSPredicate(format: "value == %@", "헥사고날")).firstMatch
        XCTAssertTrue(
            heading.waitForExistence(timeout: 12),
            "제목 블록이 마커 없이 렌더되지 않음 — 마크다운→블록 파싱/렌더 실패")
        let paragraph = app.textViews.containing(
            NSPredicate(format: "value == %@", "포트와 어댑터.")).firstMatch
        XCTAssertTrue(paragraph.exists, "문단 블록 렌더 실패")
        Thread.sleep(forTimeInterval: 0.5)
        shot("writev2-loaded-rendered")

        // 2) 편집: 문단 끝에 이어 쓴다(블록 텍스트뷰 직접 편집 → document → markdown 동기화).
        paragraph.tap()
        // 캐럿을 끝으로 보내려 한 번 더 탭(짧은 텍스트라 끝 근처). 이어서 타이핑.
        paragraph.typeText(" 그리고 경계.")
        Thread.sleep(forTimeInterval: 0.6)
        shot("writev2-edited")

        // 3) 저장 → 마크다운 계약으로 mock 백엔드에 왕복 저장. 저장됨 배지(체크)로 성공 확인.
        let save = app.buttons["저장"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "저장 버튼 없음")
        save.tap()

        let statusBadge = app.buttons["저장 상태 보기"]
        XCTAssertTrue(
            statusBadge.waitForExistence(timeout: 12),
            "저장됨 배지 안 뜸 — WriteV2 편집분의 마크다운 왕복 저장 실패 의심")
        Thread.sleep(forTimeInterval: 0.6)
        shot("writev2-saved")
    }
}
