import AVKit
import SwiftUI

extension NoteMedia {
    var isVideo: Bool { contentType.hasPrefix("video/") }
    var isAudio: Bool { contentType.hasPrefix("audio/") }
}

/// 다른 서버에서 받은 동영상 — 화면에 절반 넘게 보이면 소리 없이 되풀이해 틀고(스레드·X 문법), 누르면
/// 전체 화면에서 소리와 함께 튼다. 설정의 "비디오 미리보기 자동 재생"이 꺼졌거나 저전력 모드면 틀지 않는다.
struct NoteVideoTile: View {
    let media: NoteMedia
    let height: CGFloat?
    let onOpen: () -> Void
    @State private var visible = false
    @State private var autoplayAllowed = Self.autoplayAllowed
    @State private var sound: Bool?
    @Environment(\.scenePhase) private var scenePhase

    private var playing: Bool { visible && autoplayAllowed && scenePhase == .active }

    enum Badge: Equatable {
        case play, muted, none
    }

    static func badge(playing: Bool, sound: Bool?) -> Badge {
        guard playing else { return .play }
        return sound == true ? .muted : .none
    }

    static var autoplayAllowed: Bool {
        UIAccessibility.isVideoAutoplayEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.88))
            if playing, let url = URL(string: media.url) {
                MutedLoopingVideo(url: url) { sound = $0 }
                    .transition(.opacity)
            }
            switch Self.badge(playing: playing, sound: sound) {
            case .muted:
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(GlassTokens.mediaChip, in: Circle())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            case .play:
                NotePlayMark()
            case .none:
                EmptyView()
            }
        }
        .modifier(TileFrame(ratio: media.ratio ?? 16.0 / 9.0, height: height))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .onTapGesture(perform: onOpen)
        .onGeometryChange(for: Bool.self) { proxy in
            Self.mostlyOnScreen(proxy.frame(in: .global))
        } action: { visible = $0 }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.videoAutoplayStatusDidChangeNotification)) { _ in
            autoplayAllowed = Self.autoplayAllowed
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            autoplayAllowed = Self.autoplayAllowed
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(media.altText ?? String(localized: "동영상")))
        .accessibilityValue(playing ? Text("소리 없이 재생 중") : Text(""))
        .accessibilityHint(sound == false ? Text("두 번 탭하면 크게 봅니다") : Text("두 번 탭하면 소리와 함께 재생합니다"))
        .accessibilityIdentifier("note.video")
    }

    private static func mostlyOnScreen(_ frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0,
            let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first
        else { return false }
        let shown = frame.intersection(screen.bounds)
        guard !shown.isNull else { return false }
        return shown.width * shown.height >= frame.width * frame.height * 0.5
    }
}

struct NotePlayMark: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.ultraThinMaterial, in: Circle())
    }
}

/// 피드의 소리 없는 되풀이 재생. 소리가 없어도 오디오 세션이 다른 앱 음악을 끊지 않게 ambient 로 둔다.
private struct MutedLoopingVideo: UIViewRepresentable {
    let url: URL
    let onSound: (Bool) -> Void

    func makeUIView(context: Context) -> PlayerLayerView {
        AudioSessionMode.mixWithOthers()
        let view = PlayerLayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        context.coordinator.probe = Task { [onSound] in
            if let sound = await NoteVideoSound.hasAudio(item.asset) { onSound(sound) }
        }
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
        coordinator.looper = nil
        coordinator.probe?.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
        var probe: Task<Void, Never>?
    }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

enum NoteVideoSound {
    enum Playback: Equatable {
        case loopSilently, withSound
    }

    static func playback(sound: Bool?) -> Playback {
        sound == false ? .loopSilently : .withSound
    }

    static func hasAudio(_ asset: AVAsset) async -> Bool? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio) else { return nil }
        return !tracks.isEmpty
    }
}

/// 피드의 소리 없는 재생은 다른 앱 음악과 섞이고(ambient), 사용자가 고른 소리 재생만 playback 으로 끊는다.
enum AudioSessionMode {
    static func mixWithOthers() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback else { return }
        try? session.setCategory(.ambient)
    }

    static func withSound() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)
    }

    static func done() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@Observable
final class VideoPlayback {
    let url: URL
    private(set) var player: AVPlayer?
    private(set) var sound: Bool?
    private(set) var playing = false
    private(set) var muted = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var ratio: CGFloat?
    private(set) var failed = false
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var holdsAudio = false
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var resumeAfterScrub = false
    @ObservationIgnored private var stopped = false

    init(url: URL) {
        self.url = url
    }

