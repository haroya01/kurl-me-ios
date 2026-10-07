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

/// 다른 서버에서 받은 동영상 — 피드에선 재생 표시만, 누르면 전체 화면에서 소리와 함께 튼다.
struct NoteVideoTile: View {
    let media: NoteMedia
    let height: CGFloat?
    let onOpen: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.88))
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
        }
        .frame(width: height.map { $0 * 16 / 9 }, height: height ?? 220)
        .frame(maxWidth: height == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
        .onTapGesture(perform: onOpen)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(media.altText ?? String(localized: "동영상")))
        .accessibilityHint(Text("두 번 탭하면 재생합니다"))
        .accessibilityIdentifier("note.video")
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
            let next = AVPlayer(url: url)
            player = next
            next.play()
        }
        .onDisappear { player?.pause() }
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
            .background(Palette.hairline.opacity(0.35), in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(playing ? "오디오 정지" : "오디오 재생"))
        .accessibilityIdentifier("note.audio")
        .onDisappear {
            player?.pause()
            playing = false
        }
    }

    private func toggle() {
        guard let url = URL(string: media.url) else { return }
        if player == nil { player = AVPlayer(url: url) }
        if playing { player?.pause() } else { player?.play() }
        playing.toggle()
    }
}
