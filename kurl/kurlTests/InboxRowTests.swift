import XCTest

@testable import kurl

@MainActor
final class InboxRowTests: XCTestCase {
    private func notice(
        _ type: String, actor: String? = "yuki_dev", count: Int? = nil, postTitle: String? = nil,
        commentId: Int64? = nil, highlightId: Int64? = nil, collection: String? = nil,
        noteExcerpt: String? = nil, sourceExcerpt: String? = nil, milestone: Int? = nil, at: Date? = nil
    ) -> AppNotification {
        AppNotification(
            id: 1, type: type, actorUsername: actor, actorAvatarUrl: nil,
            postId: postTitle == nil ? nil : 9, postSlug: nil, postTitle: postTitle, postAuthorUsername: nil,
            commentId: commentId, highlightId: highlightId, seriesId: nil, seriesSlug: nil, seriesTitle: nil,
            collectionId: collection == nil ? nil : 3, collectionName: collection, read: false, createdAt: at,
            noteExcerpt: noteExcerpt, sourceExcerpt: sourceExcerpt, count: count, milestone: milestone)
    }

    func testEachKindReadsAsANameAShortWordAndWhatItIsAbout() {
        let reply = InboxRow(notice("NOTE_REPLY", actor: "alice@mastodon.social", sourceExcerpt: "좋은 글이네요"), me: "me")
        XCTAssertEqual(reply.name, "alice")
        XCTAssertEqual(reply.kind, .reply)
        XCTAssertEqual(reply.detail, .theirs("좋은 글이네요"))

        let likes = InboxRow(notice("NOTE_LIKE", count: 4, noteExcerpt: "아침 산책"), me: "me")
        XCTAssertEqual(likes.kind, .like)
        XCTAssertEqual(likes.others, 3)
        XCTAssertEqual(likes.detail, .mine(.note, "아침 산책"))

        let replyLike = InboxRow(notice("COMMENT_LIKE", postTitle: "여름 일기", highlightId: 5), me: "me")
        XCTAssertEqual(replyLike.detail, .mine(.highlightReply, "여름 일기"))
        let commentLike = InboxRow(notice("COMMENT_LIKE", postTitle: "여름 일기", commentId: 7, highlightId: 5), me: "me")
        XCTAssertEqual(commentLike.detail, .mine(.comment, "여름 일기"))

        XCTAssertEqual(InboxRow(notice("NOTE_EDIT", noteExcerpt: "고친 노트"), me: "me").detail, .theirs("고친 노트"))
        XCTAssertEqual(InboxRow(notice("REMOTE_FOLLOW", actor: "bob@fosstodon.org"), me: "me").kind, .follow)
        XCTAssertNil(InboxRow(notice("FOLLOW"), me: "me").detail)
        XCTAssertEqual(InboxRow(notice("CONNECTED", postTitle: "글", collection: "여름"), me: "me").kind, .connected("여름"))

        let mine = InboxRow(notice("NOTE_POLL", actor: "me", noteExcerpt: "점심 뭐 먹지"), me: "me")
        XCTAssertNil(mine.name, "my own poll has no actor to name")
        XCTAssertEqual(mine.detail, .mine(.poll, "점심 뭐 먹지"))
        let theirs = InboxRow(notice("NOTE_POLL", noteExcerpt: "점심 뭐 먹지"), me: "me")
        XCTAssertEqual(theirs.name, "yuki_dev")
        XCTAssertEqual(theirs.detail, .theirs("점심 뭐 먹지"))

        let readers = InboxRow(notice("POST_READ_MILESTONE", actor: nil, postTitle: "여름 일기", milestone: 100), me: "me")
        XCTAssertNil(readers.name)
        XCTAssertEqual(readers.kind, .readMilestone(100))
        XCTAssertEqual(readers.detail, .mine(.post, "여름 일기"))
    }

