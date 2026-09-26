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

    func testLegacyPayloadHasNoRoute() {
        XCTAssertNil(NotificationRoute.route(push: ["aps": ["alert": ["body": "좋아합니다"]]]))
    }
}
