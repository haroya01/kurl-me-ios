//
//  StoreShotsUITests.swift
//  kurlUITests
//

import XCTest

final class StoreShotsUITests: XCTestCase {

    private struct Anchors {
        let author: String
        let feedTitle: String
        let body: String
        let highlighted: String
        let draft: String
        let path: String
        let pathIntro: String
    }

    private static let anchors: [String: Anchors] = [
        "ko": Anchors(
            author: "hayoung", feedTitle: "걷는 속도로 읽기", body: "빨리 읽은 글은", highlighted: "긋는 동안",
            draft: "늦가을 아침 산책", path: "천천히 읽기 입문", pathIntro: "처음 오는 분께"),
        "en": Anchors(
            author: "clara", feedTitle: "Reading at walking pace", body: "What you read fast",
            highlighted: "drawing the line", draft: "A late autumn morning walk", path: "A slow reading starter",
            pathIntro: "The order I suggest"),
        "ja": Anchors(
            author: "haruka_walks", feedTitle: "歩く速さで読む", body: "速く読んだ文章は", highlighted: "線を引くあいだに",
            draft: "晩秋の朝の散歩", path: "ゆっくり読む入門", pathIntro: "初めての人に"),
        "vi": Anchors(
            author: "lan", feedTitle: "Đọc theo nhịp bước chân", body: "Đọc nhanh thì quên", highlighted: "trong lúc tô",
            draft: "Buổi sáng cuối thu đi dạo", path: "Nhập môn đọc chậm", pathIntro: "Thứ tự mình gợi ý"),
        "hi": Anchors(
            author: "ananya", feedTitle: "क़दमों की रफ़्तार से पढ़ना", body: "जल्दी पढ़ा हुआ", highlighted: "रेखा खींचते हुए",
            draft: "पतझड़ के आख़िर की एक सुबह", path: "धीरे पढ़ने की शुरुआत", pathIntro: "पहली बार आने वालों"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testStoreShots_ko() { run("ko", "ko_KR") }
    func testStoreShots_en() { run("en", "en_US") }
    func testStoreShots_ja() { run("ja", "ja_JP") }
    func testStoreShots_vi() { run("vi", "vi_VN") }
    func testStoreShots_hi() { run("hi", "hi_IN") }

    private var lang = "ko"
    private var locale = "ko_KR"
    private var anchors: Anchors { Self.anchors[lang] ?? Self.anchors["en"]! }

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

    private func paragraph(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.textViews.containing(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
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
    }

    private func reader() {
        let app = launch(["--post", "\(anchors.author)/walking-pace"])
        XCTAssertTrue(paragraph(app, containing: anchors.body).waitForExistence(timeout: 15), "\(lang): 글 본문이 안 뜸")
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
        let app = launch(["--tab", "write", "--reset-recovery"])
        let draft = element(app, containing: anchors.draft)
        XCTAssertTrue(draft.waitForExistence(timeout: 15), "\(lang): 스튜디오에 초안이 없음")
        draft.tap()
        XCTAssertTrue(app.buttons["composeFormat"].waitForExistence(timeout: 10), "\(lang): 편집기가 안 열림")
        settle(3)
        shot("3-editor")
        app.terminate()
    }

    private func feed() {
        let app = launch([])
        XCTAssertTrue(element(app, containing: anchors.feedTitle).waitForExistence(timeout: 15), "\(lang): 피드가 안 뜸")
        settle(3)
        shot("4-feed")
        app.terminate()
    }

    private func collection() {
        let app = launch([])
        let row = app.descendants(matching: .any)["feed.connection.31"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "\(lang): 피드에 연결 행이 없음")
        let link = row.buttons.matching(NSPredicate(format: "label CONTAINS %@", anchors.path)).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 4), "\(lang): 연결 행에 길 링크가 없음")
        link.tap()
        XCTAssertTrue(element(app, containing: anchors.pathIntro).waitForExistence(timeout: 10), "\(lang): 길이 안 열림")
        settle(2)
        shot("5-collection")
        app.terminate()
    }

    private func conversation() {
        let app = launch(["--post", "\(anchors.author)/walking-pace"])
        let marked = paragraph(app, containing: anchors.highlighted)
        XCTAssertTrue(marked.waitForExistence(timeout: 15), "\(lang): 하이라이트 문단이 없음")
        settle(1.5)
        let card = app.otherElements["highlightCard"]
        search: for dy in [0.45, 0.3, 0.6, 0.15, 0.75, 0.9] {
            for dx in [0.5, 0.25, 0.75] {
                marked.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
                if card.waitForExistence(timeout: 1.5) { break search }
            }
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
}
