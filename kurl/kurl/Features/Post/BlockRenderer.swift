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

    /// 본 글(단독 상세)에서만 주입 — 있으면 문단이 선택→하이라이트 + 공개 하이라이트 페인트를
    /// 띄운다. 없으면(발견 덱 임베드·프리뷰) 종전 SwiftUI Text 그대로.
    @Environment(\.postHighlightStore) private var highlightStore

    // 읽기 타입 스케일(§ 타이포 시스템) — 한국어 기준으로 자간·행간을 함께 설계한다.
    // 제목류는 클수록 더 조여(−tracking) 디스플레이의 무게를, 본문은 행간으로 숨을 준다.
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 18
    @ScaledMetric(relativeTo: .title) private var h1Size: CGFloat = 27
    @ScaledMetric(relativeTo: .title2) private var h2Size: CGFloat = 23
    @ScaledMetric(relativeTo: .title3) private var h3Size: CGFloat = 19
    // h4~6 은 블록 타입이 아니라(백엔드·웹 에디터 모두 H3 에서 캡) 문단 속 `#### ` 로 온다.
    // 웹 리더는 그 문단을 react-markdown 으로 <h4>(17px semibold) 로 그리므로 여기서도 맞춘다.
    // h5·h6 은 웹에 전용 스타일이 없어 h4 아래로 한 칸씩 내려 사다리를 잇는다(소실 금지).
    @ScaledMetric(relativeTo: .headline) private var h4Size: CGFloat = 17

    var body: some View {
        switch block.kind {
        // 본문 = 차분한 읽기. 행간 ≈1.7(한국어 기준)로 숨을 주고, 문단 사이 한 호흡.
        // 첫 문단(lead)은 한 단계 크고 진하게 — 글 입구의 도입 호흡.
        case .paragraph:
            let size = isLead ? bodySize + 2 : bodySize
            let lineSpacing = size * (isLead ? 0.6 : 0.68)
            let color = isLead ? Palette.heading : Palette.body
            // h4~6 소제목 — `#### `/`##### `/`###### ` 로 시작하는 단독 문단은 웹 리더가 <h4~6>
            // 로 그린다(블록 모델은 H3 에서 캡되어 이런 헤딩이 PARAGRAPH 로 넘어온다). Apple
            // 인라인 파서는 `#` 를 헤딩으로 안 읽어 해시가 리터럴로 새므로, 여기서 직접 소제목으로 그린다.
            if let sub = Self.subHeading(block.content ?? "") {
                subHeadingView(level: sub.level, text: sub.text)
            }
            // 문단 속 인라인 이미지(노션 붙여넣기 등) — Apple 마크다운 파서는 이미지를 못 그려 alt
            // 텍스트만 남으므로, 텍스트/이미지 세그먼트로 갈라 이미지는 IMAGE 블록 문법으로 그린다
            // (웹 리더의 인라인 <img> 등가). 이런 문단은 블록 내 오프셋 기반 하이라이트와 안 맞아
            // 하이라이트 없이 그린다(분해가 오프셋을 흔든다 — 순수 텍스트 문단은 종전 그대로).
            else if InlineImageMarkdown.containsImage(block.content ?? "") {
                inlineImageParagraph(block.content ?? "", size: size, lineSpacing: lineSpacing, color: color)
            }
            // 본 글이면 선택 가능한 문단(UITextView) — 길게 눌러 하이라이트, 공개 하이라이트 페인트.
            // 임베드·프리뷰(store 없음)는 종전 Text 경로 그대로(블래스트 레이디어스 최소화).
            // 스토어 관찰은 얇은 래퍼(HighlightableParagraph)에 가둔다 — BlockView 본문이 store.highlights
            // 를 직접 읽으면 어느 하이라이트가 바뀌든 모든 문단이 재바디(→마크다운 재파싱)되던 것을 막는다.
            else if let store = highlightStore, let order = block.blockOrder {
                HighlightableParagraph(
                    store: store,
                    blockOrder: order,
                    raw: block.content ?? "",
                    fontSize: size,
                    textColor: color,
                    lineSpacing: lineSpacing
                )
                .padding(.bottom, isLead ? 20 : 18)
            } else {
                inline(block.content ?? "")
                    .font(.system(size: size))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(color)
                    .padding(.bottom, isLead ? 20 : 18)
            }

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
            // 이탤릭 없음 — 한글엔 진짜 기울임꼴이 없어 합성 오블리크가 지저분하다(웹 결정 미러).
            // 위계는 그린 좌측 룰 + secondary 색 + 넉넉한 행간으로 세운다.
            inline(block.content ?? "")
                .font(.system(size: bodySize))
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

    /// 문단 속 인라인 이미지 — 텍스트/이미지 세그먼트를 세로로 쌓는다(웹 인라인 <img> 의 iOS 번역).
    /// 이미지의 «WxH» 치수는 로드 전 비율 캐시에 미리 심어 정확한 높이를 예약한다(본문 밀림 방지).
    @ViewBuilder
    private func inlineImageParagraph(
        _ raw: String, size: CGFloat, lineSpacing: CGFloat, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(InlineImageMarkdown.segments(raw).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    inline(text)
                        .font(.system(size: size))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(color)
                case .image(let image):
                    ImageBlockView(
                        payload: ImagePayload(url: image.url, caption: image.caption, width: image.width)
                    )
                    .onAppear {
                        if let dims = image.dimensions, let url = URL(string: image.url) {
                            ImageRatioCache.record(dims, for: url)
                        }
                    }
                }
            }
        }
        .padding(.bottom, isLead ? 20 : 18)
    }

    /// 본문 속 맨 URL(`https://…`)을 CommonMark 오토링크(`<url>`)로 감싼다 — 웹 렌더(remark-gfm)는
    /// 맨 URL 을 자동 링크하는데 Apple 마크다운 파서는 안 해서, 붙여넣은 주소가 웹에선 링크·앱에선
    /// 죽은 텍스트로 갈라지던 것을 맞춘다. `[라벨](url)` 안 주소는 링크 문법 소유라 제외하고,
    /// 인라인 코드가 섞인 문단은 통째로 건너뛴다(코드 속 주소 보호 — 보수적 판정).
    private static let bareURLAutolink = try? NSRegularExpression(
        pattern: "(?<!\\]\\()(?<!<)(https?://[^\\s<>\\)\\]]+)")

    private func autolinkBareURLs(_ raw: String) -> String {
        guard raw.contains("http://") || raw.contains("https://"), !raw.contains("`"),
              let regex = Self.bareURLAutolink else { return raw }
        let ns = raw as NSString
        return regex.stringByReplacingMatches(
            in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "<$1>")
    }

    /// 인라인 파싱 결과 캐시 — 같은 문단이 스크롤·하이라이트 토글·부모 무효화마다 다시 파싱되던 것을 막는다
    /// (`AttributedString(markdown:)` + 오토링크 정규식이 body 마다 O(보이는 블록)만큼 돌던 비용).
    /// 키 = 원문 + 인라인 코드 크기(bodySize) — 색은 동적 `Color`(Palette)를 그대로 담아 Text 가 스킴별로
    /// 다시 해석하므로(라이트/다크 자동 대응) 키에 넣지 않는다. countLimit 으로 긴 글 연속 열람에도 유계.
    private static let inlineCache: NSCache<NSString, InlineBox> = {
        let cache = NSCache<NSString, InlineBox>()
        cache.countLimit = 512
        return cache
    }()

    /// NSCache 는 참조 타입만 담아 AttributedString(값 타입)을 감싼다.
    private final class InlineBox {
        let attributed: AttributedString
        init(_ attributed: AttributedString) { self.attributed = attributed }
    }

    private func inline(_ raw: String) -> Text {
        let key = "\(bodySize)|\(raw)" as NSString
        if let box = Self.inlineCache.object(forKey: key) {
            return Text(box.attributed)
        }
        let source = autolinkBareURLs(raw)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if var attributed = try? AttributedString(markdown: source, options: options) {
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
            Self.inlineCache.setObject(InlineBox(attributed), forKey: key)
            return Text(attributed)
        }
        return Text(raw)
    }

    /// 단독 `#### `/`##### `/`###### ` 줄이면 (레벨 4~6, 뒤 내용). 여러 줄이거나 h1~3(블록으로
    /// 승격됨)·해시 뒤 공백 없음이면 nil → 보통 문단. 웹 리더의 h4~6 처리와 파리티.
    static func subHeading(_ content: String) -> (level: Int, text: String)? {
        let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.contains("\n") else { return nil }
        var hashes = 0
        for ch in line { if ch == "#" { hashes += 1 } else { break } }
        guard hashes >= 4, hashes <= 6 else { return nil }
        let after = line.dropFirst(hashes)
        guard after.first == " " else { return nil }
        let text = String(after.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes, text)
    }

    /// h4~6 소제목 뷰 — h4 는 웹(17px semibold)에 맞추고, h5·h6 은 그 아래로 한 칸씩 내려
    /// 사다리를 잇는다(웹엔 h5·h6 전용 스타일이 없어 소실을 막는 쪽으로 확장).
    @ViewBuilder
    private func subHeadingView(level: Int, text: String) -> some View {
        let size = h4Size - CGFloat(level - 4) // h4=17, h5=16, h6=15
        inline(text)
            .font(.system(size: size, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(level >= 6 ? Palette.heading : Palette.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 14).padding(.bottom, 2)
    }

    private func parseListItems(_ content: String?) -> [ListItem] {
        guard let content, !content.isEmpty else { return [] }
        if let data = content.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array.map { text in
                let (task, stripped) = Self.taskMarker(text)
                return ListItem(depth: 0, text: stripped, task: task)
            }
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { rawLine in
                let line = String(rawLine)
                // 선행 공백/탭으로 중첩 깊이 — 2칸(또는 탭 1)을 한 단계, 최대 4단계.
                var lead = 0
                for ch in line {
                    if ch == " " { lead += 1 } else if ch == "\t" { lead += 2 } else { break }
                }
                var s = line.trimmingCharacters(in: .whitespaces)
                for marker in ["- ", "* ", "+ "] where s.hasPrefix(marker) {
                    s.removeFirst(marker.count)
                }
                if let dot = s.firstIndex(of: "."), s[..<dot].allSatisfy(\.isNumber) {
                    s = String(s[s.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                }
                let (task, stripped) = Self.taskMarker(s)
                return ListItem(depth: min(4, lead / 2), text: stripped, task: task)
            }
    }

    /// GFM 작업 목록 마커 — 글머리 뗀 항목 텍스트가 `[ ] `/`[x] `/`[X] ` 로 시작하면
    /// (완료 여부, 마커 뗀 텍스트)를, 아니면 (nil, 원문). 웹 리더가 그리는 disabled 체크박스와 파리티.
    static func taskMarker(_ text: String) -> (checked: Bool?, text: String) {
        let lower = text.prefix(4).lowercased()
        guard lower.hasPrefix("[ ] ") || lower.hasPrefix("[x] ") else { return (nil, text) }
        return (lower.hasPrefix("[x] "), String(text.dropFirst(4)))
    }
}

/// 하이라이트 스토어 관찰을 한 문단으로 가둔 얇은 래퍼. 여기서만 `store.marks(forBlock:)` 를 읽어
/// SwiftUI 가 이 문단에 대해서만 `store.highlights`(·paintHidden)를 추적한다 — 다른 문단의 마크가
/// 바뀌어도 이 뷰는 무효화되지 않는다. 넘겨받는 `[Mark]` 는 Equatable 값 타입이라, 마크가 실제로
/// 달라진 문단만 SelectableProseText 의 페인트가 다시 돈다(그마저도 파싱은 재사용, #2). 스토어 전체를
/// 모든 BlockView 에 주입해 아무 하이라이트 변경이 글 전체를 재파싱하던 블래스트 레이디어스를 좁힌다.
private struct HighlightableParagraph: View {
    let store: PostHighlightStore
    let blockOrder: Int
    let raw: String
    let fontSize: CGFloat
    let textColor: Color
    let lineSpacing: CGFloat

    var body: some View {
        SelectableProseText(
            raw: raw,
            fontSize: fontSize,
            textColor: textColor,
            lineSpacing: lineSpacing,
            highlights: store.marks(forBlock: blockOrder),
            onHighlight: { start, end, quote in
                store.create(
                    blockOrder: blockOrder, startOffset: start, endOffset: end, quote: quote)
            },
            onHighlightNote: { start, end, quote in
                store.noteDraft = PostHighlightStore.NoteDraft(
                    blockOrder: blockOrder, startOffset: start, endOffset: end, quote: quote)
            },
            onOpenThread: { id in store.threadHighlightId = id }
        )
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
    // 코드 바·본문 크기 — 사다리 밖(mono/소형)이라 크기 보존하되 Dynamic Type 는 얹는다(읽기면 나머지와 같은 결).
    @ScaledMetric(relativeTo: .caption) private var langLabelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var codeSize: CGFloat = 14

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
                        .font(.system(size: langLabelSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.codeText.opacity(0.7)) // codeBg 위 ≥4.5:1
                }
                Spacer(minLength: 0)
                Button(action: copy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(copied ? "복사됨" : "복사")
                            .typeScale(.meta)
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
                    .font(.system(size: codeSize, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.codeBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusControl).strokeBorder(Palette.hairlineStrong.opacity(0.4), lineWidth: 1))
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

/// slate-900 위에서 또렷한, 절제된 다크 테마. 색은 `Palette.code*`(§색 규율의 유일한
/// 다색 예외) 에서 다스리고 여기선 참조만 한다. 언어를 정확히 파싱하지 않는다 —
/// 문자열·주석·숫자·식별자(키워드/타입) 수준의 범용 토큰만 칠해 어떤 언어든
/// "코드처럼" 보이게 한다(과채색보다 안전 우선). 발행 리더와 V2 에디터 코드 블록이
/// 같은 워커(walk)를 공유한다 — 편집 중 보던 색이 발행 후에도 같은 자리에 선다.
enum CodeSyntax {
    static let plain = Palette.codeText
    static let comment = Palette.codeComment
    static let keyword = Palette.codeKeyword
    static let string = Palette.codeString
    static let number = Palette.codeNumber
    static let type = Palette.codeType

    /// 토큰 종류 — 색 매핑은 각 표면(리더=SwiftUI Color, 에디터=UIColor)이 맡는다.
    enum TokenKind { case plain, comment, string, number, keyword, type }

    /// 에디터(UITextView) 표면 — 같은 워커로 UIKit 속성 문자열을 만든다.
    static func nsHighlight(_ code: String, lang: String?, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func color(_ kind: TokenKind) -> UIColor {
            switch kind {
            case .plain: return UIColor(plain)
            case .comment: return UIColor(comment)
            case .string: return UIColor(string)
            case .number: return UIColor(number)
            case .keyword: return UIColor(keyword)
            case .type: return UIColor(type)
            }
        }
        walk(code, lang: lang) { piece, kind in
            result.append(NSAttributedString(
                string: piece,
                attributes: [.font: font, .foregroundColor: color(kind)]))
        }
        return result
    }

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
        var result = AttributedString()
        func color(_ kind: TokenKind) -> Color {
            switch kind {
            case .plain: return plain
            case .comment: return comment
            case .string: return string
            case .number: return number
            case .keyword: return keyword
            case .type: return type
            }
        }
        walk(code, lang: lang) { piece, kind in
            var attributed = AttributedString(piece)
            attributed.foregroundColor = color(kind)
            result += attributed
        }
        return result
    }

    /// 공용 토큰 워커 — 코드를 순서대로 (조각, 종류) 로 흘린다. 색·속성은 호출자가 입힌다.
    static func walk(_ code: String, lang: String?, emit emitPiece: (String, TokenKind) -> Void) {
        // 아주 긴 블록은 색칠 비용을 피한다(스캔·다수 append).
        guard code.count <= 6000 else {
            emitPiece(code, .plain)
            return
        }
        let s = Array(code)
        let n = s.count
        let hashComment = hashCommentLangs.contains((lang ?? "").lowercased())
        var i = 0

        func emit(_ range: Range<Int>, _ kind: TokenKind) {
            guard !range.isEmpty else { return }
            emitPiece(String(s[range]), kind)
        }

        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

        while i < n {
            let c = s[i]

            // 줄/블록 주석
            if c == "/", i + 1 < n, s[i + 1] == "/" {
                var j = i
                while j < n, s[j] != "\n" { j += 1 }
                emit(i..<j, .comment); i = j; continue
            }
            if c == "/", i + 1 < n, s[i + 1] == "*" {
                var j = i + 2
                while j < n, !(s[j] == "*" && j + 1 < n && s[j + 1] == "/") { j += 1 }
                j = min(n, j + 2)
                emit(i..<j, .comment); i = j; continue
            }
            if hashComment, c == "#" {
                var j = i
                while j < n, s[j] != "\n" { j += 1 }
                emit(i..<j, .comment); i = j; continue
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
                emit(i..<min(j, n), .string); i = min(j, n); continue
            }

            // 숫자
            if c.isNumber {
                var j = i
                while j < n, s[j].isNumber || s[j] == "." || s[j] == "_"
                    || "xXoObBeE".contains(s[j]) || "abcdefABCDEF".contains(s[j]) { j += 1 }
                emit(i..<j, .number); i = j; continue
            }

            // 식별자 → 키워드/타입/일반
            if c.isLetter || c == "_" {
                var j = i
                while j < n, isWordChar(s[j]) { j += 1 }
                let word = String(s[i..<j])
                if keywords.contains(word) {
                    emit(i..<j, .keyword)
                } else if let first = word.first, first.isUppercase {
                    emit(i..<j, .type)
                } else {
                    emit(i..<j, .plain)
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
            emit(i..<j, .plain); i = j
        }
    }
}

// MARK: 이미지 블록 — rounded-2xl + 캡션 slate-400

private struct ImagePayload {
    var url: String
    var caption: String?
    var width: String? // "wide" / "full" = 컬럼보다 넓게(블리드), "half" = 좁게. 없으면 기본.

    static func decode(_ content: String?) -> ImagePayload {
        guard let content, let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ImagePayload(url: content ?? "", caption: nil, width: nil) }
        return ImagePayload(
            url: json["url"] as? String ?? "",
            caption: json["caption"] as? String,
            width: json["width"] as? String)
    }
}

/// 한 번 그린 본문 이미지의 실제 비율(가로/세로) 세션 캐시. 블록 payload 에 원본 크기가
/// 없어 처음 보는 이미지는 비율을 모른다 — 재로드(캐시 축출 후 재방문)만이라도 정확한
/// 높이를 예약해, 로드되는 순간 읽던 본문이 밀리지 않게 한다.
@MainActor
private enum ImageRatioCache {
    private static var ratios: [URL: CGFloat] = [:]

    static func ratio(for url: URL) -> CGFloat? { ratios[url] }

    static func record(_ size: CGSize, for url: URL) {
        guard size.width > 0, size.height > 0 else { return }
        ratios[url] = size.width / size.height
    }
}

private struct ImageBlockView: View {
    let payload: ImagePayload

    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 13
    /// 탭하면 전체 화면 뷰어로 — 커버·본문 이미지 모두 이 경로를 탄다.
    @State private var showLightbox = false

    var body: some View {
        VStack(spacing: 12) {
            if let url = URL(string: payload.url) {
                // 첫 로드만 마크 플레이스홀더에서 부드럽게 페이드인 — 이미 본 이미지(캐시)는 즉시 그려진다.
                RemoteImage(url: url, animation: .easeOut(duration: 0.35)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().transition(.opacity)
                            .onAppear {
                                // 실제 비율을 기억 — 다음 로드의 placeholder 가 정확한 높이를 잡는다.
                                if let loaded = RemoteImageCache.shared.cached(url) {
                                    ImageRatioCache.record(loaded.size, for: url)
                                }
                            }
                    case .failure:
                        // 로드 실패 — 무한 스피너 대신 또렷한 안내(다시 시도는 글 새로고침으로).
                        reservedBox(for: url)
                            .overlay {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 22))
                                    Text("이미지를 불러오지 못했어요")
                                        .typeScale(.meta)
                                }
                                .foregroundStyle(Palette.secondary)
                            }
                    default:
                        reservedBox(for: url)
                            .overlay(KurlLoadingMark())
                            .transition(.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMini))
                .accessibilityLabel(Text(
                    payload.caption?.isEmpty == false
                        ? payload.caption! : String(localized: "본문 이미지")))
                // 폭: half = 좁게 중앙, wide/full = 컬럼 밖으로 블리드, 기본 = 컬럼 전폭.
                .frame(maxWidth: payload.width == "half" ? 320 : .infinity)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(
                    .horizontal,
                    payload.width == "wide" || payload.width == "full" ? -Metrics.gutter : 0)
                // 탭 = 전체 화면으로 크게 보기(핀치·팬·닫기).
                .contentShape(Rectangle())
                .onTapGesture { showLightbox = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("두 번 탭하면 크게 봅니다"))
                .fullScreenCover(isPresented: $showLightbox) {
                    ImageLightbox(url: url, caption: payload.caption)
                }
            }
            if let caption = payload.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: captionSize))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 6)
    }

    /// 로드 전·실패 자리 — 고정 높이 대신 실제 비율(모르면 사진 일반형 4:3)로 컬럼폭 기준
    /// 높이를 예약한다. 고정 200pt 는 성공 시 자연 비율과의 차이만큼 아래 본문을 밀었다.
    private func reservedBox(for url: URL) -> some View {
        RoundedRectangle(cornerRadius: Metrics.radiusMini)
            .fill(Palette.hairline)
            .aspectRatio(ImageRatioCache.ratio(for: url) ?? 4.0 / 3.0, contentMode: .fit)
    }
}

// MARK: 리스트 블록 — 마커 그린

/// 리스트 항목 — 중첩 깊이(들여쓰기)와 텍스트. 0 = 최상위.
/// task = GFM 작업 목록(`- [ ]`/`- [x]`) 상태. nil 이면 보통 항목(글머리·번호).
private struct ListItem {
    let depth: Int
    let text: String
    var task: Bool?
}

private struct ListBlockView: View {
    let items: [ListItem]
    let ordered: Bool

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    markerView(item, index: index)
                    Text(inline(item.text))
                        .font(.system(size: bodySize))
                        .lineSpacing(bodySize * 0.5)
                        .foregroundStyle(Palette.body)
                }
                .padding(.leading, CGFloat(item.depth) * 18) // 중첩 들여쓰기
                // 작업 항목은 완료 여부를 음성으로 알린다(글리프는 숨겨 중복 낭독 방지).
                .accessibilityElement(children: item.task == nil ? .contain : .combine)
                .accessibilityLabel(taskAXLabel(item))
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    // 항목 앞 글머리 — 작업 목록은 읽기 전용 체크박스 글리프(웹 disabled input 파리티),
    // 그 외엔 글머리·번호 텍스트. 체크박스는 눌러도 상태가 안 바뀐다(읽기면은 열람만).
    @ViewBuilder
    private func markerView(_ item: ListItem, index: Int) -> some View {
        if let checked = item.task {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: bodySize * 0.92))
                .foregroundStyle(checked ? Palette.accentFill : Palette.secondary)
                .accessibilityHidden(true)
        } else {
            Text(marker(item, index: index))
                .font(.system(size: bodySize))
                .foregroundStyle(Palette.secondary)
                .monospacedDigit()
        }
    }

    // 작업 항목의 음성 라벨 — "완료/미완료, 본문". 보통 항목은 빈 텍스트(자식 낭독에 맡김).
    private func taskAXLabel(_ item: ListItem) -> Text {
        guard let checked = item.task else { return Text("") }
        return Text(checked ? "완료됨" : "미완료") + Text(", ") + Text(item.text)
    }

    // 중첩 단계별 글머리(•→◦→▪). 번호 목록은 그대로 번호(중첩 번호 재시작은 생략).
    private func marker(_ item: ListItem, index: Int) -> String {
        if ordered { return "\(index + 1)." }
        switch item.depth {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }

    private func inline(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }
}

