//
//  FeedSwitcherLocalizationUITests.swift
//  kurlUITests
//

import UIKit
import XCTest

final class FeedSwitcherLocalizationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testKorean() { assertSwitcherFits(language: "ko", locale: "ko_KR") }
    func testJapanese() { assertSwitcherFits(language: "ja", locale: "ja_JP") }
    func testEnglish() { assertSwitcherFits(language: "en", locale: "en_US") }
    func testVietnamese() { assertSwitcherFits(language: "vi", locale: "vi_VN") }
    func testHindi() { assertSwitcherFits(language: "hi", locale: "hi_IN") }

    private func assertSwitcherFits(language: String, locale: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()

        let menu = app.buttons["segment.menu"]
        let segments = ["following", "recent", "trending"].map { app.buttons["segment.\($0)"] }
        let appeared = NSPredicate { _, _ in segments[0].exists || menu.exists }
        wait(for: [XCTNSPredicateExpectation(predicate: appeared, object: nil)], timeout: 12)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "feed-switcher-\(language)"
        shot.lifetime = .keepAlways
        add(shot)

        let screen = app.windows.firstMatch.frame
        if menu.exists {
            XCTAssertTrue(screen.contains(menu.frame), "\(language): 접힌 메뉴가 화면 밖 \(menu.frame)")
            return
        }
        for (index, segment) in segments.enumerated() {
            XCTAssertTrue(segment.exists, "\(language): 세그먼트 \(index) 이 없음")
            XCTAssertTrue(screen.contains(segment.frame), "\(language): \(segment.label) 이 화면 밖 \(segment.frame)")
            let font = UIFont.systemFont(ofSize: 14 * 0.86, weight: segment.isSelected ? .semibold : .medium)
            let needed = (segment.label as NSString).size(withAttributes: [.font: font]).width + 2 * 8
            XCTAssertGreaterThanOrEqual(
                segment.frame.width, needed.rounded(.down),
                "\(language): '\(segment.label)' 칸이 라벨보다 좁아 잘림 \(segment.frame)")
            XCTAssertEqual(segment.frame.height, segments[0].frame.height, accuracy: 0.5, "\(language): 세그먼트 높이가 다름")
            for other in segments.dropFirst(index + 1) {
                XCTAssertFalse(segment.frame.intersects(other.frame), "\(language): \(segment.label)·\(other.label) 겹침")
            }
        }
    }
}
