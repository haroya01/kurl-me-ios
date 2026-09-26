import XCTest

final class PushTapRouteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(push json: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--push", json]
        app.launch()
        return app
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLikePushOpensThePostAndBackGoesToInbox() throws {
        let app = launch(push: #"{"type":"LIKE","actorUsername":"reader_kim","ownerUsername":"honggildong","postSlug":"p-mock-2"}"#)
        let readingTime = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '읽는 시간'")).firstMatch
        XCTAssertTrue(readingTime.waitForExistence(timeout: 15), "좋아요 푸시를 누르면 그 글이 열려야 함")
        let like = app.buttons["좋아요"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 8), "푸시로 연 글에도 좋아요·북마크 독이 있어야 함")
        XCTAssertTrue(like.isHittable, "푸시로 연 글의 독이 화면 안에서 눌려야 함")
        shoot("push-like-opens-post")
        app.buttons["뒤로"].firstMatch.tap()
        XCTAssertTrue(app.buttons["모두 읽음"].firstMatch.waitForExistence(timeout: 10), "뒤로 가면 알림함이어야 함")
        shoot("push-back-to-inbox")
    }

    func testFollowPushOpensTheProfile() throws {
        let app = launch(push: #"{"type":"FOLLOW","actorUsername":"stranger99"}"#)
        XCTAssertTrue(app.buttons["팔로우"].firstMatch.waitForExistence(timeout: 15), "팔로우 푸시를 누르면 그 사람 프로필이 열려야 함")
        shoot("push-follow-opens-profile")
    }

    func testLegacyPushStillOpensInbox() throws {
        let app = launch(push: #"{"aps":{"alert":{"body":"좋아합니다"}}}"#)
        XCTAssertTrue(app.buttons["모두 읽음"].firstMatch.waitForExistence(timeout: 15), "목적지 없는 푸시는 알림함으로")
    }
}
