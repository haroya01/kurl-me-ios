//
//  InlineImageMarkdownTests.swift
//  kurlTests
//
//  문단 속 인라인 이미지 분해 회귀 — "웹은 이미지가 나오는데 앱은 alt 텍스트만" 의 근본이던
//  노션 붙여넣기 산출물 모양들(이미지+캡션+하드브레이크 `\`, 이미지 뒤 텍스트, 한 줄 두 이미지,
//  «마커» alt)을 실제 신고 글(p/eunseong/draft-sm5p3dz)의 블록에서 그대로 가져와 고정한다.
//

import XCTest

@testable import kurl

final class InlineImageMarkdownTests: XCTestCase {

    func testImageWithCaptionAndTrailingHardBreak() {
        // 신고 글 블록 원문 — 캡션 title + 뒤에 하드브레이크 `\` 가 남는 모양.
        let raw = "![«399x303» image.png](https://cdn.example/a.png \"k-means clustering\")\\"
        let segs = InlineImageMarkdown.segments(raw)
        XCTAssertEqual(segs.count, 1, "하드브레이크 잔재는 버려진다: \(segs)")
        guard case .image(let img) = segs[0] else { return XCTFail("이미지 세그먼트가 아님") }
        XCTAssertEqual(img.url, "https://cdn.example/a.png")
        XCTAssertEqual(img.alt, "image.png", "«WxH» 마커는 alt 에서 벗겨진다")
        XCTAssertEqual(img.caption, "k-means clustering")
        XCTAssertEqual(img.dimensions, CGSize(width: 399, height: 303))
    }

    func testImageFollowedByText() {
        let raw = "![«307x303» image.png](https://cdn.example/b.png)\\[개념\\]"
        let segs = InlineImageMarkdown.segments(raw)
        XCTAssertEqual(segs.count, 2)
        guard case .image(let img) = segs[0], case .text(let text) = segs[1] else {
            return XCTFail("이미지+텍스트 순열이 아님: \(segs)")
        }
        XCTAssertEqual(img.dimensions, CGSize(width: 307, height: 303))
        XCTAssertTrue(text.contains("개념"), "이미지 뒤 텍스트가 보존된다: \(text)")
    }

    func testTwoImagesOnOneLine() {
        let raw = "![a](https://cdn.example/1.png \"왼쪽\")![b](https://cdn.example/2.png \"오른쪽\")"
        let segs = InlineImageMarkdown.segments(raw)
        XCTAssertEqual(segs.count, 2)
        guard case .image(let first) = segs[0], case .image(let second) = segs[1] else {
            return XCTFail("두 이미지가 각각 분해되지 않음")
        }
        XCTAssertEqual(first.caption, "왼쪽")
        XCTAssertEqual(second.caption, "오른쪽")
    }

    func testWidthAndAlignMarkers() {
        let raw = "![«wide» «left» «1200x800» hero](https://cdn.example/h.png)"
        let segs = InlineImageMarkdown.segments(raw)
        guard case .image(let img) = segs[0] else { return XCTFail() }
        XCTAssertEqual(img.width, "wide")
        XCTAssertEqual(img.dimensions, CGSize(width: 1200, height: 800))
        XCTAssertEqual(img.alt, "hero", "폭·정렬·치수 마커를 순서대로 벗긴다")
    }

    func testTextAroundImage() {
        let raw = "앞 문장 ![pic](https://cdn.example/c.png) 뒷 문장"
        let segs = InlineImageMarkdown.segments(raw)
        XCTAssertEqual(segs.count, 3)
        guard case .text(let head) = segs[0], case .image = segs[1], case .text(let tail) = segs[2] else {
            return XCTFail("텍스트-이미지-텍스트 순열이 아님: \(segs)")
        }
        XCTAssertEqual(head, "앞 문장")
        XCTAssertEqual(tail, "뒷 문장")
    }

