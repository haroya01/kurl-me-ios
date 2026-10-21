import SwiftUI
import XCTest

@testable import kurl

@MainActor
final class FollowStatusUnknownTests: XCTestCase {

    private static var retained: [AnyObject] = []

    private struct Offline: Error {}

    private func status(following: Bool) throws -> InteractionsAPI.FollowStatus {
        let json = #"{"following":\#(following),"followerCount":12,"notifyNotes":false}"#
        return try JSONDecoder().decode(InteractionsAPI.FollowStatus.self, from: Data(json.utf8))
    }

    func testUnseededButtonStaysUnknownUntilStatusArrives() async throws {
        let gate = StatusGate()
        let followed = try status(following: true)
        let model = FollowModel(username: "yuki", setFollow: { _, _ in
            XCTFail("보기만 했는데 팔로우 요청이 나갔다")
            return followed
        }, fetchStatus: { _ in
            await gate.wait()
            return followed
        })
        Self.retained.append(model)
        XCTAssertFalse(model.resolved)

        let hydrating = Task { await model.hydrateIfNeeded() }
        await Task.yield()
        XCTAssertFalse(model.resolved)
        XCTAssertFalse(model.following)

        await gate.open()
        await hydrating.value
        XCTAssertTrue(model.resolved)
        XCTAssertTrue(model.following)
        XCTAssertEqual(model.userToggleCount, 0)
    }

    func testSeededButtonIsKnownAtOnce() throws {
        let model = FollowModel(username: "yuki", seed: try status(following: true))
        Self.retained.append(model)
        XCTAssertTrue(model.resolved)
        XCTAssertTrue(model.following)
    }

    func testUnknownStatusDrawsNoButton() throws {
        XCTAssertEqual(try inkedPixels(FollowButton(username: "yuki")), 0)
        XCTAssertGreaterThan(try inkedPixels(FollowButton(username: "yuki", initialStatus: try status(following: true))), 0)
        XCTAssertGreaterThan(try inkedPixels(FollowButton(username: "yuki", initialStatus: try status(following: false))), 0)
    }

    private func inkedPixels<V: View>(_ view: V) throws -> Int {
        let renderer = ImageRenderer(content: view.padding(8))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
    }

    func testFailedStatusStaysUnknown() async {
        let model = FollowModel(username: "yuki", fetchStatus: { _ in throw Offline() })
        Self.retained.append(model)
        await model.hydrate()
        XCTAssertFalse(model.resolved)
    }

    func testSignedOutTagButtonIsKnownWithoutFetching() async throws {
        try XCTSkipIf(AuthStore.shared.isSignedIn)
        let model = TagFollowModel(tag: "swift", fetchPrefs: {
            XCTFail("비로그인은 구독 상태를 묻지 않는다")
            throw Offline()
        })
        Self.retained.append(model)
        XCTAssertFalse(model.resolved)
        await model.hydrate()
        XCTAssertTrue(model.resolved)
    }
}

private actor StatusGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
