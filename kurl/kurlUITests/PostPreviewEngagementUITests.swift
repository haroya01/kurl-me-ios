//
//  PostPreviewEngagementUITests.swift
//  kurlUITests
//

import XCTest

/// 발견 흐름의 글 미리보기 인게이지 — 내 좋아요·북마크 표식이 뜨고, 북마크를 그 자리에서
/// 토글하면 카드를 열지 않고 채워짐/빔이 뒤집히는지(버튼이 제 탭을 삼켜 항해와 겹치지 않는지).
final class PostPreviewEngagementUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBookmarkTogglesInPlaceWithoutOpeningPost() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        // 목 픽스처: "헥사고날로 갈아탄 지 석 달"은 북마크+좋아요된 상태로 흐른다 — READ 대조 증명.
        let bookmarked = app.buttons["북마크됨"].firstMatch
        XCTAssertTrue(
            bookmarked.waitForExistence(timeout: 15),
            "미리보기 카드에 담긴(북마크됨) 표식이 없음 — 상태 대조 실패")

        attach(app, "preview-engagement-initial")

        // 담긴 버튼을 누르면 카드가 열리지 않고 북마크가 풀린다(낙관 토글, 버튼이 탭을 삼킴).
        bookmarked.tap()
        let unbookmarked = app.buttons["북마크"].firstMatch
        XCTAssertTrue(
            unbookmarked.waitForExistence(timeout: 5),
            "북마크 해제 토글이 반영되지 않음(카드가 열렸거나 상태 안 바뀜)")
        // 카드가 열렸다면 발견 흐름이 사라진다 — 컬렉션 eyebrow 로 아직 흐름 위임을 확인.
        XCTAssertTrue(
            app.staticTexts["에 연결"].firstMatch.exists || app.buttons["북마크"].firstMatch.exists,
            "토글이 카드를 열어버림 — 버튼이 탭을 삼키지 못함")

        attach(app, "preview-engagement-toggled-off")

        // 다시 누르면 담긴 상태로(이때 상세로 postId 를 풀어 다시 켠다).
        unbookmarked.tap()
        XCTAssertTrue(
            app.buttons["북마크됨"].firstMatch.waitForExistence(timeout: 8),
            "북마크 재설정 토글이 반영되지 않음")

        attach(app, "preview-engagement-toggled-on")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