// MARK: 테이블 블록 — flat (헤더 밑줄 + 행 구분선)

/// GFM 표 파서 — 뷰에서 떼어내 순수 함수로 둔다(단위 테스트로 빈 셀 보존·정렬을 고정).
enum TableMarkdown {
    /// 마크다운 표를 셀 행렬로 — 감싸는 양 끝 파이프만 벗기고 내부 빈 셀은 보존한다.
    /// (예전엔 빈 셀을 전부 걸러 `| a || c |` 가 왼쪽으로 밀렸다. 웹은 빈 칸을 지킨다.)
    static func rows(_ markdown: String) -> [[String]] {
        let parsed = markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> [String] in
                var parts = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // 표준 GFM 행은 `|…|` 라 양 끝이 빈 조각으로 나온다 — 그 둘만 벗긴다.
                if parts.first == "" { parts.removeFirst() }
                if parts.last == "" { parts.removeLast() }
                return parts
            }
            .filter { cells in
                // 구분선 행(--- / :--: 등)은 렌더하지 않는다 — 빈 셀 보존과 무관하게 그대로.
                !(cells.isEmpty || cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } })
            }
        // 헤더(첫 행)의 열 수에 맞춰 데이터 행을 pad/truncate — 빈 셀이 있어도 열이 어긋나지 않게.
        guard let columnCount = parsed.first?.count, columnCount > 0 else { return parsed }
        return parsed.map { row in
            if row.count == columnCount { return row }
            if row.count < columnCount { return row + Array(repeating: "", count: columnCount - row.count) }
            return Array(row.prefix(columnCount))
        }
    }

    enum ColumnAlignment {
        case leading, center, trailing
    }

    /// GFM 구분선 행에서 열 정렬을 읽는다 — `:---` 왼쪽 · `:---:` 가운데 · `---:` 오른쪽.
    /// 구분선이 없으면 빈 배열(호출측이 전부 왼쪽 기본으로 처리). 빈 셀 보존과는 독립.
    static func columnAlignments(_ markdown: String) -> [ColumnAlignment] {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: true) {
            var parts = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first == "" { parts.removeFirst() }
            if parts.last == "" { parts.removeLast() }
            let isSeparator = !parts.isEmpty && parts.allSatisfy { token in
                token.contains("-") && token.allSatisfy { "-: ".contains($0) }
            }
            guard isSeparator else { continue }
            return parts.map { token in
                let leadingColon = token.hasPrefix(":")
                let trailingColon = token.hasSuffix(":")
                if leadingColon && trailingColon { return .center }
                if trailingColon { return .trailing }
                return .leading
            }
        }
        return []
    }
}

