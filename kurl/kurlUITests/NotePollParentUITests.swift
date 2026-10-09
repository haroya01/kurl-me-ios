//
//  NotePollParentUITests.swift
//  kurlUITests
//
//  답글 상세에서 위쪽 원글 자리의 투표도 투표하면 그 자리에서 결과로 바뀐다 — 원글 행이 변경을
//  버려 선택지가 그대로 남고, 다시 누르면 "이미 투표한 투표"가 되던 결함의 회귀 방지.
//

import XCTest

final class NotePollParentUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testVotingOnTheParentPollAboveAReplyShowsItsResults() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()

        let pollNote = app.buttons["note.body.9509"]
        var tries = 0
        while !pollNote.waitForExistence(timeout: 2), tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(pollNote.exists, "투표 노트(9509)가 피드에 없음")
        pollNote.tap()

        let reply = app.buttons["note.body.9542"]
        tries = 0
        while !reply.waitForExistence(timeout: 2), tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(reply.exists, "투표 노트 상세에 답글이 없음")
        reply.tap()

        let option = app.descendants(matching: .any)["note.poll.option.9509.1"]
        XCTAssertTrue(option.waitForExistence(timeout: 8), "답글 상세 위쪽에 원글 투표가 없음")
        option.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["note.poll.result.9509.1"].waitForExistence(timeout: 6),
            "원글 투표가 투표 뒤에도 결과로 바뀌지 않음")
    }
}
