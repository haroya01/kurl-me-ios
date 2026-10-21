import SnapshotTesting
import SwiftUI
import XCTest

@testable import kurl

@MainActor
final class NotePollSnapshotTests: XCTestCase {

    override func invokeTest() {
        let record: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : .missing
        withSnapshotTesting(record: record) { super.invokeTest() }
    }

    private func poll(_ options: [(String, Int)], multiple: Bool, voted: Bool) throws -> NotePoll {
        let total = options.map(\.1).reduce(0, +)
        let json: [String: Any] = [
            "expiresAt": NSNull(), "expired": false, "multiple": multiple,
            "votesCount": total, "votersCount": total,
            "options": options.map { ["title": $0.0, "votesCount": $0.1] },
            "voted": voted, "ownVotes": voted ? [0] : [],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(NotePoll.self, from: data)
    }

    private func single(voted: Bool) throws -> NotePoll {
        try poll([("국밥", 5), ("파스타", 3), ("샐러드", 1)], multiple: false, voted: voted)
    }

    private func multiple() throws -> NotePoll {
        try poll([("헥사고날 아키텍처에서 포트와 어댑터 이름을 정하는 기준", 4), ("테스트 더블", 2), ("도메인 이벤트", 3), ("배포", 1)],
                 multiple: true, voted: false)
    }

    private func card(_ poll: NotePoll) -> some View {
        NotePollView(noteId: 1, poll: poll) { _ in }
            .padding(16)
            .frame(width: 360, alignment: .topLeading)
            .background(Palette.readingBg)
    }

    private func check(_ poll: NotePoll, height: CGFloat, named name: String) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertSnapshot(
                of: card(poll),
                as: .image(
                    precision: 0.99, perceptualPrecision: 0.98,
                    layout: .fixed(width: 360, height: height),
                    traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light",
                testName: name)
        }
    }

    func testSingleChoiceBeforeVoting() throws {
        check(try single(voted: false), height: 230, named: "single")
    }

    func testMultipleChoiceBeforeVoting() throws {
        check(try multiple(), height: 380, named: "multiple")
    }

    func testResultsAfterVoting() throws {
        check(try single(voted: true), height: 210, named: "results")
    }
}
