//
//  SeriesBannerUITests.swift
//  kurlUITests
//

import XCTest

/// 시리즈 글 상세의 상단 배너(펼침+회차 페치)와 하단 다음 편 카드 — simctl 로는
/// 탭·스크롤이 안 되는 인터랙션이라 여기가 유일한 자동화 경로. 검증 대상 글은
/// 실서버에서 동적으로 찾는다(특정 slug 고정 금지 — 테스트 데이터는 언제든 바뀐다).
final class SeriesBannerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 실서버 공개 API 에서 "2편 이상 시리즈의 1편" 슬러그를 찾는다. 없으면 nil.
    private func firstSeriesPost() throws -> (username: String, slug: String)? {
        let username = "honggildong"
        guard let listData = try? Data(
            contentsOf: URL(string: "https://kurl.me/api/v1/public/profiles/\(username)/series")!),
            let list = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
            let seriesArray = list["series"] as? [[String: Any]],
            let series = seriesArray.first(where: { ($0["postCount"] as? Int ?? 0) >= 2 }),
            let slug = series["slug"] as? String
        else { return nil }
        guard let detailData = try? Data(
            contentsOf: URL(
                string: "https://kurl.me/api/v1/public/profiles/\(username)/series/\(slug)")!),
            let detail = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
            let posts = detail["posts"] as? [[String: Any]],
            let firstSlug = posts.first?["slug"] as? String
        else { return nil }
        return (username, firstSlug)
    }

    func testBannerExpandsAndNextCardNavigates() throws {
        guard let target = try firstSeriesPost() else {
            throw XCTSkip("실서버에 2편 이상 공개 시리즈가 없음 — 배너 검증 불가")
        }

        let app = XCUIApplication()
        app.launchArguments = ["--post", "\(target.username)/\(target.slug)"]
        app.launch()

        // 상단 배너 — 펼치면 회차 목록을 그때 가져온다(현재 글 행은 링크가 아닌 텍스트).
        let expand = app.buttons["회차 목록 펼치기"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 12), "시리즈 배너가 없음")
        expand.tap()
        // 행 자식은 accessibilityLabel 뒤로 숨는다 — 현재 글 행의 라벨로 목록 도착을 판정.
        let currentRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '현재 글'")).firstMatch
        XCTAssertTrue(currentRow.waitForExistence(timeout: 8), "펼침 후 회차 목록이 안 옴")

        let banner = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        banner.name = "series-banner-expanded"
        banner.lifetime = .keepAlways
        add(banner)

        // 본문 끝의 다음 편 카드 — 1편에서 진입했으니 반드시 있다.
        let nextCard = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '다음 편'")).firstMatch
        var swipes = 0
        while !(nextCard.exists && nextCard.isHittable), swipes < 14 {
            app.swipeUp(velocity: .fast)
            swipes += 1
        }
        XCTAssertTrue(nextCard.exists, "다음 편 카드가 없음")

        let next = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        next.name = "series-next-card"
        next.lifetime = .keepAlways
        add(next)

        // 카드 탭 = 다음 편으로 푸시 — 새 상세에도 시리즈 배너가 선다.
        nextCard.tap()
        XCTAssertTrue(
            app.buttons["회차 목록 펼치기"].firstMatch.waitForExistence(timeout: 12),
            "다음 편으로 푸시되지 않음")
    }
}
