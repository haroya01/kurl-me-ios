import UIKit
import XCTest

@testable import kurl

@MainActor
final class NoteCameraTests: XCTestCase {

    func testATakenPhotoIsHandedToTheComposerAndTheCameraCloses() {
        var received: UIImage?
        var closed = 0
        let coordinator = NoteCamera.Coordinator(onImage: { received = $0 }, close: { closed += 1 })
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3)).image { _ in }
        coordinator.imagePickerController(UIImagePickerController(), didFinishPickingMediaWithInfo: [.originalImage: photo])
        XCTAssertTrue(received === photo)
        XCTAssertEqual(closed, 1)
    }

    func testCancellingClosesWithoutAttaching() {
        var received: UIImage?
        var closed = 0
        let coordinator = NoteCamera.Coordinator(onImage: { received = $0 }, close: { closed += 1 })
        coordinator.imagePickerControllerDidCancel(UIImagePickerController())
        XCTAssertNil(received)
        XCTAssertEqual(closed, 1)
    }

    func testACameraJpegBecomesAnUploadableNotePhoto() async throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let jpeg = try XCTUnwrap(photo.jpegData(compressionQuality: 0.95))
        let prepared = await NoteUploadImage.prepare(jpeg)
        let upload = try XCTUnwrap(prepared)
        XCTAssertEqual(upload.contentType, "image/jpeg")
        XCTAssertGreaterThan(upload.pixelWidth, 0)
    }
}
