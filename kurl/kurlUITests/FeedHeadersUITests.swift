//
//  FeedHeadersUITests.swift
//  kurlUITests
//
//  블로그·노트 피드 머리는 같은 골격이다 — 왼쪽 피드 더 보기, 가운데 [팔로잉 · 최신 · 인기], 오른쪽 벨.
//  두 탭에서 같은 자리·같은 크기로 서고, 비로그인이면 최신으로 열린다.
//

import XCTest

final class FeedHeadersUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private let segments = ["팔로잉", "최신", "인기"]

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private struct Header {
        let more: CGRect
        let segments: [CGRect]
        let bell: CGRect?
    }

    /// 두 탭 루트가 함께 상주해 같은 라벨이 둘 잡힌다 — 지금 화면에서 눌리는 쪽만 고른다.
    private func onScreen(_ query: XCUIElementQuery) -> XCUIElement? {
        query.allElementsBoundByIndex.first { $0.isHittable }
    }

    private func button(_ app: XCUIApplication, _ label: String) -> XCUIElement? {
        _ = app.buttons[label].firstMatch.waitForExistence(timeout: 5)
        return onScreen(app.buttons.matching(NSPredicate(format: "label == %@", label)))
    }

    private func header(_ app: XCUIApplication, more identifier: String, signedIn: Bool) -> Header {
        let more = app.buttons[identifier]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "\(identifier) 더 보기 버튼이 없음")
        let items = segments.compactMap { button(app, $0) }
        XCTAssertEqual(items.count, segments.count, "머리 스위처에 팔로잉 · 최신 · 인기가 다 보이지 않음")
        let frames = items.map(\.frame)
        XCTAssertEqual(frames.map(\.midX), frames.map(\.midX).sorted(), "스위처 순서가 팔로잉 · 최신 · 인기가 아님")
        XCTAssertLessThan(more.frame.maxX, frames[0].minX, "더 보기가 스위처 왼쪽에 있지 않음")
        XCTAssertEqual(more.frame.midY, frames[1].midY, accuracy: 2, "더 보기와 스위처가 한 줄이 아님")

        let bell = onScreen(app.buttons.matching(NSPredicate(format: "label == '알림'")))
        if signedIn {
            XCTAssertNotNil(bell, "로그인했는데 벨이 없음")
            XCTAssertGreaterThan(bell?.frame.minX ?? 0, frames[2].maxX, "벨이 스위처 오른쪽에 있지 않음")
        } else {
            XCTAssertNil(bell, "비로그인인데 벨이 있음")
        }
        XCTAssertTrue(items[1].isSelected, "머리가 최신으로 열리지 않음")
        return Header(more: more.frame, segments: frames, bell: bell?.frame)
    }

    private func openNotesTab(_ app: XCUIApplication) {
        let tab = app.buttons["노트"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "탭바에 노트가 없음")
        tab.tap()
    }

    private func assertSameSkeleton(_ blog: Header, _ notes: Header) {
        XCTAssertEqual(blog.more.minX, notes.more.minX, accuracy: 1, "두 머리의 더 보기 자리가 다름")
        XCTAssertEqual(blog.more.width, notes.more.width, accuracy: 1, "두 머리의 더 보기 크기가 다름")
        for (b, n) in zip(blog.segments, notes.segments) {
            XCTAssertEqual(b.midX, n.midX, accuracy: 1, "두 머리의 스위처 칸 자리가 다름")
            XCTAssertEqual(b.width, n.width, accuracy: 1, "두 머리의 스위처 칸 폭이 다름")
        }
        if let b = blog.bell, let n = notes.bell {
            XCTAssertEqual(b.minX, n.minX, accuracy: 1, "두 머리의 벨 자리가 다름")
        }
    }

    func testBlogAndNotesHeadersShareOneSkeleton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "feed"]
        app.launch()
        let blog = header(app, more: "feed.more", signedIn: true)
        shot("blog-header")

        openNotesTab(app)
        let notes = header(app, more: "notes.more", signedIn: true)
        shot("notes-header")
        assertSameSkeleton(blog, notes)
    }

    func testSignedOutBothHeadersOpenOnLatestWithTheMoreButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--screen", "none", "--tab", "feed"]
        app.launch()
        let blog = header(app, more: "feed.more", signedIn: false)
        shot("blog-header-signed-out")

        openNotesTab(app)
        let notes = header(app, more: "notes.more", signedIn: false)
        shot("notes-header-signed-out")
        assertSameSkeleton(blog, notes)

        app.buttons["notes.more"].tap()
        XCTAssertTrue(menuItem(app, "다른 서버").waitForExistence(timeout: 4), "비로그인 노트 더 보기에 다른 서버가 없음")
        XCTAssertFalse(menuItem(app, "리스트 관리").exists, "비로그인 노트 더 보기에 계정 전용 리스트 관리가 있음")
        shot("notes-more-menu-signed-out")
    }

    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private let blogMoreItems: [(label: String, screen: String, login: String)] = [
        ("추천", "추천", "추천을 받으려면 로그인하세요"),
        ("구독한 태그", "구독한 태그", "구독한 태그를 보려면 로그인하세요"),
        ("내 컬렉션", "컬렉션", "컬렉션을 열려면 로그인하세요"),
    ]

    private func openBlogMore(_ app: XCUIApplication) {
        let more = app.buttons["feed.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "블로그 더 보기가 없음")
        more.tap()
    }

    func testTheMoreMenusHoldTheirOwnFeeds() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "feed"]
        app.launch()

        for (index, item) in blogMoreItems.enumerated() {
            openBlogMore(app)
            if index == 0 {
                for other in blogMoreItems {
                    XCTAssertTrue(menuItem(app, other.label).waitForExistence(timeout: 4), "블로그 더 보기에 \(other.label)이 없음")
                }
                shot("blog-more-menu")
            }
            menuItem(app, item.label).tap()
            XCTAssertTrue(
                app.navigationBars[item.screen].waitForExistence(timeout: 6), "\(item.label)이 \(item.screen) 화면을 열지 않음")
            shot("blog-more-\(item.screen)")
            app.navigationBars[item.screen].buttons["BackButton"].tap()
            XCTAssertTrue(app.buttons["feed.more"].waitForExistence(timeout: 6), "피드 머리로 돌아오지 못함")
        }

        openNotesTab(app)
        let notesMore = app.buttons["notes.more"]
        XCTAssertTrue(notesMore.waitForExistence(timeout: 8), "노트 더 보기가 없음")
        notesMore.tap()
        for label in ["다른 서버", "북마크한 노트", "개인 멘션", "리스트 관리"] {
            XCTAssertTrue(menuItem(app, label).waitForExistence(timeout: 4), "노트 더 보기에 \(label)이 없음")
        }
        shot("notes-more-menu")
    }

    func testSignedOutBlogMoreItemsAskToSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--screen", "none", "--tab", "feed"]
        app.launch()
        let sheet = app.descendants(matching: .any).matching(identifier: "login.sheet").firstMatch

        for item in blogMoreItems {
            openBlogMore(app)
            menuItem(app, item.label).tap()
            XCTAssertTrue(sheet.waitForExistence(timeout: 5), "비로그인 \(item.label)이 로그인 시트를 열지 않음")
            XCTAssertTrue(app.staticTexts[item.login].exists, "\(item.label) 로그인 시트 문구가 맥락과 다름")
            XCTAssertFalse(app.navigationBars[item.screen].exists, "비로그인인데 \(item.screen) 화면이 열림")
            shot("blog-more-login-\(item.screen)")
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(
                forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)),
                withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "로그인 시트가 닫히지 않음")
        }
    }
}
