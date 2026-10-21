import XCTest

final class FollowListRemoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFollowingMixesOtherServerAccountsAndOpensTheirAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let following = app.buttons["follow.following"]
        XCTAssertTrue(following.waitForExistence(timeout: 12), "프로필 팔로잉 링크가 없음")
        expectation(for: NSPredicate(format: "label CONTAINS '9'"), evaluatedWith: following)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(app.buttons["follow.followers"].label.contains("14"), app.buttons["follow.followers"].label)
        following.tap()

        let remote = app.buttons["remote.row.mina@mastodon.social"]
        XCTAssertTrue(remote.waitForExistence(timeout: 8), "팔로잉 목록에 다른 서버 계정이 없음")
        XCTAssertTrue(app.staticTexts["@mina@mastodon.social"].exists, "다른 서버 행에 @도메인이 없음")
        XCTAssertTrue(app.buttons["remote.follow.mina@mastodon.social"].label.contains("팔로잉"))
        XCTAssertLessThan(
            app.staticTexts["minji"].firstMatch.frame.minY, remote.frame.minY, "kurl 팔로우와 섞인 순서가 아님")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "following-mixed"
        shot.lifetime = .keepAlways
        add(shot)

        remote.tap()
        XCTAssertTrue(app.navigationBars["@mina@mastodon.social"].waitForExistence(timeout: 8), "다른 서버 계정 화면이 안 열림")
        XCTAssertTrue(
            app.staticTexts["mastodon.social에 있는 계정이에요. 이 계정의 새 노트가 팔로잉 피드에 와요."].waitForExistence(timeout: 8),
            "계정 화면이 그 계정을 불러오지 못함")
    }

    func testFollowersMixesOtherServerFollowersAndOpensTheirAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let followers = app.buttons["follow.followers"]
        XCTAssertTrue(followers.waitForExistence(timeout: 12), "프로필 팔로워 링크가 없음")
        expectation(for: NSPredicate(format: "label CONTAINS '14'"), evaluatedWith: followers)
        waitForExpectations(timeout: 6)
        followers.tap()

        let remote = app.buttons["remote.row.carol@fosstodon.org"]
        XCTAssertTrue(remote.waitForExistence(timeout: 8), "팔로워 목록에 다른 서버 계정이 없음")
        XCTAssertTrue(app.buttons["remote.row.haruto@misskey.io"].exists, "두 번째 다른 서버 팔로워가 없음")
        XCTAssertTrue(app.buttons["remote.follow.carol@fosstodon.org"].label.contains("팔로우"))

        remote.tap()
        XCTAssertTrue(app.navigationBars["@carol@fosstodon.org"].waitForExistence(timeout: 8), "다른 서버 계정 화면이 안 열림")
        XCTAssertTrue(
            app.staticTexts["fosstodon.org에 있는 계정이에요. 팔로우하면 fosstodon.org에 요청을 보내요."].waitForExistence(timeout: 8),
            "계정 화면이 그 계정을 불러오지 못함")
    }
}