    func testPlainParagraphUntouched() {
        XCTAssertFalse(InlineImageMarkdown.containsImage("그냥 **본문** 문단이다."))
        XCTAssertEqual(
            InlineImageMarkdown.segments("그냥 문단"),
            [.text("그냥 문단")])
    }

    func testLinkIsNotImage() {
        // `[라벨](url)` 은 링크 — 이미지 분해가 낚아채면 안 된다.
        XCTAssertFalse(InlineImageMarkdown.containsImage("[라벨](https://example.com)"))
    }
}

/// 노트 본문의 링크·길이 규칙 — 서버가 다른 서버로 보낼 때와 같아야 한다(http(s)만, 끝 문장부호 제외,
/// 길이는 코드 포인트).
final class NoteTextTests: XCTestCase {

    func testOnlyHttpUrlsBecomeLinksWithoutTrailingPunctuation() {
        let text = NoteText.attributed("see https://kurl.me/a?b=1. and javascript:alert(1)")
        let links = text.runs.compactMap { run in run.link.map { ($0, String(text[run.range].characters)) } }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.0.absoluteString, "https://kurl.me/a?b=1")
        XCTAssertEqual(links.first?.1, "https://kurl.me/a?b=1")
        XCTAssertEqual(String(text.characters), "see https://kurl.me/a?b=1. and javascript:alert(1)")
    }

    func testHashtagKeepsItsHashOnTheSameLineWithoutChangingWhatIsSent() {
        let body = "다시 배운다. #아키텍처. 끝 #디자인·"
        let text = NoteText.attributed(body)
        let links = text.runs.compactMap { run in run.link.map { ($0, String(text[run.range].characters)) } }
        XCTAssertEqual(links.map(\.1), ["#\u{2060}아키텍처", "#\u{2060}디자인"])
        XCTAssertEqual(links.compactMap { NoteText.target(from: $0.0) }, [.tag("아키텍처"), .tag("디자인")])
        XCTAssertEqual(String(text.characters), "다시 배운다. #\u{2060}아키텍처. 끝 #\u{2060}디자인·")
        XCTAssertEqual(NoteText.plain(String(text.characters)), body)
    }

    func testACommentLinksMembersTheServerFoundAndAddressesButNoTags() {
        let body = "@yuki_dev 봤어요 #태그 @ghost https://kurl.me"
        let text = NoteText.attributed(body, mentions: ["yuki_dev"], tags: false)
        let links = text.runs.compactMap { run in run.link.map { ($0, String(text[run.range].characters)) } }
        XCTAssertEqual(links.map(\.1), ["@yuki_dev", "https://kurl.me"])
        XCTAssertEqual(NoteText.target(from: links[0].0), .member("yuki_dev"))
        XCTAssertEqual(String(text.characters), body)
    }

    func testLengthCountsCodePointsLikeTheServer() {
        XCTAssertEqual(NoteText.length("😀😀"), 2)
        XCTAssertEqual(NoteText.length("  가나  "), 2)
    }
}

final class NoteMediaSizeTests: XCTestCase {

