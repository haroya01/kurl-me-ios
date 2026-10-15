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

    private func notice(
        _ type: String, postSlug: String? = nil, postAuthor: String? = nil,
        commentId: Int64? = nil, highlightId: Int64? = nil, noteId: Int64? = nil
    ) -> AppNotification {
        AppNotification(
            id: 1, type: type, actorUsername: "yuki_dev", actorAvatarUrl: nil,
            postId: postSlug == nil ? nil : 9, postSlug: postSlug, postTitle: nil,
            postAuthorUsername: postAuthor, commentId: commentId, highlightId: highlightId,
            seriesId: nil, seriesSlug: nil, seriesTitle: nil, collectionId: nil, collectionName: nil,
            read: false, createdAt: nil, noteId: noteId)
    }

    @MainActor
    func testAQuoteOfMyPostOpensTheQuotingNote() {
        XCTAssertEqual(NotificationRoute.route(for: notice("POST_QUOTE", noteId: 9501)), .note(id: 9501))
    }

    @MainActor
    func testMyNoteQuotedInAPostOpensThatPost() {
        XCTAssertEqual(
            NotificationRoute.route(for: notice("NOTE_EMBED", postSlug: "roundup", postAuthor: "yuki_dev")),
            .post(username: "yuki_dev", slug: "roundup"))
    }

    @MainActor
    func testCommentLikesAndHighlightsOpenTheirSpot() {
        XCTAssertEqual(
            NotificationRoute.route(
                for: notice("COMMENT_LIKE", postSlug: "p", postAuthor: "honggildong", commentId: 506)),
            .postSpot(username: "honggildong", slug: "p", spot: .comment(506)))
        XCTAssertEqual(
            NotificationRoute.route(
                for: notice("HIGHLIGHT", postSlug: "p", postAuthor: "honggildong", highlightId: 6001)),
            .postSpot(username: "honggildong", slug: "p", spot: .highlight(6001)))
    }

    @MainActor
    private func page(_ items: String) throws -> NotificationsPage {
        try JSONDecoder.blog.decode(
            NotificationsPage.self, from: Data(#"{"items":[\#(items)],"nextCursor":null,"hasMore":false}"#.utf8))
    }

    @MainActor
    func testReaderNoticesDecodeWithoutAnActor() throws {
        let items = try page(
            #"{"id":31,"type":"POST_READ_MILESTONE","postId":9101,"postSlug":"hexagonal","postTitle":"석 달","milestone":1000,"read":false,"createdAt":"2026-10-16T01:00:00Z"},"#
                + #"{"id":32,"type":"POST_FIRST_READER","postId":9002,"postSlug":"p-mock-2","postTitle":"발행된 목 글","read":true,"createdAt":"2026-10-16T00:00:00Z"},"#
                + #"{"id":33,"type":"POST_READ_MILESTONE","postId":9002,"postSlug":"p-mock-2","postTitle":"발행된 목 글","read":false,"createdAt":"2026-10-15T00:00:00Z"},"#
                + #"{"id":34,"type":"SOMETHING_NEWER","read":false,"createdAt":"2026-10-14T00:00:00Z"}"#
        ).items

        XCTAssertEqual(items.map(\.type), ["POST_READ_MILESTONE", "POST_FIRST_READER", "POST_READ_MILESTONE", "SOMETHING_NEWER"])
        XCTAssertEqual(items.map(\.milestone), [1000, nil, nil, nil])
        XCTAssertEqual(items.map(\.postSlug), ["hexagonal", "p-mock-2", "p-mock-2", nil])
        XCTAssertEqual(items[0].postTitle, "석 달")
        for item in items {
            XCTAssertNil(item.actorUsername)
            XCTAssertNil(item.actorAvatarUrl)
            XCTAssertNil(item.actorRemoteId)
            XCTAssertNil(item.postAuthorUsername)
        }
    }

    @MainActor
    func testReaderNoticesOpenMyOwnPost() throws {
        let items = try page(
            #"{"id":31,"type":"POST_READ_MILESTONE","postId":9101,"postSlug":"hexagonal","postTitle":"석 달","milestone":10,"read":false},"#
                + #"{"id":32,"type":"POST_FIRST_READER","postId":9002,"postSlug":"p-mock-2","postTitle":"발행된 목 글","read":false}"#
        ).items

        XCTAssertEqual(
            NotificationRoute.route(for: items[0], mine: "honggildong"), .post(username: "honggildong", slug: "hexagonal"))
        XCTAssertEqual(
            NotificationRoute.route(for: items[1], mine: "honggildong"), .post(username: "honggildong", slug: "p-mock-2"))
    }

    func testReaderPushOpensThePostOfItsOwner() {
        XCTAssertEqual(
            NotificationRoute.route(push: [
                "type": "POST_READ_MILESTONE", "ownerUsername": "honggildong", "postSlug": "hexagonal",
            ]),
            .post(username: "honggildong", slug: "hexagonal"))
        XCTAssertEqual(
            NotificationRoute.route(push: [
                "type": "POST_FIRST_READER", "ownerUsername": "honggildong", "postSlug": "p-mock-2",
            ]),
            .post(username: "honggildong", slug: "p-mock-2"))
    }

    @MainActor
    func testReaderSettingsAppearOnlyWhenTheServerListsThem() {
        let older = NotificationPreferencesAPI.preferences(from: ["LIKE": false])
        XCTAssertNil(older[.postFirstReader])
        XCTAssertNil(older[.postReadMilestone])
        XCTAssertEqual(older[.like], false)
        XCTAssertEqual(older[.comment], true)

        let newer = NotificationPreferencesAPI.preferences(
            from: ["POST_FIRST_READER": true, "POST_READ_MILESTONE": false])
        XCTAssertEqual(newer[.postFirstReader], true)
        XCTAssertEqual(newer[.postReadMilestone], false)
        XCTAssertEqual(newer.count, NotificationKind.allCases.count)
    }

    func testEveryKindSitsInExactlyOneSettingsSection() {
        let placed = NotificationKindSection.allCases.flatMap(\.kinds)
        XCTAssertEqual(placed.count, Set(placed).count)
        XCTAssertEqual(Set(placed), Set(NotificationKind.allCases))
    }
}
