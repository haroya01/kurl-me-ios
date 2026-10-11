import XCTest
@testable import kurl

final class CollectionOrderedTests: XCTestCase {

    private func summary(_ fields: String) throws -> CollectionSummary {
        let json = #"{"id": 7, "title": "경계", "visibility": "PUBLIC", "count": 3"# + fields + "}"
        return try JSONDecoder().decode(CollectionSummary.self, from: Data(json.utf8))
    }

    func testOrderedWinsOverTheLegacyKind() throws {
        XCTAssertTrue(try summary(#", "kind": "COLLECTION", "ordered": true"#).isOrdered)
        XCTAssertFalse(try summary(#", "kind": "PATH", "ordered": false"#).isOrdered)
    }

    func testAServerThatDoesNotSendOrderedIsReadByItsKind() throws {
        XCTAssertTrue(try summary(#", "kind": "PATH""#).isOrdered)
        XCTAssertFalse(try summary(#", "kind": "COLLECTION""#).isOrdered)
        XCTAssertFalse(try summary("").isOrdered)
    }

    func testAFeedEventReadsCollectionOrderedThenTheLegacyKind() throws {
        func event(_ fields: String) throws -> ConnectionEvent {
            let json = #"{"id": 1, "curator": {"id": 2, "username": "minji"}, "collectionId": 104, "#
                + #""collectionTitle": "경계", "blockType": "NOTE", "body": "한 줄""# + fields + "}"
            return try JSONDecoder().decode(ConnectionEvent.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try event(#", "collectionKind": "COLLECTION", "collectionOrdered": true"#).isOrdered)
        XCTAssertTrue(try event(#", "collectionKind": "PATH""#).isOrdered)
        XCTAssertFalse(try event("").isOrdered)
    }

    func testCreatingSendsOrderedWithTheMatchingLegacyKind() throws {
        func body(ordered: Bool) throws -> [String: Any] {
            let data = try JSONEncoder().encode(CollectionsAPI.NewCollectionBody(
                title: "경계", description: nil, visibility: "PRIVATE",
                ordered: ordered, kind: CollectionKind(ordered: ordered).rawValue))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let ordered = try body(ordered: true)
        XCTAssertEqual(ordered["ordered"] as? Bool, true)
        XCTAssertEqual(ordered["kind"] as? String, "PATH")
        let plain = try body(ordered: false)
        XCTAssertEqual(plain["ordered"] as? Bool, false)
        XCTAssertEqual(plain["kind"] as? String, "COLLECTION")
    }

    func testEditingSendsOrderedOnlyWhenItIsChosen() throws {
        func body(_ ordered: Bool?) throws -> [String: Any] {
            let data = try JSONEncoder().encode(CollectionsAPI.EditCollectionBody(
                title: "경계", description: nil, visibility: "PUBLIC", ordered: ordered))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        XCTAssertEqual(try body(true)["ordered"] as? Bool, true)
        XCTAssertNil(try body(nil)["ordered"])
    }

    func testALocallyMadeCollectionCarriesBothFields() {
        let made = CollectionSummary(id: 1, title: "경계", blurb: nil, visibility: .private, ordered: true, count: 0)
        XCTAssertTrue(made.isOrdered)
        XCTAssertEqual(made.kind, .path)
    }
}
