//
//  ContentTranslationTests.swift
//  kurlTests
//
//  번역 보기의 세 계약 — 기기가 읽는 언어면 권하지 않는다, 노트의 멘션·해시태그·링크는 그대로 둔다,
//  글은 글 블록만 번역하고 코드·목록 표식·표 구분선은 그대로 둔다. 실패하면 원문에 머물고 알린다.
//

import XCTest

@testable import kurl

@MainActor
final class ContentTranslationTests: XCTestCase {

    private func fake(_ texts: [String]) -> [String] { texts.map { "T(\($0))" } }

    // MARK: 언어 판정

    func testADeclaredLanguageOutsideThePreferredOnesIsOffered() {
        XCTAssertEqual(TranslationGate.source(declared: "ja", text: "", preferred: ["ko-KR"])?.languageCode?.identifier, "ja")
    }

    func testALanguageTheDeviceReadsIsNotOffered() {
        XCTAssertNil(TranslationGate.source(declared: "ko", text: "", preferred: ["ko-KR", "en-KR"]))
        XCTAssertNil(TranslationGate.source(declared: "en-US", text: "", preferred: ["ko-KR", "en-KR"]))
        XCTAssertNil(TranslationGate.source(
            declared: nil, text: "Hexagonal ports, named after a long afternoon.", preferred: ["en-US"]))
    }

    func testAnUndeclaredLanguageIsDetectedFromTheText() {
        XCTAssertEqual(
            TranslationGate.source(declared: nil, text: "Hexagonal ports, named after a long afternoon.", preferred: ["ko"])?
                .languageCode?.identifier, "en")
        XCTAssertEqual(
            TranslationGate.source(declared: nil, text: "境界を先に引き、実装はその外側へ押し出す。", preferred: ["ko"])?
                .languageCode?.identifier, "ja")
    }

    func testShortTextIsNotGuessed() {
        XCTAssertNil(TranslationGate.source(declared: nil, text: "ok lol", preferred: ["ko"]))
        XCTAssertNil(TranslationGate.source(declared: nil, text: "", preferred: ["ko"]))
    }

    // MARK: 노트 — 토큰 보존

    func testMentionsTagsAndLinksStayAsTheyAre() {
        let body = "Named by @yuki_dev at https://kurl.me/p/1 for #architecture today."
        let parts = NoteTranslation.parts(body)
        let requests = NoteTranslation.requests(parts)
        XCTAssertFalse(requests.contains { $0.contains("@yuki_dev") || $0.contains("https://") || $0.contains("#architecture") })

        let rebuilt = NoteTranslation.rebuild(parts, translations: fake(requests))
        XCTAssertTrue(rebuilt.contains("@yuki_dev"))
        XCTAssertTrue(rebuilt.contains("https://kurl.me/p/1"))
        XCTAssertTrue(rebuilt.contains("#architecture"))
        XCTAssertTrue(rebuilt.hasPrefix("T(Named by) @yuki_dev "), rebuilt)
        XCTAssertTrue(rebuilt.hasSuffix(" T(today.)"), rebuilt)
    }

    func testTheWarningIsTranslatedWithTheBody() {
        let requests = NoteTranslation.requests(body: "Long afternoon.", warning: "Spoilers")
        XCTAssertEqual(requests, ["Long afternoon.", "Spoilers"])
        let applied = NoteTranslation.apply(fake(requests), body: "Long afternoon.", warning: "Spoilers")
        XCTAssertEqual(applied.body, "T(Long afternoon.)")
        XCTAssertEqual(applied.warning, "T(Spoilers)")
    }

    func testAMismatchedResultKeepsTheOriginal() {
        let applied = NoteTranslation.apply(["only one"], body: "Long afternoon.", warning: "Spoilers")
        XCTAssertEqual(applied.body, "Long afternoon.")
        XCTAssertEqual(applied.warning, "Spoilers")
    }

    // MARK: 글 — 블록 고르기

    private func block(_ type: String, _ content: String, order: Int) -> PostBlock {
        let json = #"{"type":"\#(type)","content":\#(String(data: try! JSONEncoder().encode(content), encoding: .utf8)!),"blockOrder":\#(order)}"#
        return try! JSONDecoder().decode(PostBlock.self, from: Data(json.utf8))
    }