    func testNamesDropTheServerAndKeepTheLocalPart() {
        XCTAssertEqual(InboxRow.displayName("alice@mastodon.social"), "alice")
        XCTAssertEqual(InboxRow.displayName("@bob@fosstodon.org"), "bob")
        XCTAssertEqual(InboxRow.displayName("reader_kim"), "reader_kim")
        XCTAssertNil(InboxRow.displayName("@"))
        XCTAssertNil(InboxRow.displayName(""))
        XCTAssertNil(InboxRow.displayName(nil))
    }

    func testADisplayNameWinsAndABlankOneFallsBackToTheTrimmedHandle() {
        var named = notice("NOTE_REPLY", actor: "alice@mastodon.social", sourceExcerpt: "좋네요")
        named.actorDisplayName = "앨리스"
        XCTAssertEqual(InboxRow(named, me: nil).name, "앨리스")
        named.actorDisplayName = "  "
        XCTAssertEqual(InboxRow(named, me: nil).name, "alice")
        named.actorDisplayName = nil
        XCTAssertEqual(InboxRow(named, me: nil).name, "alice")
    }

    func testARemoteDisplayNameKeepsItsEmojisAndAnOldServerSendsNone() throws {
        let json = #"""
        {"id":1,"type":"NOTE_LIKE","actorUsername":"ged@m.example","actorDisplayName":"Ged :verified:",
         "actorEmojis":[{"shortcode":"verified","url":"https://files.m.example/v.png"}],"count":2,"read":false}
        """#
        let decoded = try JSONDecoder().decode(AppNotification.self, from: Data(json.utf8))
        let row = InboxRow(decoded, me: nil)
        XCTAssertEqual(row.name, "Ged :verified:")
        XCTAssertEqual(row.emojis.map(\.shortcode), ["verified"])

        let old = try JSONDecoder().decode(
            AppNotification.self, from: Data(#"{"id":2,"type":"FOLLOW","actorUsername":"bob@f.org","read":true}"#.utf8))
        XCTAssertEqual(InboxRow(old, me: nil).name, "bob")
        XCTAssertEqual(InboxRow(old, me: nil).emojis, [])
    }

    func testAGroupCountsTheOthersBesideTheNewestPerson() {
        XCTAssertEqual(InboxRow(notice("NOTE_LIKE"), me: nil).others, 0)
        XCTAssertEqual(InboxRow(notice("NOTE_LIKE", count: 1), me: nil).others, 0)
        XCTAssertEqual(InboxRow(notice("NOTE_LIKE", count: 4), me: nil).others, 3)
    }

    func testABlankExcerptLeavesNoSecondLine() {
        XCTAssertNil(InboxRow(notice("NOTE_REPLY", sourceExcerpt: "  \n "), me: nil).detail)
        XCTAssertNil(InboxRow(notice("LIKE", postTitle: ""), me: nil).detail)
    }

    func testLabelsCarryTheirArguments() {
        XCTAssertTrue(String(localized: InboxRow.Kind.readMilestone(100).label!).contains("100"))
        XCTAssertTrue(String(localized: InboxRow.Kind.connected("여름 산책").label!).contains("여름 산책"))
        XCTAssertNil(InboxRow.Kind.other.label)
    }

    func testSectionsFollowTheDeviceDayAndWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 2
        func kst(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
        let now = kst("2026-11-04T10:00:00+09:00")
        let items: [AppNotification] = [
            notice("LIKE", at: kst("2026-11-04T01:30:00+09:00")),
            notice("LIKE", at: kst("2026-11-03T23:50:00+09:00")),
            notice("LIKE", at: kst("2026-11-02T00:10:00+09:00")),
            notice("LIKE", at: kst("2026-11-01T23:59:00+09:00")),
            notice("LIKE", at: nil),
        ]
        let buckets = InboxSection.buckets(items, now: now, calendar: calendar)
        XCTAssertEqual(buckets.map(\.section), [.today, .thisWeek, .earlier])
        XCTAssertEqual(buckets.map(\.items.count), [1, 2, 2])
        XCTAssertEqual(buckets[1].items.map(\.createdAt), [items[1].createdAt, items[2].createdAt])
        XCTAssertTrue(InboxSection.buckets([], now: now, calendar: calendar).isEmpty)
    }
}
