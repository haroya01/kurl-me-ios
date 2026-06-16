//
//  HighlightReaderUITests.swift
//  kurlUITests
//

import XCTest

/// 리더 소셜 하이라이트의 UI/UX 를 실기기 경로로 확인한다(simctl 은 터치를 못 넣으니 XCUITest 가 유일).
/// 시드 글 `hexagonal-after-3-months` 의 첫 문단엔 메모+답글이 달린 하이라이트(6001)와
/// 다중 블록 하이라이트(6002)가 미리 칠해져 있다. 흐름:
///  (1) 칠해진 하이라이트 렌더 → (2) 탭 → 답글 스레드 시트 → (3) 답글 작성 왕복 →
///  (4) 새 선택 → 편집 메뉴의 "하이라이트"/"메모" → 새 하이라이트 칠.
/// 좌표 탭/제스처가 어긋나도 단계별 스크린샷이 남도록 soft 하게 진행한다.
final class HighlightReaderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testReaderHighlightFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        // 본문 로드 대기 — 첫 문단(인용 문구 포함)을 가진 prose textView 를 찾는다.
        let quote = "돌아가라면"
        let paragraph = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", quote)).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "하이라이트가 칠해진 첫 문단을 못 찾음")
        Thread.sleep(forTimeInterval: 0.8)
        shot("1-highlights-painted")

        // (2) 칠해진 하이라이트("다시 돌아가라면 또 갈아탄다") 탭 → 답글 스레드.
        // 문구는 첫 줄 중반(offset 10~24)에 있다 — textView 상단 첫 줄 중앙을 친다.
        let onMark = paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.16))
        onMark.tap()

        let sendReply = app.buttons["답글 보내기"]
        let threadOpened = sendReply.waitForExistence(timeout: 6)
        if !threadOpened {
            // 첫 줄 위치 추정이 어긋났을 수 있다 — 한 줄 더 위/아래로 한 번 더 시도.
            paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            _ = sendReply.waitForExistence(timeout: 6)
        }
        Thread.sleep(forTimeInterval: 0.7)
        shot("2-thread-sheet")
        XCTAssertTrue(sendReply.exists, "하이라이트 탭으로 답글 스레드가 안 열림")

        // (3) 답글 작성 왕복 — 시트의 입력란(placeholder "답글 남기기…")에 한 줄 적고 보낸다.
        if sendReply.exists {
            let byPlaceholder = NSPredicate(format: "placeholderValue CONTAINS '답글 남기기'")
            var field = app.textViews.matching(byPlaceholder).firstMatch
            if !field.exists { field = app.textFields.matching(byPlaceholder).firstMatch }
            if field.waitForExistence(timeout: 3) {
                field.tap()
                field.typeText("실기기에서도 정확히 같은 위치에 칠해지네요. 확인했습니다.")
                Thread.sleep(forTimeInterval: 0.4)
                shot("3-reply-typed")
                if sendReply.isEnabled { sendReply.tap() }
                Thread.sleep(forTimeInterval: 0.9)
                shot("4-reply-sent")
            }
            // 시트 닫기 — 헤더의 "닫기" 버튼.
            let close = app.buttons["닫기"]
            if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
            Thread.sleep(forTimeInterval: 0.5)
        }

        // (4) 새 하이라이트 — 다른 문단의 단어를 더블탭 선택 → 편집 메뉴의 "하이라이트"/"메모".
        let secondParagraph = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "레이어드 구조로 3년을")).firstMatch
        if secondParagraph.waitForExistence(timeout: 5) {
            // 첫 줄 시작("레이어드 구조로 3년을")은 다중블록 하이라이트(6002)에 칠해져 있으니,
            // 칠 안 된 문단 중반을 더블탭해야 '단어 선택 → 편집 메뉴'가 뜬다.
            secondParagraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .doubleTap()
            Thread.sleep(forTimeInterval: 0.6)
            shot("5-selection-menu")

            // 편집 메뉴가 좁으면 커스텀 액션이 chevron(더 보기) 뒤에 있을 수 있다.
            let highlightItem = app.menuItems["하이라이트"]
            if !highlightItem.exists {
                let more = app.menuItems.matching(
                    NSPredicate(format: "label CONTAINS '더' OR label CONTAINS 'More'")).firstMatch
                if more.exists { more.tap(); Thread.sleep(forTimeInterval: 0.4) }
            }
            if highlightItem.waitForExistence(timeout: 3) {
                highlightItem.tap()
                Thread.sleep(forTimeInterval: 0.8)
                shot("6-new-highlight-painted")
            } else {
                shot("6-highlight-action-missing")
            }
        }
    }
}
