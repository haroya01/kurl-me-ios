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
        guard let i = index(of: id) else { return }
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
        let head = String(block.text[..<cut])
        let tail = String(block.text[cut...])

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
    /// `marker+marker`를 캐럿 자리에 넣고 그 사이에 캐럿을 둔다. 감싼 뒤엔 안쪽 내용을 다시 선택 상태로
    /// 되돌려(연속 서식·해제 편의), 라이브 렌더가 즉시 최종 모습으로 보여준다. 왕복: text 에 마크다운 원문을 넣을 뿐.
    func wrapFocusedSelection(with marker: String) {
        if focus == nil { focusTail() }  // 포커스 전에 눌린 버튼도 죽지 않게 — 끝에 빈 마커쌍을 놓고 캐럿을 그 사이에.
        guard let f = focus, let i = index(of: f.blockID), !blocks[i].isNonText else { return }
        let text = blocks[i].text
        let start = clampIndex(f.caret, in: text)
        let end = clampIndex(f.caret + f.selectionLength, in: text)
        let lo = text.index(text.startIndex, offsetBy: min(start, end))
        let hi = text.index(text.startIndex, offsetBy: max(start, end))
        let inner = String(text[lo..<hi])
        let wrapped = marker + inner + marker
        blocks[i].text = text.replacingCharacters(in: lo..<hi, with: wrapped)
        // 마커 뒤(안쪽 시작)부터 inner 길이만큼 다시 선택 — 무선택이었으면 length 0(마커 사이 캐럿).
        let innerStart = min(start, end) + marker.count
        focus = EditorFocus(blockID: f.blockID, caret: innerStart, selectionLength: inner.count)
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
}
