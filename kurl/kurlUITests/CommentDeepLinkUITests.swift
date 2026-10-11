//
//  CommentDeepLinkUITests.swift
//  kurlUITests
//

import XCTest

/// 댓글 알림을 누르면 그 댓글에 내려가 잠깐 비추고, 위쪽이 늦게 그려져도(엣지 섹션 등) 그 자리에 머문다.
final class CommentDeepLinkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(at commentId: Int, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"] + extra + [
            "--push",
            #"{"type":"COMMENT","actorUsername":"haruka","ownerUsername":"honggildong","postSlug":"hexagonal-after-3-months","commentId":\#(commentId)}"#,
        ]
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        let screen = app.windows.firstMatch.frame
        return !frame.isEmpty && frame.minY > screen.minY + 100 && frame.maxY < screen.maxY - 60
    }

    private func waitOnScreen(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isOnScreen(element, in: app) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// 화면 한 점의 색 — 스크린샷 픽셀(포인트 × 배율)에서 읽는다.
    private func color(at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { return (0, 0, 0) }
        let scale = CGFloat(cg.width) / image.size.width
        let x = Int(point.x * scale), y = Int(point.y * scale)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    /// 화면 안에 들어와 멈출 때까지(세 번 연달아 같은 자리) 기다리며, 그동안 본문 왼쪽 여백 색의 가장 짙은 값을 잰다.
    private func settle(
        _ reply: XCUIElement, text: XCUIElement, in app: XCUIApplication
    ) -> (landed: CGFloat?, darkest: Int) {
        let deadline = Date().addingTimeInterval(15)
        var darkest = 255
        var last: CGFloat?
        var steady = 0
        while Date() < deadline {
            if isOnScreen(reply, in: app) {
                if text.exists { darkest = min(darkest, color(at: CGPoint(x: text.frame.minX - 5, y: text.frame.midY)).r) }
                let y = reply.frame.minY
                steady = last.map { abs($0 - y) < 2 } == true ? steady + 1 : 0
                last = y
                if steady >= 2 { return (y, darkest) }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return (nil, darkest)
    }

    /// 내려가고, 3초 뒤에도 같은 자리(±40pt)에 남아 있고 비춤은 걷힌다. 비춤 자체는 1.3초뿐이라 부하에서 표본이
    /// 늦으면 못 잡는다 — 판정하지 않고 가장 짙은 값만 남긴다.
    private func land(on commentId: Int, body: String, _ extra: [String] = []) {
        let app = launch(at: commentId, extra)
        let reply = app.buttons["comment.reply.\(commentId)"]
        let text = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", body)).firstMatch
        let (landed, darkest) = settle(reply, text: text, in: app)
        attach("landed-\(commentId)")
        guard let landed else { return XCTFail("알림으로 연 댓글이 화면에 없음") }

        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(isOnScreen(reply, in: app), "위쪽이 늦게 그려지자 댓글이 화면 밖으로 밀림: \(reply.frame)")
        XCTAssertEqual(reply.frame.minY, landed, accuracy: 40, "위쪽이 늦게 그려지자 댓글 자리가 흘러감")
        let settled = color(at: CGPoint(x: text.frame.minX - 5, y: text.frame.midY))
        XCTAssertGreaterThan(settled.r, 245, "비춤이 사라지지 않음: \(settled)")
        attach("settled-\(commentId)")
        let note = XCTAttachment(string: "landing tint r=\(darkest)")
        note.lifetime = .keepAlways
        add(note)
    }

    func testACommentNotificationLandsOnTheFirstCommentAndStaysWhenEdgesArriveLate() throws {
        land(on: 501, body: "경계를 먼저 긋는다는", ["--slow-edges"])
    }

    /// 엣지가 1초 안정 창보다 늦게 와도(느린 망) 댓글은 제자리 — 엣지가 올 때까지는 자리를 놓지 않는다.
    func testACommentNotificationStaysPutWhenEdgesAreSlowerThanTheSettleWindow() throws {
        land(on: 501, body: "경계를 먼저 긋는다는", ["--slow-edges", "2.5"])
    }

    func testACommentNotificationLandsOnTheLastReplyAndStays() throws {
        land(on: 507, body: "@yuki_dev 저희도")
    }

    /// 내려간 뒤 손으로 스크롤하면 그 자리를 놓아준다 — 다시 끌어당기지 않는다.
    func testAManualScrollAfterLandingIsNotOverridden() throws {
        let app = launch(at: 501, ["--slow-edges"])
        let reply = app.buttons["comment.reply.501"]
        XCTAssertTrue(waitOnScreen(reply, in: app, timeout: 15), "알림으로 연 댓글이 화면에 없음")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(isOnScreen(reply, in: app), "위로 넘겼는데 댓글 자리로 다시 끌려 내려감")
    }
}
