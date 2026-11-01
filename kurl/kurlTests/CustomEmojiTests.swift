import SwiftUI
import XCTest

@testable import kurl

@MainActor
final class CustomEmojiTests: XCTestCase {

    private func shown(_ inlines: [NoteText.Inline]) -> [String] {
        inlines.map { inline in
            switch inline {
            case let .text(text): String(text.characters)
            case let .emoji(code): "<\(code)>"
            }
        }
    }

    private func split(_ body: String, _ codes: Set<String>, mentions: [String] = []) -> [String] {
        shown(NoteText.inlines(NoteText.attributed(body, mentions: mentions), emojis: codes))
    }

    func testOnlyShortcodesInTheNoteListBecomePictures() {
        XCTAssertEqual(split("hi :neko: and :unknown:", ["neko"]), ["hi ", "<neko>", " and :unknown:"])
        XCTAssertEqual(split(":Neko:", ["neko"]), [":Neko:"])
        XCTAssertEqual(split("no list :neko:", []), ["no list :neko:"])
    }

    func testZeroWidthSpacesNextToAPictureGo() {
        XCTAssertEqual(split("Ged \u{200B}:verified:\u{200B} here", ["verified"]), ["Ged ", "<verified>", " here"])
        XCTAssertEqual(split(":aramaki_halloween_mummy:\u{200B}", ["aramaki_halloween_mummy"]), ["<aramaki_halloween_mummy>"])
        XCTAssertEqual(split("a\u{200B}b :x_y:", ["x_y"]), ["a\u{200B}b ", "<x_y>"])
        XCTAssertEqual(split("keep\u{200B} :gone:\u{200B}", []), ["keep\u{200B} :gone:\u{200B}"])
    }

    func testPicturesBackToBack() {
        XCTAssertEqual(split(":neko::blob:", ["neko", "blob"]), ["<neko>", "<blob>"])
        XCTAssertEqual(split(":neko:\u{200B}:blob:\u{200B}:neko:", ["neko", "blob"]), ["<neko>", "<blob>", "<neko>"])
        XCTAssertEqual(split("::neko:::", ["neko"]), [":", "<neko>", "::"])
        XCTAssertEqual(split(":neko:blob:", ["blob"]), [":neko", "<blob>"])
    }

    func testShortcodeShape() {
        XCTAssertEqual(split(":a: :a_b: :a-b: :한글:", ["a", "a_b", "a-b", "한글"]), [":a: ", "<a_b>", " :a-b: :한글:"])
        XCTAssertEqual(split("at 10:30, :neko:", ["neko"]), ["at 10:30, ", "<neko>"])
    }

    func testLinksTagsAndMentionsKeepTheirText() {
        let codes: Set<String> = ["neko"]
        let attributed = NoteText.attributed(
            "see https://ex.example/:neko:/x #neko :neko: @mina", mentions: ["mina"])
        let inlines = NoteText.inlines(attributed, emojis: codes)

        XCTAssertEqual(
            shown(inlines),
            ["see https://ex.example/:neko:/x #\(NoteText.tagJoiner)neko ", "<neko>", " @mina"])
        let links = inlines.flatMap { inline -> [URL] in
            guard case let .text(text) = inline else { return [] }
            return text.runs.compactMap(\.link)
        }
        XCTAssertEqual(links.map(\.absoluteString), [
            "https://ex.example/:neko:/x", "kurl-note://tag/neko", "kurl-note://member/mina",
        ])
    }

    func testDecodingWithoutEmojisIsEmpty() throws {
        let note = try JSONDecoder.blog.decode(Note.self, from: Data(Self.note(emojis: nil, authorEmojis: nil).utf8))

        XCTAssertNil(note.emojis)
        XCTAssertNil(note.author.emojis)
        XCTAssertTrue(CustomEmoji.table(note.emojis).isEmpty)
        XCTAssertTrue(CustomEmoji.table(note.author.emojis).isEmpty)
    }

