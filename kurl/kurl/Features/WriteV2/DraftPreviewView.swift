//
//  DraftPreviewView.swift
//  kurl — WriteV2
//
//  초안(미발행 글)의 네이티브 읽기 미리보기 — 지금 문서(마크다운)를 발행 후 읽기면과 같은 모습으로
//  보여준다. 인앱 사파리(웹 URL)로 내쫓지 않고, 리더(BlockRenderer 의 BlockView)를 그대로 재사용해
//  "발행하면 이렇게 보인다"를 종이 세계(§1)에서 그린다. 하이라이트·댓글·시리즈 같은 발행 후 표면은
//  빼고 본문만 — 제목 마스트헤드 + 읽는 시간 + 블록. 발행된 글의 미리보기 경로는 여기 오지 않는다
//  (PostDetailView 항해로 별도). 왕복 계약과 무관 — 읽기 전용 렌더다.
//

import SwiftUI

struct DraftPreviewView: View {
    let title: String
    /// 지금 문서 → 읽기면 블록. 한 번만 파싱하도록 init 에서 만든다(body 매 평가마다 재파싱 방지).
    private let blocks: [PostBlock]

    init(title: String, markdown: String) {
        self.title = title
        self.blocks = DraftPreviewBlocks.from(markdown: markdown)
    }

    @Environment(\.dismiss) private var dismiss

    // 마스트헤드 메타 크기(읽는 시간 등) — Dynamic Type 따라간다.
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    private var readingMinutes: Int? {
        let prose: Set<BlockKind> = [.paragraph, .h1, .h2, .h3, .quote]
        let chars = blocks.reduce(0) { sum, block in
            prose.contains(block.kind) ? sum + (block.content?.count ?? 0) : sum
        }
        guard chars > 0 else { return nil }
        return max(1, Int((Double(chars) / 500.0).rounded()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    masthead
                    article(blocks)
                }
                .frame(maxWidth: Metrics.readingColumn)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Palette.readingBg.ignoresSafeArea())
            .navigationTitle("미리보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Palette.link)
                }
            }
        }
    }

    // MARK: 마스트헤드 — 제목 + 읽는 시간(작가·시리즈 링크는 초안 프리뷰에서 뺀다)

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 8)
            Text(title.isEmpty ? String(localized: "제목 없음") : title)
                .typeScale(.display)
                .lineSpacing(6)
                .foregroundStyle(title.isEmpty ? Palette.faint : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let minutes = readingMinutes {
                HStack(spacing: 5) {
                    Image(systemName: "book")
                        .font(.system(size: 11 * metaUnit, weight: .medium))
                    Text("\(minutes)분 읽기")
                        .typeScale(.footnote)
                }
                .foregroundStyle(Palette.secondary)
                .padding(.top, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("읽는 시간 약 \(minutes)분"))
            }

            Hairline().padding(.top, 18)
        }
    }

    // MARK: 본문 — 리더(BlockView) 그대로. 첫 문단은 lead.

    @ViewBuilder
    private func article(_ blocks: [PostBlock]) -> some View {
        if blocks.isEmpty || onlyEmptyParagraph(blocks) {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 2) {
                let leadIndex = blocks.firstIndex { $0.kind == .paragraph }
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    BlockView(block: block, isLead: index == leadIndex)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 20)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("아직 본문이 없어요")
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
            Text("글을 쓰면 여기에서 발행 후 모습을 미리 볼 수 있어요.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.faint)
        }
        .padding(.top, 40)
    }

    /// 본문이 사실상 비었는가(빈 문단 하나뿐) — 파서는 빈 입력에도 문단 1개를 돌려준다.
    private func onlyEmptyParagraph(_ blocks: [PostBlock]) -> Bool {
        blocks.count == 1 && blocks[0].kind == .paragraph
            && (blocks[0].content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
