import Foundation

extension HomeFeedItem {
    var roomId: Int64? {
        switch kind {
        case .note(let note): note.room?.id
        case .post(let post): post.room?.id
        case .remote: nil
        }
    }

    var room: NoteRoom? {
        switch kind {
        case .note(let note): note.room
        case .post(let post): post.room
        case .remote: nil
        }
    }
}

@MainActor
@Observable
final class RoomItemsModel {
    enum Source: Equatable {
        case room(Int64)
        case all
    }

    private(set) var items: [HomeFeedItem] = []
    private(set) var phase: LoadState<Bool> = .idle
    private var next: String?
    private var loadingMore = false
    private var epoch = 0
    private let source: Source

    init(_ source: Source) {
        self.source = source
    }

    var newestNoteId: Int64? {
        items.compactMap { $0.note?.id }.max()
    }

    func reload() async {
        epoch += 1
        let mine = epoch
        if items.isEmpty { phase = .loading }
        do {
            let batch = try await load(nil)
            guard mine == epoch else { return }
            items = batch.items
            next = batch.next
            phase = .loaded(true)
        } catch {
            guard mine == epoch else { return }
            if items.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    func loadMoreIfNeeded(current item: HomeFeedItem) async {
        guard let next, !loadingMore, items.suffix(5).contains(where: { $0.id == item.id }) else { return }
        loadingMore = true
        let mine = epoch
        await Task {
            defer { loadingMore = false }
            guard let batch = try? await load(next), mine == epoch else { return }
            let known = Set(items.map(\.id))
            items += batch.items.filter { !known.contains($0.id) }
            self.next = batch.next
        }.value
    }

    func inserted(_ note: Note) {
        items.insert(HomeFeedItem(kind: .note(note)), at: 0)
    }

    func replaced(_ note: Note) {
        if let at = items.firstIndex(where: { $0.note?.id == note.id }) { items[at] = HomeFeedItem(kind: .note(note)) }
    }

    func removed(_ id: Int64) {
        items.removeAll { $0.note?.id == id }
    }

    private func load(_ cursor: String?) async throws -> HomeFeedBatch {
        switch source {
        case .room(let id): try await RoomAPI.items(room: id, cursor: cursor)
        case .all: try await RoomAPI.allItems(cursor: cursor)
        }
    }
}