    func testOnlyTextBlocksAreTranslatedAndCodeStaysAsItIs() throws {
        let code = #"{"lang":"swift","code":"protocol PostStore { func save() }"}"#
        let blocks = [
            block("PARAGRAPH", "境界を**先に**引く。", order: 0),
            block("CODE", code, order: 1),
            block("IMAGE", #"{"url":"https://example.com/a.png"}"#, order: 2),
            block("H2", "ポートとアダプター", order: 3),
            block("DIVIDER", "", order: 4),
        ]
        let plan = PostTranslationPlan(title: "境界を先に引く", blocks: blocks)
        XCTAssertEqual(plan.texts, ["境界を先に引く", "境界を先に引く。", "ポートとアダプター"])
        XCTAssertFalse(plan.texts.contains { $0.contains("protocol") })

        let applied = try XCTUnwrap(plan.apply(fake(plan.texts)))
        XCTAssertEqual(applied.title, "T(境界を先に引く)")
        XCTAssertEqual(applied.blocks[0].content, "T(境界を先に引く。)")
        XCTAssertEqual(applied.blocks[1].content, code)
        XCTAssertEqual(applied.blocks[2].content, blocks[2].content)
        XCTAssertEqual(applied.blocks[3].content, "T(ポートとアダプター)")
    }

    func testListMarkersAndTableSeparatorsStay() throws {
        let blocks = [
            block("LIST_BULLET", "- ドメインはフレームワークを知らない\n  - [x] 差し替えられる", order: 0),
            block("TABLE", "| 層 | 役割 |\n|---|---|\n| ドメイン | 規則 |", order: 1),
        ]
        let plan = PostTranslationPlan(title: "題", blocks: blocks)
        let applied = try XCTUnwrap(plan.apply(fake(plan.texts)))
        XCTAssertEqual(
            applied.blocks[0].content,
            "- T(ドメインはフレームワークを知らない)\n  - [x] T(差し替えられる)")
        let table = try XCTUnwrap(applied.blocks[1].content).components(separatedBy: "\n")
        XCTAssertEqual(table[0], "| T(層) | T(役割) |")
        XCTAssertEqual(table[1], "|---|---|")
        XCTAssertEqual(table[2], "| T(ドメイン) | T(規則) |")
    }

    func testACalloutLabelIsLeftForItsKindToName() throws {
        let blocks = [
            block("QUOTE", "💡 **팁**", order: 0),
            block("PARAGRAPH", "Keep the boundary first.", order: 1),
        ]
        let plan = PostTranslationPlan(title: "Title", blocks: blocks)
        XCTAssertEqual(plan.texts, ["Title", "Keep the boundary first."])
        let applied = try XCTUnwrap(plan.apply(fake(plan.texts)))
        XCTAssertEqual(applied.blocks[0].content, "💡 **팁**")
    }

    func testTranslatedTextCannotTurnIntoMarkup() {
        XCTAssertEqual(PostTranslationPlan.escaped("a*b_c[d]"), #"a\*b\_c\[d\]"#)
        XCTAssertEqual(PostTranslationPlan.tableCell("x|y [z]"), "x｜y [z]", "표 셀은 마크다운이 아니라 이스케이프하지 않는다")
    }

    // MARK: 실패

    func testAFailedOrShortTranslationKeepsTheOriginalAndSaysSo() {
        let store = ContentTranslations.shared
        store.begin("fail-nil")
        store.finish("fail-nil", nil, expected: 1)
        XCTAssertNil(store.phases["fail-nil"], "실패한 번역이 번역 중으로 남음")
        XCTAssertEqual(ToastCenter.shared.message, String(localized: "번역하지 못했어요"), "번역이 실패해도 알리지 않음")

        store.begin("fail-short")
        store.finish("fail-short", ["only one"], expected: 2)
        XCTAssertNil(store.phases["fail-short"], "개수가 어긋난 결과를 번역됨으로 보임")
        XCTAssertFalse(store.showCached("fail-short"), "개수가 어긋난 결과를 기억해 다음에 반쪽 번역이 뜸")

        store.begin("ok")
        store.finish("ok", ["T"], expected: 1)
        XCTAssertEqual(store.shown("ok"), ["T"])
    }
}
