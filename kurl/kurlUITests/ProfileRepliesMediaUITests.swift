//
//  ProfileRepliesMediaUITests.swift
//  kurlUITests
//

import XCTest

/// 프로필의 답글·미디어 탭 — 탭 순서, 답글의 머리 줄과 원래 글로 가기, 미디어 칸의 가림·장수와 노트로 가기(목).
final class ProfileRepliesMediaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func launch(author: String, language: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--author", author]
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        }
        app.launch()
        return app
    }

    private func text(_ app: XCUIApplication, containing value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    func testRepliesSitAfterNotesAndSayWhatEachAnswered() throws {
        let app = launch(author: "reader_kim")
        let notes = app.buttons["author.tab.notes"]
        let replies = app.buttons["author.tab.replies"]
        let media = app.buttons["author.tab.media"]
        let reposts = app.buttons["author.tab.reposts"]
        XCTAssertTrue(replies.waitForExistence(timeout: 15), "프로필에 답글 탭이 없음")
        XCTAssertTrue(media.exists, "프로필에 미디어 탭이 없음")
        XCTAssertLessThan(notes.frame.minX, replies.frame.minX)
        XCTAssertLessThan(replies.frame.minX, media.frame.minX)
        XCTAssertLessThan(media.frame.minX, reposts.frame.minX)

        replies.tap()
        let answered = app.buttons["profile.reply.context.9501"]
        XCTAssertTrue(answered.waitForExistence(timeout: 5), "답글 위에 원래 글 줄이 없음")
        XCTAssertTrue(answered.label.contains("@yuki_dev 님에게 답글"), answered.label)
        XCTAssertTrue(answered.label.contains("헥사고날 포트"), answered.label)
        XCTAssertTrue(
            app.descendants(matching: .any)["profile.reply.context.unavailable"].exists,
            "원래 글이 사라진 답글에 볼 수 없다는 줄이 없음")
        XCTAssertTrue(text(app, containing: "지금은 사라진 노트에 남겼던 답글").exists)
        shot("1-replies-tab")

        answered.tap()
        XCTAssertTrue(
            text(app, containing: "이름이 곧 경계라는 걸 다시 배운다").waitForExistence(timeout: 10),
            "원래 글 줄을 눌러 그 노트로 가지 못함")
        shot("2-parent-note")
    }

    func testTheTabStripKeepsTheChosenTabInViewWhenItOverflows() throws {
        let app = launch(author: "reader_kim", language: "ja")
        let replies = app.buttons["author.tab.replies"]
        XCTAssertTrue(replies.waitForExistence(timeout: 15), "프로필에 답글 탭이 없음")
        replies.tap()
        XCTAssertTrue(app.buttons["profile.reply.context.9501"].waitForExistence(timeout: 5))
        shot("ja-replies")
        app.buttons["author.tab.media"].tap()
        shot("ja-media")

        let last = app.buttons["author.tab.collections"]
        let window = app.windows.firstMatch.frame
        for _ in 0..<4 where !last.isSelected {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.75)))
        }
        XCTAssertTrue(last.isSelected, "옆으로 밀어 마지막 탭까지 가지 못함")
        XCTAssertTrue(last.isHittable, "고른 탭이 탭 줄 밖에 남음")
        XCTAssertLessThanOrEqual(last.frame.maxX, window.maxX)
        shot("ja-last-tab")
    }

    func testMediaGridHidesSensitivePhotosAndOpensTheNote() throws {
        let app = launch(author: "yuki_dev")
        let tab = app.buttons["author.tab.media"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "프로필에 미디어 탭이 없음")
        tab.tap()

        let cell = app.buttons["profile.media.9507"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "사진 붙인 노트의 칸이 없음")
        XCTAssertTrue(cell.label.contains("민감한 사진"), cell.label)
        shot("3-media-sensitive")

        cell.tap()
        XCTAssertTrue(
            text(app, containing: "수술 끝나고 꿰맨 자리").waitForExistence(timeout: 10),
            "칸을 눌러 노트로 가지 못함")
    }

    func testMediaGridCountsPhotosOfANoteWithSeveral() throws {
        let app = launch(author: "honggildong")
        let tab = app.buttons["author.tab.media"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "프로필에 미디어 탭이 없음")
        tab.tap()

        let cell = app.buttons["profile.media.9504"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "사진 세 장 노트의 칸이 없음")
        XCTAssertTrue(cell.label.contains("비 오는 창밖"), cell.label)
        XCTAssertTrue(cell.label.contains("3"), cell.label)
        XCTAssertFalse(cell.label.contains("민감한 사진"), cell.label)
        shot("4-media-count")

        cell.tap()
        XCTAssertTrue(
            text(app, containing: "창밖 사진 세 장").waitForExistence(timeout: 10),
            "칸을 눌러 노트로 가지 못함")
    }
}
