//
//  ImageVariantTests.swift
//  kurlTests
//
//  사진 사본(w480·w1080) 주소 규칙과, 사본이 없을 때 원본으로 물러서기.
//

import SwiftUI
import XCTest

@testable import kurl

@MainActor
final class ImageVariantTests: XCTestCase {

    private let cdn = "https://\(ImageVariant.host)"

    private func variant(_ path: String, _ slotPixels: CGFloat = 1170) -> String {
        ImageVariant.url(for: URL(string: cdn + path)!, slotPixels: slotPixels).absoluteString
    }

    func testOurPhotoPathsGetTheVariantForTheSlotWidth() {
        XCTAssertEqual(variant("/note-images/7/a.jpg", 480), cdn + "/note-images/7/a.w480.jpg")
        XCTAssertEqual(variant("/note-images/7/a.jpg", 481), cdn + "/note-images/7/a.w1080.jpg")
        XCTAssertEqual(variant("/post-images/3/b.jpg", 300), cdn + "/post-images/3/b.w480.jpg")
        XCTAssertEqual(variant("/post-images/3/b.jpg"), cdn + "/post-images/3/b.w1080.jpg")
    }

    func testJpegBecomesJpgAndPngStaysPngWhateverTheCase() {
        XCTAssertEqual(variant("/note-images/7/a.jpeg"), cdn + "/note-images/7/a.w1080.jpg")
        XCTAssertEqual(variant("/note-images/7/a.JPG"), cdn + "/note-images/7/a.w1080.jpg")
        XCTAssertEqual(variant("/note-images/7/a.JPEG", 200), cdn + "/note-images/7/a.w480.jpg")
        XCTAssertEqual(variant("/post-images/3/b.png"), cdn + "/post-images/3/b.w1080.png")
        XCTAssertEqual(variant("/post-images/3/b.PNG", 200), cdn + "/post-images/3/b.w480.png")
    }

    func testEverythingElseKeepsTheOriginal() {
        let untouched = [
            "https://images.unsplash.com/note-images/7/a.jpg",
            "https://picsum.photos/seed/x/900/700",
            cdn + "/avatars/7/a.jpg",
            cdn + "/banners/7/a.jpg",
            cdn + "/event-covers/7/a.jpg",
            cdn + "/x/note-images/7/a.jpg",
            cdn + "/note-images/7/a.gif",
            cdn + "/note-images/7/a.webp",
            cdn + "/note-images/7/a",
            cdn + "/note-images/7/a.w480.jpg",
            cdn + "/post-images/3/b.w1080.png",
        ]
        for original in untouched {
            XCTAssertEqual(
                ImageVariant.url(for: URL(string: original)!, slotPixels: 1170).absoluteString, original)
        }
    }

    func testTheRestOfTheAddressSurvives() {
        XCTAssertEqual(variant("/note-images/7/a%20b.jpg?v=2"), cdn + "/note-images/7/a%20b.w1080.jpg?v=2")
    }

