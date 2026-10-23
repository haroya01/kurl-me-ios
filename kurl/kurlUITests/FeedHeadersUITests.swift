//  홈 머리 — 가운데 [추천 · 팔로잉], 오른쪽 벨. 더 보기 칸은 로그인한 팔로잉에서만(리포스트 보기).
//  관리 항목은 메뉴가 아니라 서재·설정에 있다.
//

import XCTest

final class FeedHeadersUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %d OR elementType == %d)",
            label, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.switch.rawValue
        )).firstMatch
    }

    func testTheHomeHeaderIsForYouThenFollowingAndOnlyFollowingHasMore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()
        let forYou = app.buttons["segment.for-you"]
        let following = app.buttons["segment.following"]
        XCTAssertTrue(forYou.waitForExistence(timeout: 15), "홈 머리에 추천이 없음")
        XCTAssertTrue(following.exists, "홈 머리에 팔로잉이 없음")
        XCTAssertTrue(forYou.isSelected, "홈이 추천으로 열리지 않음")
        XCTAssertLessThan(forYou.frame.midX, following.frame.midX, "추천 · 팔로잉 순서가 아님")
        XCTAssertFalse(app.buttons["segment.trending"].exists, "인기 칸이 남아 있음")
        XCTAssertFalse(app.buttons["home.more"].exists, "추천에 더 보기 칸이 있음")
        let bell = app.buttons.matching(NSPredicate(format: "label == '알림'")).firstMatch
        XCTAssertTrue(bell.exists, "로그인했는데 벨이 없음")
        XCTAssertGreaterThan(bell.frame.minX, following.frame.maxX, "벨이 스위처 오른쪽에 있지 않음")
        shot("home-header-for-you")

        following.tap()
        let more = app.buttons["home.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "팔로잉에 더 보기 칸이 없음")
        more.tap()
        XCTAssertTrue(menuItem(app, "리포스트 보기").waitForExistence(timeout: 4), "팔로잉 더 보기에 리포스트 보기가 없음")
        XCTAssertFalse(menuItem(app, "추천").exists, "더 보기에 옛 블로그 추천이 남아 있음")
        shot("home-header-following-more")
    }

    func testSignedOutHomeHeaderHasNoBellAndNoMore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--screen", "none"]
        app.launch()
        let forYou = app.buttons["segment.for-you"]
        XCTAssertTrue(forYou.waitForExistence(timeout: 15), "홈 머리에 추천이 없음")
        XCTAssertTrue(forYou.isSelected, "비로그인 홈이 추천으로 열리지 않음")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == '알림'")).firstMatch.exists, "비로그인인데 벨이 있음")
        app.buttons["segment.following"].tap()
        XCTAssertFalse(app.buttons["home.more"].waitForExistence(timeout: 2), "비로그인 팔로잉에 더 보기 칸이 있음")
        shot("home-header-signed-out-following")
    }

    func testManagementLivesInTheLibraryAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let library = app.buttons["서재"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 15), "계정 탭에 서재가 없음")
        library.tap()
        for row in ["구독한 태그", "컬렉션"] {
            XCTAssertTrue(app.buttons[row].firstMatch.waitForExistence(timeout: 5), "서재에 \(row)이 없음")
        }
        shot("library")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()

        let gear = app.buttons["설정"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 6), "계정 탭에 설정이 없음")
        gear.tap()
        for (identifier, title) in [("settings.noteLists", "리스트"), ("settings.scheduledNotes", "예약한 노트")] {
            let row = app.buttons[identifier]
            var tries = 0
            while !row.isHittable, tries < 6 { app.swipeUp(); tries += 1 }
            XCTAssertTrue(row.isHittable, "설정 노트 칸에 \(title)이 없음")
            if identifier == "settings.noteLists" { shot("settings-notes") }
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 6), "설정의 \(title)이 \(title) 화면을 열지 않음")
            XCTAssertFalse(app.navigationBars[title].buttons["완료"].exists, "민 화면에 시트용 완료 버튼이 남아 있음")
            app.navigationBars[title].buttons["BackButton"].tap()
        }
    }
}
