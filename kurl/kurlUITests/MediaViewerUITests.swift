import XCTest

final class MediaViewerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        XCTAssertTrue(app.buttons["segment.for-you"].waitForExistence(timeout: 12), "홈이 열리지 않음")
        return app
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func element(_ app: XCUIApplication, label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func onScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        let screen = app.windows.firstMatch.frame
        let frame = element.frame
        return element.exists && !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5) && element.isHittable, "\(element) 까지 내려가지 못함")
    }

    private func waitSelected(_ element: XCUIElement, _ selected: Bool, _ message: String) {
        expectation(for: NSPredicate(format: "selected == %@", NSNumber(value: selected)), evaluatedWith: element)
        waitForExpectations(timeout: 6)
        XCTAssertEqual(element.isSelected, selected, message)
    }

    private func openFirstPhoto(_ app: XCUIApplication) -> XCUIElement {
        let tile = element(app, label: "비 오는 창밖")
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "사진 노트의 첫 사진 타일이 없음")
        tile.tap()
        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 6), "사진을 눌러도 뷰어가 열리지 않음")
        return close
    }

    func testThePhotoViewerClosesFromTheTopLeftPagesAndSharesTheLikeWithTheFeed() throws {
        let app = launch()
        let rowLike = app.buttons["note.like.9504"]
        scrollTo(app, rowLike)
        XCTAssertFalse(rowLike.isSelected, "목 데이터에서 이 노트는 아직 좋아요 전이어야 함")

        let close = openFirstPhoto(app)
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(close.frame.midX, window.midX / 2, "닫기가 왼쪽 위에 있지 않음")
        XCTAssertLessThan(close.frame.midY, window.height / 4, "닫기가 왼쪽 위에 있지 않음")
        shoot("viewer-photo")

        let viewerLike = app.buttons["viewer.like"]
        XCTAssertTrue(viewerLike.waitForExistence(timeout: 4), "뷰어에 노트 반응 줄이 없음")
        XCTAssertFalse(viewerLike.isSelected, "피드에서 안 누른 좋아요가 뷰어에서 눌려 있음")
        XCTAssertTrue(app.buttons["viewer.reply"].exists, "뷰어에 답글이 없음")
        XCTAssertTrue(app.buttons["viewer.repost"].exists, "뷰어에 리포스트가 없음")
        XCTAssertTrue(app.buttons["viewer.share"].exists, "뷰어에 공유가 없음")
        viewerLike.tap()
        waitSelected(viewerLike, true, "뷰어에서 누른 좋아요가 켜지지 않음")

        let second = element(app, label: "젖은 골목")
        XCTAssertFalse(onScreen(app, second), "둘째 사진이 넘기기 전부터 화면에 있음")
        app.swipeLeft()
        let paged = NSPredicate { _, _ in self.onScreen(app, second) }
        expectation(for: paged, evaluatedWith: second)
        waitForExpectations(timeout: 6)
        shoot("viewer-photo-paged")

        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 4), "닫기를 눌러도 뷰어가 남음")
        waitSelected(rowLike, true, "뷰어에서 누른 좋아요가 피드 행에 반영되지 않음")
        shoot("feed-row-after-viewer-like")

        rowLike.tap()
        waitSelected(rowLike, false, "피드 행에서 좋아요를 끄지 못함")
        _ = openFirstPhoto(app)
        waitSelected(app.buttons["viewer.like"], false, "피드에서 끈 좋아요가 뷰어에 켜진 채로 남음")

        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["viewer.close"].waitForNonExistence(timeout: 4), "아래로 끌어도 뷰어가 닫히지 않음")
    }

    func testAVideoOpensWithItsOwnControlsAndAFullScreenPill() throws {
        let app = launch()
        let following = app.buttons["팔로잉"].firstMatch
        XCTAssertTrue(following.waitForExistence(timeout: 8), "팔로잉 피드가 없음")
        following.tap()
        let remote = app.buttons["note.menu.9600"]
        for _ in 0..<6 where !remote.exists {
            app.swipeUp()
        }
        let author = app.buttons.matching(NSPredicate(format: "label CONTAINS '@mina@mastodon.social'")).firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 6), "팔로잉에 다른 서버 노트가 없음")
        author.tap()

        let video = app.buttons["note.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 8), "계정 화면에 동영상 타일이 없음")
        video.tap()

        let close = app.buttons["viewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 6), "동영상 뷰어가 열리지 않음")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(close.frame.midX, window.midX / 2, "닫기가 왼쪽 위에 있지 않음")
        XCTAssertTrue(app.buttons["viewer.play"].waitForExistence(timeout: 6), "재생·일시 정지 버튼이 없음")
        let scrubber = app.sliders["viewer.scrubber"]
        XCTAssertTrue(scrubber.exists, "재생 위치 막대가 없음")
        XCTAssertEqual(scrubber.label, "재생 위치")
        XCTAssertTrue(app.buttons["viewer.like"].exists, "동영상 뷰어에 노트 반응 줄이 없음")
        shoot("viewer-video")

        let pill = app.buttons["viewer.fullScreen"]
        XCTAssertTrue(pill.exists, "가로 동영상 아래 전체 화면 버튼이 없음")
        pill.tap()
        let wide = NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }
        expectation(for: wide, evaluatedWith: app)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(app.buttons["viewer.exitFullScreen"].waitForExistence(timeout: 4), "가로 화면에 전체 화면 끝내기가 없음")
        shoot("viewer-video-landscape")

        app.buttons["viewer.exitFullScreen"].tap()
        let tall = NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.height > frame.width
        }
        expectation(for: tall, evaluatedWith: app)
        waitForExpectations(timeout: 6)

        app.buttons["viewer.close"].tap()
        XCTAssertTrue(app.buttons["viewer.close"].waitForNonExistence(timeout: 4), "닫기를 눌러도 동영상 뷰어가 남음")
    }
}
