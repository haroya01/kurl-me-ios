//
//  AuthorHeaderLocalizationUITests.swift
//  kurlUITests
//

import XCTest

final class AuthorHeaderLocalizationUITests: XCTestCase {

    private let languages = [
        ("ko", "ko_KR"), ("ja", "ja_JP"), ("en", "en_US"), ("vi", "vi_VN"), ("hi", "hi_IN"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOtherAuthorHeaderFitsEveryLanguage() {
        for (language, locale) in languages {
            let app = launch(["--author", "yuki_dev"], language: language, locale: locale)
            assertFits(
                app, language: language, name: "other",
                ids: ["follow.button", "follow.bell", "follow.followers", "follow.following", "author.card"])
            let follow = app.buttons["follow.button"].frame
            let bell = app.buttons["follow.bell"].frame
            XCTAssertLessThanOrEqual(follow.height, bell.height + 2, "\(language): 팔로우 버튼 라벨이 두 줄 \(follow)")
        }
    }

    func testOwnHeaderWithCountsFitsEveryLanguage() {
        for (language, locale) in languages {
            let app = launch(["--tab", "account"], language: language, locale: locale)
            assertFits(app, language: language, name: "own", ids: ["follow.followers", "follow.following", "author.card"])
        }
    }

    private func launch(_ arguments: [String], language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"] + arguments + ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        return app
    }

    private func assertFits(_ app: XCUIApplication, language: String, name: String, ids: [String]) {
        let items = ids.map { ($0, app.buttons[$0]) }
        for (id, element) in items {
            XCTAssertTrue(element.waitForExistence(timeout: 12), "\(language): \(id) 이 없음")
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "author-header-\(name)-\(language)"
        shot.lifetime = .keepAlways
        add(shot)

        let screen = app.windows.firstMatch.frame
        for (index, (id, element)) in items.enumerated() {
            XCTAssertTrue(screen.contains(element.frame), "\(language): \(id) 이 화면 밖으로 나감 \(element.frame)")
            for (other, otherElement) in items.dropFirst(index + 1) {
                XCTAssertFalse(
                    element.frame.intersects(otherElement.frame),
                    "\(language): \(id) \(element.frame) 와 \(other) \(otherElement.frame) 가 겹침")
            }
        }
        for id in ["follow.followers", "follow.following"] {
            let frame = app.buttons[id].frame
            XCTAssertLessThan(frame.height, 24, "\(language): \(id) 링크가 두 줄 \(frame)")
        }
    }
}
