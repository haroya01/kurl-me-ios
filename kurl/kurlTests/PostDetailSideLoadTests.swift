import XCTest

@testable import kurl

@MainActor
final class PostDetailSideLoadTests: XCTestCase {

    override func tearDown() async throws {
        BlogAPI.client = .shared
        NoteAPI.client = .shared
        SlowServer.reset()
    }

    func testCommentsAndQuotesAreAskedTogether() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowServer.self]
        let client = APIClient(session: URLSession(configuration: config), viewerToken: { nil }, bearerToken: { nil })
        BlogAPI.client = client
        NoteAPI.client = client

        let model = PostDetailViewModel(username: "writer", slug: "side-loads", recordsView: false)
        await model.load()

        guard case .loaded = model.phase else { return XCTFail("본문을 띄우지 않았다: \(model.phase)") }
        XCTAssertTrue(model.commentsLoaded)
        let comments = try XCTUnwrap(SlowServer.started(pathSuffix: "/comments"))
        let quotes = try XCTUnwrap(SlowServer.started(pathSuffix: "/quotes"))
        XCTAssertLessThan(abs(quotes.timeIntervalSince(comments)), SlowServer.delay / 2)
    }
}

private final class SlowServer: URLProtocol, @unchecked Sendable {
    static let delay: TimeInterval = 0.3
    nonisolated(unsafe) private static var starts: [(path: String, at: Date)] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        starts = []
        lock.unlock()
    }

    static func started(pathSuffix: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return starts.first { $0.path.hasSuffix(pathSuffix) }?.at
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.starts.append((path, Date()))
        Self.lock.unlock()
        let body: String =
            if path.hasSuffix("/comments") {
                "[]"
            } else if path.hasSuffix("/quotes") {
                #"{"items":[],"page":0,"hasNext":false,"total":0}"#
            } else {
                #"""
                {"author":{"id":2,"username":"writer","bio":null,"avatarUrl":null},
                 "post":{"id":77,"slug":"side-loads","title":"Side","excerpt":null,"ogImageUrl":null,
                         "languageTag":"ko","tags":[],"likeCount":0,"publishedAt":null,"lastEditedAt":null,"pinned":false},
                 "blocks":[]}
                """#
            }
        let url = request.url!
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
