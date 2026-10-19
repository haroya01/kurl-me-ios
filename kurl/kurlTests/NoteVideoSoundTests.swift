//
//  NoteVideoSoundTests.swift
//  kurlTests
//

import AVFoundation
import XCTest

@testable import kurl

@MainActor
final class NoteVideoSoundTests: XCTestCase {

    func testMutedChipOnlyWhenTheVideoHasSound() {
        XCTAssertEqual(NoteVideoTile.badge(playing: true, sound: true), .muted)
        XCTAssertEqual(NoteVideoTile.badge(playing: true, sound: false), .none)
        XCTAssertEqual(NoteVideoTile.badge(playing: true, sound: nil), .none)
        XCTAssertEqual(NoteVideoTile.badge(playing: false, sound: true), .play)
        XCTAssertEqual(NoteVideoTile.badge(playing: false, sound: false), .play)
    }

    func testSilentLoopHasNoAudio() async {
        let gif = AVMutableComposition()
        _ = gif.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let clip = AVMutableComposition()
        _ = clip.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        _ = clip.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let gifSound = await NoteVideoSound.hasAudio(gif)
        let clipSound = await NoteVideoSound.hasAudio(clip)
        XCTAssertEqual(gifSound, false)
        XCTAssertEqual(clipSound, true)
    }
}
