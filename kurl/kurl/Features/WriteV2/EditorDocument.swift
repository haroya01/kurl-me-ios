//
//  EditorDocument.swift
//  kurl — WriteV2
//
//  편집 모델. 블록 배열 + 포커스 + 편집 연산(엔터=분할 · 백스페이스=병합 · 삽입/삭제 ·
//  줄머리 마크다운 지름길). 뷰(WysiwygEditorView)는 이 @Observable 하나에만 말을 건다 —
//  per-block UITextView 는 텍스트/캐럿만 위임하고 구조 변경은 전부 여기서 일어난다.
//
//  아키텍처 선택(§4): "블록 = per-block UITextView" 를 택했다.
//   • 이유: 현행 앱이 이미 UITextView(MarkdownTextView) 로 한글 IME·선택·하이라이트를 다룬다.
//     블록별 UITextView 는 그 자산(마커드텍스트 가드·타이핑 속성)을 블록 경계 안에서 재사용한다.
//   • 어려운 부분(명시): (1) 블록 경계에서의 엔터/백스페이스를 shouldChangeText 로 가로채 구조
//     연산으로 승격 (2) 분할/병합 후 캐럿을 옮긴 블록의 정확한 오프셋으로 복원 (3) 새 블록이
//     first responder 를 이어받게 하는 포커스 핸드오프. 이 세 지점이 per-block 아키텍처의 세금이다.
//

import SwiftUI

/// 어느 블록의 어디에 캐럿이 있는지 — 포커스 핸드오프의 좌표.
nonisolated struct EditorFocus: Equatable {
    var blockID: UUID
    /// 블록 text 안 캐럿 위치(UTF-16 오프셋 아님, Swift String 인덱스 거리). 병합/분할 복원에 쓴다.
    /// 선택이 있으면 이 위치가 선택 시작이고 length 가 길이(0=순수 캐럿).
    var caret: Int
    /// 선택 길이(String 인덱스 거리). 0 이면 캐럿, >0 이면 [caret, caret+length) 가 선택됨.
    /// 서식 툴바가 "선택을 마커로 감싸기"에 쓰고, 감싼 뒤 안쪽을 다시 선택 상태로 되돌리는 데도 쓴다.
    var selectionLength: Int = 0
}

@MainActor
@Observable
final class EditorDocument {
    private(set) var blocks: [EditorBlock]
    /// 포커스 — 뷰가 이 값 변화를 보고 해당 블록 UITextView 를 first responder 로 만들고 캐럿을 놓는다.
    var focus: EditorFocus?
    /// 툴바 서식 직후 1회 마커 반개봉 억제(B1) — 이 블록의 다음 렌더는 캐럿이 스팬 안이어도 마커를
    /// 숨긴다("굵게 눌렀는데 **가 보인다"의 근본). 뷰가 그 렌더에서 소비(nil 로)한다. 이후 캐럿 이동/
    /// 타이핑엔 정상 반개봉이 돌아온다(왕복·reveal 계약 불변 — 표시 속성 1프레임만 다르다).
    var suppressRevealOnceBlockID: UUID?

    init(blocks: [EditorBlock] = [.paragraph("")]) {
        self.blocks = blocks.isEmpty ? [.paragraph("")] : blocks
    }

    convenience init(markdown: String) {
        self.init(blocks: MarkdownBlockParser.parse(markdown))
    }

    /// 현재 문서를 마크다운으로(저장·왕복 검증 진입점).
    var markdown: String { MarkdownSerializer.markdown(from: blocks) }

    // MARK: 인덱싱

    func index(of id: UUID) -> Int? { blocks.firstIndex { $0.id == id } }

    // MARK: 텍스트 갱신 (구조 변경 없음)

    /// 뷰가 블록 안 타이핑을 반영 — 구조는 그대로, text 만 바꾼다.
    func updateText(_ id: UUID, _ newText: String) {
        guard let i = index(of: id), blocks[i].text != newText else { return }
        blocks[i].text = newText
    }

    // MARK: 엔터 = 분할

