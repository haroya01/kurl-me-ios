import SwiftUI

enum HomeMix {
    static let run = 5
    static let pair = 2
    static let lowWater = 4
    static let staleAfter: TimeInterval = 30 * 60

    enum Row: Identifiable, Hashable {
        case own(HomeFeedItem)
        case remote(RemoteStreamItem, mixed: Bool)

        var id: String {
            switch self {
            case .own(let item): item.id
            case .remote(let item, _): "remote-\(item.id)"
            }
        }

        var seenKey: String? {
            switch self {
            case .own(let item): item.seenKey
            case .remote(let item, _): item.seenURI
            }
        }
    }

    enum Slot: Hashable {
        case own(String)
        case remote(String)
    }

    static func rows(
        own: [HomeFeedItem], remote: [RemoteStreamItem], ownDone: Bool, top: [Slot]
    ) -> [Row] {
        guard !top.isEmpty else { return rows(own: own, remote: remote, ownDone: ownDone) }
        let ownByID = Dictionary(own.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByKey = Dictionary(remote.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var lifted = Set<Slot>()
        let head: [Row] = top.compactMap { slot in
            guard lifted.insert(slot).inserted else { return nil }
            switch slot {
            case .own(let id): return ownByID[id].map { .own($0) }
            case .remote(let key): return remoteByKey[key].map { .remote($0, mixed: true) }
            }
        }
        let rest = rows(
            own: own.filter { !lifted.contains(.own($0.id)) },
            remote: remote.filter { !lifted.contains(.remote($0.key)) },
            ownDone: ownDone)
        return head + rest
    }

    static func block(own: [HomeFeedItem], remote: [RemoteStreamItem]) -> [Slot] {
        rows(own: own, remote: remote, ownDone: true).map { row in
            switch row {
            case .own(let item): .own(item.id)
            case .remote(let item, _): .remote(item.key)
            }
        }
    }

    static func needsReload(leftAt: Date?, now: Date) -> Bool {
        guard let leftAt else { return false }
        return now.timeIntervalSince(leftAt) >= staleAfter
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
