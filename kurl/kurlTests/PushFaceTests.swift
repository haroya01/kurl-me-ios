import ImageIO
import Intents
import UniformTypeIdentifiers
import UserNotifications
import XCTest

@testable import kurl

final class PushFaceTests: XCTestCase {

    private let face = "https://d82putaebkgm4.cloudfront.net/avatars/7/a.jpg"

    private func actor(_ extra: [String: Any] = [:]) -> [String: Any] {
        ["id": NSNumber(value: 7), "username": "sori", "displayName": "소리", "avatarUrl": face]
            .merging(extra) { $1 }
    }

    private func content(
        _ userInfo: [AnyHashable: Any], body: String = "sori님이 답글을 남겼습니다", thread: String = "post:42"
    ) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "kurl"
        content.body = body
        content.threadIdentifier = thread
        content.userInfo = userInfo
        return content
    }

    private func photo(width: Int = 400, height: Int = 300) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func decorator(
        fetch: @escaping @Sendable (URL) async throws -> Data,
        donate: @escaping @Sendable (INInteraction) async throws -> Void = { _ in },
        adopted: IntentBox = IntentBox()
    ) -> PushFaceDecorator {
        var decorator = PushFaceDecorator()
        decorator.fetch = fetch
        decorator.donate = donate
        decorator.adopt = { content, intent in
            adopted.intent = intent
            return content.mutableCopy() as! UNNotificationContent
        }
        decorator.budget = .milliseconds(300)
        return decorator
    }

    func testSomeoneTalkingToMeBecomesAConversation() {
        let plan = PushFace.plan(
            ["type": "NOTE_REPLY", "communication": true, "actor": actor(), "text": "저도요", "context": "내 노트에 답글"],
            thread: "note:812")
        XCTAssertEqual(
            plan,
            .conversation(
                PushFaceMessage(
                    sender: PushFaceActor(id: "user:7", username: "sori", displayName: "소리", avatar: URL(string: face)),
                    thread: "note:812", type: "NOTE_REPLY", text: "저도요", context: "내 노트에 답글")))
    }

    func testAReactionKeepsTheAppIconAndCarriesTheFace() {
        let plan = PushFace.plan(["type": "LIKE", "communication": false, "actor": actor()], thread: "")
        XCTAssertEqual(
            plan,
            .thumbnail(
                PushFaceActor(id: "user:7", username: "sori", displayName: "소리", avatar: URL(string: face)),
                avatar: URL(string: face)!))
    }

    func testAReactionFromSomeoneWithoutAPhotoIsLeftAlone() {
        let plan = PushFace.plan(
            ["type": "FOLLOW", "communication": false, "actor": actor(["avatarUrl": NSNull()])], thread: "")
        XCTAssertEqual(plan, .untouched)
    }

    func testAnOldServerPayloadPassesThroughUntouched() async {
        let legacy = content(["type": "REPLY", "actorUsername": "sori", "ownerUsername": "me", "postSlug": "p"])
        XCTAssertEqual(PushFace.plan(legacy.userInfo, thread: ""), .untouched)
        let fetched = Counter()
        let adopted = IntentBox()
        let result = await decorator(fetch: { _ in fetched.add(); return Data() }, adopted: adopted).decorate(legacy)
        XCTAssertTrue(result === legacy)
        XCTAssertEqual(fetched.value, 0)
        XCTAssertNil(adopted.intent)
    }

    func testOnlyHttpsOnOurOwnHostsIsFetched() {
        for allowed in [face, "https://D82PUTAEBKGM4.CLOUDFRONT.NET/avatars/7/a.png", "https://d82putaebkgm4.cloudfront.net:443/a.jpg"] {
            XCTAssertNotNil(PushFace.allowedAvatar(allowed), allowed)
        }
        for refused in [
            "http://d82putaebkgm4.cloudfront.net/a.jpg", "https://files.mastodon.social/a.jpg",
            "https://d82putaebkgm4.cloudfront.net.evil.example/a.jpg", "https://evil.cloudfront.net/a.jpg",
            "https://d82putaebkgm4.cloudfront.net@evil.example/a.jpg", "https://u:p@d82putaebkgm4.cloudfront.net/a.jpg",
            "https://d82putaebkgm4.cloudfront.net:8443/a.jpg", "https://evil.example/?u=d82putaebkgm4.cloudfront.net",
            "file:///var/mobile/a.jpg", "d82putaebkgm4.cloudfront.net/a.jpg", "",
        ] {
            XCTAssertNil(PushFace.allowedAvatar(refused), refused)
        }
        let foreign = PushFace.plan(
            ["communication": true, "actor": actor(["avatarUrl": "https://files.mastodon.social/a.jpg"])],
            thread: "t")
        guard case let .conversation(message) = foreign else { return XCTFail("\(foreign)") }
        XCTAssertNil(message.sender.avatar)
    }

    func testEachPushInOneThreadKeepsItsOwnSender() async throws {
        let photo = photo()
        var senders: [String?] = []
        var threads: [String?] = []
        for person in [actor(), actor(["id": NSNumber(value: 8), "username": "yuki", "displayName": NSNull()])] {
            let adopted = IntentBox()
            _ = await decorator(fetch: { _ in photo }, adopted: adopted)
                .decorate(content(["type": "NOTE_REPLY", "communication": true, "actor": person], thread: "note:812"))
            let intent = try XCTUnwrap(adopted.intent)
            senders.append(intent.sender?.customIdentifier)
            threads.append(intent.conversationIdentifier)
        }
        XCTAssertEqual(senders, ["user:7", "user:8"])
        XCTAssertEqual(threads, ["note:812", "note:812"])
    }

    func testAFailedDownloadKeepsTheOriginal() async {
        for communication in [true, false] {
            let original = content(["communication": communication, "actor": actor()])
            let result = await decorator(fetch: { _ in throw URLError(.notConnectedToInternet) }).decorate(original)
            XCTAssertTrue(result === original, "communication \(communication)")
        }
    }

    func testASlowDownloadKeepsTheOriginalWithinTheBudget() async {
        let original = content(["communication": true, "actor": actor()])
        let started = ContinuousClock.now
        let result = await decorator(fetch: { _ in
            try await Task.sleep(for: .seconds(20))
            return Data()
        }).decorate(original)
        XCTAssertTrue(result === original)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
    }

    func testAFailedDonationKeepsTheOriginal() async {
        let photo = photo()
        let original = content(["communication": true, "actor": actor()])
        let result = await decorator(
            fetch: { _ in photo }, donate: { _ in throw INIntentError(.donatingInteraction) }
        ).decorate(original)
        XCTAssertTrue(result === original)
    }

    func testTheConversationShowsWhatTheyWroteUnderTheirName() async throws {
        let photo = photo()
        let adopted = IntentBox()
        let donated = Counter()
        let result = await decorator(
            fetch: { _ in photo }, donate: { $0.direction == .incoming ? donated.add() : () }, adopted: adopted
        ).decorate(
            content(
                ["type": "MENTION", "communication": true, "actor": actor(), "text": "같이 봐요", "context": "멘션"],
                body: "sori님이 회원님을 언급했습니다"))
        let intent = try XCTUnwrap(adopted.intent)
        XCTAssertEqual(donated.value, 1)
        XCTAssertEqual(intent.sender?.displayName, "소리")
        XCTAssertEqual(intent.sender?.customIdentifier, "user:7")
        XCTAssertNotNil(intent.sender?.image)
        XCTAssertEqual(intent.conversationIdentifier, "post:42")
        XCTAssertEqual(intent.content, "같이 봐요")
        XCTAssertEqual(result.body, "같이 봐요")
        XCTAssertEqual(result.subtitle, "멘션")
        XCTAssertEqual((intent.donationMetadata as? INSendMessageIntentDonationMetadata)?.mentionsCurrentUser, true)
    }

    func testWithoutTheirWordsTheServerSentenceStays() async throws {
        let photo = photo()
        let adopted = IntentBox()
        let result = await decorator(fetch: { _ in photo }, adopted: adopted)
            .decorate(content(["type": "COMMENT", "communication": true, "actor": actor()], body: "sori님이 댓글을 남겼습니다"))
        XCTAssertEqual(result.body, "sori님이 댓글을 남겼습니다")
        XCTAssertEqual(result.subtitle, "")
        XCTAssertEqual(try XCTUnwrap(adopted.intent).content, "sori님이 댓글을 남겼습니다")
    }

    func testATappedConversationStillOpensTheReply() async throws {
        let photo = photo()
        var live = PushFaceDecorator()
        live.fetch = { _ in photo }
        live.donate = { _ in }
        let original = content([
            "type": "REPLY", "communication": true, "actor": actor(),
            "actorUsername": "sori", "ownerUsername": "me", "postSlug": "p-mock-2", "commentId": NSNumber(value: 5),
        ])
        let result = await live.decorate(original)
        XCTAssertFalse(result === original)
        XCTAssertEqual(
            NotificationRoute.route(push: result.userInfo),
            .postSpot(username: "me", slug: "p-mock-2", spot: .comment(5)))
    }

    func testARemoteSenderInARoomShowsTheirHandleAndTheRoom() async throws {
        let adopted = IntentBox()
        let fetched = Counter()
        let result = await decorator(fetch: { _ in fetched.add(); return Data() }, adopted: adopted).decorate(
            content(
                [
                    "type": "NOTE_MENTION", "communication": true, "text": "여기 봐요", "context": "도쿄 산책",
                    "actor": ["remoteId": NSNumber(value: 42), "username": "dal@qdon.space"],
                ],
                thread: "room:3"))
        let intent = try XCTUnwrap(adopted.intent)
        XCTAssertEqual(intent.sender?.displayName, "dal@qdon.space")
        XCTAssertEqual(intent.sender?.customIdentifier, "remote:42")
        XCTAssertNil(intent.sender?.image)
        XCTAssertNil(intent.speakableGroupName)
        XCTAssertEqual(intent.conversationIdentifier, "room:3")
        XCTAssertEqual(result.subtitle, "도쿄 산책")
        XCTAssertEqual(fetched.value, 0)
    }

    func testAReactionGetsARoundFaceAttachment() async throws {
        let photo = photo()
        let original = content(["type": "LIKE", "communication": false, "actor": actor()])
        let result = await decorator(fetch: { _ in photo }).decorate(original)
        XCTAssertEqual(result.attachments.count, 1)
        XCTAssertEqual(result.body, original.body)
        XCTAssertEqual(result.userInfo["postSlug"] as? String, original.userInfo["postSlug"] as? String)

        let png = try XCTUnwrap(PushFace.face(photo, side: 120, round: true))
        let image = try XCTUnwrap(
            CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil))
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 120)
        XCTAssertEqual(alpha(image, x: 2, y: 2), 0)
        XCTAssertEqual(alpha(image, x: 60, y: 60), 255)
    }

    func testAnOversizedOrForeignResponseIsRefused() async {
        func response(_ url: String, status: Int = 200, type: String = "image/jpeg", length: Int = 1000) -> URLResponse {
            HTTPURLResponse(
                url: URL(string: url)!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": type, "Content-Length": "\(length)"])!
        }
        XCTAssertTrue(PushFace.accepts(response(face)))
        XCTAssertFalse(PushFace.accepts(response(face, status: 404)))
        XCTAssertFalse(PushFace.accepts(response(face, type: "text/html")))
        XCTAssertFalse(PushFace.accepts(response(face, length: PushFace.avatarByteLimit + 1)))
        XCTAssertFalse(PushFace.accepts(response("https://evil.example/a.jpg")))

        let bytes = AsyncStream<UInt8> { continuation in
            for _ in 0..<64 { continuation.yield(1) }
            continuation.finish()
        }
        do {
            _ = try await PushFace.collect(bytes, limit: 32)
            XCTFail("collected past the limit")
        } catch {}
    }

    func testExpiryDeliversTheOriginalOnceAndDropsTheLateFace() async throws {
        let photo = photo()
        let service = NotificationService()
        service.decorator = decorator(fetch: { _ in
            try? await Task.sleep(for: .milliseconds(200))
            return photo
        })
        service.decorator.budget = .seconds(5)
        let original = content(["communication": false, "actor": actor()])
        let delivered = ContentBox()
        service.didReceive(
            UNNotificationRequest(identifier: "n", content: original, trigger: nil),
            withContentHandler: { delivered.append($0) })
        service.serviceExtensionTimeWillExpire()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.body, original.body)
        XCTAssertEqual(delivered.first?.attachments.count, 0)
    }

    func testTheExtensionDeliversTheDecoratedContent() async throws {
        let photo = photo()
        let service = NotificationService()
        service.decorator = decorator(fetch: { _ in photo })
        let delivered = ContentBox()
        service.didReceive(
            UNNotificationRequest(
                identifier: "n", content: content(["communication": false, "actor": actor()]), trigger: nil),
            withContentHandler: { delivered.append($0) })
        for _ in 0..<50 where delivered.count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        service.serviceExtensionTimeWillExpire()
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.attachments.count, 1)
    }

    private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return pixel[3]
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}

private final class IntentBox: @unchecked Sendable {
    var intent: INSendMessageIntent?
}

private final class ContentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UNNotificationContent] = []
    var count: Int { lock.withLock { items.count } }
    var first: UNNotificationContent? { lock.withLock { items.first } }
    func append(_ content: UNNotificationContent) { lock.withLock { items.append(content) } }
}