    /// 블록 `id` 의 caret 위치에서 엔터. 코드 블록 안 엔터는 분할이 아니라 개행(뷰가 처리) —
    /// 여기 오는 엔터는 "블록을 가르는" 엔터다. caret 앞은 현재 블록, 뒤는 새 블록으로.
    /// 반환: 새로 포커스를 받아야 하는 (blockID, caret=0).
    @discardableResult
    func splitBlock(_ id: UUID, at caret: Int) -> EditorFocus? {
        guard let i = index(of: id) else { return nil }
        let block = blocks[i]
        let clamped = max(0, min(caret, block.text.count))
        let cut = block.text.index(block.text.startIndex, offsetBy: clamped)
        var head = String(block.text[..<cut])
        var tail = String(block.text[cut...])

        // 강조 스팬 안에서 분할하면 짝이 갈려 양쪽에 리터럴 마커가 남는다(`**굵|게**`→`**굵`·`게**`).
        // head 를 닫는 마커로 닫고 tail 을 여는 마커로 다시 열어 양쪽 서식을 보존한다(리스트 항목도 동일).
        if let marker = BlockInlineRenderer.splitMarker(in: block.text, caret: clamped) {
            head += marker
            tail = marker + tail
        }

        // 리스트 항목에서 엔터 — 빈 항목이면 리스트 탈출(내어쓰기 → indent 0 이면 문단),
        // 내용이 있으면 같은 종류·indent 의 새 항목으로.
        if case .listItem(let ordered, let indent) = block.kind {
            if head.isEmpty, tail.isEmpty {
                // 빈 항목에서 엔터 = 리스트 종료. indent 가 있으면 한 단계 내어쓰기, 0 이면 문단으로.
                if indent > 0 {
                    blocks[i].kind = .listItem(ordered: ordered, indent: indent - 1)
                } else {
                    blocks[i].kind = .paragraph
                }
                let f = EditorFocus(blockID: blocks[i].id, caret: 0)
                focus = f
                return f
            }
            blocks[i].text = head
            let newBlock = EditorBlock(kind: .listItem(ordered: ordered, indent: indent), text: tail)
            blocks.insert(newBlock, at: i + 1)
            let f = EditorFocus(blockID: newBlock.id, caret: 0)
            focus = f
            return f
        }

        blocks[i].text = head

        // 제목/인용 뒤로 엔터를 치면 새 줄은 문단으로 떨어진다(에디터 관습) — 단 내용이 남은
        // 뒷부분이 있으면 같은 종류를 유지(제목 중간에서 가른 경우).
        let newKind: EditorBlockKind = {
            switch block.kind {
            case .heading, .quote:
                return tail.isEmpty ? .paragraph : block.kind
            case .paragraph:
                return .paragraph
            case .code:
                return .paragraph  // 코드 분할은 뷰가 개행으로 흡수하므로 여기 안 옴(안전 기본).
            case .divider, .image, .table, .listItem:
                return .paragraph  // 비텍스트/리스트는 위에서 처리(안전 기본).
            }
        }()

        let newBlock = EditorBlock(kind: newKind, text: tail)
        blocks.insert(newBlock, at: i + 1)
        let f = EditorFocus(blockID: newBlock.id, caret: 0)
        focus = f
        return f
    }

    // MARK: 리스트 들여쓰기 / 내어쓰기 (탭·시프트탭 또는 툴바)

    /// 리스트 항목을 한 단계 안으로(최대 4). 리스트가 아니면 무동작.
    func indentListItem(_ id: UUID) {
        guard let i = index(of: id), case .listItem(let ordered, let indent) = blocks[i].kind else { return }
        blocks[i].kind = .listItem(ordered: ordered, indent: min(4, indent + 1))
    }

    /// 리스트 항목을 한 단계 밖으로 — indent 0 이면 문단으로 강등.
    func outdentListItem(_ id: UUID) {
        guard let i = index(of: id), case .listItem(let ordered, let indent) = blocks[i].kind else { return }
        if indent > 0 {
            blocks[i].kind = .listItem(ordered: ordered, indent: indent - 1)
        } else {
            blocks[i].kind = .paragraph
        }
    }

