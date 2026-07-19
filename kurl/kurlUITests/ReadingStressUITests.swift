//
//  ReadingStressUITests.swift
//  kurlUITests
//
//  읽기 소크 — 실사용 패턴을 격하게 반복하며 앱이 살아 있는지를 본다:
//  글 열기 → 빠른 하강 스크롤 → 바닥 러버밴드 연타 → 내비 타이틀 경계 위아래 왕복(워치독
//  루프 트리거 지점) → 바닥 큐로 다음 글/다음 편 이동 → 엣지 스와이프 복귀 → 다른 글.
//  목 모드(무네트워크)라 결정적이고, 실기기에서 돌리면 워치독(0x8BADF00D)까지 실측된다.
//  실패 신호 = 앱이 runningForeground 를 잃음(워치독 킬·크래시) 또는 쿼리 무응답(행).
//

import XCTest

final class ReadingStressUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReadingSoak() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "런치 실패")

        // 목 피드의 글 제목들 — 시리즈(K-means)와 긴 글(헥사고날)을 섞는다.
        let titles = [
            "편집 제목",
            "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
            "조용한 웹로그라는 결정",
            "K-means clustering accelerator 설계 (1)",
        ]

        for round in 1...3 {
            for title in titles {
                guard openFromFeed(app, title: title) else { continue }
                assertAlive(app, "글 진입 직후 — \(title) (라운드 \(round))")

                // 격한 읽기: 빠른 하강 → 바닥 러버밴드 연타.
                for _ in 0..<8 { app.swipeUp(velocity: .fast) }
                for _ in 0..<3 { app.swipeUp(velocity: .fast) }
                assertAlive(app, "바닥 도달 후 — \(title) (라운드 \(round))")

                // 바닥 큐가 있으면 다음 글/다음 편으로 넘어간다(시리즈 전환 포함).
                let cue = app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH '계속 당기면'")).firstMatch
                var advanced = false
                if cue.exists, cue.isHittable {
                    cue.tap()
                    Thread.sleep(forTimeInterval: 1.2)
                    assertAlive(app, "다음 글 전환 후 — \(title) (라운드 \(round))")
                    advanced = true
                }

                // 내비 타이틀·크롬 경계 왕복 — 숨김↔표시 진동을 일부러 유발한다.
                jiggle(app, times: 6)
                assertAlive(app, "경계 왕복 후 — \(title) (라운드 \(round))")

                // 복귀 — 다음 글로 넘어갔으면 두 겹, 아니면 한 겹.
                edgeSwipeBack(app)
                if advanced { edgeSwipeBack(app) }
                assertAlive(app, "복귀 후 — \(title) (라운드 \(round))")
            }
        }
    }

    // MARK: 헬퍼

    /// 피드에서 제목을 찾아 연다 — 피드가 설 때까지 기다린 뒤 아래로, 그다음 위로 훑는다.
    /// 진입은 인게이지 독(컬렉션에 연결)으로 확인한다 — 탭이 빗나가면 false 로 넘긴다.
    private func openFromFeed(_ app: XCUIApplication, title: String) -> Bool {
        let target = app.staticTexts[title].firstMatch
        _ = target.waitForExistence(timeout: 8)
        for _ in 0..<10 {
            if target.exists, target.isHittable { break }
            app.swipeUp()
        }
        if !(target.exists && target.isHittable) {
            // 위쪽에 있을 수도 — 화면 중간에서 짧게 끌어올려(리프레시 트리거 없이) 되짚는다.
            for _ in 0..<10 where !(target.exists && target.isHittable) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                    .press(forDuration: 0.05,
                           thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
            }
        }
        guard target.exists, target.isHittable else { return false }
        target.tap()
        let dock = app.buttons["컬렉션에 연결"].firstMatch
        return dock.waitForExistence(timeout: 8)
    }

    /// 경계 왕복 — 짧은 위/아래 스와이프를 번갈아 내비 타이틀·크롬 토글 지점을 진동시킨다.
    private func jiggle(_ app: XCUIApplication, times: Int) {
        for _ in 0..<times {
            app.swipeDown(velocity: .slow)
            app.swipeUp(velocity: .slow)
        }
    }

    /// 글 상세는 스크롤 전 내비바가 숨어 시스템 back 이 없다 — 엣지 스와이프로 복귀.
    private func edgeSwipeBack(_ app: XCUIApplication) {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        edge.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.9)
    }

    /// 생존 단언 — 워치독 킬·크래시면 foreground 를 잃고, 행이면 쿼리가 늘어져 실패한다.
    private func assertAlive(_ app: XCUIApplication, _ context: String) {
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 12),
            "앱이 죽거나 멈춤: \(context)")
    }
}
