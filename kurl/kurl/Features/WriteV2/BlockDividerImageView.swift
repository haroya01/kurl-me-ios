//
//  BlockDividerImageView.swift
//  kurl — WriteV2 (Phase 2)
//
//  비텍스트 블록 두 종의 최종 모습 렌더 — 구분선(얇은 룰)·이미지(플레이스홀더+alt 캡션).
//  둘 다 캐럿을 담지 않는다(§4 재정의): 탭하면 선택(포커스)되고, 다음 문단에서의 백스페이스가
//  이 블록을 지운다(EditorDocument.mergeBackward 의 prev.isNonText 경로). 발행면(BlockRenderer)의
//  Hairline·ImageBlockView 와 같은 문법을 종이 세계(§1)에서 재현한다.
//

import SwiftUI

/// 구분선 — 발행면 `Hairline().padding(.vertical, 8)` 의 에디터 대응. 선택되면 은은한 강조 +
/// 삭제 버튼(비텍스트 블록이라 백스페이스로만 지우던 걸 명시적 어포던스로 — 이미지 삭제 문법 미러).
struct BlockDividerView: View {
    let isFocused: Bool
    let onFocused: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 탭 표적은 선(1pt)이 아니라 위아래 여백까지 포함한 띠 — 얇은 선을 정확히 눌러야 하는 부담을 없앤다.
            Rectangle()
                .fill(isFocused ? Palette.accentSoft : Palette.hairlineStrong)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(.rect)
                .onTapGesture { onFocused() }
                .accessibilityElement()
                .accessibilityLabel(Text("구분선"))
                .accessibilityIdentifier("editor-divider")
                .accessibilityAddTraits(.isButton)
            // 선택 시에만 삭제 버튼 노출 — 평소엔 순수 구분선(§10 조용함).
            if isFocused {
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash").labelStyle(.iconOnly)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel(Text("구분선 삭제"))
            }
        }
    }
}

/// 이미지 — 실제 사진을 캔버스에서 바로 보인다(발행면 ImageBlockView 와 같은 RemoteImage 경로).
/// 로드 전·실패는 4:3 예약 박스로 자리를 지킨다(레이아웃 점프 방지). alt 는 아래 캡션 필드로 편집
/// (비텍스트 블록이라 본문 캐럿 규칙과 분리). 폭(기본/와이드/하프)·삭제는 이미지 아래 컨트롤 바에서.
/// 왕복 계약: block.text = `«폭» alt`(폭 마커는 웹 image-width.ts·발행 렌더 InlineImageMarkdown 과 동형).
struct BlockImageView: View {
    let block: EditorBlock
    let isFocused: Bool
    let onAltChange: (String) -> Void
    let onDelete: () -> Void
    let onFocused: () -> Void

    private var url: String {
        if case .image(let u, _) = block.kind { return u }
        return ""
    }

    /// 사용자가 보고 고치는 순수 alt(폭 마커 제외). block.text 에서 마커를 벗겨 채운다.
    @State private var alt: String = ""
    /// 현재 폭(`nil`=기본·`"wide"`·`"half"`). block.text 의 «마커»에서 읽어 컨트롤 활성 표시.
    @State private var width: String?
    /// 대체 텍스트 필드의 키보드 포커스 — 문서 focus 에 이 이미지 블록을 등록하는 방아쇠.
    /// 등록하지 않으면 문서 focus 가 직전 텍스트 블록에 남아, 첫 글자 입력(블록 배열 변경)의
    /// 뷰 갱신에서 그 텍스트 블록 UITextView 가 first responder 를 도로 뺏었다
    /// ("설명 한 글자 쓰면 다음 단락으로 이동"의 근본).
    @FocusState private var altFocused: Bool

    private static let widthOptions: [(value: String?, label: LocalizedStringKey, icon: String)] = [
        (nil, "기본", "rectangle.center.inset.filled"),
        ("wide", "와이드", "rectangle"),
        ("half", "하프", "rectangle.split.2x1"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            imageBody
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMini))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusMini)
                        .strokeBorder(isFocused ? Palette.accentSoft : Color.clear, lineWidth: 2)
                )
                .contentShape(.rect)
                .onTapGesture { onFocused() }

            TextField("대체 텍스트", text: $alt)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .focused($altFocused)
                .onChange(of: altFocused) { _, focused in
                    if focused { onFocused() }
                }
                // alt 변화를 «폭» alt 로 합쳐 반영. onAppear 초기 세팅이 유발하는 첫 변화는
                // updateText 가 값 동일 시 무동작(멱등)이라 거짓 dirty 를 만들지 않는다.
                .onChange(of: alt) { _, _ in commit() }

            // 폭·삭제 컨트롤 — 종이 세계 링크색(§10, 유리 아님). 삭제는 조용한 secondary + 되돌리기 토스트.
            controls
        }
        .onAppear {
            let (w, a) = DraftPreviewBlocks.parseImageAlt(block.text)
            width = w
            alt = a ?? ""
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("이미지"))
    }

    /// 폭(기본/와이드/하프) + 삭제. 레거시 ImageActionBar 미러 — 폭은 한 탭, 삭제는 되돌리기 가능.
    private var controls: some View {
        HStack(spacing: 12) {
            ForEach(Self.widthOptions, id: \.icon) { opt in
                // full 은 리더에서 wide 와 같게 그려지므로 와이드 칸으로 활성 표시(웹·리비전 «full» 대비).
                let active = opt.value == width || (opt.value == "wide" && width == "full")
                Button {
                    onFocused()
                    width = opt.value
                    commit()
                } label: {
                    Label(opt.label, systemImage: opt.icon).labelStyle(.titleAndIcon)
                        .fontWeight(active ? .semibold : .medium)
                }
                .foregroundStyle(active ? Palette.link : Palette.secondary)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Label("삭제", systemImage: "trash").labelStyle(.titleAndIcon)
            }
            .foregroundStyle(Palette.secondary)
            .accessibilityHint(Text("이 이미지를 지웁니다"))
        }
        .font(.system(size: 13, weight: .medium))
    }

    /// alt·폭을 block.text(`«폭» alt`)로 합쳐 문서에 반영. 폭 없으면 마커 생략(순수 alt).
    private func commit() {
        let trimmed = alt.trimmingCharacters(in: .whitespaces)
        let marker = width.map { "«\($0)» " } ?? ""
        onAltChange(marker + trimmed)
    }

    @ViewBuilder
    private var imageBody: some View {
        if let remote = URL(string: url), remote.scheme?.hasPrefix("http") == true {
            RemoteImage(url: remote, animation: .easeOut(duration: 0.35)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().transition(.opacity)
                case .failure:
                    placeholder(caption: String(localized: "이미지를 불러오지 못했어요"))
                default:
                    placeholder(caption: nil)
                }
            }
        } else {
            // http(s) 가 아닌 주소(목 픽스처 등)는 로드를 시도하지 않고 자리만 지킨다.
            placeholder(caption: nil)
        }
    }

    private func placeholder(caption: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.radiusMini)
                .fill(Palette.hairline)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Palette.faint)
                Text(caption ?? url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 24)
            }
        }
    }
}
