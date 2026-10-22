import SwiftUI

enum HomeMix {
    static let run = 5
    static let pair = 2
    static let lowWater = 4

    enum Row: Identifiable, Hashable {
        case own(HomeFeedItem)
        case remote(RemoteStreamItem, mixed: Bool)

        var id: String {
            switch self {
            case .own(let item): item.id
            case .remote(let item, _): "remote-\(item.id)"
            }
        }
    }

    static func rows(own: [HomeFeedItem], remote: [RemoteStreamItem], ownDone: Bool) -> [Row] {
        let pool = candidates(own: own, remote: remote)
        var rows: [Row] = []
        var next = 0
        for (index, item) in own.enumerated() {
            rows.append(.own(item))
            guard (index + 1) % run == 0, next < pool.count else { continue }
            let slot = pool[next..<min(next + pair, pool.count)]
            rows += slot.map { .remote($0, mixed: true) }
            next += slot.count
        }
        if ownDone { rows += pool[next...].map { .remote($0, mixed: false) } }
        return rows
    }

    static func unused(own: [HomeFeedItem], remote: [RemoteStreamItem]) -> Int {
        max(0, candidates(own: own, remote: remote).count - own.count / run * pair)
    }

    private static func candidates(own: [HomeFeedItem], remote: [RemoteStreamItem]) -> [RemoteStreamItem] {
        let shown = Set(own.compactMap { $0.note?.id })
        return remote.filter { item in item.keptID.map { !shown.contains($0) } ?? true }
    }
}
