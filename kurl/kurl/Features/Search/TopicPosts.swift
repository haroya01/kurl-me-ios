import SwiftUI

@MainActor
@Observable
final class TopicPostsModel {
    let key: TopicKey
    private(set) var topic: Topic?
    private(set) var loaded: [RemoteStreamItem] = []
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    private(set) var next: String?
    private var epoch = 0
    private let load: (TopicKey, String?) async throws -> TopicPostsPage
    private let isVisible: @MainActor (Note) -> Bool
    static let chaseLimit = 3
    static let relatedCap = 3

    init(
        key: TopicKey,
        load: @escaping (TopicKey, String?) async throws -> TopicPostsPage = FederationAPI.topicPosts,
        isVisible: @escaping @MainActor (Note) -> Bool = {
            NoteFilterStore.shared.verdict(for: $0, in: .public) != .hide
        }
    ) {
        self.key = key
        self.load = load
        self.isVisible = isVisible
    }

    var items: [RemoteStreamItem] { loaded.filter(shows) }

    var related: [TopicArticle] {
        Array((topic?.related ?? []).filter { $0.link != nil }.prefix(Self.relatedCap))
    }

    private func shows(_ item: RemoteStreamItem) -> Bool {
        switch item {
        case .trending(let note): isVisible(note.displayNote)
        case .kept(let note): isVisible(note)
        }
    }

    func loadIfNeeded() async {
        if case .idle = phase { await reload() }
    }

    func reload() async {
        epoch += 1
        loadMoreFailed = false
        let myEpoch = epoch
        if loaded.isEmpty { phase = .loading }
        do {
            let first = try await pages(after: nil, epoch: myEpoch)
            guard myEpoch == epoch else { return }
            topic = first.topic
            loaded = RemoteStreamModel.unique(first.items)
            next = first.next
            phase = .loaded(true)
        } catch {
            guard myEpoch == epoch else { return }
            if !loaded.isEmpty {
                if !error.isCancellation { ToastCenter.shared.show(String(localized: "새로고침하지 못했어요")) }
            } else if error.isCancellation {
                phase = .idle
            } else {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    func loadMoreIfNeeded(current item: RemoteStreamItem) async {
        guard !loadMoreFailed, items.suffix(5).contains(where: { $0.id == item.id }) else { return }
        await loadMore()
    }

    func retryLoadMore() async {
        loadMoreFailed = false
        await loadMore()
    }

    private func loadMore() async {
        guard let cursor = next, !isLoadingMore else { return }
        isLoadingMore = true
        let myEpoch = epoch
        await Task {
            defer { isLoadingMore = false }
            do {
                let page = try await pages(after: cursor, epoch: myEpoch)
                guard myEpoch == epoch else { return }
                if let fresh = page.topic { topic = fresh }
                next = page.next
                loaded.append(contentsOf: RemoteStreamModel.unique(page.items, besides: loaded))
            } catch {
                guard myEpoch == epoch, !error.isCancellation else { return }
                loadMoreFailed = true
            }
        }.value
    }

    private func pages(after cursor: String?, epoch myEpoch: Int) async throws -> TopicPostsPage {
        var page = try await load(key, cursor)
        var items = page.items
        var followed = 0
        while !items.contains(where: shows), let next = page.next, followed < Self.chaseLimit, myEpoch == epoch {
            followed += 1
            page = try await load(key, next)
            items += page.items
        }
        return TopicPostsPage(topic: page.topic, items: items, next: page.next)
    }

    func replaced(_ note: Note) {
        guard let index = loaded.firstIndex(where: {
            if case .kept(let kept) = $0 { kept.id == note.id } else { false }
        }) else { return }
        loaded[index] = .kept(note)
    }

    func removed(_ id: Int64) {
        withMotion(Motion.move) {
            loaded.removeAll { if case .kept(let note) = $0 { note.id == id } else { false } }
        }
    }
}

struct TopicPostRows: View {
    let model: TopicPostsModel
    var gutter: CGFloat = Metrics.gutter

    var body: some View {
        let items = model.items
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            row(item)
                .modifier(QuietAppear(index: index))
                .task { await model.loadMoreIfNeeded(current: item) }
            if index < items.count - 1 { Hairline().padding(.horizontal, -gutter) }
        }
        LoadMoreTail(loading: model.isLoadingMore, failed: model.loadMoreFailed) {
            Task { await model.retryLoadMore() }
        }
    }

    @ViewBuilder
    private func row(_ item: RemoteStreamItem) -> some View {
        switch item {
        case .trending(let note):
            TrendingNoteRow(item: note, showsContext: false)
        case .kept(let note):
            NoteFeedItem(
                note: note,
                onChange: { model.replaced($0) },
                onDelete: { model.removed($0) })
        }
    }
}

struct TopicRelatedArticles: View {
    let articles: [TopicArticle]
    var gutter: CGFloat = Metrics.gutter

    var body: some View {
        if !articles.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RailHeading("관련 기사")
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                ForEach(Array(articles.enumerated()), id: \.element.url) { index, article in
                    if let link = article.link {
                        Link(destination: link) { label(article) }
                            .buttonStyle(RowButtonStyle())
                            .rowDivider(index > 0)
                            .accessibilityIdentifier("topic.related.\(index)")
                    }
                }
            }
            Hairline().padding(.horizontal, -gutter)
        }
    }

    private func label(_ article: TopicArticle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: article.shownTitle)
                .typeScale(.note)
                .fontWeight(.medium)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let source = article.source, !source.isEmpty {
                Text(verbatim: source)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
