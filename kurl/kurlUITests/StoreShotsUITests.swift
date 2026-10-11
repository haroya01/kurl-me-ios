//
//  StoreShotsUITests.swift
//  kurlUITests
//

import XCTest

final class StoreShotsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testStoreShots_ko() { run("ko", "ko_KR") }
    func testStoreShots_en() { run("en", "en_US") }
    func testStoreShots_ja() { run("ja", "ja_JP") }

    private var lang = "ko"
    private var locale = "ko_KR"

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--store-demo"] + args
            + ["-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
        app.launch()
        return app
    }

    private func settle(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(lang)~\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func run(_ lang: String, _ locale: String) {
        self.lang = lang
        self.locale = locale
        feed()
        collection()
        reader()
        conversation()
        notes()
        editor()
        profile()
    }

    private func reader() {
        let app = launch(["--post", "hayoung/walking-pace"])
        let body = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "빨리 읽은 글은")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 15), "\(lang): 글 본문이 안 뜸")
        settle(3)
        shot("1-reader")
        app.terminate()
    }

    private func notes() {
        let app = launch(["--tab", "notes"])
        XCTAssertTrue(app.buttons["note.menu.9701"].waitForExistence(timeout: 15), "\(lang): 노트 피드가 안 뜸")
        settle(3)
        shot("2-notes")
        app.terminate()
    }

    private func editor() {
        let app = launch(["--tab", "write"])
        let draft = element(app, containing: "늦가을 아침 산책")
        XCTAssertTrue(draft.waitForExistence(timeout: 15), "\(lang): 스튜디오에 초안이 없음")
        draft.tap()
        XCTAssertTrue(app.buttons["composeFormat"].waitForExistence(timeout: 10), "\(lang): 편집기가 안 열림")
        settle(3)
        shot("3-editor")
        app.terminate()
    }

    private func feed() {
        let app = launch([])
        XCTAssertTrue(element(app, containing: "걷는 속도로 읽기").waitForExistence(timeout: 15), "\(lang): 피드가 안 뜸")
        settle(3)
        shot("4-feed")
        app.terminate()
    }

    private func collection() {
        let app = launch([])
        let row = app.descendants(matching: .any)["feed.connection.31"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "\(lang): 피드에 연결 행이 없음")
        let link = row.buttons.matching(NSPredicate(format: "label CONTAINS %@", "천천히 읽기 입문")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 4), "\(lang): 연결 행에 길 링크가 없음")
        link.tap()
        XCTAssertTrue(element(app, containing: "처음 오는 분께").waitForExistence(timeout: 10), "\(lang): 길이 안 열림")
        settle(2)
        shot("5-collection")
        app.terminate()
    }

    private func conversation() {
        let app = launch(["--post", "hayoung/walking-pace"])
        let paragraph = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "긋는 동안")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "\(lang): 하이라이트 문단이 없음")
        settle(1.5)
        let card = app.otherElements["highlightCard"]
        for offset in [CGVector(dx: 0.55, dy: 0.45), CGVector(dx: 0.3, dy: 0.55), CGVector(dx: 0.7, dy: 0.35)] {
            paragraph.coordinate(withNormalizedOffset: offset).tap()
            if card.waitForExistence(timeout: 3) { break }
        }
        let entry = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'highlightCard.conversation' OR identifier == 'highlightCard.talk'"
        )).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 4), "\(lang): 하이라이트 카드가 안 뜸")
        entry.tap()
        XCTAssertTrue(app.buttons["highlightReply.like.7201"].waitForExistence(timeout: 8), "\(lang): 대화가 안 열림")
        settle(2)
        shot("6-conversation")
        app.terminate()
    }

    private func profile() {
        let app = launch(["--tab", "account"])
        XCTAssertTrue(element(app, containing: "honggildong").waitForExistence(timeout: 15), "\(lang): 프로필이 안 뜸")
        settle(2)
        shot("7-profile")
        app.terminate()
    }
}
