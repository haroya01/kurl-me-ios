//
//  ReaderChromeSlideUITests.swift
//  kurlUITests
//

import XCTest

/// 글 상세 커스텀 상단 크롬(뒤로·제목·⋯) — 스크롤 다운에 접히고 업에 돌아오는지,
/// 복귀한 뒤로가 실제 pop 하는지. 시스템 내비바 토글(워치독 0x8BADF00D 근원)을
/// 오버레이 바로 바꾼 구조의 회귀 가드.
///
/// ⚠️ 진입은 피드에서 탭으로 — `--post` 직진입 하네스는 탭 구조 밖이라
/// tabBarVisibility env 가 nil 이고, 크롬 숨김 신호가 영영 오지 않는다(실측).
final class ReaderChromeSlideUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChromeSlidesWithScrollAndPops() throws {
        let app = XCUIApplication()
        // --longpost = 본문 40배 — 두 번의 스와이프가 바닥(러버밴드)에 닿지 않게 길이를 보장.
        app.launchArguments = ["--mocks", "--longpost"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "런치 실패")

        // 이 제목은 추천(for-you) 피드 첫 항목 — 최신 피드엔 없다(ReadingStress 가
        // 조용히 skip 하던 함정). 추천 탭으로 건너가 첫 카드로 결정적으로 진입한다.
        let forYou = app.buttons["추천"].firstMatch
        XCTAssertTrue(forYou.waitForExistence(timeout: 10), "피드 상단 추천 탭이 없음")
        forYou.tap()
        XCTAssertTrue(
            openFromFeed(app, title: "헥사고날로 갈아탄 지 석 달, 무엇이 남았나"),
            "피드에서 글 상세로 못 들어감")

        let back = app.buttons["뒤로"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 8), "상세 진입 후 커스텀 뒤로 버튼이 없음")
        XCTAssertTrue(back.isHittable, "진입 직후 뒤로 버튼이 눌리지 않음")
        attach("1-top-discs-only")

        // 아래로 읽어 내려가면 크롬이 접힌다 — 하단 탭바와 같은 판정(isHittable).
        app.swipeUp()
        app.swipeUp()
        expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: back)
        waitForExpectations(timeout: 5)
        attach("2-chrome-hidden")

        // 위로 되돌리면 크롬이 같은 결로 돌아온다.
        app.swipeDown()
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: back)
        waitForExpectations(timeout: 5)
        attach("3-chrome-returned-title-spilled")

        // 복귀한 뒤로가 실제로 pop 한다 — 상세가 닫히면 버튼 자체가 사라진다.
        back.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: back)
        waitForExpectations(timeout: 5)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 피드에서 제목을 찾아 연다(ReadingStress 와 같은 문법) — 진입 확인은 인게이지 독.
    /// 큰 스와이프가 카드를 지나칠 수 있어, 못 찾으면 위쪽으로 짧게 되짚는다.
    private func openFromFeed(_ app: XCUIApplication, title: String) -> Bool {
        let target = app.staticTexts[title].firstMatch
        _ = target.waitForExistence(timeout: 8)
        for _ in 0..<10 {
            if target.exists, target.isHittable { break }
            app.swipeUp()
        }
        if !(target.exists && target.isHittable) {
            // 위쪽에 있을 수도 — 화면 중간에서 짧게 끌어올려(리프레시 트리거 없이) 되짚는다.
            for _ in 0..<10 where !(target.exists && target.isHittable) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                    .press(forDuration: 0.05,
                           thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
            }
        }
        guard target.exists, target.isHittable else { return false }
        target.tap()
        let dock = app.buttons["컬렉션에 연결"].firstMatch
        return dock.waitForExistence(timeout: 8)
    }
}