    func testDecodingKeepsGoodEntriesAndDropsBadOnes() throws {
        let emojis = #"""
        [{"shortcode":"neoghost","url":"https://e.example/neoghost.png"},
         {"shortcode":"plain","url":"http://e.example/plain.png"},
         {"shortcode":"x","url":"https://e.example/x.png"},
         {"shortcode":"no-dash","url":"https://e.example/d.png"},
         {"shortcode":"nourl"},
         {"shortcode":"neoghost","url":"https://e.example/second.png"},
         "junk"]
        """#
        let note = try JSONDecoder.blog.decode(
            Note.self,
            from: Data(Self.note(emojis: emojis, authorEmojis: #"[{"shortcode":"verified","url":"https://e.example/v.png"}]"#).utf8))

        XCTAssertEqual(CustomEmoji.table(note.emojis), ["neoghost": URL(string: "https://e.example/neoghost.png")!])
        XCTAssertEqual(CustomEmoji.table(note.author.emojis), ["verified": URL(string: "https://e.example/v.png")!])
    }

    func testTrendingNoteCarriesEmojisIntoTheRow() throws {
        let json = #"""
        {"uri":"https://mastodon.social/users/ged/statuses/1","body":"hi :neoghost:","createdAt":"2026-11-01T01:00:00Z",
         "author":{"username":"ged@mastodon.social","displayName":"Ged :verified:","avatarUrl":null,"url":"https://mastodon.social/@ged",
                   "emojis":[{"shortcode":"verified","url":"https://e.example/v.png"}]},
         "media":[],"contentWarning":null,"sensitive":false,"language":"en","likeCount":1,"repostCount":0,"replyCount":0,
         "poll":null,"linkPreview":null,"remote":null,"servers":["mastodon.social"],
         "emojis":[{"shortcode":"neoghost","url":"https://e.example/n.png"}]}
        """#
        let note = try JSONDecoder.blog.decode(TrendingNote.self, from: Data(json.utf8)).displayNote

        XCTAssertEqual(note.emojis?.map(\.shortcode), ["neoghost"])
        XCTAssertEqual(note.author.emojis?.map(\.shortcode), ["verified"])
        XCTAssertEqual(QuotedNote(note).emojis?.map(\.shortcode), ["neoghost"])
    }

    func testSlotIsDecidedFromWhatTheCacheAlreadyKnows() async {
        let cache = EmojiStub.cache()
        let wide = URL(string: "https://\(EmojiStub.host)/wide.png")!
        let gone = URL(string: "https://\(EmojiStub.host)/gone.png")!
        let fresh = URL(string: "https://\(EmojiStub.host)/fresh.png")!

        XCTAssertEqual(EmojiText.slot(for: wide, in: cache), .square)
        _ = await cache.load(wide, maxPixel: EmojiText.loadPoints)
        _ = await cache.load(gone, maxPixel: EmojiText.loadPoints)

        XCTAssertEqual(EmojiText.slot(for: wide, in: cache), .sized(2))
        XCTAssertEqual(EmojiText.slot(for: gone, in: cache), .text)
        XCTAssertEqual(EmojiText.slot(for: fresh, in: cache), .square)
    }

    func testPictureDoesNotGrowTheLine() {
        let emojis = [CustomEmoji(shortcode: "neko", url: URL(string: "https://\(EmojiStub.host)/never.png"))]
        func height(_ text: String) -> CGFloat {
            UIHostingController(rootView: EmojiText(verbatim: text, emojis: emojis).typeScale(.note))
                .sizeThatFits(in: CGSize(width: 320, height: 1000)).height
        }

        XCTAssertGreaterThan(height("Hello :neko: there"), 0)
        XCTAssertEqual(height("Hello :neko: there"), height("Hello there"), accuracy: 0.01)
        XCTAssertEqual(height("one\ntwo :neko: two\nthree"), height("one\ntwo two\nthree"), accuracy: 0.01)
    }

    private static func note(emojis: String?, authorEmojis: String?) -> String {
        let authorField = authorEmojis.map { #","emojis":\#($0)"# } ?? ""
        let noteField = emojis.map { #","emojis":\#($0)"# } ?? ""
        return #"""
        {"id":9601,"body":"hi :neoghost:","createdAt":"2026-11-01T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,
         "author":{"id":-9800,"username":"ged@mastodon.social","bio":null,"avatarUrl":null,"displayName":"Ged :verified:","remoteId":9800,"url":"https://mastodon.social/@ged"\#(authorField)},
         "media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,
         "linkPreview":null,"mentions":[],"contentWarning":null,"sensitive":false,"visibility":"public"\#(noteField)}
        """#
    }
}

private final class EmojiStub: URLProtocol, @unchecked Sendable {
    static let host = "emoji.example"

    static func cache() -> RemoteImageCache {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EmojiStub.self]
        return RemoteImageCache(session: URLSession(configuration: config))
    }

    private static let wide: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 32), format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }.pngData()!
    }()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let found = request.url?.path == "/wide.png"
        let response = HTTPURLResponse(
            url: request.url!, statusCode: found ? 200 : 404, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: found ? Self.wide : Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
