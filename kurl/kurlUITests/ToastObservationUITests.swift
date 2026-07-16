//
//  ToastObservationUITests.swift
//  kurlUITests
//
//  ToastHost 가 ToastCenter(@Observable)를 실제로 관찰하는지 — 다른 뷰 갱신이 함께
//  일어나지 않는 맥락(스튜디오 핀 토글: pinned set 만 바뀌고 목록은 재구성 안 됨)에서
//  토스트가 뜨는지 가드한다. 회귀 시(center 를 computed var 로 되돌리면) 토스트가 body
//  재실행을 못 유발해 영영 안 뜬다.
//

import XCTest

final class ToastObservationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 스튜디오 발행 글 ⋯ → '프로필에 고정' → 확인 토스트가 실제로 화면에 뜬다.
    /// 토스트는 ~2.4s 만 유지되므로 탭 직후 곧바로 존재를 폴링한다.
    func testStudioPinToastIsVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write"]
        app.launch()

        let manage = app.buttons["발행된 목 글 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "스튜디오 관리 메뉴 미표시")
        manage.tap()

        let pin = app.buttons["프로필에 고정"]
        let unpin = app.buttons["프로필 고정 해제"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5) || unpin.exists, "핀 토글 항목 없음")
        (pin.exists ? pin : unpin).tap()

        // ToastHost 가 ToastCenter.message 변화를 관찰하지 못하면(회귀) 이 토스트는 앱 전역에서
        // 조용히 증발한다 — 성공/해제 어느 문구든 실제로 화면에 서야 한다. 토스트는 ~2.4s 만
        // 유지되는 짧은 전이라 waitForExistence 스냅샷 지연에 놓치기 쉽다 — 탭 직후 빠르게 폴링한다.
        let toast = app.staticTexts.matching(
            NSPredicate(format:
                "label CONTAINS '고정했어요' OR label CONTAINS '고정을 해제했어요'")).firstMatch
        var appeared = false
        for _ in 0..<20 {
            if toast.exists { appeared = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(
            appeared,
            "핀 토글 확인 토스트가 화면에 뜨지 않음 — ToastHost 가 ToastCenter 를 관찰 못 함")
    }
}
