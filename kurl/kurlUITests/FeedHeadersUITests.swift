//
//  FeedHeadersUITests.swift
//  kurlUITests
//
//  블로그·노트 피드 머리는 같은 골격이다 — 가운데 [팔로잉 · 최신 · 인기 | 더 보기], 오른쪽 벨.
//  더 보기의 피드는 화면을 밀지 않고 그 자리에서 바뀌고, 고른 피드는 더 보기 칸에 선다.
//  관리 항목은 메뉴가 아니라 서재·설정에 있다.
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

    private func segmentItems(_ app: XCUIApplication) -> [XCUIElement] {
        segments.compactMap { button(app, $0) }
    }

    private func header(_ app: XCUIApplication, more identifier: String, signedIn: Bool) -> Header {
        let more = app.buttons[identifier]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "\(identifier) 더 보기 칸이 없음")
        let items = segmentItems(app)
        XCTAssertEqual(items.count, segments.count, "머리 스위처에 팔로잉 · 최신 · 인기가 다 보이지 않음")
        let frames = items.map(\.frame)
        XCTAssertEqual(frames.map(\.midX), frames.map(\.midX).sorted(), "스위처 순서가 팔로잉 · 최신 · 인기가 아님")
        XCTAssertGreaterThan(more.frame.minX, frames[2].maxX - 1, "더 보기가 스위처 끝 칸에 있지 않음")
        XCTAssertEqual(more.frame.midY, frames[1].midY, accuracy: 2, "더 보기와 스위처가 한 줄이 아님")
        XCTAssertFalse(more.isSelected, "더 보기 피드를 고르지 않았는데 더 보기 칸이 선택돼 있음")

        let bell = onScreen(app.buttons.matching(NSPredicate(format: "label == '알림'")))
        if signedIn {
            XCTAssertNotNil(bell, "로그인했는데 벨이 없음")
            XCTAssertGreaterThan(bell?.frame.minX ?? 0, more.frame.maxX, "벨이 스위처 오른쪽에 있지 않음")
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

    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// 더 보기 피드로 바꾸면 화면이 밀리지 않고, 세 칸은 선택이 빠지고, 더 보기 칸이 그 피드 이름으로 선다.
    private func assertSwitchedInPlace(_ app: XCUIApplication, more identifier: String, to name: String) {
        let more = app.buttons[identifier]
        XCTAssertTrue(
            more.waitForExistence(timeout: 6) && more.label == name, "더 보기 칸이 \(name)으로 서지 않음(\(more.label))")
        XCTAssertTrue(more.isSelected, "\(name)을 골랐는데 더 보기 칸이 선택 상태가 아님")
        XCTAssertFalse(app.navigationBars.buttons["BackButton"].exists, "\(name)이 제자리가 아니라 새 화면으로 밀렸음")
        XCTAssertFalse(segmentItems(app).contains { $0.isSelected }, "\(name)을 골랐는데 세 칸 중 하나가 아직 선택돼 있음")
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

    func testSignedOutBothHeadersOpenOnLatestWithTheMoreSlot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--screen", "none", "--tab", "feed"]
        app.launch()
        let blog = header(app, more: "feed.more", signedIn: false)
        shot("blog-header-signed-out")

        openNotesTab(app)
        let notes = header(app, more: "notes.more", signedIn: false)
        shot("notes-header-signed-out")
        assertSameSkeleton(blog, notes)
    }

    func testBlogMoreFeedSwitchesInPlaceAndASegmentComesBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "feed"]
        app.launch()
        let more = app.buttons["feed.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "블로그 더 보기 칸이 없음")
        more.tap()
        XCTAssertTrue(menuItem(app, "추천").waitForExistence(timeout: 4), "블로그 더 보기에 추천이 없음")
        for moved in ["구독한 태그", "내 컬렉션", "컬렉션"] {
            XCTAssertFalse(menuItem(app, moved).exists, "블로그 더 보기에 피드가 아닌 \(moved)이 남아 있음")
        }
        shot("blog-more-menu")
        menuItem(app, "추천").tap()
        assertSwitchedInPlace(app, more: "feed.more", to: "추천")
        shot("blog-for-you-in-place")

        button(app, "인기")?.tap()
        XCTAssertTrue(button(app, "인기")?.isSelected ?? false, "추천에서 인기를 눌러도 인기로 돌아가지 않음")
        XCTAssertEqual(app.buttons["feed.more"].label, "블로그 피드 더 보기", "세 칸으로 돌아왔는데 더 보기 칸이 추천에 머묾")
        XCTAssertFalse(app.buttons["feed.more"].isSelected)
    }

    func testNotesMoreFeedsSwitchInPlaceAndShowTheirNameOnTheSlot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        let more = app.buttons["notes.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "노트 더 보기 칸이 없음")
        more.tap()
        for label in ["다른 서버", "북마크한 노트", "개인 멘션"] {
            XCTAssertTrue(menuItem(app, label).waitForExistence(timeout: 4), "노트 더 보기에 \(label)이 없음")
        }
        for moved in ["리스트 관리", "예약한 노트"] {
            XCTAssertFalse(menuItem(app, moved).exists, "노트 더 보기에 피드가 아닌 \(moved)이 남아 있음")
        }
        shot("notes-more-menu")
        menuItem(app, "다른 서버").tap()
        assertSwitchedInPlace(app, more: "notes.more", to: "다른 서버")
        shot("notes-federated-in-place")

        for (label, short) in [("북마크한 노트", "북마크"), ("개인 멘션", "멘션")] {
            app.buttons["notes.more"].tap()
            let item = menuItem(app, label)
            XCTAssertTrue(item.waitForExistence(timeout: 4), "노트 더 보기에 \(label)이 없음")
            item.tap()
            assertSwitchedInPlace(app, more: "notes.more", to: short)
        }

        button(app, "팔로잉")?.tap()
        XCTAssertTrue(button(app, "팔로잉")?.isSelected ?? false, "멘션에서 팔로잉을 눌러도 팔로잉으로 돌아가지 않음")
        XCTAssertFalse(app.buttons["notes.more"].isSelected, "세 칸으로 돌아왔는데 더 보기 칸이 선택돼 있음")
        app.buttons["notes.more"].tap()
        XCTAssertTrue(menuItem(app, "리포스트 보기").waitForExistence(timeout: 4), "팔로잉의 더 보기에 보기 칸(리포스트 보기)이 없음")
        shot("notes-more-menu-following")
    }

    func testSignedOutMoreFeedsAskToSignInAndDoNotSwitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--screen", "none", "--tab", "feed"]
        app.launch()
        let sheet = app.descendants(matching: .any).matching(identifier: "login.sheet").firstMatch

        func ask(more identifier: String, item: String, login: String) {
            let more = app.buttons[identifier]
            XCTAssertTrue(more.waitForExistence(timeout: 15), "\(identifier) 더 보기 칸이 없음")
            more.tap()
            let option = menuItem(app, item)
            XCTAssertTrue(option.waitForExistence(timeout: 4), "비로그인 더 보기에 \(item)이 없음")
            option.tap()
            XCTAssertTrue(sheet.waitForExistence(timeout: 5), "비로그인 \(item)이 로그인 시트를 열지 않음")
            XCTAssertTrue(app.staticTexts[login].exists, "\(item) 로그인 시트 문구가 맥락과 다름")
            shot("login-\(item)")
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(
                forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)),
                withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "로그인 시트가 닫히지 않음")
            XCTAssertFalse(app.buttons[identifier].isSelected, "비로그인인데 \(item)으로 바뀌었음")
            XCTAssertTrue(button(app, "최신")?.isSelected ?? false, "로그인을 닫았는데 최신이 아님")
        }

        ask(more: "feed.more", item: "추천", login: "추천을 받으려면 로그인하세요")
        openNotesTab(app)
        ask(more: "notes.more", item: "다른 서버", login: "다른 서버의 노트를 보려면 로그인하세요")
        ask(more: "notes.more", item: "북마크한 노트", login: "북마크한 노트를 보려면 로그인하세요")
        ask(more: "notes.more", item: "개인 멘션", login: "개인 멘션을 보려면 로그인하세요")
    }

    func testManagementLivesInTheLibraryAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let library = app.buttons["서재"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 15), "계정 탭에 서재가 없음")
        library.tap()
        for row in ["구독한 태그", "컬렉션"] {
            XCTAssertTrue(app.buttons[row].firstMatch.waitForExistence(timeout: 5), "서재에 \(row)이 없음")
        }
        shot("library")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()

        let gear = app.buttons["설정"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 6), "계정 탭에 설정이 없음")
        gear.tap()
        for (identifier, title) in [("settings.noteLists", "리스트"), ("settings.scheduledNotes", "예약한 노트")] {
            let row = app.buttons[identifier]
            var tries = 0
            while !row.isHittable, tries < 6 { app.swipeUp(); tries += 1 }
            XCTAssertTrue(row.isHittable, "설정 노트 칸에 \(title)이 없음")
            if identifier == "settings.noteLists" { shot("settings-notes") }
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 6), "설정의 \(title)이 \(title) 화면을 열지 않음")
            XCTAssertFalse(app.navigationBars[title].buttons["완료"].exists, "민 화면에 시트용 완료 버튼이 남아 있음")
            app.navigationBars[title].buttons["BackButton"].tap()
        }
    }
}
