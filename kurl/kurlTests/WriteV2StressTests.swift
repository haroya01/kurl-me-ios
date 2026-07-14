//
//  WriteV2StressTests.swift
//  kurlTests
//
//  글쓰기 엔진 가혹 조건 — 10만 자 문서·수천 블록·별표 2만 개·인라인 이미지 50장처럼 "보통 글"
//  에선 안 밟는 크기에서 왕복(저장 계약)이 안 흔들리고, 파서·렌더러가 병리적 입력에 매달리지
//  않는지(시간 상한) 고정한다. 서버 실효 한도(블록 500·블록당 10만 자)는 백엔드
//  PostWriteStressTest 가 짝으로 고정한다.
//

import XCTest

@testable import kurl

@MainActor
final class WriteV2StressTests: XCTestCase {

    /// Xcode 27 베타 시뮬 런타임의 isolated-deinit malloc abort 우회 — WriteV2FocusEngineTests 와 동일.
    private static var retained: [EditorDocument] = []

    private func makeDoc(_ blocks: [EditorBlock]) -> EditorDocument {
        let doc = EditorDocument(blocks: blocks)
        Self.retained.append(doc)
        return doc
    }

    /// 상한 시간 안에 끝나는지 재면서 실행 — 병리 입력이 파서/정규식을 붙드는 회귀를 잡는다.
    /// CI 시뮬 변동을 감안해 상한은 넉넉히(로컬 실측의 ~10배).
    private func assertCompletes<T>(
        within seconds: Double, _ label: String, file: StaticString = #filePath, line: UInt = #line,
        _ work: () -> T
    ) -> T {
        let start = Date()
        let result = work()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, seconds, "\(label) 이 \(seconds)s 상한을 넘김", file: file, line: line)
        return result
    }

    // MARK: 10만 자 문서 — 왕복 고정점 + 시간 상한

    func testHundredThousandCharacterDocumentRoundTrips() {
        // 복합 블록을 섞어 ~10만 자(서버 총 캡 20만 자의 절반, 블록 수는 500 한도 아래).
        var parts: [String] = []
        let paragraph = "가나다라마바사아자차카타파하 **볼드**와 `코드` 그리고 [링크](https://example.com/a) 를 담은 문단. ".repeat(times: 20)
        for i in 1...220 {
            switch i % 5 {
            case 0: parts.append("## 소제목 \(i)")
            case 1: parts.append(paragraph)
            case 2: parts.append("- 항목 \(i)\n- 항목 \(i)-2")
            case 3: parts.append("> 인용 \(i)")
            default: parts.append("![«1200x800» 사진 \(i)](https://cdn.example/s/\(i).png \"캡션 \(i)\")")
            }
        }
        let md = parts.joined(separator: "\n\n")
        XCTAssertGreaterThan(md.count, 60_000, "픽스처가 의도보다 작음: \(md.count)")

        let once = assertCompletes(within: 5, "10만 자 파싱+직렬화") {
            MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(md))
        }
        let twice = MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(once))
        XCTAssertEqual(twice, once, "대형 문서 왕복이 고정점이 아님")
    }

    // MARK: 수천 블록 문서 — 문서 연산이 끝단에서도 안전

    func testThreeThousandBlockDocumentOperations() {
        var blocks: [EditorBlock] = []
        for i in 1...3000 {
            blocks.append(.paragraph("문단 \(i)"))
        }
        let doc = makeDoc(blocks)

        assertCompletes(within: 3, "3천 블록 focusTail+분할+병합") {
            doc.focusTail()
            let lastId = doc.blocks[2999].id
            doc.splitBlock(lastId, at: 2)
            XCTAssertEqual(doc.blocks.count, 3001)
            doc.mergeBackward(doc.blocks[3000].id)
            XCTAssertEqual(doc.blocks.count, 3000)
        }
        let md = assertCompletes(within: 3, "3천 블록 직렬화") { doc.markdown }
        XCTAssertTrue(md.hasSuffix("문단 3000"))
    }

    // MARK: 병리 입력 — 별표 2만 개·백틱 벽에 렌더러가 매달리지 않는다

    func testPathologicalAsteriskWallDoesNotHang() {
        let wall = String(repeating: "*", count: 20_000)
        _ = assertCompletes(within: 5, "별표 2만 개 렌더") {
            BlockInlineRenderer.render(.paragraph(wall))
        }
        _ = assertCompletes(within: 5, "별표 2만 개 반개봉 판정") {
            BlockInlineRenderer.activeMarkupSpan(in: wall, caret: 10_000)
        }
        let mixed = String(repeating: "*가*", count: 5_000)
        _ = assertCompletes(within: 5, "이탤릭 5천 쌍 렌더") {
            BlockInlineRenderer.render(.paragraph(mixed))
        }
    }

    // MARK: 인라인 이미지 50장 한 문단

    func testFiftyInlineImagesInOneParagraphSegment() {
        let raw = (1...50)
            .map { "![«80\($0 % 10)x600» 컷 \($0)](https://cdn.example/m/\($0).png \"설명 \($0)\")" }
            .joined(separator: " 사이글 ")
        let segs = assertCompletes(within: 2, "인라인 이미지 50장 분해") {
            InlineImageMarkdown.segments(raw)
        }
        let images = segs.filter { if case .image = $0 { return true }; return false }
        let texts = segs.filter { if case .text = $0 { return true }; return false }
        XCTAssertEqual(images.count, 50)
        XCTAssertEqual(texts.count, 49, "이미지 사이 텍스트가 전부 보존")
    }

    // MARK: CodeSyntax 상한 경계 — 6,000자까지 토큰 채색, 넘으면 단색 폴백

    func testCodeSyntaxCapBoundary() {
        let under = String(repeating: "let x = 1\n", count: 599)  // 5,990자
        var underKinds = Set<String>()
        CodeSyntax.walk(under, lang: "swift") { _, kind in underKinds.insert(String(describing: kind)) }
        XCTAssertTrue(underKinds.count > 1, "상한 아래는 토큰별 채색이어야 함: \(underKinds)")

        let over = String(repeating: "let x = 1\n", count: 700)  // 7,000자
        var overPieces = 0
        var overKinds = Set<String>()
        CodeSyntax.walk(over, lang: "swift") { _, kind in
            overPieces += 1
            overKinds.insert(String(describing: kind))
        }
        XCTAssertEqual(overPieces, 1, "상한 초과는 통짜 하나")
        XCTAssertEqual(overKinds, ["plain"], "상한 초과는 단색 폴백")
    }

    // MARK: 표 극한 — 40열 × 60행 편집 왕복

    func testWideTallTableRoundTrip() {
        let cols = 40
        let header = "| " + (1...cols).map { "열\($0)" }.joined(separator: " | ") + " |"
        let sep = "| " + (1...cols).map { _ in "---" }.joined(separator: " | ") + " |"
        let rows = (1...60)
            .map { r in "| " + (1...cols).map { "셀\(r)-\($0)" }.joined(separator: " | ") + " |" }
            .joined(separator: "\n")
        let md = header + "\n" + sep + "\n" + rows

        let once = assertCompletes(within: 3, "40×60 표 왕복") {
            MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(md))
        }
        let twice = MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(once))
        XCTAssertEqual(twice, once)
    }
}

private extension String {
    func `repeat`(times: Int) -> String { String(repeating: self, count: times) }
}