    private func cache(now: @escaping () -> Date = Date.init) -> RemoteImageCache {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageCDNStub.self]
        return RemoteImageCache(session: URLSession(configuration: config), now: now)
    }

    override func setUp() {
        super.setUp()
        ImageCDNStub.reset()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(ImageCDNStub.self)
        ImageCDNStub.reset()
        super.tearDown()
    }

    private var sameVariantOtherBucket: CGFloat { 500 / UIScreen.main.scale }

    private func photo() -> (url: URL, dir: String) {
        let dir = "/note-images/7/\(UUID().uuidString)"
        return (URL(string: cdn + dir + ".jpg")!, dir)
    }

    func testAMissingVariantFallsBackToTheOriginalOnceAndIsNotAskedAgainRightAway() async {
        let cache = cache()
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(403, Data()))
        ImageCDNStub.serve(dir + ".w480.jpg", .status(403, Data()))
        ImageCDNStub.serve(dir + ".jpg", .status(200, ImageCDNStub.red))

        let first = await cache.load(url, maxPixel: 900)
        XCTAssertNotNil(first)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg"])

        let again = await cache.load(url, maxPixel: sameVariantOtherBucket)
        XCTAssertNotNil(again)
        XCTAssertEqual(
            ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg", dir + ".jpg"],
            "사본 실패는 기억하고, 원본은 막지 않는다")

        let small = await cache.load(url, maxPixel: 20)
        XCTAssertNotNil(small)
        XCTAssertEqual(ImageCDNStub.requested.suffix(2), [dir + ".w480.jpg", dir + ".jpg"])
    }

    func testAFreshCacheTriesTheVariantAgain() async {
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(403, Data()))
        ImageCDNStub.serve(dir + ".jpg", .status(200, ImageCDNStub.red))
        _ = await cache().load(url, maxPixel: 900)

        ImageCDNStub.serve(dir + ".w1080.jpg", .status(200, ImageCDNStub.red))
        let next = await cache().load(url, maxPixel: 900)
        XCTAssertNotNil(next)
        XCTAssertEqual(ImageCDNStub.requested.suffix(1), [dir + ".w1080.jpg"])
    }

    func testAMissingVariantIsAskedAgainOnceTheMemoryExpires() async {
        var clock = Date(timeIntervalSince1970: 0)
        let cache = cache(now: { clock })
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(403, Data()))
        ImageCDNStub.serve(dir + ".jpg", .status(200, ImageCDNStub.red))
        _ = await cache.load(url, maxPixel: 900)

        ImageCDNStub.serve(dir + ".w1080.jpg", .status(200, ImageCDNStub.red))
        clock += RemoteImageCache.variantRetryInterval - 1
        _ = await cache.load(url, maxPixel: sameVariantOtherBucket)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg", dir + ".jpg"])

        clock += 2
        let made = await cache.load(url, slotWidth: Metrics.readingColumn)
        XCTAssertNotNil(made)
        XCTAssertEqual(
            ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg", dir + ".jpg", dir + ".w1080.jpg"],
            "방금 올린 사진은 사본이 생기면 곧 사본으로 바뀐다")
    }

    func testAPresentVariantIsTheOnlyRequest() async {
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(200, ImageCDNStub.red))
        let image = await cache().load(url, maxPixel: 900)
        XCTAssertNotNil(image)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg"])
    }

    func testAVariantThatIsNotAnImageFallsBackAndIsRemembered() async {
        let cache = cache()
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(200, Data("<Error/>".utf8)))
        ImageCDNStub.serve(dir + ".jpg", .status(200, ImageCDNStub.red))

        let first = await cache.load(url, maxPixel: 900)
        let again = await cache.load(url, maxPixel: sameVariantOtherBucket)
        XCTAssertNotNil(first)
        XCTAssertNotNil(again)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg", dir + ".jpg"])
    }

    func testAnUnreachableVariantFallsBackWithoutBeingRemembered() async {
        let cache = cache()
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .unreachable)
        ImageCDNStub.serve(dir + ".jpg", .status(200, ImageCDNStub.red))

        let offline = await cache.load(url, maxPixel: 900)
        XCTAssertNotNil(offline)
        _ = await cache.load(url, maxPixel: sameVariantOtherBucket)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg", dir + ".w1080.jpg", dir + ".jpg"])
    }

    func testAMissingOriginalIsStillBlockedForTheSession() async {
        let cache = cache()
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(403, Data()))
        ImageCDNStub.serve(dir + ".jpg", .status(404, Data()))

        let gone = await cache.load(url, maxPixel: 900)
        let again = await cache.load(url, maxPixel: 20)
        XCTAssertNil(gone)
        XCTAssertNil(again)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg"])
    }

    func testBodyImagesUseTheVariantAndTheLightboxTheOriginal() async {
        let cache = cache()
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(200, ImageCDNStub.red))
        ImageCDNStub.serve(dir + ".jpg", .status(200, ImageCDNStub.red))

        let body = await cache.load(url, slotWidth: Metrics.readingColumn)
        XCTAssertNotNil(body)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg"])
        XCTAssertNotNil(cache.cachedVariant(url), "라이트박스는 원본이 오기 전까지 본문 사본을 보여 준다")
        XCTAssertNil(cache.cached(url))

        let full = await cache.load(url)
        XCTAssertNotNil(full)
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg"])
    }

    func testRemoteBodyImagesShareTheLightboxEntryAsBefore() async {
        let cache = cache()
        let url = URL(string: "https://\(ImageCDNStub.remoteHost)/\(UUID().uuidString).jpg")!
        ImageCDNStub.serve(url.path, .status(200, ImageCDNStub.red))

        _ = await cache.load(url, slotWidth: Metrics.readingColumn)
        XCTAssertNotNil(cache.cached(url))
        XCTAssertEqual(ImageCDNStub.requested, [url.path])
    }

    func testAFeedPhotoStillShowsWhenEveryVariantIsMissing() async throws {
        URLProtocol.registerClass(ImageCDNStub.self)
        let (url, dir) = photo()
        ImageCDNStub.serve(dir + ".w1080.jpg", .status(403, Data()))
        ImageCDNStub.serve(dir + ".w480.jpg", .status(403, Data()))
        ImageCDNStub.serve(dir + ".jpg", .status(200, ImageCDNStub.red))

        let note = try JSONDecoder.blog.decode(Note.self, from: Data(#"""
            {"id":91,"body":"창밖","createdAt":"2026-10-17T00:00:00Z","editedAt":null,"likeCount":null,
             "likedByMe":null,"author":{"id":3,"username":"reader","bio":null,"avatarUrl":null},
             "media":[{"url":"\#(url.absoluteString)","altText":null,"contentType":"image/jpeg","width":1800,"height":2400}],
             "quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":null,
             "quotedNote":null}
            """#.utf8))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.windowLevel = .alert
        window.rootViewController = UIHostingController(
            rootView: NoteRowView(note: note, onChange: { _ in }, onDelete: { _ in })
                .frame(width: 390)
                .background(Color.white)
                .environment(\.colorScheme, .light))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var shown = 0
        var waited = 0
        while shown == 0, waited < 50 {
            try await Task.sleep(for: .milliseconds(100))
            shown = Self.redPixels(in: window)
            waited += 1
        }
        XCTAssertGreaterThan(shown, 10_000, "사본이 모두 403이어도 피드 사진은 원본으로 그려진다")
        XCTAssertEqual(ImageCDNStub.requested, [dir + ".w1080.jpg", dir + ".jpg"])
    }

    private static func redPixels(in window: UIWindow) -> Int {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cg = image.cgImage, let data = cg.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else { return 0 }
        let stride = cg.bitsPerPixel / 8
        var count = 0
        for i in Swift.stride(from: 0, to: CFDataGetLength(data) - stride + 1, by: stride) {
            let (r, g, b) =
                cg.bitmapInfo.contains(.byteOrder32Little)
                ? (bytes[i + 2], bytes[i + 1], bytes[i]) : (bytes[i], bytes[i + 1], bytes[i + 2])
            if r > 200, g < 40, b < 40 { count += 1 }
        }
        return count
    }
}

private final class ImageCDNStub: URLProtocol, @unchecked Sendable {
    enum Reply {
        case status(Int, Data)
        case unreachable
    }

    static let remoteHost = "photos.example"
    static let red: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 60, height: 80), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
        }.pngData()!
    }()

    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var sent: [String] = []
    private static let lock = NSLock()

    static func serve(_ path: String, _ reply: Reply) {
        lock.lock()
        replies[path] = reply
        lock.unlock()
    }

    static var requested: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    static func reset() {
        lock.lock()
        replies = [:]
        sent = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        [ImageVariant.host, remoteHost].contains(request.url?.host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.sent.append(path)
        let reply = Self.replies[path] ?? .status(404, Data())
        Self.lock.unlock()
        switch reply {
        case .unreachable:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .status(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
