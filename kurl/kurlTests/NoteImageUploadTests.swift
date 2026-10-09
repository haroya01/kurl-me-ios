//
//  NoteImageUploadTests.swift
//  kurlTests
//
//  노트 사진 업로드 준비 — 원본 해상도 JPEG 가 서버 5MB 한도를 넘기던 것을 긴 변 2400px 로 줄이고
//  위치 등 원본 메타데이터를 떼며, GIF 는 웹처럼 원본 그대로 보낸다.
//

import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import kurl

final class NoteImageUploadTests: XCTestCase {

    private func encoded(
        _ type: UTType, width: Int, height: Int, frames: Int = 1, properties: [CFString: Any] = [:]
    ) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil))
        for _ in 0..<frames {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func testLargePhotoIsDownscaledToLongSide2400WithoutLocation() async throws {
        let original = try encoded(.jpeg, width: 3600, height: 2400, properties: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.6812, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.7671, kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "QA-Camera"],
        ])
        XCTAssertNotNil(try properties(of: original)[kCGImagePropertyGPSDictionary])

        let result = await NoteUploadImage.prepare(original)
        let prepared = try XCTUnwrap(result)

        XCTAssertEqual(prepared.contentType, "image/jpeg")
        XCTAssertEqual(prepared.pixelWidth, 2400)
        XCTAssertEqual(prepared.pixelHeight, 1600)
        let out = try properties(of: prepared.data)
        XCTAssertEqual(out[kCGImagePropertyPixelWidth] as? Int, 2400)
        XCTAssertNil(out[kCGImagePropertyGPSDictionary])
        let tiff = out[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNotEqual(tiff?[kCGImagePropertyTIFFMake] as? String, "QA-Camera")
    }

    func testSmallImageIsNotUpscaled() async throws {
        let original = try encoded(.png, width: 300, height: 200)
        let result = await NoteUploadImage.prepare(original)
        let prepared = try XCTUnwrap(result)
        XCTAssertEqual(prepared.contentType, "image/jpeg")
        XCTAssertEqual(prepared.pixelWidth, 300)
        XCTAssertEqual(prepared.pixelHeight, 200)
    }

    func testGifIsSentAsIs() async throws {
        let original = try encoded(.gif, width: 320, height: 240, frames: 2)
        let result = await NoteUploadImage.prepare(original)
        let prepared = try XCTUnwrap(result)
        XCTAssertEqual(prepared.contentType, "image/gif")
        XCTAssertEqual(prepared.data, original)
        XCTAssertEqual(prepared.pixelWidth, 320)
        XCTAssertEqual(prepared.pixelHeight, 240)
    }

    func testNotAnImageIsRejected() async {
        let prepared = await NoteUploadImage.prepare(Data("not an image".utf8))
        XCTAssertNil(prepared)
    }

    func testTooLargeMessageNamesTheLimit() {
        let message = NoteImageTooLarge(maxBytes: 5 * 1024 * 1024).errorDescription ?? ""
        XCTAssertTrue(message.contains("5MB"), message)
    }
}
