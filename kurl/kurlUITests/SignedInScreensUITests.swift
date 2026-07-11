//
//  SignedInScreensUITests.swift
//  kurlUITests
//

import XCTest

/// 로그인(mock) 딥 화면 캡처 — `simctl` 로는 탭·스크롤이 안 되는 게이트 화면(For You·내 하이라이트·
/// 읽기 기록)을 XCUITest 로 도달해 스크린샷 첨부한다. 절제 패스의 시각 검증을 자동화하는 정공법.
///
/// 실행:
///   xcodebuild test -scheme kurl -only-testing:kurlUITests/SignedInScreensUITests \
///     -destination 'platform=iOS Simulator,id=<udid>'
/// 추출:
///   xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
///   (manifest.json 의 suggestedHumanReadableName 이 아래 name 과 매핑)
///
/// `--mocks` 면 AuthStore 가 로그인 상태이고 MockBackend 가 authed 엔드포인트를 데이터까지
/// 내주므로 실서버 없이 결정론적으로 렌더된다.
final class SignedInScreensUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 라벨을 포함하는 첫 버튼(행 NavigationLink) — 행 자식은 라벨 뒤로 합쳐진다.
    private func rowButton(_ app: XCUIApplication, contains label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// 계정 탭 = 내 블로그. 서재(북마크·하이라이트·기록·노트)는 오른쪽 헤더의 책 버튼으로 들어간다.
    /// 하이라이트·읽기 기록·노트 행은 이 서재 목록 안에 있어, 먼저 서재를 열어야 도달한다.
    private func openLibrary(_ app: XCUIApplication) {
        let library = app.buttons["서재"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 12), "계정 탭에 서재 버튼이 없음")
        library.tap()
    }

    func testForYouFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()

        let forYou = app.buttons["추천"].firstMatch
        XCTAssertTrue(forYou.waitForExistence(timeout: 12), "피드 세그먼트에 '추천' 탭이 없음")
        forYou.tap()
        _ = app.staticTexts["발행된 목 글"].firstMatch.waitForExistence(timeout: 8)
        shoot("for-you-feed")
    }

    func testMyHighlights() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        openLibrary(app)
        let row = rowButton(app, contains: "내 하이라이트")
        XCTAssertTrue(row.waitForExistence(timeout: 12), "서재에 '내 하이라이트' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '경계를 먼저'"))
            .firstMatch.waitForExistence(timeout: 8)
        shoot("my-highlights")
    }

    /// 내 하이라이트 조직화 — 같은 글의 구절이 한 헤더 아래 묶이고, 검색이 글/구절을 좁힌다.
    func testMyHighlightsGroupAndSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        openLibrary(app)
        let row = rowButton(app, contains: "내 하이라이트")
        XCTAssertTrue(row.waitForExistence(timeout: 12), "서재에 '내 하이라이트' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()

        // 글별 그룹 — 두 글 헤더가 보인다.
        let group2 = app.buttons.matching(NSPredicate(format: "label CONTAINS '발행된 목 글'")).firstMatch
        let group1 = app.buttons.matching(NSPredicate(format: "label CONTAINS '헥사고날 정리'")).firstMatch
        XCTAssertTrue(group2.waitForExistence(timeout: 8), "글 그룹 헤더(발행된 목 글)가 없음")
        XCTAssertTrue(group1.waitForExistence(timeout: 4), "글 그룹 헤더(목 초안)가 없음")
        shoot("my-highlights-grouped")

        // 검색 — "추상" 으로 좁히면 그 구절의 글 그룹만 남는다.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 4), "검색 필드가 없음")
        search.tap()
        search.typeText("추상")
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '헥사고날 정리'")).firstMatch
                .waitForExistence(timeout: 4),
            "검색 결과에 매칭 글 그룹이 없음")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '발행된 목 글'")).firstMatch.exists,
            "검색 후에도 매칭 안 되는 글 그룹이 남음")
        shoot("my-highlights-search")
    }

    func testReadingHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        openLibrary(app)
        let row = rowButton(app, contains: "읽기 기록")
        XCTAssertTrue(row.waitForExistence(timeout: 12), "서재에 '읽기 기록' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()
        _ = app.staticTexts["발행된 목 글"].firstMatch.waitForExistence(timeout: 8)
        shoot("reading-history")
    }

    /// 알림 종류별 뮤트 — 계정 톱니(설정) → 알림 종류. 7타입 토글 리스트가 서고, 목은 새 글을
    /// 꺼둔 채 시작하므로 섞인 상태(켬/끔)가 그대로 보인다.
    func testNotificationPreferences() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let gear = app.buttons["설정"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 12), "계정 탭에 설정 버튼이 없음")
        gear.tap()

        let row = rowButton(app, contains: "알림 종류")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "설정에 '알림 종류' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()

        // 7타입 토글이 도달했는지 — 목이 꺼둔 '팔로우한 작가의 새 글' 스위치가 off 로 렌더된다.
        let newPost = app.switches.matching(NSPredicate(format: "label CONTAINS '새 글'")).firstMatch
        XCTAssertTrue(newPost.waitForExistence(timeout: 8), "알림 종류 화면에 토글이 없음")
        // 목 기본값 = 새 글만 꺼짐. 값까지 확인해 "렌더됨"을 "off 로 렌더됨"으로 좁힌다.
        XCTAssertEqual(newPost.value as? String, "0", "새 글 토글이 목 기본값(off)으로 렌더되지 않음")
        shoot("notification-preferences")

        // 새 글 토글을 켜 낙관적 반영 — 값이 실제로 off→on 으로 뒤집혔는지 단언(탭이 먹혔음을 증명).
        // 스위치 요소는 행 라벨(아이콘·제목·설명)까지 감싸 중앙 탭이 라벨에 떨어진다 — 실제 컨트롤이
        // 있는 오른쪽 끝을 좌표로 눌러 값을 뒤집는다(SwiftUI Toggle + 넓은 라벨의 XCUITest 함정).
        newPost.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(newPost.value as? String, "1", "탭 후에도 새 글 토글이 on 으로 뒤집히지 않음")
        // 목 PUT 은 항상 성공하므로 되돌림 토스트가 떠선 안 된다 — 거짓 성공(값만 바뀌고 저장 실패)을 배제.
        XCTAssertFalse(
            app.staticTexts["설정을 저장하지 못했습니다"].exists,
            "저장 성공인데 되돌림 토스트가 떴음(거짓 성공)")
        shoot("notification-preferences-toggled")
    }
}
