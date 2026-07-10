//
//  ImageLightbox.swift
//  kurl
//
//  Created by 김동현 on 7/3/26.
//

import SwiftUI

/// 본문 이미지를 탭하면 뜨는 전체 화면 뷰어 — 핀치 확대·패닝·더블탭 확대·아래로 끌어 닫기.
/// 읽기(종이) 위에 잠깐 뜨는 몰입 표면이라 어두운 스크림을 깐다. 닫기 버튼만 유리(떠 있는 크롬).
/// 커버·본문 이미지 모두 `.image` 블록이라 이 한 뷰어가 둘 다 받는다.
struct ImageLightbox: View {
    let url: URL
    let caption: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 라이트박스 캡션 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .footnote) private var captionSize: CGFloat = 13

    /// 커밋된 확대율(핀치·더블탭이 끝나면 확정) — 라이브 배율은 pinch 를 곱해 얻는다.
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    /// 확대 상태에서 커밋된 이동 — 라이브 이동은 drag 를 더해 얻는다.
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    /// 열릴 때 한 호흡 떠오르는 materialize(§10.7). reduce-motion 이면 즉시.
    @State private var appeared = false
    /// 팬 경계 계산용 실측 — scaledToFit 된 이미지 크기(scaleEffect 는 레이아웃 불변)와 컨테이너 크기.
    @State private var fittedSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private let maxScale: CGFloat = 4

    private var liveScale: CGFloat { scale * pinch }
    private var zoomed: Bool { liveScale > 1.01 }

    /// 확대하지 않은 상태의 아래로 끌기 진행도(0~1, 임계 300pt) — 스크림·이미지가 손가락을 따라 물러난다.
    private var dismissProgress: CGFloat {
        guard !zoomed else { return 0 }
        return min(1, max(0, drag.height) / 300)
    }

    var body: some View {
        ZStack {
            // 스크림 = 유일한 배경(presentationBackground 는 clear). 끌어 내리면 옅어져 뒤 본문이 비친다.
            Color.black
                .opacity(appeared ? (1 - dismissProgress * 0.65) : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            imageLayer
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .bottom) { captionBar }
        .statusBarHidden(true)
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { appeared = true }
        }
    }

    private var imageLayer: some View {
        // 본문에서 이미 로드한 이미지는 캐시 히트 — 뷰어가 재다운로드 없이 즉시 열린다.
        RemoteImage(
            url: url,
            animation: reduceMotion ? nil : .easeOut(duration: 0.3)
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { fittedSize = $0 }
                    .scaleEffect(zoomed ? min(maxScale, liveScale) : 1)
                    .offset(liveOffset)
                    .gesture(dragGesture)
                    .simultaneousGesture(magnifyGesture)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .transition(.opacity)
                    .accessibilityLabel(Text(caption?.isEmpty == false ? caption! : String(localized: "본문 이미지")))
                    .accessibilityHint(Text("두 번 탭하면 확대, 아래로 쓸어 닫기"))
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                    Text("이미지를 불러오지 못했어요")
                        .typeScale(.meta)
                }
                .foregroundStyle(.white.opacity(0.7))
            default:
                KurlLoadingMark()
                    .frame(width: 44, height: 26)
            }
        }
        // 열림 = 살짝 커지며 떠오름, 끌어 내리면 함께 작아지고 옅어진다.
        .scaleEffect(appeared ? (1 - dismissProgress * 0.12) : 0.94)
        .opacity(appeared ? (1 - dismissProgress * 0.3) : 0)
    }

    /// 확대 중이면 커밋 이동 + 라이브 드래그, 아니면 아래로 끌기(가로는 절반만 따라와 세로 이동을 강조).
    private var liveOffset: CGSize {
        if zoomed {
            return CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
        }
        return CGSize(width: drag.width * 0.4, height: max(0, drag.height))
    }

    /// 팬 이동을 이미지가 컨테이너 밖으로 완전히 벗어나지 않는 범위로 제한.
    /// 렌더 크기(fittedSize × 커밋 배율)와 컨테이너 차의 절반이 각 축 한계 — 작은 축은 0(중앙 고정).
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (fittedSize.width * scale - containerSize.width) / 2)
        let maxY = max(0, (fittedSize.height * scale - containerSize.height) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                if zoomed {
                    // 클램프 없이 누적하면 이미지가 화면 밖에 고정돼 복귀 제스처가 닿지 않는다 → 가시 범위로 스냅백.
                    let proposed = CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                        offset = clampedOffset(proposed, scale: scale)
                    }
                } else if value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                    close()
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
                    // 축소로 가시 범위가 줄면 기존 이동이 경계를 넘으므로 다시 클램프.
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                        offset = clampedOffset(offset, scale: scale)
                    }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = 2.5
            }
        }
    }

    /// 닫기 = 물러나며 사라지고(있으면) dismiss. presentationBackground 가 clear 라 슬라이드는 안 보인다.
    private func close() {
        if reduceMotion {
            dismiss()
        } else {
            withAnimation(.easeIn(duration: 0.2)) { appeared = false }
            dismiss()
        }
    }

    private var closeButton: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Metrics.gutter)
        .padding(.top, 8)
        .opacity(dismissProgress > 0.05 ? 0 : 1) // 끌어 내리는 동안엔 크롬을 비운다.
        .accessibilityLabel(Text("닫기"))
    }

    @ViewBuilder
    private var captionBar: some View {
        if let caption, !caption.isEmpty {
            Text(caption)
                .font(.system(size: captionSize))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
                .opacity(dismissProgress > 0.05 ? 0 : 1)
                .accessibilityHidden(true) // 이미지 라벨에 이미 포함.
        }
    }
}
