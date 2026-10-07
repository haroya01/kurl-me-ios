import XCTest
@testable import kurl

final class NotificationRouteTests: XCTestCase {

    func testPostPushOpensThePostOfItsOwner() {
        let route = NotificationRoute.route(push: [
            "type": "LIKE", "actorUsername": "reader_kim",
            "ownerUsername": "honggildong", "postSlug": "p-mock-2",
        ])
        XCTAssertEqual(route, .post(username: "honggildong", slug: "p-mock-2"))
    }

    func testSeriesPushOpensTheSeries() {
        let route = NotificationRoute.route(push: [
            "type": "SERIES_SUBSCRIBE", "actorUsername": "yuki_dev",
            "ownerUsername": "honggildong", "seriesSlug": "tokyo-walks",
        ])
        XCTAssertEqual(route, .series(username: "honggildong", slug: "tokyo-walks"))
    }

    func testCollectionPushWinsOverEverythingElse() {
        let route = NotificationRoute.route(push: [
            "type": "CONNECTED", "actorUsername": "yuki_dev",
            "collectionId": NSNumber(value: 42),
        ])
        XCTAssertEqual(route, .collection(id: 42))
    }

    func testFollowRequestPushOpensTheRequestsNotTheAsker() {
        let route = NotificationRoute.route(push: ["type": "FOLLOW_REQUEST", "actorUsername": "sori"])
        XCTAssertEqual(route, .followRequests)
    }

    func testFollowPushOpensTheActor() {
        let route = NotificationRoute.route(push: ["type": "FOLLOW", "actorUsername": "stranger99"])
        XCTAssertEqual(route, .author(username: "stranger99"))
    }

    func testPostWithoutOwnerFallsBackToActor() {
        let route = NotificationRoute.route(push: [
            "type": "LIKE", "actorUsername": "reader_kim", "postSlug": "p-mock-2", "ownerUsername": "",
        ])
        XCTAssertEqual(route, .author(username: "reader_kim"))
    }

    func testCommentPushOpensThePostAtThatComment() {
        let route = NotificationRoute.route(push: [
            "type": "COMMENT", "actorUsername": "yuki_dev",
            "ownerUsername": "honggildong", "postSlug": "p-mock-2",
            "commentId": NSNumber(value: 506),
        ])
        XCTAssertEqual(route, .postSpot(username: "honggildong", slug: "p-mock-2", spot: .comment(506)))
    }

    func testHighlightReplyPushOpensThePostAtThatHighlight() {
        let route = NotificationRoute.route(push: [
            "type": "REPLY", "actorUsername": "reader_kim",
            "ownerUsername": "honggildong", "postSlug": "p-mock-2",
            "highlightId": NSNumber(value: 6001),
        ])
        XCTAssertEqual(route, .postSpot(username: "honggildong", slug: "p-mock-2", spot: .highlight(6001)))
    }

    func testSpotWithoutAPostOwnerFallsBackToActor() {
        let route = NotificationRoute.route(push: [
            "type": "COMMENT", "actorUsername": "yuki_dev", "postSlug": "p-mock-2",
            "commentId": NSNumber(value: 506),
        ])
        XCTAssertEqual(route, .author(username: "yuki_dev"))
    }

    func testInboxRowCarriesItsSpot() {
        XCTAssertEqual(
            NotificationRoute.route(
                actorUsername: "yuki_dev", ownerUsername: "honggildong", postSlug: "p-mock-2",
                seriesSlug: nil, collectionId: nil, commentId: 506, highlightId: nil),
            .postSpot(username: "honggildong", slug: "p-mock-2", spot: .comment(506)))
        XCTAssertEqual(
            NotificationRoute.route(
                actorUsername: "yuki_dev", ownerUsername: "honggildong", postSlug: "p-mock-2",
                seriesSlug: nil, collectionId: nil, commentId: nil, highlightId: 6001),
            .postSpot(username: "honggildong", slug: "p-mock-2", spot: .highlight(6001)))
    }

    func testLegacyPayloadHasNoRoute() {
        XCTAssertNil(NotificationRoute.route(push: ["aps": ["alert": ["body": "좋아합니다"]]]))
    }
}
