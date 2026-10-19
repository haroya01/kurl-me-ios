//
//  RemoteImage.swift
//  kurl
//

import ImageIO
import SwiftUI
import UIKit

enum ImageVariant {
    static let host = "d82putaebkgm4.cloudfront.net"
    private static let prefixes = ["/note-images/", "/post-images/"]
    private static let extensions = ["jpg": "jpg", "jpeg": "jpg", "png": "png"]

    static func width(forSlotPixels slotPixels: CGFloat) -> Int {
        slotPixels <= 480 ? 480 : 1080
    }

    static func url(for url: URL, slotPixels: CGFloat) -> URL {
        guard url.host?.lowercased() == host,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        let path = components.percentEncodedPath
        guard prefixes.contains(where: path.hasPrefix) else { return url }
        let ext = url.pathExtension
        guard let variantExt = extensions[ext.lowercased()] else { return url }
        guard !path.contains(".w480."), !path.contains(".w1080.") else { return url }
        let width = width(forSlotPixels: slotPixels)
        components.percentEncodedPath = String(path.dropLast(ext.count)) + "w\(width).\(variantExt)"
        return components.url ?? url
    }
}

/// URL → 디코드된 UIImage 메모리 캐시. AsyncImage 는 뷰가 재생성되면(덱의 화면 밖 장,
/// 리스트 재활용) 디스크 캐시 히트여도 placeholder 부터 다시 밟아 "매번 리로드"로 보인다 —
/// 여기 캐시에 있으면 첫 프레임부터 완성본을 그린다. 에디터의 ImageThumbCache 와 같은 원리,
/// 리더/피드 SwiftUI 면 전용.
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let session: URLSession
    private let now: () -> Date

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

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
    private var failedVariants: [URL: Date] = [:]
    static let variantRetryInterval: TimeInterval = 60

    // 요청 크기를 몇 단계 버킷으로 반올림해, 40pt·46pt 아바타가 한 캐시 엔트리를 공유하게 한다.
    nonisolated private static let buckets: [CGFloat] = [128, 256, 512, 1024]

    private static var scale: CGFloat { UIScreen.main.scale > 0 ? UIScreen.main.scale : 3 }

    /// 표시 프레임(pt)을 화면 스케일로 px 로 올린 뒤, 그보다 크거나 같은 최소 버킷으로 올림.
    /// nil 이면 원본 그대로(라이트박스·본문 이미지) — 이 경우 URL 만으로 키를 만든다.
    private func key(for url: URL, maxPixel: CGFloat?, slotWidth: CGFloat?) -> NSString {
        if let maxPixel {
            let px = maxPixel * Self.scale
            let bucket = Self.buckets.first { px <= $0 } ?? Self.buckets.last!
            return "\(url.absoluteString)|\(Int(bucket))" as NSString
        }
        if let slotWidth, variant(of: url, points: slotWidth) != nil {
            return Self.variantKey(url, width: ImageVariant.width(forSlotPixels: slotWidth * Self.scale))
        }
        return url.absoluteString as NSString
    }

    private static func variantKey(_ url: URL, width: Int) -> NSString {
        "\(url.absoluteString)|w\(width)" as NSString
    }

    private func variant(of url: URL, points: CGFloat?) -> URL? {
        guard let points else { return nil }
        let variant = ImageVariant.url(for: url, slotPixels: points * Self.scale)
        return variant == url ? nil : variant
    }

    func cached(_ url: URL, maxPixel: CGFloat? = nil, slotWidth: CGFloat? = nil) -> UIImage? {
        cache.object(forKey: key(for: url, maxPixel: maxPixel, slotWidth: slotWidth))
    }

    func cachedVariant(_ url: URL) -> UIImage? {
        cache.object(forKey: Self.variantKey(url, width: 1080))
            ?? cache.object(forKey: Self.variantKey(url, width: 480))
    }

    /// 캐시에 있으면 즉시, 없으면 받아서 캐시 후 반환. 같은 (URL·크기) 동시 요청은 한 다운로드를 나눠 탄다.
    /// maxPixel 을 주면 그 크기에 맞춰 ImageIO 로 축소해 저장 — 380pt 카드에 2000px 원본을 쥐고 있지 않게.
    func load(_ url: URL, maxPixel: CGFloat? = nil, slotWidth: CGFloat? = nil) async -> UIImage? {
        if let hit = cached(url, maxPixel: maxPixel, slotWidth: slotWidth) { return hit }
        if failed.contains(url) { return nil }
        let cacheKey = key(for: url, maxPixel: maxPixel, slotWidth: slotWidth)
        if let running = inFlight[cacheKey] { return await running.value }
        let variant = variant(of: url, points: maxPixel ?? slotWidth)
            .flatMap { recentlyFailed($0) ? nil : $0 }
        let task = Task { () -> UIImage? in
            var fetched: Fetched?
            if let variant {
                fetched = await self.fetch(variant, maxPixel: maxPixel)
                if case .rejected = fetched { self.failedVariants[variant] = self.now() }
            }
            if fetched?.image == nil {
                fetched = await self.fetch(url, maxPixel: maxPixel)
                if case .rejected = fetched { self.failed.insert(url) }
            }
            guard let image = fetched?.image else { return nil }
            // 비용은 실제로 저장하는(축소된) 크기로 다시 계산한다.
            let frames = CGFloat(max(1, image.images?.count ?? 1))
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4 * frames)
            self.cache.setObject(image, forKey: cacheKey, cost: cost)
            return image
        }
        inFlight[cacheKey] = task
        let result = await task.value
        inFlight[cacheKey] = nil
        return result
    }

    private func recentlyFailed(_ variant: URL) -> Bool {
        guard let failedAt = failedVariants[variant] else { return false }
        return now().timeIntervalSince(failedAt) < Self.variantRetryInterval
    }

    private enum Fetched {
        case image(UIImage)
        case rejected
        case unreachable

        var image: UIImage? {
            if case .image(let image) = self { return image }
            return nil
        }
    }

    private func fetch(_ url: URL, maxPixel: CGFloat?) async -> Fetched {
        // 전송 오류(오프라인 등)는 일시적일 수 있어 블랙리스트에 넣지 않는다 — 다음 기회에 재시도.
        guard let (data, response) = try? await session.data(from: url) else { return .unreachable }
        let statusOK =
            (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
        guard statusOK else { return .rejected }
        let scale = Self.scale
        if let animated = await Task.detached(priority: .userInitiated, operation: {
            Self.animated(data, maxPixel: maxPixel, scale: scale)
        }).value {
            return .image(animated)
        }
        // 축소·디코드는 이미지 크기만큼 걸리는 동기 작업 — 메인 액터(기본 격리)에서 돌면 스크롤 중
        // 카드가 들어올 때마다 프레임을 먹는다. 분리된 작업에서 하고 결과만 받는다.
        var downsampled: UIImage?
        if let maxPixel {
            downsampled = await Task.detached(priority: .userInitiated) {
                Self.downsample(data, maxPixel: maxPixel, scale: scale)
            }.value
        }
        if let downsampled {
            // 축소본은 이미 그릴 준비가 끝난 비트맵 — byPreparingForDisplay 를 다시 밟지 않는다.
            return .image(downsampled)
        }
        // maxPixel 없음(원본) 또는 이례적 포맷으로 썸네일 실패 — 기존 원본 경로로 폴백.
        guard let full = UIImage(data: data) else { return .rejected }
        // 표시 시점의 메인 스레드 디코드 히치를 피한다 — 캐시에는 그릴 준비가 끝난 비트맵만.
        return .image(await full.byPreparingForDisplay() ?? full)
    }

    nonisolated static let animatedByteBudget = 48 * 1024 * 1024
    nonisolated static let animatedFrameLimit = 300

    nonisolated static func animated(_ data: Data, maxPixel: CGFloat?, scale: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 1, count <= animatedFrameLimit,
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
            let height = props[kCGImagePropertyPixelHeight] as? CGFloat, width > 0, height > 0
        else { return nil }
        var side = min(max(width, height), (maxPixel ?? 1024 / scale) * scale)
        let budgetSide = (CGFloat(animatedByteBudget) / CGFloat(count * 4) * max(width, height) / min(width, height)).squareRoot()
        side = min(side, budgetSide)
        guard side >= min(64, max(width, height)) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(src, index, options as CFDictionary) else { return nil }
            frames.append(UIImage(cgImage: frame))
            duration += frameDelay(src, index)
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    nonisolated static func frameDelay(_ src: CGImageSource, _ index: Int) -> TimeInterval {
        let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
        let dict = (props?[kCGImagePropertyGIFDictionary] ?? props?[kCGImagePropertyPNGDictionary]
            ?? props?[kCGImagePropertyWebPDictionary]) as? [CFString: Any]
        let keys = [
            kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime,
            kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime,
            kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime,
        ]
        let delay = keys.lazy.compactMap { dict?[$0] as? Double }.first { $0 > 0 } ?? 0
        return delay < 0.02 ? 0.1 : delay
    }

    /// ImageIO 썸네일 — 원본을 통째로 디코드하지 않고 maxPixel(px) 이하로 바로 줄인다.
    nonisolated private static func downsample(_ data: Data, maxPixel: CGFloat, scale: CGFloat) -> UIImage? {
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
    private let slotWidth: CGFloat?
    private let content: (RemoteImagePhase) -> Content

    @State private var phase: RemoteImagePhase
    @State private var animated: UIImage?
    @Environment(\.accessibilityPlayAnimatedImages) private var playsAnimatedImages

    init(
        url: URL?,
        animation: Animation? = nil,
        maxPixel: CGFloat? = nil,
        slotWidth: CGFloat? = nil,
        @ViewBuilder content: @escaping (RemoteImagePhase) -> Content
    ) {
        self.url = url
        self.animation = animation
        self.maxPixel = maxPixel
        self.slotWidth = slotWidth
        self.content = content
        if let url, let hit = RemoteImageCache.shared.cached(url, maxPixel: maxPixel, slotWidth: slotWidth) {
            _phase = State(initialValue: .success(Self.still(hit)))
            _animated = State(initialValue: Self.frames(hit) == nil ? nil : hit)
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        frame
            .task(id: url) {
                guard let url else { return }
                if let hit = RemoteImageCache.shared.cached(url, maxPixel: maxPixel, slotWidth: slotWidth) {
                    show(hit)
                    return
                }
                // 같은 identity 로 url 만 바뀐 경우 — 이전 글 이미지가 남아 보이지 않게 비운다.
                if case .success = phase {
                    phase = .empty
                    animated = nil
                }
                let loaded = await RemoteImageCache.shared.load(url, maxPixel: maxPixel, slotWidth: slotWidth)
                guard !Task.isCancelled else { return }
                withAnimation(animation) {
                    if let loaded { show(loaded) } else { phase = .failure }
                }
            }
    }

    @ViewBuilder private var frame: some View {
        if let animated, let frames = Self.frames(animated), playsAnimatedImages {
            TimelineView(.animation(minimumInterval: animated.duration / Double(frames.count))) { context in
                let index = Self.frameIndex(at: context.date, count: frames.count, duration: animated.duration)
                content(.success(Image(uiImage: frames[index])))
            }
        } else {
            content(phase)
        }
    }

    private func show(_ image: UIImage) {
        phase = .success(Self.still(image))
        animated = Self.frames(image) == nil ? nil : image
    }

    private static func frames(_ image: UIImage) -> [UIImage]? {
        guard let frames = image.images, frames.count > 1, image.duration > 0 else { return nil }
        return frames
    }

    private static func still(_ image: UIImage) -> Image {
        Image(uiImage: frames(image)?.first ?? image)
    }

    static func frameIndex(at date: Date, count: Int, duration: TimeInterval) -> Int {
        guard count > 0, duration > 0 else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return min(count - 1, Int(elapsed / duration * Double(count)))
    }
}
