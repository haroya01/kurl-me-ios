import Foundation

/// 웹 `highlight-clustering.ts`와 같은 규칙. 바꿀 땐 두 곳을 함께 바꾼다.
enum HighlightPaint {
    static let topMinReaders = 2

    private struct Pos: Comparable {
        let block: Int
        let offset: Int

        static func < (a: Pos, b: Pos) -> Bool {
            a.block != b.block ? a.block < b.block : a.offset < b.offset
        }
    }

    private static func start(_ h: HighlightView) -> Pos {
        Pos(block: h.blockOrder ?? -1, offset: h.startOffset ?? 0)
    }

    private static func end(_ h: HighlightView) -> Pos {
        Pos(block: h.endBlockOrder ?? h.blockOrder ?? -1, offset: h.endOffset ?? 0)
    }

    static func clusters(_ highlights: [HighlightView]) -> [[HighlightView]] {
        let sorted = highlights.sorted { a, b in
            let (sa, sb) = (start(a), start(b))
            if sa != sb { return sa < sb }
            return end(a) < end(b)
        }
        var clusters: [[HighlightView]] = []
        var current: [HighlightView] = []
        var currentEnd: Pos?
        for h in sorted {
            if let reach = currentEnd, start(h) < reach {
                current.append(h)
                if reach < end(h) { currentEnd = end(h) }
            } else {
                if !current.isEmpty { clusters.append(current) }
                current = [h]
                currentEnd = end(h)
            }
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    static func hasThread(_ h: HighlightView) -> Bool {
        !(h.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || h.replyCount > 0
    }

    static func isMine(_ h: HighlightView, me: Int64?) -> Bool {
        h.id < 0 || (me != nil && h.author?.id == me)
    }

    static func paintedIds(_ highlights: [HighlightView], me: Int64?) -> Set<Int64> {
        var painted: Set<Int64> = []
        for cluster in clusters(highlights) {
            let others = Set(cluster.compactMap { h -> Int64? in
                guard let id = h.author?.id, id != me else { return nil }
                return id
            })
            let isTop = others.count >= topMinReaders
            for h in cluster where isMine(h, me: me) || hasThread(h) || isTop {
                painted.insert(h.id)
            }
        }
        return painted
    }
}
