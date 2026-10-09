//
//  FeedRowLayoutTests.swift
//  kurlTests
//
//  피드 행의 썸네일은 제 열을 가진다 — 제목·발췌가 썸네일 밑으로 흘러들거나 위에 얹히지 않는다.
//  ImageRenderer 는 .task 를 돌리지 않아 썸네일 자리엔 늘 같은 자리표시 면이 그려진다.
//

import SwiftUI
import XCTest

@testable import kurl

@MainActor
final class FeedRowLayoutTests: XCTestCase {

    private let width: CGFloat = 362
    private let cover = URL(string: "https://example.invalid/cover.png")
    private let longTitle = "경계를 긋는다는 것 — 헥사고날로 갈아탄 지 석 달, 포트 이름을 짓다가 다시 배운 것들과 남은 질문"
    private let longExcerpt = "결론부터 적는다. 다시 돌아가라면 또 갈아탄다. 다만 이름을 짓는 데 들인 시간이 생각보다 길었고, 그 시간이 곧 설계였다."

    private func render(title: String, excerpt: String?, cover: URL?, byline: Bool = false) throws -> CGImage {
        let row = RowLayout(title: title, excerpt: excerpt.map { Text($0) }, cover: cover) {
            EmptyView()
        } byline: {
            if byline {
                Text(verbatim: "eunseong · 2개월 전").typeScale(.meta).foregroundStyle(Color.black)
            }
        }
        .frame(width: width)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: row)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func inkRows(in image: CGImage, xRange: Range<Int>) -> [Bool] {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (0..<h).map { y in
            xRange.contains { x in
                let i = (y * w + x) * 4
                return pixels[i] < 110 && pixels[i + 1] < 110 && pixels[i + 2] < 110
            }
        }
    }

    private func inkPixels(in image: CGImage, fromX minX: Int) -> Int {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var count = 0
        for y in 0..<h {
            for x in minX..<w {
                let i = (y * w + x) * 4
                if pixels[i] < 110, pixels[i + 1] < 110, pixels[i + 2] < 110 { count += 1 }
            }
        }
        return count
    }

    private func largestBlankRun(_ rows: [Bool]) -> Int {
        guard let first = rows.firstIndex(of: true), let last = rows.lastIndex(of: true) else { return 0 }
        var longest = 0, run = 0
        for ink in rows[first...last] {
            run = ink ? 0 : run + 1
            longest = max(longest, run)
        }
        return longest
    }

    func testTextNeverEntersTheThumbnailColumn() throws {
        let gutterStart = Int(width) - 72 - 14
        let withCover = try render(title: longTitle, excerpt: longExcerpt, cover: cover)
        XCTAssertEqual(inkPixels(in: withCover, fromX: gutterStart), 0, "제목이 썸네일 열이나 그 앞 틈으로 넘어갔다")

        let withoutCover = try render(title: longTitle, excerpt: longExcerpt, cover: nil)
        XCTAssertGreaterThan(
            inkPixels(in: withoutCover, fromX: gutterStart), 0,
            "썸네일이 없으면 글이 그 열까지 써야 한다(대조군이 비면 위 단언이 무의미하다)")
    }

    func testABylineSitsOnTheThumbnailEdgeWhenTheTextIsShorter() throws {
        let row = try render(title: "짧은 제목", excerpt: nil, cover: cover, byline: true)
        XCTAssertLessThanOrEqual(row.height, 16 + 72 + 16 + 1, "작가 줄이 썸네일 아래로 밀려 행이 길어졌다")
        let textColumn = 0..<(Int(width) - 72 - 14)
        let gap = largestBlankRun(inkRows(in: row, xRange: textColumn))
        XCTAssertLessThanOrEqual(gap, 48, "발췌 없는 썸네일 행의 제목과 작가 줄 사이가 \(gap)pt 비었다")

        let bare = try render(title: "짧은 제목", excerpt: nil, cover: nil, byline: true)
        XCTAssertLessThan(bare.height, row.height, "썸네일 없는 행이 썸네일 높이만큼 늘어났다")
        XCTAssertLessThanOrEqual(
            largestBlankRun(inkRows(in: bare, xRange: textColumn)), 16,
            "썸네일 없는 행의 제목과 작가 줄 사이가 벌어졌다")
    }

    func testATallRowGrowsPastTheThumbnailAndKeepsItsByline() throws {
        let row = try render(title: longTitle, excerpt: longExcerpt, cover: cover, byline: true)
        XCTAssertGreaterThan(row.height, 16 + 72 + 16 + 20, "썸네일보다 긴 글 열이 썸네일 높이로 잘렸다")
        let rows = inkRows(in: row, xRange: 0..<(Int(width) - 72 - 14))
        let lastInk = try XCTUnwrap(rows.lastIndex(of: true))
        XCTAssertGreaterThan(lastInk, row.height - 16 - 20, "작가 줄이 행 아래 끝에 보이지 않는다(넘쳐 잘렸다)")
    }

    func testThumbnailTakesLayoutHeightInsteadOfOverlaying() throws {
        let short = try render(title: "짧은 제목", excerpt: nil, cover: cover)
        let bare = try render(title: "짧은 제목", excerpt: nil, cover: nil)
        XCTAssertGreaterThanOrEqual(short.height, 16 + 72 + 16, "썸네일이 행 높이에 들어가지 않았다")
        XCTAssertLessThan(bare.height, short.height, "썸네일이 없는 행이 썸네일 행만큼 높다")
    }
}
