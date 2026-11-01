import XCTest

@testable import kurl

@MainActor
final class ViewerChromeTests: XCTestCase {

    private let start = ContinuousClock.now

    private func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int(seconds * 1000))
    }

    func testAPhotoKeepsItsChromeUntilTapped() {
        var chrome = ViewerChrome()
        XCTAssertTrue(chrome.visible)
        XCTAssertNil(chrome.hideAt)
        chrome.tick(at: at(60))
        XCTAssertTrue(chrome.visible)

        chrome.toggle(at: at(61))
        XCTAssertFalse(chrome.visible)
        chrome.toggle(at: at(62))
        XCTAssertTrue(chrome.visible)
        XCTAssertNil(chrome.hideAt)
    }

    func testPlaybackHidesTheChromeThreeSecondsAfterItStarts() {
        var chrome = ViewerChrome()
        chrome.playback(true, at: at(0))
        XCTAssertEqual(chrome.hideAt, at(3))

        chrome.tick(at: at(2.9))
        XCTAssertTrue(chrome.visible)
        chrome.tick(at: at(3))
        XCTAssertFalse(chrome.visible)
        XCTAssertNil(chrome.hideAt)
    }

    func testTappingWhilePlayingShowsTheChromeForAnotherThreeSeconds() {
        var chrome = ViewerChrome()
        chrome.playback(true, at: at(0))
        chrome.tick(at: at(3))
        chrome.toggle(at: at(10))
        XCTAssertTrue(chrome.visible)
        XCTAssertEqual(chrome.hideAt, at(13))

        chrome.toggle(at: at(11))
        XCTAssertFalse(chrome.visible)
        XCTAssertNil(chrome.hideAt)
    }

    func testPausingBringsTheChromeBackAndKeepsIt() {
        var chrome = ViewerChrome()
        chrome.playback(true, at: at(0))
        chrome.tick(at: at(3))
        XCTAssertFalse(chrome.visible)

        chrome.playback(false, at: at(5))
        XCTAssertTrue(chrome.visible)
        XCTAssertNil(chrome.hideAt)
        chrome.tick(at: at(100))
        XCTAssertTrue(chrome.visible)
    }

    func testScrubbingKeepsTheChromeAndRestartsTheClockWhenItEnds() {
        var chrome = ViewerChrome()
        chrome.playback(true, at: at(0))
        chrome.scrubbing(true, at: at(2))
        XCTAssertTrue(chrome.visible)
        XCTAssertNil(chrome.hideAt)
        chrome.tick(at: at(30))
        XCTAssertTrue(chrome.visible)

        chrome.scrubbing(false, at: at(31))
        XCTAssertEqual(chrome.hideAt, at(34))
    }

    func testTouchingAControlRestartsTheClock() {
        var chrome = ViewerChrome()
        chrome.playback(true, at: at(0))
        chrome.touched(at: at(2))
        XCTAssertEqual(chrome.hideAt, at(5))
        chrome.tick(at: at(3))
        XCTAssertTrue(chrome.visible)
    }

    func testARepeatedPlayingReportDoesNotPushTheClockBack() {
        var chrome = ViewerChrome()
        chrome.playback(true, at: at(0))
        chrome.playback(true, at: at(2))
        XCTAssertEqual(chrome.hideAt, at(3))
    }

    func testVoiceOverNeverHidesTheChrome() {
        var chrome = ViewerChrome(autoHides: false)
        chrome.playback(true, at: at(0))
        XCTAssertNil(chrome.hideAt)
        chrome.tick(at: at(60))
        XCTAssertTrue(chrome.visible)

        var running = ViewerChrome()
        running.playback(true, at: at(0))
        running.tick(at: at(3))
        running.setAutoHides(false, at: at(4))
        XCTAssertTrue(running.visible)
        XCTAssertNil(running.hideAt)
    }

    func testTurningThePageShowsTheChromeAndForgetsPlayback() {
        var chrome = ViewerChrome()
        chrome.playback(true, at: at(0))
        chrome.tick(at: at(3))
        chrome.pageChanged()
        XCTAssertTrue(chrome.visible)
        XCTAssertNil(chrome.hideAt)
        chrome.playback(true, at: at(10))
        XCTAssertEqual(chrome.hideAt, at(13))
    }
}

