//
//  NoteMediaPlayers.swift
//  kurl
//

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
    @Environment(\.scenePhase) private var scenePhase

    private var playing: Bool { visible && autoplayAllowed && scenePhase == .active }

    static var autoplayAllowed: Bool {
        UIAccessibility.isVideoAutoplayEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.88))
            if playing, let url = URL(string: media.url) {
                MutedLoopingVideo(url: url)
                    .transition(.opacity)
            }
            if playing {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(GlassTokens.mediaChip, in: Circle())
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(width: height.map { $0 * 16 / 9 }, height: height ?? 220)
        .frame(maxWidth: height == nil ? .infinity : nil)
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
        .accessibilityHint(Text("두 번 탭하면 소리와 함께 재생합니다"))
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

/// 피드의 소리 없는 되풀이 재생. 소리가 없어도 오디오 세션이 다른 앱 음악을 끊지 않게 ambient 로 둔다.
private struct MutedLoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        AudioSessionMode.mixWithOthers()
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
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

struct VideoLightbox: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel("닫기")
        }
        .onAppear {
            AudioSessionMode.withSound()
            let next = AVPlayer(url: url)
            player = next
            next.play()
        }
        .onDisappear {
            player?.pause()
            AudioSessionMode.done()
        }
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