    // MARK: 백스페이스 = 병합

    /// 블록 `id` 의 맨 앞(caret==0)에서 백스페이스 → 앞 블록과 병합. 앞 블록 끝에 캐럿을 남긴다.
    /// 첫 블록이면 종류만 문단으로 강등(제목/인용 → 문단; 이미 문단이면 무시).
    /// 반환: 병합 후 포커스(앞 블록, caret=앞 블록 원래 길이).
    @discardableResult
    func mergeBackward(_ id: UUID) -> EditorFocus? {
        guard let i = index(of: id) else { return nil }

        // 리스트 항목 맨 앞 백스페이스 = 리스트 마커 벗기기(내어쓰기 → indent 0 이면 문단으로 강등).
        // 이렇게 하면 리스트를 "백스페이스로 해제"하는 관습과 맞고, 앞 항목과 텍스트가 섞이지 않는다.
        if case .listItem(let ordered, let indent) = blocks[i].kind {
            if indent > 0 {
                blocks[i].kind = .listItem(ordered: ordered, indent: indent - 1)
            } else {
                blocks[i].kind = .paragraph
            }
            let f = EditorFocus(blockID: blocks[i].id, caret: 0)
            focus = f
            return f
        }

        guard i > 0 else {
            // 첫 블록에서 앞이 없으면: 제목/인용을 문단으로 내린다(마커 제거 UX).
            if case .paragraph = blocks[i].kind {
                return nil
            }
            blocks[i].kind = .paragraph
            let f = EditorFocus(blockID: blocks[i].id, caret: 0)
            focus = f
            return f
        }
        let prev = blocks[i - 1]

        // 앞이 비텍스트(구분선·이미지·표)면 텍스트 병합이 불가 — 그 비텍스트 블록을 삭제하고
        // 현재 블록 맨 앞에 캐럿을 남긴다(비텍스트 블록을 "백스페이스로 지우는" 관습).
        if prev.isNonText {
            blocks.remove(at: i - 1)
            let f = EditorFocus(blockID: id, caret: 0)
            focus = f
            return f
        }

        // 코드 블록과의 병합은 종류가 섞이므로 막는다(빈 현재 블록만 삭제하고 앞으로 포커스).
        if case .code = prev.kind {
            let caret = prev.text.count
            if blocks[i].text.isEmpty { blocks.remove(at: i) }
            let f = EditorFocus(blockID: prev.id, caret: caret)
            focus = f
            return f
        }
        // 앞이 리스트 항목이면 종류 섞임을 막는다 — 빈 현재 블록만 지우고 앞 항목 끝으로 포커스.
        if prev.listInfo != nil {
            let caret = prev.text.count
            if blocks[i].text.isEmpty { blocks.remove(at: i) }
            let f = EditorFocus(blockID: prev.id, caret: caret)
            focus = f
            return f
        }

        let joinCaret = prev.text.count
        blocks[i - 1].text = prev.text + blocks[i].text
        // 병합 시 앞 블록의 종류를 따른다(문단으로 붙는 게 관습 — 제목에 문단을 이어붙이면 제목 유지).
        blocks.remove(at: i)
        let f = EditorFocus(blockID: blocks[i - 1].id, caret: joinCaret)
        focus = f
        return f
    }

    // MARK: 비텍스트 블록 삽입 (툴바) — 구분선·이미지·표

    /// 현재 포커스 블록 뒤에 비텍스트 블록을 넣고, 이어서 편집을 잇도록 빈 문단을 하나 더한다.
    /// 포커스가 없으면 문서 끝에 붙인다. 반환: 새 후속 문단의 포커스.
    @discardableResult
    func insertNonText(_ block: EditorBlock) -> EditorFocus? {
        let anchorIndex = focus.flatMap { index(of: $0.blockID) } ?? (blocks.count - 1)
        let insertAt = min(anchorIndex + 1, blocks.count)
        blocks.insert(block, at: insertAt)
        // 비텍스트 블록 뒤엔 캐럿이 놓일 문단이 필요 — 없으면(문서 끝) 하나 만든다.
        let trailingIndex = insertAt + 1
        let trailing: EditorBlock
        if trailingIndex < blocks.count, !blocks[trailingIndex].isNonText {
            trailing = blocks[trailingIndex]
        } else {
            let p = EditorBlock.paragraph("")
            blocks.insert(p, at: trailingIndex)
            trailing = p
        }
        let f = EditorFocus(blockID: trailing.id, caret: 0)
        focus = f
        return f
    }

