//
//  ContentTranslationTests.swift
//  kurlTests
//
//  번역 보기의 세 계약 — 기기의 첫 언어로 쓴 노트는 권하지 않는다, 노트의 멘션·해시태그·링크는 그대로 둔다,
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

    func testTheDevicesFirstLanguageIsNotOffered() {
        XCTAssertNil(TranslationGate.source(declared: "ko", text: "", preferred: ["ko-KR", "en-KR"]))
        XCTAssertNil(TranslationGate.source(
            declared: nil, text: "Hexagonal ports, named after a long afternoon.", preferred: ["en-US"]))
    }

    func testALaterPreferredLanguageIsStillOffered() {
        XCTAssertEqual(
            TranslationGate.source(declared: "en-US", text: "", preferred: ["ko-KR", "en-KR"])?.languageCode?.identifier, "en")
        XCTAssertEqual(
            TranslationGate.source(declared: "ja", text: "", preferred: ["en-US", "ja-JP"])?.languageCode?.identifier, "ja")
    }

    func testThePostLanguageIsKnownEvenWhenTheDeviceReadsIt() {
        XCTAssertEqual(TranslationGate.language(declared: "ko-KR", text: "")?.languageCode?.identifier, "ko")
        XCTAssertNil(TranslationGate.language(declared: nil, text: "ok lol"))
    }

    // MARK: 글 — 바로 번역 또는 언어 고르기

    private func codes(_ languages: [Locale.Language]) -> [String] {
        languages.compactMap { $0.languageCode?.identifier }
    }

    func testAPostInAnotherLanguageTranslatesStraightIntoTheDeviceLanguage() async {
        let offer = await PostTranslationOffer.make(language: Locale.Language(identifier: "ja"), preferred: ["ko-KR", "ja-JP"]) { _ in true }
        XCTAssertEqual(offer?.direct?.languageCode?.identifier, "ko")
        XCTAssertEqual(offer?.source.languageCode?.identifier, "ja")
        XCTAssertEqual(offer?.choices, [])
    }

    func testAPostInTheDeviceLanguageOffersTheOtherAppLanguages() async {
        let offer = await PostTranslationOffer.make(language: Locale.Language(identifier: "ko"), preferred: ["ko-KR"]) { _ in true }
        XCTAssertNil(offer?.direct)
        XCTAssertEqual(codes(offer?.choices.map(\.target) ?? []), ["en", "ja", "vi", "hi"])
    }

    func testUnsupportedPairsAreListedButNotChoosable() async {
        let offer = await PostTranslationOffer.make(language: Locale.Language(identifier: "ko"), preferred: ["ko-KR"]) {
            $0.languageCode?.identifier != "hi"
        }
        XCTAssertEqual(offer?.choices.filter { !$0.available }.map { $0.target.languageCode?.identifier }, ["hi"])
    }

    func testAnUnsupportedDirectPairFallsBackToChoosing() async {
        let offer = await PostTranslationOffer.make(language: Locale.Language(identifier: "ja"), preferred: ["ko-KR"]) {
            $0.languageCode?.identifier == "en"
        }
        XCTAssertNil(offer?.direct)
        XCTAssertEqual(codes(offer?.choices.filter(\.available).map(\.target) ?? []), ["en"])
    }

    func testNothingIsOfferedWhenNoPairIsSupported() async {
        let offer = await PostTranslationOffer.make(language: Locale.Language(identifier: "sw"), preferred: ["ko-KR"]) { _ in false }
        XCTAssertNil(offer)
    }

    func testChoicesAreNamedInTheirOwnLanguage() {
        let names = TranslationGate.appLanguages.map { TranslationGate.nativeName(Locale.Language(identifier: $0)) }
        XCTAssertEqual(names, ["한국어", "English", "日本語", "Tiếng Việt", "हिन्दी"])
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

    // MARK: 글 — 도착한 블록부터

    func testBlocksSwapOnlyOnceAllTheirPiecesArrive() throws {
        let blocks = [
            block("PARAGRAPH", "境界を**先に**引く。", order: 0),
            block("CODE", #"{"lang":"swift","code":"let a = 1"}"#, order: 1),
            block("LIST_BULLET", "- ドメイン\n- アダプター", order: 2),
            block("H2", "ポート", order: 3),
        ]
        let plan = PostTranslationPlan(title: "題", blocks: blocks)
        XCTAssertEqual(plan.texts, ["題", "境界を先に引く。", "ドメイン", "アダプター", "ポート"])

        let none = try XCTUnwrap(plan.apply(partial: Array(repeating: nil, count: plan.texts.count)))
        XCTAssertEqual(none.title, "題")
        XCTAssertFalse(none.titleTranslated)
        XCTAssertEqual(none.translatedBlocks, [])
        XCTAssertEqual(none.blocks.map(\.content), blocks.map(\.content), "아무것도 안 왔는데 원문이 바뀜")

        let some = try XCTUnwrap(plan.apply(partial: ["T(題)", "T(境界を先に引く。)", "T(ドメイン)", nil, "T(ポート)"]))
        XCTAssertEqual(some.title, "T(題)")
        XCTAssertTrue(some.titleTranslated)
        XCTAssertEqual(some.translatedBlocks, [0, 3])
        XCTAssertEqual(some.blocks[0].content, "T(境界を先に引く。)")
        XCTAssertEqual(some.blocks[2].content, blocks[2].content, "목록이 항목 하나만 와도 바뀜")
        XCTAssertEqual(some.blocks[3].content, "T(ポート)")

        let titleLate = try XCTUnwrap(plan.apply(partial: [nil, "T(境界を先に引く。)", nil, nil, nil]))
        XCTAssertEqual(titleLate.title, "題")
        XCTAssertFalse(titleLate.titleTranslated)
        XCTAssertEqual(titleLate.translatedBlocks, [0])

        let all = try XCTUnwrap(plan.apply(partial: fake(plan.texts)))
        XCTAssertEqual(all.translatedBlocks, [0, 2, 3])
        XCTAssertEqual(all.blocks[2].content, "- T(ドメイン)\n- T(アダプター)")
        XCTAssertNil(plan.apply(partial: [nil]), "개수가 어긋난 조각을 적용함")
    }

    func testACalloutBodyIsTheBlockThatSwaps() throws {
        let blocks = [
            block("QUOTE", "💡 **팁**", order: 0),
            block("PARAGRAPH", "Keep the boundary first.", order: 1),
        ]
        let plan = PostTranslationPlan(title: "Title", blocks: blocks)
        let applied = try XCTUnwrap(plan.apply(partial: [nil, "T(Keep the boundary first.)"]))
        XCTAssertEqual(applied.translatedBlocks, [1])
        XCTAssertEqual(applied.blocks[0].content, "💡 **팁**")
    }

    // MARK: 진행

    private func request(_ key: String, _ texts: [String]) -> TranslationRequest {
        TranslationRequest(
            key: key, source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "ko"), texts: texts)
    }

    func testProgressCountsArrivedPiecesOnce() {
        let store = ContentTranslations.shared
        let key = "progress-\(UUID())"
        XCTAssertNil(store.progress(key))
        store.begin(request(key, ["a", "b", "c"]))
        XCTAssertEqual(store.progress(key), TranslationProgress(done: 0, total: 3))

        store.receive(key, index: 2, text: "C")
        store.receive(key, index: 2, text: "C again")
        store.receive(key, index: 7, text: "nowhere")
        XCTAssertEqual(store.progress(key), TranslationProgress(done: 1, total: 3))
        XCTAssertEqual(store.partial(key), [nil, nil, "C"])

        store.receive(key, index: 0, text: "A")
        XCTAssertEqual(store.progress(key), TranslationProgress(done: 2, total: 3))
        XCTAssertNil(store.shown(key), "다 오기 전에 번역됨으로 보임")

        store.showOriginal(key)
        XCTAssertNil(store.progress(key))
        XCTAssertNil(store.partial(key))
        store.receive(key, index: 1, text: "B")
        XCTAssertNil(store.partial(key), "원문 보기 뒤에 늦게 온 조각이 되살아남")
        XCTAssertFalse(store.showCached(key), "끝나지 않은 번역을 기억함")
    }

    private struct ScriptedTranslator: ContentTranslator {
        let order: [Int]
        var failAfter: Int?

        func translate(
            _ texts: [String], from source: Locale.Language, to target: Locale.Language,
            received: (_ index: Int, _ text: String) -> Bool
        ) async throws {
            for (step, index) in order.enumerated() {
                if step == failAfter { throw EchoTranslator.Failure() }
                guard received(index, "T(\(texts[index]))") else { return }
            }
        }
    }

    func testResultsArrivingOutOfOrderLandInTheirPlace() async {
        let store = ContentTranslations.shared
        let key = "order-\(UUID())"
        let req = request(key, ["a", "b", "c"])
        store.begin(req)
        await store.run(req, with: ScriptedTranslator(order: [2, 0, 1]), isCurrent: { true })
        XCTAssertEqual(store.shown(key), ["T(a)", "T(b)", "T(c)"])
        XCTAssertNil(store.progress(key))
    }

    func testAMissingPieceFallsBackToItsOriginal() async {
        let store = ContentTranslations.shared
        let key = "missing-\(UUID())"
        let req = request(key, ["a", "b"])
        store.begin(req)
        await store.run(req, with: ScriptedTranslator(order: [1]), isCurrent: { true })
        XCTAssertEqual(store.shown(key), ["a", "T(b)"])
    }

    func testAFailureMidwayRevertsAndSaysSo() async {
        let store = ContentTranslations.shared
        let key = "midway-\(UUID())"
        let req = request(key, ["a", "b", "c", "d"])
        ToastCenter.shared.show("sentinel")
        store.begin(req)
        await store.run(req, with: ScriptedTranslator(order: [0, 1, 2, 3], failAfter: 2), isCurrent: { true })
        XCTAssertNil(store.phases[key], "중간에 실패했는데 번역 중으로 남음")
        XCTAssertNil(store.partial(key), "중간에 실패했는데 반쪽 번역이 남음")
        XCTAssertEqual(ToastCenter.shared.message, String(localized: "번역하지 못했어요"))
        XCTAssertFalse(store.showCached(key))
    }

    func testCancellingStopsQuietly() async {
        let store = ContentTranslations.shared
        let key = "cancel-\(UUID())"
        let req = request(key, ["a", "b", "c", "d"])
        ToastCenter.shared.show("sentinel")
        store.begin(req)
        var delivered = 0
        await store.run(req, with: ScriptedTranslator(order: [0, 1, 2, 3]), isCurrent: {
            delivered += 1
            if delivered == 3 { store.showOriginal(key) }
            return true
        })
        XCTAssertNil(store.phases[key])
        XCTAssertEqual(ToastCenter.shared.message, "sentinel", "원문 보기로 멈춘 번역을 실패라고 알림")
        XCTAssertFalse(store.showCached(key))
    }

    func testTheMockTranslatorStreamsOnePieceAtATime() async throws {
        var seen: [Int] = []
        try await EchoTranslator(delay: .zero).translate(
            ["a", "b", "c"], from: Locale.Language(identifier: "ja"), to: Locale.Language(identifier: "ko")
        ) { index, text in
            seen.append(index)
            XCTAssertEqual(text, "[ko] " + ["a", "b", "c"][index])
            return index < 1
        }
        XCTAssertEqual(seen, [0, 1], "멈추라고 했는데 계속 보냄")
    }

    // MARK: 실패

    func testAFailedOrShortTranslationKeepsTheOriginalAndSaysSo() {
        let store = ContentTranslations.shared
        store.begin(request("fail-nil", ["a"]))
        store.finish("fail-nil", nil, expected: 1)
        XCTAssertNil(store.phases["fail-nil"], "실패한 번역이 번역 중으로 남음")
        XCTAssertEqual(ToastCenter.shared.message, String(localized: "번역하지 못했어요"), "번역이 실패해도 알리지 않음")

        store.begin(request("fail-short", ["a", "b"]))
        store.finish("fail-short", ["only one"], expected: 2)
        XCTAssertNil(store.phases["fail-short"], "개수가 어긋난 결과를 번역됨으로 보임")
        XCTAssertFalse(store.showCached("fail-short"), "개수가 어긋난 결과를 기억해 다음에 반쪽 번역이 뜸")

        store.begin(request("ok", ["a"]))
        store.finish("ok", ["T"], expected: 1)
        XCTAssertEqual(store.shown("ok"), ["T"])
    }
}
