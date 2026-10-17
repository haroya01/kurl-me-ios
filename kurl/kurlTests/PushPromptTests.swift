//
//  PushPromptTests.swift
//  kurlTests
//
//  알림 권한은 로그인한 기기에 한 번만 묻는다 — 아직 정하지 않은 기기만, 목·테스트 실행에선 묻지 않는다.
//

import UserNotifications
import XCTest

@testable import kurl

@MainActor
final class PushPromptTests: XCTestCase {

    private let statuses: [UNAuthorizationStatus] = [
        .notDetermined, .denied, .authorized, .provisional, .ephemeral,
    ]

    func testASignedInDeviceThatNeverAnsweredIsAsked() {
        XCTAssertTrue(PushRegistrar.shouldPrompt(signedIn: true, status: .notDetermined, suppressed: false))
    }

    func testADeviceThatAlreadyAnsweredIsNeverAskedAgain() {
        for status in statuses where status != .notDetermined {
            XCTAssertFalse(
                PushRegistrar.shouldPrompt(signedIn: true, status: status, suppressed: false),
                "status \(status.rawValue)")
        }
    }

    func testASignedOutDeviceIsNeverAsked() {
        for status in statuses {
            XCTAssertFalse(
                PushRegistrar.shouldPrompt(signedIn: false, status: status, suppressed: false),
                "status \(status.rawValue)")
        }
    }

    func testMocksAndTestRunsAreNeverAsked() {
        for status in statuses {
            for signedIn in [true, false] {
                XCTAssertFalse(PushRegistrar.shouldPrompt(signedIn: signedIn, status: status, suppressed: true))
            }
        }
    }
}
