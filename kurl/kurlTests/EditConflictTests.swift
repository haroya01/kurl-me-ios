//
//  EditConflictTests.swift
//  kurlTests
//
//  글 동시 편집 충돌(서버 #795) — 저장은 직전 응답의 contentVersion 을 baseVersion 으로 싣고(PUT 다음 PATCH 는
//  PUT 응답 버전), 버전이 어긋난 409 는 아무것도 쓰지 않은 채 충돌로 올린다. 응답만 잃은 재시도의 409 는 서버 본문이
//  내 것과 같으면 성공. overwrite 는 막힌 요청 하나에만. 자기 쓰기끼리는 직렬. 버전을 안 주는 옛 서버엔 base 없이.
//

import XCTest

@testable import kurl

@MainActor
final class EditConflictTests: XCTestCase {

    override func setUp() async throws {
        ScriptedServer.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedServer.self]
        WriteAPI.client = APIClient(session: URLSession(configuration: config), viewerToken: { nil })
        ComposeRecoveryStore.wipeAll()
    }

    override func tearDown() async throws {
        WriteAPI.client = .shared
        ScriptedServer.reset()
        ComposeRecoveryStore.wipeAll()
    }

    private func postView(version: Int64?) -> String {
        let versionField = version.map { #","contentVersion":\#($0)"# } ?? ""
        return #"{"id":7,"slug":"p-7","title":"제목","status":"DRAFT","tags":[]\#(versionField)}"#
    }

    private let conflict = #"{"status":409,"title":"Conflict","code":"POST_EDIT_CONFLICT","detail":"post was changed by another save; current content version is 4","contentVersion":4}"#

    func testBodyThenMetadataCarryTheChainedBaseVersion() async throws {
        ScriptedServer.script("PUT /posts/7/markdown", 200, #"{"markdown":"본문","contentVersion":4}"#)
        ScriptedServer.script("PATCH /posts/7", 200, postView(version: 5))
        let gate = PostVersionGate(version: 3)

        _ = try await PostSave.send(postId: 7, markdown: "본문", metadata: .init(title: "새 제목"), gate: gate)

        let sent = ScriptedServer.requests
        XCTAssertEqual(sent.map(\.route), ["PUT /posts/7/markdown", "PATCH /posts/7"])
        XCTAssertEqual(sent[0].json["baseVersion"] as? Int, 3)
        XCTAssertNil(sent[0].json["overwrite"])
        XCTAssertEqual(sent[1].json["baseVersion"] as? Int, 4, "PATCH 의 base 는 PUT 응답 버전")
        XCTAssertEqual(gate.version, 5)
    }

    func testEditFromAnotherDeviceSurfacesAsConflictWithoutWriting() async throws {
        ScriptedServer.script("PUT /posts/7/markdown", 409, conflict)
        ScriptedServer.script("GET /posts/7/markdown", 200, #"{"markdown":"다른 기기 본문","contentVersion":4}"#)
        let gate = PostVersionGate(version: 3)

        do {
            _ = try await PostSave.send(postId: 7, markdown: "본문", metadata: .init(title: "새 제목"), gate: gate)
            XCTFail("충돌이어야 한다")
        } catch is PostEditConflict {}

        XCTAssertEqual(ScriptedServer.requests.map(\.route), ["PUT /posts/7/markdown", "GET /posts/7/markdown"])
        XCTAssertEqual(gate.version, 3)
    }

    func testRetryWhoseEarlierSaveAlreadyLandedCountsAsSuccess() async throws {
        ScriptedServer.script("PUT /posts/7/markdown", 409, conflict)
        ScriptedServer.script("GET /posts/7/markdown", 200, #"{"markdown":"본문\n","contentVersion":4}"#)
        ScriptedServer.script("PATCH /posts/7", 200, postView(version: 5))
        let gate = PostVersionGate(version: 3)

        _ = try await PostSave.send(postId: 7, markdown: "본문", metadata: .init(title: "새 제목"), gate: gate)

        XCTAssertEqual(ScriptedServer.requests.last?.json["baseVersion"] as? Int, 4)
        XCTAssertEqual(gate.version, 5)
    }

    func testOverwriteRidesOnlyOnTheRequestThatWasBlocked() async throws {
        ScriptedServer.script("PUT /posts/7/markdown", 200, #"{"markdown":"본문","contentVersion":5}"#)
        ScriptedServer.script("PATCH /posts/7", 200, postView(version: 6))
        let gate = PostVersionGate(version: 3)

        _ = try await PostSave.send(
            postId: 7, markdown: "본문", metadata: .init(title: "새 제목"), gate: gate, overwrite: true)

        let sent = ScriptedServer.requests
        XCTAssertEqual(sent[0].json["overwrite"] as? Bool, true)
        XCTAssertNil(sent[1].json["overwrite"], "이어지는 요청에 overwrite 를 붙이면 리비전이 쌓인다")
        XCTAssertEqual(sent[1].json["baseVersion"] as? Int, 5)
    }

    func testOwnVersionedWritesNeverOverlap() async throws {
        ScriptedServer.script("PATCH /posts/7", 200, postView(version: 4), delay: 0.3)
        ScriptedServer.script("PATCH /posts/7", 200, postView(version: 5))
        let gate = PostVersionGate(version: 3)

        async let first: Void = PostSave.cover(postId: 7, url: "https://img/a.jpg", key: "a", chosen: true, gate: gate)
        async let second: Void = PostSave.cover(postId: 7, url: "https://img/b.jpg", key: "b", chosen: true, gate: gate)
        _ = try await (first, second)

        XCTAssertEqual(ScriptedServer.requests.map { $0.json["baseVersion"] as? Int }, [3, 4])
        XCTAssertEqual(gate.version, 5)
    }

    func testServerWithoutVersionsGetsNoBaseVersion() async throws {
        ScriptedServer.script("PUT /posts/7/markdown", 200, #"{"markdown":"본문"}"#)
        let gate = PostVersionGate()

        _ = try await PostSave.send(postId: 7, markdown: "본문", metadata: .init(), gate: gate)

        XCTAssertNil(ScriptedServer.requests[0].json["baseVersion"])
        XCTAssertNil(ScriptedServer.requests[0].json["overwrite"])
        XCTAssertNil(gate.version)
    }

    func testOtherConflictCodesAreNotEditConflicts() async throws {
        ScriptedServer.script(
            "PATCH /posts/7", 409, #"{"status":409,"title":"Conflict","code":"SLUG_FROZEN","detail":"slug is frozen"}"#)
        do {
            try await PostSave.cover(
                postId: 7, url: "https://img/a.jpg", key: nil, chosen: true, gate: PostVersionGate(version: 3))
            XCTFail("실패해야 한다")
        } catch is PostEditConflict {
            XCTFail("다른 409 를 편집 충돌로 오인했다")
        } catch {}
    }

    func testLeavingFlushThatConflictsKeepsMyDraftOnTheDevice() async throws {
        ScriptedServer.script("PUT /posts/7/markdown", 409, conflict)
        ScriptedServer.script("GET /posts/7/markdown", 200, #"{"markdown":"다른 기기 본문","contentVersion":4}"#)
        let key = UUID()
        ComposeRecoveryStore.stash(postId: 7, draftKey: key, title: "제목", markdown: "내 본문")
        let flusher = DraftFlusher()

        flusher.flush(DraftFlusher.Payload(
            postId: 7, draftKey: key, title: "제목", markdown: "내 본문", savedTitle: "제목", savedExcerpt: "",
            savedTags: [], excerpt: "", tags: [], savedSeriesId: nil, seriesId: nil,
            gate: PostVersionGate(version: 3)))
        let deadline = Date().addingTimeInterval(3)
        while !flusher.pendingDraftKeys.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(ComposeRecoveryStore.peek(postId: 7, draftKey: key)?.markdown, "내 본문")
        XCTAssertEqual(flusher.completedTick, 0)
        XCTAssertFalse(ScriptedServer.requests.contains { $0.route == "PATCH /posts/7" })
    }

    func testConflictBackupLivesApartFromTheDraftSlot() {
        let key = UUID()
        ComposeRecoveryStore.stashConflict(postId: 7, title: "제목", markdown: "밀려난 내 본문")
        ComposeRecoveryStore.stash(postId: 7, draftKey: key, title: "제목", markdown: "최신본 위 편집")
        XCTAssertEqual(ComposeRecoveryStore.peekConflict(postId: 7)?.markdown, "밀려난 내 본문")
        ComposeRecoveryStore.clear(postId: 7, draftKey: key)
        XCTAssertEqual(ComposeRecoveryStore.peekConflict(postId: 7)?.markdown, "밀려난 내 본문")
        ComposeRecoveryStore.clearConflict(postId: 7)
        XCTAssertNil(ComposeRecoveryStore.peekConflict(postId: 7))
    }
}

/// 경로별로 정해 둔 응답을 차례로 돌려주고, 나간 요청(경로·JSON 본문)을 기록한다.
private final class ScriptedServer: URLProtocol, @unchecked Sendable {
    struct Sent {
        let route: String
        let json: [String: Any]
    }

    private struct Reply {
        let status: Int
        let body: String
        let delay: TimeInterval
    }

    nonisolated(unsafe) private static var replies: [String: [Reply]] = [:]
    nonisolated(unsafe) private static var sent: [Sent] = []
    private static let lock = NSLock()

    static func script(_ route: String, _ status: Int, _ body: String, delay: TimeInterval = 0) {
        lock.lock()
        replies[route, default: []].append(Reply(status: status, body: body, delay: delay))
        lock.unlock()
    }

    static var requests: [Sent] {
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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path.replacingOccurrences(of: "/api/v1", with: "") ?? ""
        let route = "\(request.httpMethod ?? "GET") \(path)"
        let json = Self.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        Self.lock.lock()
        Self.sent.append(Sent(route: route, json: json))
        let reply = Self.replies[route]?.isEmpty == false ? Self.replies[route]!.removeFirst() : nil
        Self.lock.unlock()
        let answer = reply ?? Reply(status: 500, body: "{}", delay: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + answer.delay) { [self] in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