    // MARK: 링크 / 임베드 삽입 (툴바) — 하나의 "링크"로 통합

    /// 툴바 링크 삽입 — URL 이 동영상(YouTube·Vimeo)이면 발행 시 플레이어가 되도록 **단독 URL 문단**으로
    /// 넣고(백엔드 md→blocks 가 그 줄을 EMBED 블록으로 접는다), 아니면 `[라벨](url)` 문단으로 넣는다.
    /// 링크는 인라인이 자연스럽지만(캔버스에서 직접 `[..](..)` 를 쳐도 라이브 렌더된다), 이 버튼은
    /// 주소를 손에 든 채 한 번에 떨어뜨리는 편의라 자체 문단으로 앉힌다(구분선·이미지·표와 같은 결).
    /// `label` 이 비면 URL 자체를 라벨로 쓴다. 반환: 이어서 쓸 새 후속 문단의 포커스.
    @discardableResult
    func insertLink(url: String, label: String) -> EditorFocus? {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return focus }
        let block: EditorBlock
        if WriteV2VideoDetect.isVideoURL(trimmedURL) {
            // 임베드는 URL 이 제 문단에 홀로 서야 플레이어로 렌더된다(insertVideoEmbed 방언과 동형).
            block = .paragraph(trimmedURL)
        } else {
            let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
            block = .paragraph("[\(text.isEmpty ? trimmedURL : text)](\(trimmedURL))")
        }
        return insertNonText(block)
    }

    // MARK: 표 셀 편집

    /// 표 블록의 (row,col) 셀 텍스트 갱신.
    func updateTableCell(_ id: UUID, row: Int, col: Int, text: String) {
        guard let i = index(of: id), case .table(var table) = blocks[i].kind else { return }
        guard row >= 0, row < table.rows.count, col >= 0, col < table.rows[row].count else { return }
        table.rows[row][col] = text
        blocks[i].kind = .table(table)
    }

    /// 표에 행 추가(맨 아래).
    func addTableRow(_ id: UUID) {
        guard let i = index(of: id), case .table(var table) = blocks[i].kind else { return }
        table.rows.append(Array(repeating: "", count: table.columnCount))
        blocks[i].kind = .table(table)
    }

    /// 표에 열 추가(맨 오른쪽) — 정렬 기본 leading.
    func addTableColumn(_ id: UUID) {
        guard let i = index(of: id), case .table(var table) = blocks[i].kind else { return }
        for r in table.rows.indices { table.rows[r].append("") }
        table.alignments.append(.leading)
        blocks[i].kind = .table(table)
    }

    /// 열 정렬을 순환(leading → center → trailing → leading). GFM 구분선 토큰으로 왕복된다.
    func cycleTableColumnAlignment(_ id: UUID, col: Int) {
        guard let i = index(of: id), case .table(var table) = blocks[i].kind else { return }
        while table.alignments.count <= col { table.alignments.append(.leading) }
        let next: EditorTable.Alignment = {
            switch table.alignments[col] {
            case .leading: return .center
            case .center: return .trailing
            case .trailing: return .leading
            }
        }()
        table.alignments[col] = next
        blocks[i].kind = .table(table)
    }

    /// 표 블록의 현재 상태 스냅샷 — 삭제 되돌리기(토스트 undo)용. 표가 아니면 nil.
    func tableSnapshot(_ id: UUID) -> EditorTable? {
        guard let i = index(of: id), case .table(let table) = blocks[i].kind else { return nil }
        return table
    }

    /// 스냅샷으로 표를 되돌린다 — 삭제 되돌리기(토스트 undo)에서 호출.
    func restoreTable(_ id: UUID, to table: EditorTable) {
        guard let i = index(of: id), case .table = blocks[i].kind else { return }
        blocks[i].kind = .table(table)
    }

    /// 마지막 본문 행 삭제(맨 아래) — 헤더는 보호하고 본문 1행은 남긴다(레거시 deleteTableRow 미러).
    /// 지웠으면 true(삭제 토스트 표시용). +행이 맨 아래에 붙이므로 −행도 맨 아래에서 뺀다(대칭).
    @discardableResult
    func deleteTableRow(_ id: UUID) -> Bool {
        guard let i = index(of: id), case .table(var table) = blocks[i].kind else { return false }
        // rows[0]=헤더. 본문(rows[1...])이 2행 이상일 때만 마지막 본문 행을 뺀다.
        guard table.rows.count >= 3 else { return false }
        table.rows.removeLast()
        blocks[i].kind = .table(table)
        return true
    }

    /// 마지막 열 삭제(맨 오른쪽) — 마지막 한 열은 보호한다(레거시 deleteTableColumn 미러).
    /// 지웠으면 true. +열이 맨 오른쪽에 붙으므로 −열도 맨 오른쪽에서 뺀다(대칭).
    @discardableResult
    func deleteTableColumn(_ id: UUID) -> Bool {
        guard let i = index(of: id), case .table(var table) = blocks[i].kind else { return false }
        guard table.columnCount >= 2 else { return false }
        let last = table.columnCount - 1
        for r in table.rows.indices where last < table.rows[r].count {
            table.rows[r].remove(at: last)
        }
        if last < table.alignments.count { table.alignments.remove(at: last) }
        blocks[i].kind = .table(table)
        return true
    }

    // MARK: 이어 쓰기 포커스 — 캔버스 빈 곳 탭 / 포커스 없는 툴바 조작의 도착지

    /// 문서 끝에서 이어 쓰도록 포커스를 놓는다. 마지막 블록이 문단·제목·인용·리스트면 그 끝으로,
    /// 코드·비텍스트(구분선·이미지·표)로 끝나면 빈 문단을 하나 붙여 그리로 — 코드 블록은 "아래를
    /// 탭해 이어 쓰기"의 도착지로 어색하다(코드 안에 이어 쓰는 게 아니라 다음 문단을 원한다).
    /// 캔버스 빈 영역 탭과, 포커스 없이 눌린 서식 버튼이 이 포커스를 쓴다.
    @discardableResult
    func focusTail() -> EditorFocus {
        if let last = blocks.last, !last.isNonText, !isCodeKind(last.kind) {
            let f = EditorFocus(blockID: last.id, caret: last.text.count)
            focus = f
            return f
        }
        let p = EditorBlock.paragraph("")
        blocks.append(p)
        let f = EditorFocus(blockID: p.id, caret: 0)
        focus = f
        return f
    }

    private func isCodeKind(_ kind: EditorBlockKind) -> Bool {
        if case .code = kind { return true }
        return false
    }

    // MARK: 블록 종류 전환 (줄머리 마크다운 지름길)

    /// 줄머리 지름길을 블록 종류 전환으로 승격 — 뷰가 `> `·`# `·```` 를 감지해 부른다.
    /// text 는 마커를 뗀 나머지. 전환 후 caret 을 새 text 기준으로 되돌린다.
    func transform(_ id: UUID, to kind: EditorBlockKind, strippedText: String, caret: Int) {
        guard let i = index(of: id) else { return }
        blocks[i].kind = kind
        blocks[i].text = strippedText
        focus = EditorFocus(blockID: id, caret: max(0, min(caret, strippedText.count)))
    }

    // MARK: 서식 툴바 — 블록 종류 토글 / 인라인 마커 감싸기

    /// 포커스 블록의 종류를 `kind`로 토글한다 — 이미 그 종류면 문단으로 되돌린다(누르면 켜고 다시 누르면 끔).
    /// 텍스트는 보존하고 캐럿만 유지. 비텍스트 블록(구분선·이미지·표)엔 무동작. 리스트는 ordered/indent 비교로 토글.
    /// 포커스가 없으면 문서 끝을 잡아 거기에 적용한다 — 캔버스를 탭하기 전에 누른 서식 버튼이
    /// 조용히 죽는 대신 "끝에서 이어 쓰기"로 응답한다(포커스·키보드도 함께 선다).
    func toggleFocusedBlockKind(_ kind: EditorBlockKind) {
        if focus == nil { focusTail() }
        guard let f = focus, let i = index(of: f.blockID) else { return }
        if blocks[i].isNonText { return }
        let current = blocks[i].kind
        let next: EditorBlockKind = Self.sameToggleKind(current, kind) ? .paragraph : kind
        blocks[i].kind = next
        focus = EditorFocus(blockID: f.blockID, caret: min(f.caret, blocks[i].text.count))
    }

    /// 제목 버튼 하나가 크기를 순환한다 — 문단 → `#`(1) → `##`(2) → `###`(3) → 문단. 누를수록
    /// 작아지고 끝에서 본문으로 돌아온다(구 에디터 cycleHeading 과 같은 순서라 근육기억이 이어진다).
    /// 인용·리스트 등 다른 텍스트 블록에서 눌리면 제목 1 부터 시작. 그 외 규칙(텍스트·캐럿 보존,
    /// 비텍스트 무동작, 무포커스 = 끝에서 이어 쓰기)은 toggleFocusedBlockKind 와 같다.
    func cycleFocusedHeading() {
        if focus == nil { focusTail() }
        guard let f = focus, let i = index(of: f.blockID) else { return }
        if blocks[i].isNonText { return }
        let next: EditorBlockKind
        if case .heading(let level) = blocks[i].kind {
            next = level >= 3 ? .paragraph : .heading(level: level + 1)
        } else {
            next = .heading(level: 1)
        }
        blocks[i].kind = next
        focus = EditorFocus(blockID: f.blockID, caret: min(f.caret, blocks[i].text.count))
    }

    /// 토글 비교 — 같은 "버튼"이 가리키는 종류인가. 리스트는 ordered 만 보고(indent 무관), 코드는 언어 무관, 제목은 레벨까지.
    private static func sameToggleKind(_ a: EditorBlockKind, _ b: EditorBlockKind) -> Bool {
        switch (a, b) {
        case (.heading(let la), .heading(let lb)): return la == lb
        case (.quote, .quote): return true
        case (.code, .code): return true
        case (.listItem(let oa, _), .listItem(let ob, _)): return oa == ob
        default: return false
        }
    }

    /// 포커스 블록의 선택 범위를 `marker`로 감싼다(볼드=`**`·이탤릭=`*`·인라인코드=`` ` ``). 선택이 없으면
    /// `marker+marker`를 캐럿 자리에 넣고 그 사이에 캐럿을 둔다. **이미 그 마커로 감싸진 선택이면 벗긴다**
    /// (굵게 다시 누르면 해제 — 재랩·별표 잔존 방지). 감싼/벗긴 뒤엔 내용을 다시 선택 상태로 되돌려
    /// 연속 서식·해제를 잇는다. 왕복: text 에 마크다운 원문을 넣을 뿐.
    func wrapFocusedSelection(with marker: String) {
        if focus == nil { focusTail() }  // 포커스 전에 눌린 버튼도 죽지 않게 — 끝에 빈 마커쌍을 놓고 캐럿을 그 사이에.
        guard let f = focus, let i = index(of: f.blockID), !blocks[i].isNonText else { return }
        let text = blocks[i].text
        let start = clampIndex(f.caret, in: text)
        let end = clampIndex(f.caret + f.selectionLength, in: text)
        let loOff = min(start, end)
        let hiOff = max(start, end)
        let lo = text.index(text.startIndex, offsetBy: loOff)
        let hi = text.index(text.startIndex, offsetBy: hiOff)
        let inner = String(text[lo..<hi])

        let markerLen = marker.count
        // 토글 오프 — 이미 정확히 이 마커로 감싸진 선택이면 마커를 벗긴다.
        // 같은 문자의 더 긴 마커(`*` 로 `**` 을 오탐)를 막으려 경계 바로 안쪽이 같은 문자가 아닌지 확인한다.
        // ① 선택이 마커까지 포함(`[**굵게**]`) ② 선택 밖 양옆이 마커(`**[굵게]**`) 두 경우 모두.
        if inner.count >= 2 * markerLen, inner.hasPrefix(marker), inner.hasSuffix(marker),
           Self.isExactMarker(inner, marker: marker) {
            let stripped = String(inner.dropFirst(markerLen).dropLast(markerLen))
            blocks[i].text = text.replacingCharacters(in: lo..<hi, with: stripped)
            focus = EditorFocus(blockID: f.blockID, caret: loOff, selectionLength: stripped.count)
            suppressRevealOnceBlockID = f.blockID
            return
        }
        let before = text[..<lo]
        let after = text[hi...]
        // 앞뒤 마커가 정확히 이 마커여야 — 벗길 마커 바로 바깥이 같은 문자면 더 긴 마커(`**` 를 `*` 로
        // 오탐)라 벗기지 않는다(예: `**[굵게]**` 에 이탤릭 `*` → 볼드 마커 건드리지 말고 감싸기).
        let markerChar = marker.first
        let outerBefore = before.dropLast(markerLen).last
        let outerAfter = after.dropFirst(markerLen).first
        if loOff >= markerLen, before.hasSuffix(marker), after.hasPrefix(marker),
           outerBefore != markerChar, outerAfter != markerChar {
            // `**[굵게]**` — 선택 앞뒤 마커를 벗기고 선택(내용)은 그대로 유지.
            // 정수 오프셋으로 뒤(after) 마커 먼저, 앞(before) 마커 나중에 지운다(앞을 먼저 지우면 뒤 오프셋이 밀린다).
            let afterMarkerLo = text.index(text.startIndex, offsetBy: hiOff)
            let afterMarkerHi = text.index(text.startIndex, offsetBy: hiOff + markerLen)
            let beforeMarkerLo = text.index(text.startIndex, offsetBy: loOff - markerLen)
            var t = text
            t.removeSubrange(afterMarkerLo..<afterMarkerHi)
            t.removeSubrange(beforeMarkerLo..<lo)
            blocks[i].text = t
            focus = EditorFocus(blockID: f.blockID, caret: loOff - markerLen, selectionLength: inner.count)
            suppressRevealOnceBlockID = f.blockID
            return
        }

        let wrapped = marker + inner + marker
        blocks[i].text = text.replacingCharacters(in: lo..<hi, with: wrapped)
        // 마커 뒤(안쪽 시작)부터 inner 길이만큼 다시 선택 — 무선택이었으면 length 0(마커 사이 캐럿).
        let innerStart = loOff + marker.count
        focus = EditorFocus(blockID: f.blockID, caret: innerStart, selectionLength: inner.count)
        // 감싼 직후엔 선택이 스팬 안이라 반개봉 규칙상 마커가 보인다("굵게 눌렀는데 ** 노출"). 이 1회
        // 렌더만 마커를 숨긴다(B1) — 선택·왕복은 그대로, 다음 캐럿 이동/타이핑엔 정상 반개봉 복귀.
        suppressRevealOnceBlockID = f.blockID
    }

    /// `wrapped` 가 `marker` 로 **정확히** 감싸졌는가 — 같은 문자의 더 긴 마커 오탐 방지.
    /// 예: 마커 `*`(이탤릭)로 `**굵게**`(볼드)를 벗기려 하면 경계 안쪽이 또 `*` 라 false → 오작동 차단.
    /// 마커 `**` 로 `***x***` 도 안쪽이 `*` 라 false. 마커 문자와 다른 종류(`~`·`` ` ``)엔 영향 없음.
    private static func isExactMarker(_ wrapped: String, marker: String) -> Bool {
        guard let markerChar = marker.first else { return false }
        let chars = Array(wrapped)
        let m = marker.count
        guard chars.count >= 2 * m + 1 else { return false } // 안쪽 내용이 최소 1자
        // 여는 마커 바로 뒤·닫는 마커 바로 앞 문자가 마커 문자와 같으면 더 긴 마커의 일부.
        return chars[m] != markerChar && chars[chars.count - 1 - m] != markerChar
    }

    /// 특정 포커스(블록·선택)의 선택을 `[선택](url)` 링크로 감싼다. 선택이 없으면 `[라벨](url)`를 넣고
    /// 라벨 자리에 캐럿을 둔다. `at` 을 명시하는 이유: 링크 URL 을 알럿(UIAlertController)으로 받으면
    /// 그 알럿이 텍스트뷰의 first responder 를 뺏어 선택이 접히므로(document.focus.selectionLength=0),
    /// 알럿을 열기 **전에** 잡아둔 포커스를 넘겨 원래 선택을 감싼다. 성공하면 true(호출자가 폴백 판단).
    @discardableResult
    func linkSelection(at target: EditorFocus, url: String, label: String = "") -> Bool {
        guard let i = index(of: target.blockID), !blocks[i].isNonText else { return false }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return false }
        let text = blocks[i].text
        let start = clampIndex(target.caret, in: text)
        let end = clampIndex(target.caret + target.selectionLength, in: text)
        let lo = text.index(text.startIndex, offsetBy: min(start, end))
        let hi = text.index(text.startIndex, offsetBy: max(start, end))
        let selected = String(text[lo..<hi])
        let labelText = selected.isEmpty ? label.trimmingCharacters(in: .whitespacesAndNewlines) : selected
        let replacement = "[\(labelText)](\(trimmedURL))"
        blocks[i].text = text.replacingCharacters(in: lo..<hi, with: replacement)
        // 라벨을 선택 상태로 되돌린다(`[` 다음부터 labelText 길이). 라벨이 비면 그 자리에 캐럿.
        let labelStart = min(start, end) + 1
        focus = EditorFocus(blockID: target.blockID, caret: labelStart, selectionLength: labelText.count)
        return true
    }

    /// 현재 포커스의 선택을 링크로 감싼다(선택 손실 우려 없는 즉시 호출용 — 알럿 경유는 linkSelection(at:) 사용).
    @discardableResult
    func linkFocusedSelection(url: String, label: String = "") -> Bool {
        guard let f = focus else { return false }
        return linkSelection(at: f, url: url, label: label)
    }

    /// String 인덱스 거리를 0…count 로 클램프.
    private func clampIndex(_ n: Int, in text: String) -> Int {
        max(0, min(n, text.count))
    }

    // MARK: 삽입 · 삭제

    func insertBlock(_ block: EditorBlock, after id: UUID) {
        guard let i = index(of: id) else { blocks.append(block); return }
        blocks.insert(block, at: i + 1)
        focus = EditorFocus(blockID: block.id, caret: 0)
    }

    func deleteBlock(_ id: UUID) {
        guard blocks.count > 1, let i = index(of: id) else { return }
        blocks.remove(at: i)
        let target = blocks[max(0, i - 1)]
        focus = EditorFocus(blockID: target.id, caret: target.text.count)
    }

    /// 블록 하나를 지우고 되돌리기 재료(지운 블록·바로 앞 블록 id)를 돌려준다 — 삭제 토스트 undo 용.
    /// 앞이 없으면(맨 앞) afterId=nil. 문서에 블록이 하나뿐이면 지우지 않는다(nil).
    func removeBlock(_ id: UUID) -> (block: EditorBlock, afterId: UUID?)? {
        guard blocks.count > 1, let i = index(of: id) else { return nil }
        let removed = blocks[i]
        let afterId = i > 0 ? blocks[i - 1].id : nil
        blocks.remove(at: i)
        let target = blocks[max(0, i - 1)]
        focus = EditorFocus(blockID: target.id, caret: target.text.count)
        return (removed, afterId)
    }

    /// removeBlock 으로 지운 블록을 원래 자리에 되돌린다(삭제 토스트 undo).
    func restoreBlock(_ block: EditorBlock, afterId: UUID?) {
        if let afterId, let i = index(of: afterId) {
            blocks.insert(block, at: i + 1)
        } else {
            blocks.insert(block, at: 0)
        }
        focus = EditorFocus(blockID: block.id, caret: 0)
    }
}
