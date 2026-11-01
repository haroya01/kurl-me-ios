import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct ViewerItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case photo, video
    }

    let url: URL
    let kind: Kind
    let caption: String?
    let ratio: CGFloat?
    let label: String

    var id: URL { url }

    init(url: URL, kind: Kind, caption: String?, ratio: CGFloat? = nil, fallbackLabel: String) {
        self.url = url
        self.kind = kind
        self.caption = caption
        self.ratio = ratio
        if let caption, !caption.isEmpty {
            label = caption
        } else {
            label = fallbackLabel
        }
    }

    init?(_ media: NoteMedia) {
        guard !media.isAudio, let url = URL(string: media.url) else { return nil }
        self.init(
            url: url, kind: media.isVideo ? .video : .photo, caption: media.altText, ratio: media.ratio,
            fallbackLabel: media.isVideo ? String(localized: "동영상") : String(localized: "사진"))
    }
}

struct ViewerChrome: Equatable {
    static let autoHide: Duration = .seconds(3)

    private(set) var visible = true
    private(set) var hideAt: ContinuousClock.Instant?
    private(set) var autoHides: Bool
    private var playing = false
    private var scrubbing = false

    init(autoHides: Bool = true) {
        self.autoHides = autoHides
    }

    mutating func toggle(at now: ContinuousClock.Instant) {
        visible.toggle()
        schedule(now)
    }

    mutating func touched(at now: ContinuousClock.Instant) {
        visible = true
        schedule(now)
    }

    mutating func playback(_ playing: Bool, at now: ContinuousClock.Instant) {
        guard playing != self.playing else { return }
        self.playing = playing
        if !playing { visible = true }
        schedule(now)
    }

    mutating func scrubbing(_ on: Bool, at now: ContinuousClock.Instant) {
        scrubbing = on
        if on { visible = true }
        schedule(now)
    }

    mutating func pageChanged() {
        playing = false
        scrubbing = false
        visible = true
        hideAt = nil
    }

    mutating func setAutoHides(_ on: Bool, at now: ContinuousClock.Instant) {
        autoHides = on
        if !on { visible = true }
        schedule(now)
    }

    mutating func tick(at now: ContinuousClock.Instant) {
        guard let hideAt, now >= hideAt else { return }
        visible = false
        self.hideAt = nil
    }

    private mutating func schedule(_ now: ContinuousClock.Instant) {
        hideAt = autoHides && visible && playing && !scrubbing ? now + Self.autoHide : nil
    }
}

enum MediaClock {
    static func label(_ seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let whole = wholeSeconds(seconds)
        let pattern: Duration.TimeFormatStyle.Pattern = whole >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(whole).formatted(.time(pattern: pattern).locale(locale))
    }

    static func spoken(_ seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(wholeSeconds(seconds))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale))
    }

    private static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds.rounded(.down))
    }
}

struct MediaViewer<Actions: View>: View {
    let items: [ViewerItem]
    private let actions: () -> Actions

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @ScaledMetric(relativeTo: .footnote) private var captionSize: CGFloat = 13

    @State private var current: URL?
    @State private var chrome = ViewerChrome()
    @State private var zoomed = false
    @State private var drag: CGSize = .zero
    @State private var appeared = false
    @State private var playback: VideoPlayback?
    @State private var stageSize: CGSize = .zero
    @State private var forcedLandscape = false

    init(items: [ViewerItem], start: URL? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.items = items
        self.actions = actions
        _current = State(initialValue: start ?? items.first?.url)
    }

    private var currentItem: ViewerItem? { items.first { $0.url == current } ?? items.first }
    private var landscape: Bool { stageSize.width > stageSize.height }
    private var dismissProgress: CGFloat { zoomed ? 0 : min(1, max(0, drag.height) / 300) }
    private var chromeShown: Bool { chrome.visible && dismissProgress <= 0.05 }
    private var videoInLandscape: Bool { landscape && currentItem?.kind == .video }

