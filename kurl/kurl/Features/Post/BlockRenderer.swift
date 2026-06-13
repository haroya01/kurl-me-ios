//
//  BlockRenderer.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import UIKit
import WebKit

/// blocks → 네이티브 SwiftUI. 읽기 타이포는 프론트 `.prose-post`(§10.7) 를 그대로 옮기되,
/// 크기는 Dynamic Type 에 상대화(@ScaledMetric) — 시스템 글자 크기 설정을 따라간다.
/// 서드파티 마크다운 라이브러리 없이 인라인 서식만 AttributedString(markdown:) 로 처리.
struct BlockView: View {
    let block: PostBlock
    /// 첫 문단이면 lead — 한 호흡 큰 도입으로 독자를 들인다(에디토리얼 마스트헤드의 일부).
    var isLead = false

    // 읽기 타입 스케일(§ 타이포 시스템) — 한국어 기준으로 자간·행간을 함께 설계한다.
    // 제목류는 클수록 더 조여(−tracking) 디스플레이의 무게를, 본문은 행간으로 숨을 준다.
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 18
    @ScaledMetric(relativeTo: .title) private var h1Size: CGFloat = 27
    @ScaledMetric(relativeTo: .title2) private var h2Size: CGFloat = 23
    @ScaledMetric(relativeTo: .title3) private var h3Size: CGFloat = 19

