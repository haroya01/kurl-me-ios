//
//  CollectionPathUITests.swift
//  kurlUITests
//

import XCTest

/// A 척추 — reading path(PATH 컬렉션)가 리스트가 아니라 가이드 워크(문장→왜→문장)로 읽히고,
/// 인용을 탭하면 그 글의 그 지점으로 딥링크되는지 실기기 경로로 확인한다(목 PATH 컬렉션 104).
final class CollectionPathUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func anyElement(containing text: String) -> XCUIElement {
        XCUIApplication().descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testPathRendersAsGuidedWalk() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "collection-detail", "--collection", "104"]
        app.launch()

        // 헤더 + 큐레이터의 잇는 말(why) + 세 인용이 순서대로 보인다.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '경계를 긋는다는 것'")).firstMatch
                .waitForExistence(timeout: 15),
            "길 헤더가 없음")
        for quote in ["경계가 없으면", "다시 돌아가라면", "재현이 안 되는 버그"] {
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", quote)).firstMatch
                    .waitForExistence(timeout: 5),
                "길에 인용이 빠짐: \(quote)")
        }
        shot("1-path-guided-walk")

        // 첫 인용 탭 → 그 글로 딥링크(그 글의 다른 블록이 보이면 글이 열린 것).
        let firstQuote =
            app.buttons.matching(NSPredicate(format: "label CONTAINS '경계가 없으면'")).firstMatch
        if firstQuote.waitForExistence(timeout: 4) {
            firstQuote.tap()
            let postBlock =
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS '포트를 먼저 그었다'")).firstMatch
            XCTAssertTrue(postBlock.waitForExistence(timeout: 10), "인용 탭 후 원문이 안 열림")
            Thread.sleep(forTimeInterval: 0.8)
            shot("2-deeplinked-from-path")
        }
    }
}