    func testAKnownSizeGivesTheRatioAndAnUnknownOneDoesNot() throws {
        let json = #"""
        [{"url":"a","altText":null,"contentType":"image/jpeg","width":600,"height":800},
         {"url":"b","altText":null,"contentType":"image/jpeg"},
         {"url":"c","altText":null,"contentType":"image/jpeg","width":4000,"height":100}]
        """#
        let media = try JSONDecoder().decode([NoteMedia].self, from: Data(json.utf8))
        XCTAssertEqual(try XCTUnwrap(media[0].ratio), 0.75, accuracy: 0.0001)
        XCTAssertNil(media[1].ratio)
        XCTAssertEqual(media[2].ratio, 2)
    }

    func testTheDraftSendsEachPicturesSize() throws {
        let image = NoteDraft.Image(key: "k", altText: "a", width: 1200, height: 1600)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(image)) as? [String: Any])
        XCTAssertEqual(object["width"] as? Int, 1200)
        XCTAssertEqual(object["height"] as? Int, 1600)
    }
}

final class HighlightPaintTests: XCTestCase {

    private func h(
        _ id: Int64, by author: Int64?, block: Int = 0, _ start: Int, _ end: Int,
        endBlock: Int? = nil, note: String? = nil, replies: Int = 0
    ) -> HighlightView {
        HighlightView(
            id: id,
            author: author.map { Author(id: $0, username: "u\($0)", bio: nil, avatarUrl: nil) },
            blockOrder: block, endBlockOrder: endBlock ?? block, startOffset: start, endOffset: end,
            quote: "q", note: note, replyCount: replies, createdAt: nil)
    }

    private func ids(_ clusters: [[HighlightView]]) -> [[Int64]] {
        clusters.map { $0.map(\.id).sorted() }
    }

    func testOverlapAndChainsClusterButTouchingSpansDoNot() {
        XCTAssertEqual(ids(HighlightPaint.clusters([h(1, by: 2, 0, 10), h(2, by: 3, 5, 15)])), [[1, 2]])
        XCTAssertEqual(ids(HighlightPaint.clusters([h(1, by: 2, 0, 10), h(2, by: 3, 10, 20)])), [[1], [2]])
        XCTAssertEqual(
            ids(HighlightPaint.clusters([h(3, by: 4, 18, 30), h(1, by: 2, 0, 10), h(2, by: 3, 8, 20)])),
            [[1, 2, 3]])
        XCTAssertEqual(
            ids(HighlightPaint.clusters([h(1, by: 2, block: 0, 0, 10), h(2, by: 3, block: 1, 0, 10)])),
            [[1], [2]])
        XCTAssertEqual(
            ids(HighlightPaint.clusters([h(1, by: 2, block: 0, 5, 3, endBlock: 2), h(2, by: 3, block: 1, 0, 4)])),
            [[1, 2]])
    }

    func testPaintsMineThreadedAndTopButNotALoneBareMark() {
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 9, 0, 10)], me: 9), [1])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 2, 0, 10)], me: 9), [])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 2, 0, 10), h(2, by: 3, 5, 15)], me: 9), [1, 2])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 2, 0, 10), h(2, by: 2, 5, 15)], me: 9), [])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 9, 0, 10), h(2, by: 2, 5, 15)], me: 9), [1])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 2, 0, 10, note: "왜")], me: 9), [1])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 2, 0, 10, replies: 1)], me: 9), [1])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 2, 0, 10, note: "  ")], me: 9), [])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: 2, 0, 10), h(2, by: 3, 5, 15)], me: nil), [1, 2])
        XCTAssertEqual(HighlightPaint.paintedIds([h(1, by: nil, 0, 10), h(2, by: 3, 5, 15)], me: 9), [])
        XCTAssertEqual(HighlightPaint.topMinReaders, 2)
    }

    func testAnOptimisticMarkIsMineBeforeTheServerAnswers() {
        XCTAssertEqual(HighlightPaint.paintedIds([h(-1, by: nil, 0, 10)], me: 9), [-1])
    }
}

final class MentionDraftTests: XCTestCase {

    func testFindsTheNameBeingTypedAtTheEndOnly() {
        XCTAssertEqual(MentionDraft.trailingQuery(in: "고마워요 @yu"), "yu")
        XCTAssertEqual(MentionDraft.trailingQuery(in: "@"), "")
        XCTAssertEqual(MentionDraft.trailingQuery(in: "(@하루"), "하루")
        XCTAssertNil(MentionDraft.trailingQuery(in: "mail a@b"))
        XCTAssertNil(MentionDraft.trailingQuery(in: "@yuna "))
    }

    func testCompletingSwapsWhatWasTypedForTheHandleAndASpace() {
        XCTAssertEqual(MentionDraft.complete("고마워요 @yu", with: "yuna"), "고마워요 @yuna ")
        XCTAssertEqual(MentionDraft.complete("아무것도", with: "yuna"), "아무것도")
    }
}
