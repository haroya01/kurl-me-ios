//
//  BlockRenderer.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// blocks → 네이티브 SwiftUI. 읽기 타이포는 프론트 `.prose-post`(§10.7) 를 그대로 옮기되,
/// 크기는 Dynamic Type 에 상대화(@ScaledMetric) — 시스템 글자 크기 설정을 따라간다.
/// 서드파티 마크다운 라이브러리 없이 인라인 서식만 AttributedString(markdown:) 로 처리.
struct BlockView: View {
    let block: PostBlock

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 18
    @ScaledMetric(relativeTo: .title) private var h1Size: CGFloat = 26
    @ScaledMetric(relativeTo: .title2) private var h2Size: CGFloat = 24
    @ScaledMetric(relativeTo: .title3) private var h3Size: CGFloat = 20

    var body: some View {
        switch block.kind {
        // 가독의 두 기둥: 행간 ≈1.65(한국어 본문 기준, 5pt 는 1.28 로 너무 좁았다)
        // + 문단 사이 한 호흡. 글자를 키우는 게 아니라 숨 쉴 자리를 준다.
        case .paragraph:
            inline(block.content ?? "")
                .font(.system(size: bodySize))
                .lineSpacing(bodySize * 0.62)
                .foregroundStyle(Palette.body)
                .padding(.bottom, 14)

        // 한글은 볼드 대비가 라틴보다 약하다 — 굵기만으로는 위계가 안 서서
        // 크기 간격 + 자간 + 위 여백을 함께 벌린다.
        case .h1:
            inline(block.content ?? "")
                .font(.system(size: h1Size, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 24).padding(.bottom, 5)
        case .h2:
            inline(block.content ?? "")
                .font(.system(size: h2Size, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 20).padding(.bottom, 4)
        case .h3:
            inline(block.content ?? "")
                .font(.system(size: h3Size, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 14).padding(.bottom, 2)

        case .quote:
            inline(block.content ?? "")
                .font(.system(size: bodySize).italic())
                .lineSpacing(bodySize * 0.55)
                .foregroundStyle(Palette.secondary)
                .padding(.leading, 20)
                .padding(.vertical, 2)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.accentSoft)
                        .frame(width: 3)
                }
                .padding(.bottom, 14)

        case .divider:
            Hairline().padding(.vertical, 8)

        case .code:
            CodeBlockView(payload: CodePayload.decode(block.content))

        case .image:
            ImageBlockView(payload: ImagePayload.decode(block.content))

        case .listBullet:
            ListBlockView(items: parseListItems(block.content), ordered: false)
        case .listNumbered:
            ListBlockView(items: parseListItems(block.content), ordered: true)

        case .table:
            TableBlockView(markdown: block.content ?? "")

        case .embed:
            EmbedBlockView(payload: EmbedPayload.decode(block.content))

        case .ctaRef:
            if let cta = block.cta, !cta.deleted {
                CtaBlockView(cta: cta)
            }

        case .unknown:
            EmptyView()
        }
    }

    private func inline(_ raw: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if var attributed = try? AttributedString(markdown: raw, options: options) {
            for run in attributed.runs where run.link != nil {
                attributed[run.range].foregroundColor = Palette.link
            }
            return Text(attributed)
        }
        return Text(raw)
    }

    private func parseListItems(_ content: String?) -> [String] {
        guard let content, !content.isEmpty else { return [] }
        if let data = content.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                var s = line.trimmingCharacters(in: .whitespaces)
                for marker in ["- ", "* ", "+ "] where s.hasPrefix(marker) {
                    s.removeFirst(marker.count)
                }
                if let dot = s.firstIndex(of: "."), s[..<dot].allSatisfy(\.isNumber) {
                    s = String(s[s.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                }
                return s
            }
    }
}

// MARK: 코드 블록 — slate-900 / slate-100

private struct CodePayload {
    var lang: String?
    var code: String

    static func decode(_ content: String?) -> CodePayload {
        guard let content, let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return CodePayload(lang: nil, code: content ?? "") }
        return CodePayload(lang: json["lang"] as? String, code: json["code"] as? String ?? "")
    }
}

private struct CodeBlockView: View {
    let payload: CodePayload

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(payload.code)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Palette.codeText)
                .textSelection(.enabled)
                .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.codeBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairlineStrong.opacity(0.4), lineWidth: 1))
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}

// MARK: 이미지 블록 — rounded-2xl + 캡션 slate-400

private struct ImagePayload {
    var url: String
    var caption: String?

    static func decode(_ content: String?) -> ImagePayload {
        guard let content, let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ImagePayload(url: content ?? "", caption: nil) }
        return ImagePayload(url: json["url"] as? String ?? "", caption: json["caption"] as? String)
    }
}

private struct ImageBlockView: View {
    let payload: ImagePayload

    var body: some View {
        VStack(spacing: 12) {
            if let url = URL(string: payload.url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Palette.hairline)
                        .frame(height: 200)
                        .overlay(ProgressView().tint(Palette.accent))
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if let caption = payload.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: 리스트 블록 — 마커 그린

private struct ListBlockView: View {
    let items: [String]
    let ordered: Bool

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: bodySize))
                        .foregroundStyle(Palette.accentMarker)
                        .monospacedDigit()
                    Text(inline(item))
                        .font(.system(size: bodySize))
                        .lineSpacing(bodySize * 0.5)
                        .foregroundStyle(Palette.body)
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    private func inline(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }
}

// MARK: 테이블 블록 — flat (헤더 밑줄 + 행 구분선)

private struct TableBlockView: View {
    let markdown: String

    private var rows: [[String]] {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> [String] in
                line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            .filter { cells in
                !cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } }
            }
    }

    var body: some View {
        let rows = rows
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.system(size: 15, weight: index == 0 ? .semibold : .regular))
                                .foregroundStyle(index == 0 ? Palette.ink : Palette.body)
                                .padding(.vertical, 8)
                        }
                    }
                    Rectangle()
                        .fill(index == 0 ? Palette.hairlineStrong : Palette.hairline)
                        .frame(height: index == 0 ? 2 : 1)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: 임베드 — flat 보더 링크

private struct EmbedPayload {
    var provider: String?
    var url: String

    static func decode(_ content: String?) -> EmbedPayload {
        guard let content, let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return EmbedPayload(provider: nil, url: content ?? "") }
        return EmbedPayload(provider: json["provider"] as? String, url: json["url"] as? String ?? "")
    }
}

private struct EmbedBlockView: View {
    let payload: EmbedPayload

    var body: some View {
        if let url = URL(string: payload.url) {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 13))
                    Text(payload.provider ?? payload.url)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 12))
                }
                .foregroundStyle(Palette.link)
                .padding(14)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairlineStrong, lineWidth: 1)
                )
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: CTA — primary 그린

private struct CtaBlockView: View {
    let cta: CtaInfo

    var body: some View {
        if let url = URL(string: cta.url) {
            Link(destination: url) {
                Text(cta.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.vertical, 6)
        }
    }
}
