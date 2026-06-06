//
//  BlockRenderer.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// 백엔드 blocks 를 네이티브 SwiftUI 뷰로 렌더한다. 서드파티 마크다운 라이브러리 없이
/// 인라인 서식만 Foundation 의 AttributedString(markdown:) 으로 처리한다.
struct BlockView: View {
    let block: PostBlock

    var body: some View {
        switch block.kind {
        case .paragraph:
            inlineText(block.content ?? "")
                .font(.body)

        case .h1:
            inlineText(block.content ?? "").font(.title.bold()).padding(.top, 8)
        case .h2:
            inlineText(block.content ?? "").font(.title2.bold()).padding(.top, 6)
        case .h3:
            inlineText(block.content ?? "").font(.title3.bold()).padding(.top, 4)

        case .quote:
            inlineText(block.content ?? "")
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.brand).frame(width: 3)
                }

        case .divider:
            Divider().padding(.vertical, 8)

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

    private func inlineText(_ raw: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: raw, options: options) {
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

// MARK: 코드 블록

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
        VStack(alignment: .leading, spacing: 0) {
            if let lang = payload.lang, !lang.isEmpty {
                Text(lang)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(payload.code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: 이미지 블록

private struct ImagePayload {
    var url: String
    var alt: String?
    var caption: String?

    static func decode(_ content: String?) -> ImagePayload {
        guard let content, let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ImagePayload(url: content ?? "", alt: nil, caption: nil) }
        return ImagePayload(
            url: json["url"] as? String ?? "",
            alt: json["alt"] as? String,
            caption: json["caption"] as? String
        )
    }
}

private struct ImageBlockView: View {
    let payload: ImagePayload

    var body: some View {
        VStack(spacing: 6) {
            if let url = URL(string: payload.url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Rectangle().fill(.quaternary).frame(height: 200).overlay(ProgressView())
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if let caption = payload.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: 리스트 블록

private struct ListBlockView: View {
    let items: [String]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(inline(item))
                        .font(.body)
                }
            }
        }
    }

    private func inline(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }
}

// MARK: 테이블 블록 (GFM 마크다운)

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
                // 구분선(---) 행 제거
                !cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } }
            }
    }

    var body: some View {
        let rows = rows
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(index == 0 ? .callout.bold() : .callout)
                        }
                    }
                    if index == 0 { Divider() }
                }
            }
            .padding(12)
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: 임베드 블록

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
                HStack {
                    Image(systemName: "link")
                    Text(payload.provider ?? payload.url)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
            }
            .tint(.brand)
        }
    }
}

// MARK: CTA 블록

private struct CtaBlockView: View {
    let cta: CtaInfo

    var body: some View {
        if let url = URL(string: cta.url) {
            Link(destination: url) {
                Text(cta.label)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)
        }
    }
}
