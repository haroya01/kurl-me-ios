import XCTest

@testable import kurl

final class FollowListRemoteTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testMixedPageKeepsServerOrderAndSplitsByType() throws {
        let page = try decode(FollowListPage.self, #"""
        {"items":[
          {"type":"local","id":2,"username":"yuki_dev","bio":null,"avatarUrl":null,"followerCount":12,"followedByMe":true},
          {"type":"remote","account":{"id":9800,"acct":"mina@mastodon.social","username":"mina","domain":"mastodon.social","displayName":"Mina","avatarUrl":null,"url":"https://mastodon.social/@mina","following":false,"requested":true}},
          {"type":"local","id":3,"username":"reader_kim","bio":"읽는 사람","avatarUrl":null,"followerCount":4,"followedByMe":false}
        ],"page":0,"size":20,"hasNext":true}
        """#)

        XCTAssertEqual(page.items.map(\.id), ["local.2", "remote.9800", "local.3"])
        guard case .remote(let account) = page.items[1] else { return XCTFail("두 번째 행이 다른 서버 계정이 아님") }
        XCTAssertEqual(account.acct, "mina@mastodon.social")
        XCTAssertFalse(account.following)
        XCTAssertTrue(account.requested)
        guard case .local(let user) = page.items[0] else { return XCTFail("첫 행이 kurl 사용자가 아님") }
        XCTAssertEqual(user.username, "yuki_dev")
        XCTAssertTrue(page.hasNext)
    }

    func testItemsWithoutTypeStayKurlUsers() throws {
        let page = try decode(FollowListPage.self, #"""
        {"items":[{"id":7,"username":"haruka","bio":null,"avatarUrl":null,"followerCount":0,"followedByMe":false}],
         "page":1,"size":20,"hasNext":false}
        """#)

        XCTAssertEqual(page.items, [.local(FollowUser(
            id: 7, username: "haruka", bio: nil, avatarUrl: nil, followerCount: 0, followedByMe: false))])
    }

    func testRemoteItemAndLocalItemWithSameIdAreDistinctRows() throws {
        let page = try decode(FollowListPage.self, #"""
        {"items":[
          {"type":"local","id":5,"username":"a","bio":null,"avatarUrl":null,"followerCount":0,"followedByMe":false},
          {"type":"remote","account":{"id":5,"acct":"a@b.example","username":"a","domain":"b.example","displayName":null,"avatarUrl":null,"url":"https://b.example/@a","following":true,"requested":false}}
        ],"page":0,"size":20,"hasNext":false}
        """#)

        XCTAssertEqual(Set(page.items.map(\.id)).count, 2)
    }

    func testCountsAddRemoteFollowsToKurlFollows() throws {
        let status = try decode(InteractionsAPI.FollowStatus.self, #"""
        {"following":false,"followerCount":12,"followingCount":5,"remoteFollowerCount":2,"remoteFollowingCount":4,
         "hideFollowerCount":false}
        """#)

        XCTAssertEqual(status.allFollowers, 14)
        XCTAssertEqual(status.allFollowing, 9)
        XCTAssertEqual(status.followingCount, 5)
    }

    func testCountsFromAServerWithoutRemoteCountsShowKurlFollowsOnly() throws {
        let status = try decode(InteractionsAPI.FollowStatus.self, #"""
        {"following":false,"followerCount":12,"followingCount":5,"hideFollowerCount":false}
        """#)

        XCTAssertEqual(status.allFollowers, 12)
        XCTAssertEqual(status.allFollowing, 5)
    }

    func testHiddenCountsStayHiddenEvenWithRemoteCounts() throws {
        let status = try decode(InteractionsAPI.FollowStatus.self, #"""
        {"following":false,"remoteFollowerCount":null,"remoteFollowingCount":3,"hideFollowerCount":true}
        """#)

        XCTAssertNil(status.allFollowers)
        XCTAssertNil(status.allFollowing)
    }
}