    var body: some View {
        ZStack {
            Color.black
                .opacity(appeared ? 1 - Double(dismissProgress) * 0.65 : 0)
                .ignoresSafeArea()
            pager
                .scaleEffect(appeared ? 1 - dismissProgress * 0.12 : 0.94)
                .opacity(appeared ? 1 - dismissProgress * 0.3 : 0)
                .offset(x: zoomed ? 0 : drag.width * 0.4, y: zoomed ? 0 : max(0, drag.height))
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { stageSize = $0 }
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .bottom) { bottomChrome }
        .statusBarHidden(true)
        .persistentSystemOverlays(chromeShown ? .automatic : .hidden)
        .presentationBackground(.clear)
        .modifier(ToastHost())
        .accessibilityAction(.escape) { close() }
        .onAppear {
            chrome.setAutoHides(!voiceOver, at: .now)
            withAnimation(reduceMotion ? nil : Motion.move) { appeared = true }
        }
        .task(id: current) { await load(current) }
        .task(id: chrome.hideAt) { await autoHide() }
        .onChange(of: playback?.playing ?? false) { _, playing in chrome.playback(playing, at: .now) }
        .onChange(of: voiceOver) { _, on in chrome.setAutoHides(!on, at: .now) }
        .onChange(of: landscape) { _, wide in if !wide { forcedLandscape = false } }
        .onDisappear {
            playback?.stop()
            restorePortrait()
        }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    page(item)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.url)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
        .scrollDisabled(items.count < 2 || zoomed)
        .ignoresSafeArea()
        .gesture(DownwardPan(isEnabled: !zoomed, changed: { drag = $0 }, ended: dragEnded))
    }

    @ViewBuilder private func page(_ item: ViewerItem) -> some View {
        switch item.kind {
        case .photo:
            PhotoPage(item: item, isCurrent: item.url == current, onTap: toggleChrome) { zoom in
                if item.url == current { zoomed = zoom }
            }
        case .video:
            VideoPage(
                item: item, playback: playback?.url == item.url ? playback : nil,
                offersFullScreen: !landscape && chromeShown, onTap: toggleChrome, enterFullScreen: enterFullScreen)
        }
    }

    private var closeButton: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: Circle())
                .contentShape(Circle())
                .expandTapTarget(4)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .padding(.leading, Metrics.gutter)
        .padding(.top, 8)
        .opacity(chromeShown ? 1 : 0)
        .animation(reduceMotion ? nil : Motion.micro, value: chromeShown)
        .allowsHitTesting(chromeShown)
        .accessibilityHidden(!chromeShown)
        .accessibilityLabel(Text("닫기"))
        .accessibilityIdentifier("viewer.close")
    }

    private var bottomChrome: some View {
        VStack(spacing: 16) {
            if let item = currentItem {
                if item.kind == .photo, let caption = item.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: captionSize))
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                if item.kind == .video, let playback, playback.url == item.url {
                    VideoControls(
                        playback: playback,
                        exitFullScreen: forcedLandscape && landscape ? exitFullScreen : nil,
                        onScrub: { chrome.scrubbing($0, at: .now) },
                        onInteract: { chrome.touched(at: .now) })
                }
            }
            if !videoInLandscape {
                actions()
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
        .padding(.bottom, 6)
        .background {
            if hasBottomContent {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .opacity(chromeShown ? 1 : 0)
        .animation(reduceMotion ? nil : Motion.micro, value: chromeShown)
        .allowsHitTesting(chromeShown)
        .accessibilityHidden(!chromeShown)
    }

    private var hasBottomContent: Bool {
        guard let item = currentItem else { return false }
        switch item.kind {
        case .video: return true
        case .photo: return Actions.self != EmptyView.self || item.caption?.isEmpty == false
        }
    }

    private func toggleChrome() {
        chrome.toggle(at: .now)
    }

    private func autoHide() async {
        guard let deadline = chrome.hideAt else { return }
        try? await Task.sleep(until: deadline, clock: .continuous)
        guard !Task.isCancelled else { return }
        chrome.tick(at: .now)
    }

    private func load(_ url: URL?) async {
        chrome.pageChanged()
        zoomed = false
        guard let item = items.first(where: { $0.url == url }), item.kind == .video else {
            playback?.stop()
            playback = nil
            return
        }
        if playback?.url == item.url { return }
        playback?.stop()
        let next = VideoPlayback(url: item.url)
        playback = next
        await next.start()
    }

    private func dragEnded(_ translation: CGSize, _ predicted: CGSize) {
        if translation.height > 120 || predicted.height > 320 {
            close()
        } else {
            withAnimation(reduceMotion ? nil : Motion.move) { drag = .zero }
        }
    }

    private func close() {
        playback?.stop()
        restorePortrait()
        if reduceMotion {
            dismiss()
        } else {
            withMotion(Motion.micro) { appeared = false }
            dismiss()
        }
    }

    private func enterFullScreen() {
        forcedLandscape = true
        ViewerOrientation.request(.landscapeRight)
    }

    private func exitFullScreen() {
        forcedLandscape = false
        ViewerOrientation.request(.portrait)
    }

    private func restorePortrait() {
        guard forcedLandscape else { return }
        exitFullScreen()
    }
}

extension MediaViewer where Actions == EmptyView {
    init(items: [ViewerItem], start: URL? = nil) {
        self.init(items: items, start: start) { EmptyView() }
    }
}

enum ViewerOrientation {
    static func request(_ orientations: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }
}

private struct PhotoPage: View {
    let item: ViewerItem
    let isCurrent: Bool
    let onTap: () -> Void
    let onZoom: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pan: CGSize = .zero
    @State private var fittedSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private let maxScale: CGFloat = 4

    private var liveScale: CGFloat { scale * pinch }
    private var zoomed: Bool { liveScale > 1.01 }

    var body: some View {
        RemoteImage(url: item.url, animation: reduceMotion ? nil : Motion.move) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { fittedSize = $0 }
                    .scaleEffect(zoomed ? min(maxScale, liveScale) : 1)
                    .offset(zoomed ? CGSize(width: offset.width + pan.width, height: offset.height + pan.height) : .zero)
                    .transition(.opacity)
                    .accessibilityLabel(Text(item.label))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityHint(Text("두 번 탭하면 확대, 아래로 쓸어 닫기"))
            case .failure:
                Text("이미지를 불러오지 못했어요")
                    .typeScale(.meta)
                    .foregroundStyle(.white.opacity(0.7))
            default:
                if let preview = RemoteImageCache.shared.cachedVariant(item.url) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                } else {
                    KurlLoadingMark()
                        .frame(width: 44, height: 26)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .gesture(panGesture, isEnabled: zoomed)
        .simultaneousGesture(magnifyGesture)
        .gesture(TapGesture(count: 2).onEnded { toggleZoom() }.exclusively(before: TapGesture().onEnded { onTap() }))
        .onChange(of: zoomed) { _, zoom in onZoom(zoom) }
        .onChange(of: isCurrent) { _, current in
            guard !current else { return }
            scale = 1
            offset = .zero
        }
        .accessibilityIdentifier("viewer.photo")
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (fittedSize.width * scale - containerSize.width) / 2)
        let maxY = max(0, (fittedSize.height * scale - containerSize.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($pan) { value, state, _ in state = value.translation }
            .onEnded { value in
                let proposed = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                withAnimation(reduceMotion ? nil : Motion.move) {
                    offset = clampedOffset(proposed, scale: scale)
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                scale = min(maxScale, max(1, scale * value.magnification))
                if scale <= 1 {
                    offset = .zero
                } else {
                    withAnimation(reduceMotion ? nil : Motion.move) {
                        offset = clampedOffset(offset, scale: scale)
                    }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(reduceMotion ? nil : Motion.move) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = 2.5
            }
        }
    }
}

private struct DownwardPan: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var changed: (CGSize) -> Void
    var ended: (_ translation: CGSize, _ predicted: CGSize) -> Void

    func makeUIGestureRecognizer(context: Context) -> DownwardPanRecognizer {
        let recognizer = DownwardPanRecognizer()
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: DownwardPanRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: DownwardPanRecognizer, context: Context) {
        let point = recognizer.translation(in: recognizer.view)
        let translation = CGSize(width: point.x, height: point.y)
        switch recognizer.state {
        case .began, .changed:
            changed(translation)
        case .ended:
            let velocity = recognizer.velocity(in: recognizer.view)
            ended(translation, CGSize(width: point.x + velocity.x * 0.2, height: point.y + velocity.y * 0.2))
        case .cancelled, .failed:
            ended(.zero, .zero)
        default:
            break
        }
    }
}

final class DownwardPanRecognizer: UIPanGestureRecognizer {
    private var origin: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if origin == nil { origin = touches.first?.location(in: view) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible, let origin, let point = touches.first?.location(in: view) else {
            super.touchesMoved(touches, with: event)
            return
        }
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        guard max(abs(dx), abs(dy)) >= 6 else { return }
        guard DownwardPanRecognizer.isDownward(dx: dx, dy: dy) else {
            state = .failed
            return
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        origin = nil
    }

    static func isDownward(dx: CGFloat, dy: CGFloat) -> Bool {
        dy > abs(dx)
    }
}