@MainActor
final class MediaClockTests: XCTestCase {

    private let english = Locale(identifier: "en_US")
    private let korean = Locale(identifier: "ko_KR")

    func testTheBarShowsMinutesAndSecondsAndHoursOnlyWhenNeeded() {
        XCTAssertEqual(MediaClock.label(0, locale: english), "0:00")
        XCTAssertEqual(MediaClock.label(7.9, locale: english), "0:07")
        XCTAssertEqual(MediaClock.label(65, locale: english), "1:05")
        XCTAssertEqual(MediaClock.label(600, locale: english), "10:00")
        XCTAssertEqual(MediaClock.label(3723, locale: english), "1:02:03")
    }

    func testAnUnknownTimeReadsAsZero() {
        XCTAssertEqual(MediaClock.label(.nan, locale: english), "0:00")
        XCTAssertEqual(MediaClock.label(.infinity, locale: english), "0:00")
        XCTAssertEqual(MediaClock.label(-4, locale: english), "0:00")
    }

    func testVoiceOverHearsWordsNotDigitsWithColons() {
        XCTAssertEqual(MediaClock.spoken(65, locale: english), "1 minute, 5 seconds")
        XCTAssertEqual(MediaClock.spoken(65, locale: korean), "1분 5초")
        XCTAssertEqual(MediaClock.spoken(.nan, locale: korean), "0초")
    }
}

@MainActor
final class MediaViewerItemTests: XCTestCase {

    private func media(_ url: String, _ type: String, alt: String? = nil, width: Int? = nil, height: Int? = nil)
        -> NoteMedia
    {
        NoteMedia(url: url, altText: alt, contentType: type, width: width, height: height)
    }

    func testTheViewerPagesThroughPhotosAndVideosButNotAudio() {
        let items = [
            media("https://a.example/1.jpg", "image/jpeg", alt: "비 오는 창밖", width: 900, height: 700),
            media("https://a.example/2.mp4", "video/mp4"),
            media("https://a.example/3.mp3", "audio/mpeg"),
        ].compactMap { ViewerItem($0) }

        XCTAssertEqual(items.map(\.kind), [.photo, .video])
        XCTAssertEqual(items[0].label, "비 오는 창밖")
        XCTAssertEqual(items[0].caption, "비 오는 창밖")
        XCTAssertEqual(items[1].label, String(localized: "동영상"))
        XCTAssertNil(items[1].caption)
        XCTAssertEqual(items[0].ratio ?? 0, 900.0 / 700.0, accuracy: 0.001)
    }

    func testAnEmptyCaptionFallsBackToTheKindLabel() {
        let item = ViewerItem(media("https://a.example/1.jpg", "image/jpeg", alt: ""))
        XCTAssertEqual(item?.label, String(localized: "사진"))
    }

    func testOnlyADownwardDragClosesTheViewer() {
        XCTAssertTrue(DownwardPanRecognizer.isDownward(dx: 0, dy: 10))
        XCTAssertTrue(DownwardPanRecognizer.isDownward(dx: -4, dy: 9))
        XCTAssertFalse(DownwardPanRecognizer.isDownward(dx: 10, dy: 10))
        XCTAssertFalse(DownwardPanRecognizer.isDownward(dx: -12, dy: 3))
        XCTAssertFalse(DownwardPanRecognizer.isDownward(dx: 0, dy: -10))
    }
}

@MainActor
final class NoteEngagementTests: XCTestCase {

    private enum Failure: Error {
        case offline
    }

    private final class Calls {
        var made: [(id: Int64, on: Bool)] = []
        var seen: [(liked: Bool, count: Int64?)] = []
    }

