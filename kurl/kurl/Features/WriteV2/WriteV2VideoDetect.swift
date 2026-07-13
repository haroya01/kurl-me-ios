//
//  WriteV2VideoDetect.swift
//  kurl — WriteV2
//
//  "이 URL 이 발행 시 동영상 플레이어로 접히는가"의 판정 — 삽입 툴바의 통합 링크(신고 11)가
//  동영상 주소를 단독 URL 문단(임베드)으로 넣을지, 평범한 `[라벨](url)` 로 넣을지를 가른다.
//  발행면 BlockRenderer 의 YouTubeRef/VimeoRef(둘 다 private)와 **같은 규칙**을 미러한다 —
//  여기서 동영상이라 판정한 URL 은 발행면에서도 반드시 플레이어가 되어야(불일치 시 사용자가
//  "동영상 넣었는데 링크로 뜬다"). 규칙이 갈리면 이 파일과 BlockRenderer 를 같이 고친다.
//

import Foundation

enum WriteV2VideoDetect {
    /// YouTube·Vimeo 동영상 URL 인가(발행 시 InlineVideoEmbed 로 렌더될 것). 그 외는 false.
    static func isVideoURL(_ raw: String) -> Bool {
        youTubeID(raw) != nil || vimeoID(raw) != nil
    }

    /// 유튜브 URL → 영상 id. watch?v= · youtu.be/ · /embed/ · /shorts/ · /v/ (BlockRenderer.YouTubeRef 미러).
    private static func youTubeID(_ raw: String) -> String? {
        guard let comps = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              let host = comps.host?.lowercased() else { return nil }
        if host.contains("youtu.be") {
            let seg = comps.path.split(separator: "/").first.map(String.init)
            return (seg?.isEmpty == false) ? seg : nil
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

    /// vimeo.com/{숫자} (BlockRenderer.VimeoRef 미러).
    private static func vimeoID(_ raw: String) -> String? {
        guard let comps = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              comps.host?.lowercased().contains("vimeo.com") == true else { return nil }
        let seg = comps.path.split(separator: "/").first.map(String.init)
        return seg.flatMap { $0.allSatisfy(\.isNumber) ? $0 : nil }
    }
}
