//
//  RemoteImage.swift
//  kurl
//

import ImageIO
import SwiftUI
import UIKit

/// URL → 디코드된 UIImage 메모리 캐시. AsyncImage 는 뷰가 재생성되면(덱의 화면 밖 장,
/// 리스트 재활용) 디스크 캐시 히트여도 placeholder 부터 다시 밟아 "매번 리로드"로 보인다 —
/// 여기 캐시에 있으면 첫 프레임부터 완성본을 그린다. 에디터의 ImageThumbCache 와 같은 원리,
/// 리더/피드 SwiftUI 면 전용.
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    // 디코드된 원본을 무제한 쌓지 않게 한도를 둔다 — 이미지 많은 글에서 메모리가 폭주하지 않게.
    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 80
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()
    // 표시 크기별로 서로 다른 다운로드를 나눠 타되, 같은 (URL·버킷)이면 한 번만 받는다.
    private var inFlight: [NSString: Task<UIImage?, Never>] = [:]
    /// 404·비이미지 등 확정 실패 URL — 다시 받지 않는다(재생성마다의 요청 반복 차단).
    private var failed: Set<URL> = []

    // 요청 크기를 몇 단계 버킷으로 반올림해, 40pt·46pt 아바타가 한 캐시 엔트리를 공유하게 한다.
    private static let buckets: [CGFloat] = [128, 256, 512, 1024]

    /// 표시 프레임(pt)을 화면 스케일로 px 로 올린 뒤, 그보다 크거나 같은 최소 버킷으로 올림.
    /// nil 이면 원본 그대로(라이트박스·본문 이미지) — 이 경우 URL 만으로 키를 만든다.
    private func key(for url: URL, maxPixel: CGFloat?) -> NSString {
        guard let maxPixel else { return url.absoluteString as NSString }
        let scale = UIScreen.main.scale > 0 ? UIScreen.main.scale : 3
        let px = maxPixel * scale
        let bucket = Self.buckets.first { px <= $0 } ?? Self.buckets.last!
        return "\(url.absoluteString)|\(Int(bucket))" as NSString
    }

    func cached(_ url: URL, maxPixel: CGFloat? = nil) -> UIImage? {
        cache.object(forKey: key(for: url, maxPixel: maxPixel))
    }

    /// 캐시에 있으면 즉시, 없으면 받아서 캐시 후 반환. 같은 (URL·크기) 동시 요청은 한 다운로드를 나눠 탄다.
    /// maxPixel 을 주면 그 크기에 맞춰 ImageIO 로 축소해 저장 — 380pt 카드에 2000px 원본을 쥐고 있지 않게.
    func load(_ url: URL, maxPixel: CGFloat? = nil) async -> UIImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }
        if failed.contains(url) { return nil }
        let cacheKey = key(for: url, maxPixel: maxPixel)
        if let running = inFlight[cacheKey] { return await running.value }
        let task = Task { () -> UIImage? in
            // 전송 오류(오프라인 등)는 일시적일 수 있어 블랙리스트에 넣지 않는다 — 다음 기회에 재시도.
            guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
            let statusOK =
                (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            guard statusOK else {
                self.failed.insert(url)
                return nil
            }
            let image: UIImage
            if let maxPixel, let downsampled = Self.downsample(data, maxPixel: maxPixel) {
                // 축소본은 이미 그릴 준비가 끝난 비트맵 — byPreparingForDisplay 를 다시 밟지 않는다.
                image = downsampled
            } else {
                // maxPixel 없음(원본) 또는 이례적 포맷으로 썸네일 실패 — 기존 원본 경로로 폴백.
                guard let full = UIImage(data: data) else {
                    self.failed.insert(url)
                    return nil
                }
                // 표시 시점의 메인 스레드 디코드 히치를 피한다 — 캐시에는 그릴 준비가 끝난 비트맵만.
                image = await full.byPreparingForDisplay() ?? full
            }
            // 비용은 실제로 저장하는(축소된) 크기로 다시 계산한다.
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            self.cache.setObject(image, forKey: cacheKey, cost: cost)
            return image
        }
        inFlight[cacheKey] = task
        let result = await task.value
        inFlight[cacheKey] = nil
        return result
    }

    /// ImageIO 썸네일 — 원본을 통째로 디코드하지 않고 maxPixel(px) 이하로 바로 줄인다.
    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let scale = UIScreen.main.scale > 0 ? UIScreen.main.scale : 3
        let px = maxPixel * scale
        let bucket = buckets.first { px <= $0 } ?? buckets.last!
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

enum RemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

/// AsyncImage 대체 — RemoteImageCache 히트면 placeholder·페이드 없이 첫 프레임부터 이미지.
/// 미스면 placeholder → 네트워크 → (지정 시) 애니메이션과 함께 등장. 즉 모션은 진짜 첫
/// 로드에만 있고, 이미 본 이미지는 재생성돼도 그냥 거기 있다.
struct RemoteImage<Content: View>: View {
    private let url: URL?
    private let animation: Animation?
    /// 표시 프레임(pt) 상한 — 주면 캐시가 그 크기에 맞춰 축소본을 쥔다. nil(기본)이면 원본
    /// 그대로라, 라이트박스·본문 이미지처럼 핀치 줌 원해상도가 필요한 자리는 그대로 둔다.
    private let maxPixel: CGFloat?
    private let content: (RemoteImagePhase) -> Content

    @State private var phase: RemoteImagePhase

    init(
        url: URL?,
        animation: Animation? = nil,
        maxPixel: CGFloat? = nil,
        @ViewBuilder content: @escaping (RemoteImagePhase) -> Content
    ) {
        self.url = url
        self.animation = animation
        self.maxPixel = maxPixel
        self.content = content
        if let url, let hit = RemoteImageCache.shared.cached(url, maxPixel: maxPixel) {
            _phase = State(initialValue: .success(Image(uiImage: hit)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else { return }
                if let hit = RemoteImageCache.shared.cached(url, maxPixel: maxPixel) {
                    phase = .success(Image(uiImage: hit))
                    return
                }
                // 같은 identity 로 url 만 바뀐 경우 — 이전 글 이미지가 남아 보이지 않게 비운다.
                if case .success = phase { phase = .empty }
                let loaded = await RemoteImageCache.shared.load(url, maxPixel: maxPixel)
                guard !Task.isCancelled else { return }
                withAnimation(animation) {
                    phase = loaded.map { .success(Image(uiImage: $0)) } ?? .failure
                }
            }
    }
}
