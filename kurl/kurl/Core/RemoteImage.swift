//
//  RemoteImage.swift
//  kurl
//

import SwiftUI
import UIKit

/// URL → 디코드된 UIImage 메모리 캐시. AsyncImage 는 뷰가 재생성되면(덱의 화면 밖 장,
/// 리스트 재활용) 디스크 캐시 히트여도 placeholder 부터 다시 밟아 "매번 리로드"로 보인다 —
/// 여기 캐시에 있으면 첫 프레임부터 완성본을 그린다. 에디터의 ImageThumbCache 와 같은 원리,
/// 리더/피드 SwiftUI 면 전용.
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    // 디코드된 원본을 무제한 쌓지 않게 한도를 둔다 — 이미지 많은 글에서 메모리가 폭주하지 않게.
    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 80
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    /// 404·비이미지 등 확정 실패 URL — 다시 받지 않는다(재생성마다의 요청 반복 차단).
    private var failed: Set<URL> = []

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// 캐시에 있으면 즉시, 없으면 받아서 캐시 후 반환. 같은 URL 동시 요청은 한 다운로드를 나눠 탄다.
    func load(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if failed.contains(url) { return nil }
        if let running = inFlight[url] { return await running.value }
        let task = Task { () -> UIImage? in
            // 전송 오류(오프라인 등)는 일시적일 수 있어 블랙리스트에 넣지 않는다 — 다음 기회에 재시도.
            guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
            let statusOK =
                (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            guard statusOK, let image = UIImage(data: data) else {
                failed.insert(url)
                return nil
            }
            // 표시 시점의 메인 스레드 디코드 히치를 피한다 — 캐시에는 그릴 준비가 끝난 비트맵만.
            let prepared = await image.byPreparingForDisplay() ?? image
            let cost = Int(prepared.size.width * prepared.size.height * prepared.scale * prepared.scale * 4)
            cache.setObject(prepared, forKey: url as NSURL, cost: cost)
            return prepared
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        return result
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
    private let content: (RemoteImagePhase) -> Content

    @State private var phase: RemoteImagePhase

    init(
        url: URL?,
        animation: Animation? = nil,
        @ViewBuilder content: @escaping (RemoteImagePhase) -> Content
    ) {
        self.url = url
        self.animation = animation
        self.content = content
        if let url, let hit = RemoteImageCache.shared.cached(url) {
            _phase = State(initialValue: .success(Image(uiImage: hit)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else { return }
                if let hit = RemoteImageCache.shared.cached(url) {
                    phase = .success(Image(uiImage: hit))
                    return
                }
                // 같은 identity 로 url 만 바뀐 경우 — 이전 글 이미지가 남아 보이지 않게 비운다.
                if case .success = phase { phase = .empty }
                let loaded = await RemoteImageCache.shared.load(url)
                guard !Task.isCancelled else { return }
                withAnimation(animation) {
                    phase = loaded.map { .success(Image(uiImage: $0)) } ?? .failure
                }
            }
    }
}
