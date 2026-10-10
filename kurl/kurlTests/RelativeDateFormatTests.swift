//
//  RelativeDateFormatTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

@MainActor
final class RelativeDateFormatTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func relative(_ locale: String) -> [String] {
        let formatter = Date.makeRelativeShortFormatter(locale: Locale(identifier: locale))
        let twoMonths = Calendar(identifier: .gregorian).date(byAdding: .month, value: -2, to: now)!
        return [now - 5 * 60, now - 3 * 3_600, now - 6 * 86_400, twoMonths].map {
            formatter.localizedString(for: $0, relativeTo: now)
        }
    }

    func testJapaneseKeepsNumberAndUnitTogether() {
        XCTAssertEqual(relative("ja_JP"), ["5分前", "3時間前", "6日前", "2か月前"])
    }

    func testKoreanStaysAsBefore() {
        XCTAssertEqual(relative("ko_KR"), ["5분 전", "3시간 전", "6일 전", "2개월 전"])
    }

    func testOtherLocales() {
        XCTAssertEqual(relative("en_US"), ["5m ago", "3h ago", "6d ago", "2mo ago"])
        XCTAssertEqual(relative("vi_VN"), ["5 phút trước", "3 giờ trước", "6 ngày trước", "2 tháng trước"])
        XCTAssertEqual(relative("hi_IN"), ["5 मि॰ पहले", "3 घं॰ पहले", "6 दिन पहले", "2 माह पहले"])
    }

    private func compact(_ locale: String) -> [String] {
        let formatter = Date.makeCompactFormatter(locale: Locale(identifier: locale))
        return [30 * 60, 3_600, 6 * 86_400].map { formatter.string(from: TimeInterval($0)) ?? "" }
    }

    func testVietnameseCompactIsSpelledOut() {
        XCTAssertEqual(compact("vi_VN"), ["30 phút", "1 giờ", "6 ngày"])
    }

    func testCompactStaysNarrowElsewhere() {
        XCTAssertEqual(compact("ko_KR"), ["30분", "1시간", "6일"])
        XCTAssertEqual(compact("ja_JP"), ["30分", "1時間", "6日"])
        XCTAssertEqual(compact("en_US"), ["30m", "1h", "6d"])
        XCTAssertEqual(compact("hi_IN"), ["30 मि॰", "1 घं॰", "6 दिन"])
    }
}
