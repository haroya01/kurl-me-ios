//
//  DraftPreviewBlocks.swift
//  kurl — WriteV2
//
//  초안(미발행) 네이티브 미리보기의 데이터 다리 — 저장 계약인 마크다운 문자열을 읽기면 렌더러
//  (BlockRenderer 의 BlockView)가 먹는 PostBlock 배열로 옮긴다. 발행하면 서버 md→blocks 가
//  같은 모양을 만드므로, 이 변환은 "발행 전 미리보기가 발행 후 읽기면과 같게" 보이도록 그 규칙을
//  로컬에서 근사한다(정본은 서버지만, 방언·블록 매핑은 WriteV2 파서/직렬화가 이미 안다).
//
//  PostBlock 은 Decodable 전용(멤버 이니셜라이저 없음)이라, kind별 content 를 JSON/문자열로 만들어
//  디코드한다. content 인코딩은 리더의 payload 디코더 계약을 그대로 따른다:
//   • CODE  = {"lang":…, "code":…}     (CodePayload.decode)
//   • IMAGE = {"url":…, "caption":…, "width":…}  (ImagePayload.decode)  ← alt 의 «width» 마커·title 파싱
//   • LIST  = ["item", …]              (BlockView.parseListItems)
//   • TABLE = GFM 원문                  (TableBlockView(markdown:))
//   • EMBED = {"url":…}                (EmbedPayload.decode)            ← 단독 동영상 URL 문단
//   • 나머지(문단·제목·인용) = 인라인 마크다운 원문 그대로.
//
//  왕복 계약과 무관 — 이 변환은 읽기 전용 표시용이고 EditorBlock.text/직렬화는 손대지 않는다.
//

import Foundation

enum DraftPreviewBlocks {
    /// 저장 마크다운 → 읽기면 PostBlock 배열. WriteV2 파서로 블록을 얻고 리더 계약으로 인코딩한다.
    static func from(markdown: String) -> [PostBlock] {
        let editorBlocks = MarkdownBlockParser.parse(markdown)
        var dicts: [[String: Any]] = []
        var order = 0
        func emit(_ type: String, _ content: String?) {
            var dict: [String: Any] = ["type": type, "blockOrder": order]
            if let content { dict["content"] = content }
            dicts.append(dict)
            order += 1
        }

        var i = 0
        while i < editorBlocks.count {
            let block = editorBlocks[i]
            // 연속 리스트 항목은 한 리스트 블록으로 묶는다(리더가 한 덩이로 렌더).
            // content 는 줄바꿈으로 이은 항목들 — 리더 parseListItems 의 "선행 공백=깊이" 경로를 태워
            // 중첩을 보존한다(JSON 배열 경로는 depth 0 으로 평탄화되므로 안 쓴다).
            if let (ordered, _) = block.listInfo {
                var lines: [String] = []
                while i < editorBlocks.count,
                      let info = editorBlocks[i].listInfo, info.ordered == ordered {
                    // 중첩 깊이는 선행 공백 2칸/단계로(lead/2). 항목 텍스트는 마커가 이미 없다.
                    let pad = String(repeating: "  ", count: info.indent)
                    lines.append(pad + editorBlocks[i].text)
                    i += 1
                }
                emit(ordered ? "LIST_NUMBERED" : "LIST_BULLET", lines.joined(separator: "\n"))
                continue
            }
            append(block, emit: emit)
            i += 1
        }
        return decode(dicts)
    }

    // MARK: kind별 매핑 (리스트는 호출부에서 그룹 처리)

    private static func append(_ block: EditorBlock, emit: (String, String?) -> Void) {
        switch block.kind {
        case .paragraph:
            // 단독 동영상 URL 문단은 EMBED 로(발행면과 같게 플레이어). 아니면 문단.
            let trimmed = block.text.trimmingCharacters(in: .whitespaces)
            if WriteV2VideoDetect.isVideoURL(trimmed), let json = jsonString(["url": trimmed]) {
                emit("EMBED", json)
            } else {
                emit("PARAGRAPH", block.text)
            }
        case .heading(let level):
            emit(level == 1 ? "H1" : level == 2 ? "H2" : "H3", block.text)
        case .quote:
            emit("QUOTE", block.text)
        case .code(let language):
            var payload: [String: String] = ["code": block.text]
            if let language, !language.isEmpty { payload["lang"] = language }
            emit("CODE", jsonString(payload))
        case .divider:
            emit("DIVIDER", nil)
        case .image(let url):
            let (width, alt) = parseImageAlt(block.text)
            var payload: [String: String] = ["url": url]
            if let alt, !alt.isEmpty { payload["alt"] = alt }
            if let width { payload["width"] = width }
            emit("IMAGE", jsonString(payload))
        case .table(let table):
            emit("TABLE", MarkdownSerializer.serializeTable(table))
        case .listItem:
            break  // 그룹 처리(호출부)에서 소비.
        }
    }

    /// 이미지 alt 앞머리의 폭 마커(`«wide»`/`«full»`/`«half»`)를 (width, 나머지 alt) 로 가른다.
    /// EditorBlock.image 의 text 는 alt 를 담는다(캡션은 별도 title 이라 파서가 안 실어 여기선 미포함).
    static func parseImageAlt(_ raw: String) -> (width: String?, alt: String?) {
        var rest = raw
        var width: String?
        for w in ["wide", "full", "half"] {
            let marker = "«\(w)»"
            if rest.hasPrefix(marker) {
                width = w
                rest = String(rest.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return (width, rest.isEmpty ? nil : rest)
    }

    // MARK: PostBlock 조립 — 서버 응답과 같은 경로(배열 JSON → Decodable)

    private static func decode(_ dicts: [[String: Any]]) -> [PostBlock] {
        guard let data = try? JSONSerialization.data(withJSONObject: dicts),
              let blocks = try? JSONDecoder().decode([PostBlock].self, from: data)
        else { return [] }
        // 서버 파이프와 동일하게 배열 인덱스를 안정 식별자로 박는다.
        return blocks.enumerated().map { $0.element.withDecodeIndex($0.offset) }
    }

    private static func jsonString(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
