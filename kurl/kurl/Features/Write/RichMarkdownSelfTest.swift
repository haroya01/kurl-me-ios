//
//  RichMarkdownSelfTest.swift
//  kurl
//

import SwiftUI

/// 마크다운 ⇄ 속성문자열 왕복 검증 — 유닛 테스트 타깃이 없어, `--screen richmd-test`(DEBUG·
/// 목 전용) 진입로로 결과를 화면에 그려 스냅샷으로 확인한다. 각 케이스: 파싱→직렬화가 원문과
/// 같아야 PASS(Phase 1 지원 서식: 제목·굵게·기울임·인라인코드, 한글 포함).
enum RichMarkdownSelfTest {
    static let cases: [String] = [
        "안녕하세요 반갑습니다",
        "# 큰 제목입니다",
        "## 중간 제목",
        "### 작은 제목",
        "앞 **굵게** 뒤",
        "앞 *기울임* 뒤",
        "코드 `let x = 1` 끝",
        "첫째 줄\n둘째 줄\n셋째 줄",
        "## 제목\n본문 **굵게** 입니다",
        "한글 **볼드**·`코드`·*이탤릭* 섞임 ok",
    ]

    struct Result: Identifiable {
        let id = UUID()
        let input: String
        let got: String
        var ok: Bool { input == got }
    }

    static func run() -> [Result] {
        cases.map { md in
            let round = RichMarkdown.markdown(from: RichMarkdown.attributed(from: md, color: .label))
            return Result(input: md, got: round)
        }
    }
}

struct RichMarkdownSelfTestView: View {
    private let results = RichMarkdownSelfTest.run()
    private var allPass: Bool { results.allSatisfy(\.ok) }

    var body: some View {
        NavigationStack {
            List(results) { r in
                HStack(alignment: .top, spacing: 10) {
                    Text(r.ok ? "✅" : "❌")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(show(r.input))
                            .font(.system(size: 12).monospaced())
                        if !r.ok {
                            Text("→ " + show(r.got))
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(allPass ? "왕복 검증 PASS" : "왕복 검증 FAIL")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func show(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "⏎") }
}