    func start() async {
        guard player == nil, !stopped else { return }
        let item = AVPlayerItem(url: url)
        let sound = await NoteVideoSound.hasAudio(item.asset)
        guard !stopped, !Task.isCancelled else { return }
        self.sound = sound
        let next: AVPlayer
        switch NoteVideoSound.playback(sound: sound) {
        case .loopSilently:
            AudioSessionMode.mixWithOthers()
            let queue = AVQueuePlayer()
            let looper = AVPlayerLooper(player: queue, templateItem: item)
            observations.append(looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                Task { @MainActor [weak self] in self?.failed = true }
            })
            self.looper = looper
            next = queue
        case .withSound:
            AudioSessionMode.withSound()
            holdsAudio = true
            observations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in self?.failed = true }
            })
            next = AVPlayer(playerItem: item)
        }
        observations.append(next.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor [weak self] in self?.playing = playing }
        })
        timeObserver = next.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.advance(to: time) }
        }
        player = next
        next.play()
    }

    func togglePlay() {
        guard let player else { return }
        if playing {
            player.pause()
            return
        }
        if duration > 0, player.currentTime().seconds >= duration - 0.25 {
            elapsed = 0
            player.seek(to: .zero)
        }
        player.play()
    }

    func toggleMute() {
        muted.toggle()
        player?.isMuted = muted
    }

    func beginScrub() {
        scrubbing = true
        resumeAfterScrub = playing
        player?.pause()
    }

    func scrub(to seconds: Double) {
        elapsed = min(max(seconds, 0), duration)
        player?.seek(
            to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func endScrub() {
        scrubbing = false
        if resumeAfterScrub { player?.play() }
        resumeAfterScrub = false
    }

    func skip(by seconds: Double) {
        scrub(to: elapsed + seconds)
    }

    func stop() {
        stopped = true
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.forEach { $0.invalidate() }
        observations = []
        looper?.disableLooping()
        looper = nil
        player = nil
        playing = false
        if holdsAudio {
            holdsAudio = false
            AudioSessionMode.done()
        }
    }

    private func advance(to time: CMTime) {
        guard let item = player?.currentItem else { return }
        let total = item.duration.seconds
        if total.isFinite, total > 0 { duration = total }
        if !scrubbing, time.seconds.isFinite { elapsed = max(0, time.seconds) }
        let size = item.presentationSize
        if ratio == nil, size.width > 0, size.height > 0 { ratio = size.width / size.height }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

struct VideoPage: View {
    let item: ViewerItem
    let playback: VideoPlayback?
    let offersFullScreen: Bool
    let onTap: () -> Void
    let enterFullScreen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ratio: CGFloat { playback?.ratio ?? item.ratio ?? 16.0 / 9.0 }

    var body: some View {
        ZStack {
            Color.clear
            PlayerSurface(player: playback?.player)
                .aspectRatio(ratio, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if ratio > 1 {
                        fullScreenPill
                            .alignmentGuide(.bottom) { $0[.top] - 16 }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(item.label))
                .accessibilityAddTraits(.startsMediaSession)
            if playback?.failed == true {
                Text("동영상을 불러오지 못했어요")
                    .typeScale(.meta)
                    .foregroundStyle(.white.opacity(0.7))
            } else if playback?.player == nil {
                KurlLoadingMark()
                    .frame(width: 44, height: 26)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewer.video")
    }

    private var fullScreenPill: some View {
        Button(action: enterFullScreen) {
            Text("전체 화면")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(offersFullScreen ? 1 : 0)
        .animation(reduceMotion ? nil : Motion.micro, value: offersFullScreen)
        .allowsHitTesting(offersFullScreen)
        .accessibilityHidden(!offersFullScreen)
        .accessibilityIdentifier("viewer.fullScreen")
    }
}

struct VideoControls: View {
    let playback: VideoPlayback
    let exitFullScreen: (() -> Void)?
    let onScrub: (Bool) -> Void
    let onInteract: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                playback.togglePlay()
                onInteract()
            } label: {
                Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentTransition(.symbolEffect(.replace))
                    .expandTapTarget(10)
            }
            .accessibilityLabel(playback.playing ? Text("일시 정지") : Text("재생"))
            .accessibilityIdentifier("viewer.play")

            Slider(value: position, in: 0...max(playback.duration, 0.01)) { editing in
                if editing { playback.beginScrub() } else { playback.endScrub() }
                onScrub(editing)
            }
            .tint(.white)
            .disabled(playback.duration <= 0)
            .accessibilityLabel(Text("재생 위치"))
            .accessibilityValue(
                Text("\(MediaClock.spoken(playback.elapsed)), 전체 \(MediaClock.spoken(playback.duration))"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.skip(by: 10)
                case .decrement: playback.skip(by: -10)
                @unknown default: break
                }
                onInteract()
            }
            .accessibilityIdentifier("viewer.scrubber")

            Text(verbatim: "\(MediaClock.label(playback.elapsed)) / \(MediaClock.label(playback.duration))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize()
                .accessibilityHidden(true)

            if playback.sound == true {
                Button {
                    playback.toggleMute()
                    onInteract()
                } label: {
                    Image(systemName: playback.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentTransition(.symbolEffect(.replace))
                        .expandTapTarget(10)
                }
                .accessibilityLabel(playback.muted ? Text("소리 켜기") : Text("소리 끄기"))
                .accessibilityIdentifier("viewer.mute")
            }

            if let exitFullScreen {
                Button(action: exitFullScreen) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .expandTapTarget(10)
                }
                .accessibilityLabel(Text("전체 화면 끝내기"))
                .accessibilityIdentifier("viewer.exitFullScreen")
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private var position: Binding<Double> {
        Binding(get: { playback.elapsed }, set: { playback.scrub(to: $0) })
    }
}

/// 다른 서버에서 받은 오디오 — 행 안에서 재생·정지한다.
struct NoteAudioRow: View {
    let media: NoteMedia
    @State private var player: AVPlayer?
    @State private var playing = false

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Palette.chipBg, in: Circle())
                Image(systemName: "waveform")
                    .foregroundStyle(Palette.secondary)
                Text(media.altText ?? String(localized: "오디오"))
                    .typeScale(.meta)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Palette.hairline.opacity(0.35), in: RoundedRectangle(cornerRadius: Metrics.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(playing ? "오디오 정지" : "오디오 재생"))
        .accessibilityIdentifier("note.audio")
        .onDisappear {
            if playing { AudioSessionMode.done() }
            player?.pause()
            playing = false
        }
    }

    private func toggle() {
        guard let url = URL(string: media.url) else { return }
        if player == nil { player = AVPlayer(url: url) }
        if playing {
            player?.pause()
            AudioSessionMode.done()
        } else {
            AudioSessionMode.withSound()
            player?.play()
        }
        playing.toggle()
    }
}
