//
//  EnglishPluralTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

final class EnglishPluralTests: XCTestCase {

    private let english = Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)!
    private let locale = Locale(identifier: "en_US")

    private func en(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: english, locale: locale)
    }

    func testSingleCountPicksSingularForOne() {
        XCTAssertEqual(en("이어 읽기 — \(1)편"), "Keep reading — 1 part")
        XCTAssertEqual(en("이어 읽기 — \(3)편"), "Keep reading — 3 parts")
        XCTAssertEqual(en("팔로워 \(1)"), "1 follower")
        XCTAssertEqual(en("팔로워 \(12)"), "12 followers")
        XCTAssertEqual(en("\(1)명 참여"), "1 person voted")
        XCTAssertEqual(en("좋아요 \(1)"), "1 like")
    }

    func testCountNextToTextUsesItsOwnArgument() {
        XCTAssertEqual(en("@\("kurl") · \(1)편"), "@kurl · 1 post")
        XCTAssertEqual(en("@\("kurl") · \(4)편"), "@kurl · 4 posts")
        XCTAssertEqual(en("‘\("길")’ 외 \(1)개 컬렉션에 담김"), "In ‘길’ and 1 more collection")
    }

    func testTwoCountsPluralizeIndependently() {
        XCTAssertEqual(en("\(1)명이 보낸 알림 \(1)개"), "1 notification from 1 person")
        XCTAssertEqual(en("\(2)명이 보낸 알림 \(5)개"), "5 notifications from 2 people")
        XCTAssertEqual(en("\(1)명이 보낸 알림 \(3)개"), "3 notifications from 1 person")
    }
}
