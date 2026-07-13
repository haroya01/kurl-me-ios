//
//  EditorHarnessView.swift
//  kurl — WriteV2 (격리 하네스)
//
//  ComposeView 를 전혀 안 건드리고 새 WYSIWYG 에디터를 단독 실행·검증하는 화면.
//  실행 경로 둘:
//   1) Xcode Canvas — 이 파일 하단 #Preview("WriteV2 하네스").
//   2) 런치 플래그 `--screen editor2` — RootView 에 한 줄만 더하면(선택) simctl 스샷용 진입로.
//      Config.launchValue(after:) 규칙은 기존과 동일. (Phase 1 은 RootView 를 안 고친다 —
//      아래 EditorHarnessRoot 를 그 분기에 연결하는 한 줄이 유일한 통합 지점이다.)
//
//  하네스는 하단에 "마크다운 보기" 토글을 둔다 — 왕복(블록→마크다운)을 눈으로 확인하는 검증 장치다
//  (에디터 본체엔 원시 마크다운이 안 보이지만, 하네스는 직렬화 결과를 따로 띄워 대조한다).
//

import SwiftUI

/// simctl 진입용 루트 래퍼 — RootView 의 `--screen` 분기에서 이걸 반환하면 된다(선택 통합).
struct EditorHarnessRoot: View {
    var body: some View {
        EditorHarnessView(document: EditorDocument(blocks: EditorSample.blocks))
    }
}

struct EditorHarnessView: View {
    @State private var document: EditorDocument
    @State private var showMarkdown = false

    init(document: EditorDocument) {
        _document = State(initialValue: document)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WysiwygEditorView(document: document)

            // 검증용 유리 캡슐(§1 크롬만 유리) — 왕복 직렬화 결과를 펼쳐 대조.
            VStack(spacing: 0) {
                if showMarkdown {
                    markdownInspector
                }
                Button {
                    withAnimation(.snappy(duration: 0.22)) { showMarkdown.toggle() }
                } label: {
                    Label(
                        showMarkdown ? "마크다운 닫기" : "마크다운 보기",
                        systemImage: showMarkdown ? "chevron.down" : "curlybraces"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .foregroundStyle(Palette.link)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
            }
        }
    }

    private var markdownInspector: some View {
        ScrollView {
            Text(document.markdown)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxHeight: 220)
        .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusControl)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

/// 하네스 샘플 — 4블록 WYSIWYG 증명(문단·제목·인용·코드) + 인라인 볼드. 데모 카피는 하네스 전용.
enum EditorSample {
    static var blocks: [EditorBlock] {
        [
            .heading(1, "종이 본문, 액체 크롬"),
            .paragraph("이 문단은 **볼드**와 *이탤릭*, 그리고 `인라인 코드`가 최종 모습으로 보인다. 원시 마크다운 마커는 흐리게만 남는다."),
            .heading(2, "인용과 코드"),
            .quote("작고 깊게 사랑받기를 택한다 — 성장 천장은 의식적으로 받아들인다."),
            .code("func greet(_ name: String) {\n    print(\"안녕, \\(name)\")\n}", language: "swift"),
            .paragraph("줄머리에 # · > · ``` 를 치면 이 문단이 그 자리에서 제목·인용·코드로 바뀐다."),
        ]
    }
}

#Preview("WriteV2 하네스") {
    EditorHarnessView(document: EditorDocument(blocks: EditorSample.blocks))
}

#Preview("WriteV2 빈 문서") {
    EditorHarnessView(document: EditorDocument())
}