    private func note(liked: Bool, likes: Int64?, reposted: Bool = false, reposts: Int64? = nil) -> Note {
        Note(
            id: 9504, body: "창밖 사진 세 장", createdAt: nil, editedAt: nil, likeCount: likes, likedByMe: liked,
            author: Author(id: 1, username: "honggildong", bio: nil, avatarUrl: nil), media: [], quotedPost: nil,
            inReplyToId: nil, replyCount: 0, repostCount: reposts, repostedByMe: reposted, quotedNote: nil)
    }

    private func engagement(
        _ note: Note, signedIn: Bool = true,
        like: @escaping (Int64, Bool) async throws -> Int64 = { _, _ in 0 },
        repost: @escaping (Int64, Bool) async throws -> Int64 = { _, _ in 0 }
    ) -> NoteEngagement {
        NoteEngagement(note, signedIn: { signedIn }, like: like, repost: repost)
    }

    func testALikeShowsBeforeTheServerAnswersAndThenTakesItsCount() async {
        let calls = Calls()
        var subject: NoteEngagement?
        subject = engagement(
            note(liked: false, likes: 2),
            like: { id, on in
                calls.made.append((id, on))
                calls.seen.append((subject?.liked ?? false, subject?.likeCount))
                return 9
            })
        let outcome = await subject!.toggleLike()

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(calls.made.map(\.id), [9504])
        XCTAssertEqual(calls.made.map(\.on), [true])
        XCTAssertEqual(calls.seen.map(\.liked), [true])
        XCTAssertEqual(calls.seen.map(\.count), [3])
        XCTAssertTrue(subject!.liked)
        XCTAssertEqual(subject!.likeCount, 9)
    }

    func testAFailedLikeGoesBackAndSaysSo() async {
        let subject = engagement(note(liked: true, likes: 4), like: { _, _ in throw Failure.offline })
        let outcome = await subject.toggleLike()

        XCTAssertEqual(outcome, .failed(String(localized: "좋아요를 반영하지 못했어요")))
        XCTAssertTrue(subject.liked)
        XCTAssertEqual(subject.likeCount, 4)
    }

    func testSignedOutAsksToSignInAndTouchesNothing() async {
        let calls = Calls()
        let subject = engagement(
            note(liked: false, likes: 2), signedIn: false,
            like: { id, on in
                calls.made.append((id, on))
                return 3
            },
            repost: { id, on in
                calls.made.append((id, on))
                return 3
            })
        let liked = await subject.toggleLike()
        let reposted = await subject.toggleRepost()

        XCTAssertEqual(liked, .signIn)
        XCTAssertEqual(reposted, .signIn)
        XCTAssertTrue(calls.made.isEmpty)
        XCTAssertFalse(subject.liked)
        XCTAssertEqual(subject.likeCount, 2)
    }

    func testARepostFollowsTheSameRules() async {
        let ok = engagement(note(liked: false, likes: nil, reposted: false, reposts: nil), repost: { _, _ in 1 })
        let done = await ok.toggleRepost()
        XCTAssertEqual(done, .done)
        XCTAssertTrue(ok.reposted)
        XCTAssertEqual(ok.repostCount, 1)

        let broken = engagement(
            note(liked: false, likes: nil, reposted: true, reposts: 5), repost: { _, _ in throw Failure.offline })
        let failed = await broken.toggleRepost()
        XCTAssertEqual(failed, .failed(String(localized: "리포스트하지 못했어요")))
        XCTAssertTrue(broken.reposted)
        XCTAssertEqual(broken.repostCount, 5)
    }

    func testANewCopyOfTheNoteResetsTheState() async {
        let subject = engagement(note(liked: false, likes: 2), like: { _, _ in 3 })
        _ = await subject.toggleLike()
        subject.sync(note(liked: false, likes: 7, reposted: true, reposts: 1))

        XCTAssertFalse(subject.liked)
        XCTAssertEqual(subject.likeCount, 7)
        XCTAssertTrue(subject.reposted)
        XCTAssertEqual(subject.repostCount, 1)
    }
}
