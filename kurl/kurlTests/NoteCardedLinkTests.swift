import XCTest

@testable import kurl

final class NoteCardedLinkTests: XCTestCase {

    private let video = "https://youtu.be/6Zo0eMZB6t4"

    func testATrailingLinkDrawnAsACardLeavesTheBody() {
        let body = "あかめとあおめの切り抜き\n#アランウェイク #AlanWake\n\(video)"
        XCTAssertEqual(NoteText.hidingCardedLink(body, card: video), "あかめとあおめの切り抜き\n#アランウェイク #AlanWake")
        XCTAssertEqual(NoteText.hidingCardedLink("볼 만하다 \(video)  \n", card: video), "볼 만하다")
    }

    func testALinkInTheMiddleStays() {
        let body = "\(video) 이거 보고 잤다"
        XCTAssertEqual(NoteText.hidingCardedLink(body, card: video), body)
    }

    func testWithoutACardTheLinkStays() {
        let body = "볼 만하다 \(video)"
        XCTAssertEqual(NoteText.hidingCardedLink(body, card: nil), body)
    }

    func testATrailingLinkOtherThanTheCardStays() {
        let body = "\(video) 그리고 https://example.com/essay"
        XCTAssertEqual(NoteText.hidingCardedLink(body, card: video), body)
    }

    func testABodyThatIsOnlyTheLinkBecomesEmpty() {
        XCTAssertEqual(NoteText.hidingCardedLink(video, card: video), "")
        XCTAssertEqual(NoteText.hidingCardedLink("\n\(video)\n", card: video), "")
    }

    func testATrailingSlashDifferenceStillMatches() {
        XCTAssertEqual(NoteText.hidingCardedLink("소개 https://kurl.me/about/", card: "https://kurl.me/about"), "소개")
    }

    func testTextAfterTheLinkKeepsIt() {
        let body = "여기 \(video)."
        XCTAssertEqual(NoteText.hidingCardedLink(body, card: video), body)
    }
}