    var body: some View {
        switch block.kind {
        // 본문 = 차분한 읽기. 행간 ≈1.7(한국어 기준)로 숨을 주고, 문단 사이 한 호흡.
        // 첫 문단(lead)은 한 단계 크고 진하게 — 글 입구의 도입 호흡.
        case .paragraph:
            let size = isLead ? bodySize + 2 : bodySize
            inline(block.content ?? "")
                .font(.system(size: size))
                .lineSpacing(size * (isLead ? 0.6 : 0.68))
                .foregroundStyle(isLead ? Palette.heading : Palette.body)
                .padding(.bottom, isLead ? 20 : 18)

        // 헤딩 = 크기·자간·위 여백을 함께 — 한글은 볼드 대비가 약해 굵기만으론 위계가 안 선다.
        // 클수록 자간을 더 조여(−0.5 → −0.4 → −0.25) 디스플레이의 단단함을 만든다.
        case .h1:
            inline(block.content ?? "")
                .font(.system(size: h1Size, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 30).padding(.bottom, 6)
        case .h2:
            inline(block.content ?? "")
                .font(.system(size: h2Size, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 24).padding(.bottom, 5)
        case .h3:
            inline(block.content ?? "")
                .font(.system(size: h3Size, weight: .semibold))
                .tracking(-0.25)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16).padding(.bottom, 2)

        case .quote:
            inline(block.content ?? "")
                .font(.system(size: bodySize).italic())
                .lineSpacing(bodySize * 0.6)
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
            for run in attributed.runs {
                if run.link != nil {
                    attributed[run.range].foregroundColor = Palette.link
                }
                // 인라인 코드 — 모노스페이스 + 옅은 칩 배경으로 본문과 또렷이 구분(프론트 `code` 등가).
                // Text 는 AttributedString 의 backgroundColor 를 렌더하므로 별도 뷰 없이 면이 깔린다.
                if run.inlinePresentationIntent?.contains(.code) == true {
                    attributed[run.range].font = .system(size: bodySize * 0.92, design: .monospaced)
                    attributed[run.range].foregroundColor = Palette.ink
                    attributed[run.range].backgroundColor = Palette.chipBg
                }
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
    @State private var copied = false

    private var language: String? {
        guard let lang = payload.lang?.trimmingCharacters(in: .whitespaces), !lang.isEmpty
        else { return nil }
        return lang
    }

    var body: some View {
        VStack(spacing: 0) {
            // 라벨·복사 바 — 코드 블록을 "정말 코드"로 읽히게 한다(언어 표시 + 한 번에 복사).
            HStack(spacing: 8) {
                if let language {
                    Text(language.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.codeText.opacity(0.55))
                }
                Spacer(minLength: 0)
                Button(action: copy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(copied ? "복사됨" : "복사")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(copied ? Palette.accentSoft : Palette.codeText.opacity(0.7))
                    .expandTapTarget(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? Text("복사됨") : Text("코드 복사"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeSyntax.highlight(payload.code, lang: payload.lang))
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.codeBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairlineStrong.opacity(0.4), lineWidth: 1))
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private func copy() {
        UIPasteboard.general.string = payload.code
        withAnimation(.snappy(duration: 0.2)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}

// MARK: 경량 구문 하이라이트 — IDE 처럼 색을 입히되 서드파티 없이 한 패스 스캐너로.

/// slate-900 위에서 또렷한, 절제된 다크 테마. 문자열은 브랜드 그린 계열로 묶고
/// 나머지는 IDE 관습 색(키워드 핑크·숫자 앰버·타입 스카이·주석 muted slate).
/// 언어를 정확히 파싱하지 않는다 — 문자열·주석·숫자·식별자(키워드/타입) 수준의
/// 범용 토큰만 칠해 어떤 언어든 "코드처럼" 보이게 한다(과채색보다 안전 우선).
private enum CodeSyntax {
    static let plain = Palette.codeText
    static let comment = Color(hex: 0x7C8BA3)
    static let keyword = Color(hex: 0xF472B6)
    static let string = Color(hex: 0x6EE7B7)
    static let number = Color(hex: 0xFCD34D)
    static let type = Color(hex: 0x7DD3FC)

    /// 여러 언어 키워드의 합집합 — 식별자로 쓰일 일이 드문 예약어만(과채색 방지).
    static let keywords: Set<String> = [
        // 선언/흐름 공통
        "func", "fun", "fn", "def", "let", "var", "val", "const", "static", "final",
        "class", "struct", "enum", "interface", "protocol", "extension", "trait", "impl",
        "import", "export", "from", "package", "module", "use", "mod", "namespace",
        "return", "if", "else", "elif", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "guard", "defer", "try", "catch", "finally", "throw", "throws",
        "async", "await", "yield", "lazy", "where", "in", "is", "as", "of", "new", "delete",
        "public", "private", "protected", "internal", "open", "override", "mutating",
        "typealias", "associatedtype", "init", "deinit", "self", "this", "super", "extends",
        "implements", "abstract", "void", "type", "with", "lambda", "pass", "raise", "except",
        "global", "nonlocal", "go", "chan", "select", "pub", "mut", "ref", "unsafe", "match",
        "and", "or", "not", "typeof", "instanceof", "function",
        // 상수/타입성 키워드
        "true", "false", "nil", "null", "undefined", "None", "True", "False",
        "Int", "String", "Bool", "Double", "Float", "Void", "Any", "Self",
        "int", "float", "double", "char", "bool", "boolean", "string", "long", "short", "byte",
    ]

    private static let hashCommentLangs: Set<String> = [
        "py", "python", "rb", "ruby", "sh", "bash", "zsh", "shell", "yaml", "yml",
        "toml", "r", "perl", "makefile", "dockerfile", "ini", "conf", "elixir", "ex",
    ]

    static func highlight(_ code: String, lang: String?) -> AttributedString {
        // 아주 긴 블록은 색칠 비용을 피한다(스캔·다수 append).
        guard code.count <= 6000 else {
            var flat = AttributedString(code)
            flat.foregroundColor = plain
            return flat
        }
        let s = Array(code)
        let n = s.count
        let hashComment = hashCommentLangs.contains((lang ?? "").lowercased())
        var result = AttributedString()
        var i = 0

        func emit(_ range: Range<Int>, _ color: Color) {
            guard !range.isEmpty else { return }
            var piece = AttributedString(String(s[range]))
            piece.foregroundColor = color
            result += piece
        }

        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

        while i < n {
            let c = s[i]

            // 줄/블록 주석
            if c == "/", i + 1 < n, s[i + 1] == "/" {
                var j = i
                while j < n, s[j] != "\n" { j += 1 }
                emit(i..<j, comment); i = j; continue
            }
            if c == "/", i + 1 < n, s[i + 1] == "*" {
                var j = i + 2
                while j < n, !(s[j] == "*" && j + 1 < n && s[j + 1] == "/") { j += 1 }
                j = min(n, j + 2)
                emit(i..<j, comment); i = j; continue
            }
            if hashComment, c == "#" {
                var j = i
                while j < n, s[j] != "\n" { j += 1 }
                emit(i..<j, comment); i = j; continue
            }

            // 문자열/문자 리터럴
            if c == "\"" || c == "'" || c == "`" {
                let quote = c
                var j = i + 1
                while j < n {
                    if s[j] == "\\" { j += 2; continue }
                    if s[j] == quote { j += 1; break }
                    if s[j] == "\n", quote != "`" { break }
                    j += 1
                }
                emit(i..<min(j, n), string); i = min(j, n); continue
            }

            // 숫자
            if c.isNumber {
                var j = i
                while j < n, s[j].isNumber || s[j] == "." || s[j] == "_"
                    || "xXoObBeE".contains(s[j]) || "abcdefABCDEF".contains(s[j]) { j += 1 }
                emit(i..<j, number); i = j; continue
            }

            // 식별자 → 키워드/타입/일반
            if c.isLetter || c == "_" {
                var j = i
                while j < n, isWordChar(s[j]) { j += 1 }
                let word = String(s[i..<j])
                if keywords.contains(word) {
                    emit(i..<j, keyword)
                } else if let first = word.first, first.isUppercase {
                    emit(i..<j, type)
                } else {
                    emit(i..<j, plain)
                }
                i = j; continue
            }

            // 그 외(공백·구두점) — 다음 토큰 시작 전까지 한 덩어리로 묶어 append 수를 줄인다.
            var j = i
            while j < n {
                let d = s[j]
                if isWordChar(d) || d == "\"" || d == "'" || d == "`" { break }
                if d == "/", j + 1 < n, s[j + 1] == "/" || s[j + 1] == "*" { break }
                if hashComment, d == "#" { break }
                j += 1
            }
            if j == i { j = i + 1 }
            emit(i..<j, plain); i = j
        }
        return result
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
                .accessibilityLabel(Text(
                    payload.caption?.isEmpty == false
                        ? payload.caption! : String(localized: "본문 이미지")))
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

// MARK: 임베드 — 영상은 인라인 재생, 그 외는 링크 카드

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

/// 영상 임베드는 앱 밖으로 내보내지 않는다 — 유튜브처럼 그 자리에서 바로 재생한다.
/// 영상이 아닌 링크(트위터·깃허브 등)는 종전대로 종이 위 링크 카드.
private struct EmbedBlockView: View {
    let payload: EmbedPayload

    var body: some View {
        if let id = YouTubeRef.videoId(from: payload.url),
           let player = URL(
            string: "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&playsinline=1&rel=0&modestbranding=1") {
            InlineVideoEmbed(
                poster: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
                player: player, label: "YouTube 동영상 재생")
        } else if let id = VimeoRef.videoId(from: payload.url),
                  let player = URL(string: "https://player.vimeo.com/video/\(id)?autoplay=1&playsinline=1") {
            InlineVideoEmbed(poster: nil, player: player, label: "Vimeo 동영상 재생")
        } else {
            EmbedLinkCard(payload: payload)
        }
    }
}

private struct EmbedLinkCard: View {
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

/// 인라인 영상 — 처음엔 포스터 + 재생 버튼(웹뷰 수십 개가 동시에 살아 있지 않게),
/// 한 번 탭하면 그 자리에서 16:9 플레이어로 바뀌어 자동 재생된다.
private struct InlineVideoEmbed: View {
    let poster: URL?
    let player: URL
    let label: LocalizedStringKey
    @State private var playing = false

    var body: some View {
        ZStack {
            if playing {
                WebVideoPlayer(url: player)
            } else {
                Button {
                    playing = true
                } label: {
                    posterView
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(label))
                .accessibilityAddTraits(.isButton)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairlineStrong.opacity(0.5), lineWidth: 1)
        )
        .padding(.vertical, 8)
    }

    private var posterView: some View {
        ZStack {
            if let poster {
                AsyncImage(url: poster) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Palette.codeBg
                }
            } else {
                Palette.codeBg
            }
            Color.black.opacity(0.16)
            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.ink)
                .offset(x: 1) // 광학 보정 — 삼각형 무게중심을 원 가운데로.
                .frame(width: 58, height: 58)
                .background(.white.opacity(0.94), in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
        .contentShape(Rectangle())
    }
}

/// WKWebView 직결 — 인라인 재생 허용(전체화면 강제 X) + 자동 재생.
private struct WebVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// 유튜브 URL → 영상 id. watch?v= · youtu.be/ · /embed/ · /shorts/ · /v/ 를 모두 받는다.
private enum YouTubeRef {
    static func videoId(from raw: String) -> String? {
        guard let comps = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              let host = comps.host?.lowercased() else { return nil }
        if host.contains("youtu.be") {
            return firstPathSegment(comps.path)
        }
        guard host.contains("youtube.com") || host.contains("youtube-nocookie.com") else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let parts = comps.path.split(separator: "/").map(String.init)
        if let idx = parts.firstIndex(where: { ["embed", "shorts", "v"].contains($0) }),
           idx + 1 < parts.count {
            return parts[idx + 1]
        }
        return nil
    }

    private static func firstPathSegment(_ path: String) -> String? {
        let seg = path.split(separator: "/").first.map(String.init)
        return (seg?.isEmpty == false) ? seg : nil
    }
}

private enum VimeoRef {
    static func videoId(from raw: String) -> String? {
        guard let comps = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              comps.host?.lowercased().contains("vimeo.com") == true else { return nil }
        let seg = comps.path.split(separator: "/").first.map(String.init)
        return seg.flatMap { $0.allSatisfy(\.isNumber) ? $0 : nil }
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