private struct TableBlockView: View {
    let markdown: String

    @ScaledMetric(relativeTo: .callout) private var cellSize: CGFloat = 15
    // 콘텐츠 폭 > 뷰포트 폭이면 표가 가로로 넘친다 — 그때만 오른쪽에 페이드로 "더 있음"을 알린다.
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private var overflowing: Bool { contentWidth > viewportWidth + 1 }

    private func textAlign(_ col: Int, _ aligns: [TableMarkdown.ColumnAlignment]) -> TextAlignment {
        switch col < aligns.count ? aligns[col] : .leading {
        case .center: .center
        case .trailing: .trailing
        case .leading: .leading
        }
    }

    private func gridAlign(_ col: Int, _ aligns: [TableMarkdown.ColumnAlignment]) -> HorizontalAlignment {
        switch col < aligns.count ? aligns[col] : .leading {
        case .center: .center
        case .trailing: .trailing
        case .leading: .leading
        }
    }

    var body: some View {
        let rows = TableMarkdown.rows(markdown)
        // 열 정렬은 구분선 토큰에서 읽는다 — 셀 폭은 콘텐츠대로 두고(넘치면 가로 스크롤+페이드)
        // 정렬만 열 단위로 건다. 폭 고정(웹 table-layout:fixed)은 좁은 화면에서 표를 뭉갠다.
        let aligns = TableMarkdown.columnAlignments(markdown)
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { col, cell in
                            Text(cell)
                                .font(.system(size: cellSize, weight: index == 0 ? .semibold : .regular))
                                .foregroundStyle(index == 0 ? Palette.ink : Palette.body)
                                .multilineTextAlignment(textAlign(col, aligns))
                                .gridColumnAlignment(gridAlign(col, aligns))
                                .padding(.vertical, 8)
                        }
                    }
                    Rectangle()
                        .fill(index == 0 ? Palette.hairlineStrong : Palette.hairline)
                        .frame(height: index == 0 ? 2 : 1)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        // 넘칠 때만 오른쪽 가장자리 페이드 — 읽기면 바탕색으로 스러지게 해 "옆으로 더" 어포던스를 준다.
        .overlay(alignment: .trailing) {
            if overflowing {
                LinearGradient(
                    colors: [Palette.readingBg.opacity(0), Palette.readingBg],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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

/// 링크 카드 — 파비콘 + 정리된 host + 제목으로 "어디로 가는 링크"인지 한눈에.
/// 제목·파비콘은 블록이 이미 가진 값(provider·url)만으로 — 별도 메타 fetch 없음(파비콘 하나만).
private struct EmbedLinkCard: View {
    let payload: EmbedPayload

    @ScaledMetric(relativeTo: .callout) private var labelSize: CGFloat = 14

    /// www. 를 뗀 표시용 도메인. host 를 못 뽑으면 원문 URL 그대로.
    private var host: String {
        guard let raw = URL(string: payload.url)?.host, !raw.isEmpty else { return payload.url }
        return raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
    }

    /// 제목 = provider(있으면), 없으면 도메인. 도메인은 두 번째 줄에서 다시 세운다.
    private var title: String {
        if let provider = payload.provider?.trimmingCharacters(in: .whitespaces), !provider.isEmpty {
            return provider
        }
        return host
    }

    /// 제목이 도메인 그 자체면 둘째 줄은 생략(같은 글자 반복 금지).
    private var subtitle: String? { title == host ? nil : host }

    private var faviconURL: URL? {
        URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    var body: some View {
        if let url = URL(string: payload.url) {
            Link(destination: url) {
                HStack(spacing: 12) {
                    favicon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: labelSize, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .typeScale(.footnote)
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusControl)
                        .strokeBorder(Palette.hairlineStrong, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(title), \(host) 링크 열기"))
        }
    }

    /// 파비콘 — 로드되면 사이트 아이콘, 실패·로딩 중엔 조용한 지구본 글리프로 폴백.
    private var favicon: some View {
        RemoteImage(url: faviconURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 2))
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
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                .strokeBorder(Palette.hairlineStrong.opacity(0.5), lineWidth: 1)
        )
        .padding(.vertical, 8)
        // 화면을 벗어나면(스크롤 이탈·다른 글 푸시) 포스터로 되돌린다 —
        // 웹뷰가 내려가며 재생이 멎고, lazy 재생성 때 autoplay 재로드도 없다.
        .onDisappear { playing = false }
    }

    private var posterView: some View {
        ZStack {
            if let poster {
                RemoteImage(url: poster) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Palette.codeBg
                    }
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

    // 뷰 트리에서 내려갈 때 명시적으로 정지 — 제거만으로는 오디오가 이어질 수 있다.
    static func dismantleUIView(_ webView: WKWebView, coordinator: ()) {
        webView.pauseAllMediaPlayback()
        webView.stopLoading()
    }
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

    @ScaledMetric(relativeTo: .headline) private var labelSize: CGFloat = 15

    var body: some View {
        if let url = URL(string: cta.url) {
            Link(destination: url) {
                Text(cta.label)
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.accentFill, in: RoundedRectangle(cornerRadius: Metrics.radiusControl))
            }
            .padding(.vertical, 6)
        }
    }
}
