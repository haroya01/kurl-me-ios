import CoreGraphics
import Foundation
import ImageIO
import Intents
import UniformTypeIdentifiers
import UserNotifications

struct PushFaceActor: Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: URL?

    var name: String { displayName ?? username }
}

enum PushFacePlan: Equatable {
    case untouched
    case conversation(PushFaceActor, thread: String?, group: String?, type: String?)
    case thumbnail(PushFaceActor, avatar: URL)
}

enum PushFace {
    static let avatarHosts: Set<String> = ["d82putaebkgm4.cloudfront.net"]
    static let avatarByteLimit = 5 << 20
    static let faceSide = 240

    static func plan(_ userInfo: [AnyHashable: Any], thread: String) -> PushFacePlan {
        guard let actor = actor(userInfo["actor"] ?? (userInfo["actors"] as? [Any])?.first) else {
            return .untouched
        }
        if (userInfo["communication"] as? NSNumber)?.boolValue == true {
            let room = (userInfo["room"] as? [String: Any])?["name"] as? String
            return .conversation(
                actor, thread: filled(thread), group: filled(room), type: userInfo["type"] as? String)
        }
        guard let avatar = actor.avatar else { return .untouched }
        return .thumbnail(actor, avatar: avatar)
    }

    static func actor(_ raw: Any?) -> PushFaceActor? {
        guard let raw = raw as? [String: Any], let username = filled(raw["username"] as? String) else {
            return nil
        }
        let id: String? =
            switch raw["id"] {
            case let value as String: filled(value)
            case let value as NSNumber: value.stringValue
            default: nil
            }
        return PushFaceActor(
            id: id ?? username,
            username: username,
            displayName: filled(raw["displayName"] as? String),
            avatar: allowedAvatar(raw["avatarUrl"] as? String))
    }

    static func allowedAvatar(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), allows(url) else { return nil }
        return url
    }

    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased()
        else { return false }
        return avatarHosts.contains(host)
    }

    static func accepts(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = http.url, allows(url),
              http.mimeType?.lowercased().hasPrefix("image/") == true
        else { return false }
        return http.expectedContentLength <= Int64(avatarByteLimit)
    }

    static func collect<Bytes: AsyncSequence>(_ bytes: Bytes, limit: Int) async throws -> Data
    where Bytes.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    static func download(_ url: URL) async throws -> Data {
        guard allows(url) else { throw URLError(.badURL) }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        let (bytes, response) = try await session.bytes(for: request)
        guard accepts(response) else { throw URLError(.badServerResponse) }
        return try await collect(bytes, limit: avatarByteLimit)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func face(_ data: Data, side: Int = faceSide, round: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: side * 2,
                ] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        if round {
            context.addEllipse(in: canvas)
            context.clip()
        }
        let scale = CGFloat(side) / CGFloat(min(image.width, image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        context.interpolationQuality = .high
        context.draw(
            image, in: CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2, width: width, height: height))
        guard let shaped = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, shaped, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func intent(
        _ actor: PushFaceActor, thread: String?, group: String?, type: String?, body: String, image: INImage?
    ) -> INSendMessageIntent {
        let sender = INPerson(
            personHandle: INPersonHandle(value: actor.username, type: .unknown),
            nameComponents: nil,
            displayName: actor.name,
            image: image,
            contactIdentifier: nil,
            customIdentifier: actor.id,
            isMe: false,
            suggestionType: .socialProfile)
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: body,
            speakableGroupName: group.map { INSpeakableString(spokenPhrase: $0) },
            conversationIdentifier: thread,
            serviceName: nil,
            sender: sender,
            attachments: nil)
        let metadata = INSendMessageIntentDonationMetadata()
        metadata.mentionsCurrentUser = type == "MENTION" || type == "NOTE_MENTION"
        metadata.isReplyToCurrentUser = type == "REPLY" || type == "NOTE_REPLY"
        intent.donationMetadata = metadata
        return intent
    }

    static func within<Value: Sendable>(
        _ budget: Duration, _ work: @escaping @Sendable () async throws -> Value
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            let finish = PushFaceOnce<Value?> { continuation.resume(returning: $0) }
            let worker = Task { finish(try? await work()) }
            Task {
                try? await Task.sleep(for: budget)
                worker.cancel()
                finish(nil)
            }
        }
    }

    private static func filled(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

struct PushFaceDecorator: Sendable {
    var fetch: @Sendable (URL) async throws -> Data = PushFace.download
    var donate: @Sendable (INInteraction) async throws -> Void = { try await $0.donate() }
    var adopt: @Sendable (UNNotificationContent, INSendMessageIntent) throws -> UNNotificationContent = {
        try $0.updating(from: $1)
    }
    var budget: Duration = .seconds(5)
    var directory: URL = FileManager.default.temporaryDirectory

    func decorate(_ content: UNNotificationContent) async -> UNNotificationContent {
        switch PushFace.plan(content.userInfo, thread: content.threadIdentifier) {
        case .untouched:
            return content
        case let .conversation(actor, thread, group, type):
            var image: INImage?
            if let avatar = actor.avatar {
                guard let face = await face(avatar, round: false) else { return content }
                image = INImage(imageData: face)
            }
            let intent = PushFace.intent(
                actor, thread: thread, group: group, type: type, body: content.body, image: image)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            do {
                try await donate(interaction)
                return try adopt(content, intent)
            } catch {
                return content
            }
        case let .thumbnail(_, avatar):
            guard let face = await face(avatar, round: true),
                  let attachment = attachment(face),
                  let decorated = content.mutableCopy() as? UNMutableNotificationContent
            else { return content }
            decorated.attachments = [attachment]
            return decorated
        }
    }

    private func face(_ avatar: URL, round: Bool) async -> Data? {
        let fetch = fetch
        guard let data = await PushFace.within(budget, { try await fetch(avatar) }) else { return nil }
        return PushFace.face(data, round: round)
    }

    private func attachment(_ png: Data) -> UNNotificationAttachment? {
        let file = directory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try png.write(to: file)
            return try UNNotificationAttachment(identifier: "face", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
    }
}

final class PushFaceOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((Value) -> Void)?

    init(_ handler: @escaping (Value) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ value: Value) {
        lock.lock()
        let handler = handler
        self.handler = nil
        lock.unlock()
        handler?(value)
    }
}
