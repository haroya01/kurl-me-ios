//
//  NoteImageUpload.swift
//  kurl
//

import ImageIO
import UIKit
import UniformTypeIdentifiers

/// 노트에 올릴 사진 한 장 — 업로드 바이트와 그 타입·픽셀 크기.
nonisolated struct NoteUploadImage: Sendable {
    let data: Data
    let contentType: String
    let pixelWidth: Int
    let pixelHeight: Int

    static let maxSide = 2400

    /// 피커가 준 원본 → 업로드할 사진. GIF 는 원본 그대로, 나머지는 긴 변 2400px JPEG(원본 메타데이터 없음).
    static func prepare(_ original: Data) async -> NoteUploadImage? {
        await Task.detached(priority: .userInitiated) { () -> NoteUploadImage? in
            let sourceOptions = [kCGImageSourceShouldCache: false] as [CFString: Any] as CFDictionary
            guard let source = CGImageSourceCreateWithData(original as CFData, sourceOptions) else { return nil }
            if CGImageSourceGetType(source) as String? == UTType.gif.identifier {
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties?[kCGImagePropertyPixelHeight] as? Int
                else { return nil }
                return NoteUploadImage(data: original, contentType: "image/gif", pixelWidth: width, pixelHeight: height)
            }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
            ] as [CFString: Any] as CFDictionary
            guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
                  let jpeg = UIImage(cgImage: scaled).jpegData(compressionQuality: 0.85)
            else { return nil }
            return NoteUploadImage(
                data: jpeg, contentType: "image/jpeg", pixelWidth: scaled.width, pixelHeight: scaled.height)
        }.value
    }
}

nonisolated struct NoteImageTooLarge: LocalizedError {
    let maxBytes: Int64

    var errorDescription: String? {
        String(localized: "사진이 너무 커서 올리지 못했어요 — 한 장에 \(maxBytes / 1_048_576)MB까지 올릴 수 있어요")
    }
}
