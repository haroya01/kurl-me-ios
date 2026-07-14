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
