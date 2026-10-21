//
//  RemoteStream.swift
//  kurl
//

import SwiftUI

extension RemoteStreamFeed {
    var label: LocalizedStringKey {
        switch self {
        case .trending: "인기"
        case .latest: "최신"
        }
    }
}

@MainActor
@Observable
final class RemoteStreamModel {
    let feed: RemoteStreamFeed
    private(set) var items: [RemoteStreamItem] = []
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var isLoadingMore = false
    private(set) var next: String?
    private var epoch = 0
    private let load: (RemoteStreamFeed, String?) async throws -> RemoteStreamPage

    init(
        feed: RemoteStreamFeed,
        load: @escaping (RemoteStreamFeed, String?) async throws -> RemoteStreamPage = FederationAPI.stream
    ) {
        self.feed = feed
        self.load = load
    }

    var reachedEnd: Bool {
        if case .loaded = phase { return next == nil }
        return false
    }

    var firstKeptID: String? {
        items.first { if case .kept = $0 { true } else { false } }?.id
    }

    func loadIfNeeded() async {
        if case .idle = phase { await reload() }
    }

    func reload() async {
        epoch += 1
        let myEpoch = epoch
        if items.isEmpty { phase = .loading }
        do {
            let first = try await load(feed, nil)
            guard myEpoch == epoch else { return }
            items = Self.unique(first.items)
            next = first.next
            phase = .loaded(true)
        } catch {
            guard myEpoch == epoch, !Task.isCancelled else { return }
            if items.isEmpty {
                phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            } else {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
        }
    }

    func loadMoreIfNeeded(current item: RemoteStreamItem) async {
        guard let cursor = next, !isLoadingMore, items.suffix(5).contains(where: { $0.id == item.id }) else { return }
        isLoadingMore = true
        let myEpoch = epoch
        await Task {
            defer { isLoadingMore = false }
            guard let page = try? await load(feed, cursor), myEpoch == epoch else { return }
            next = page.next
            let seen = Set(items.map(\.id))
            items.append(contentsOf: Self.unique(page.items).filter { !seen.contains($0.id) })
        }.value
    }

    func replaced(_ note: Note) {
        guard let index = items.firstIndex(where: {
            if case .kept(let kept) = $0 { kept.id == note.id } else { false }
        }) else { return }
        items[index] = .kept(note)
    }

    func removed(_ id: Int64) {
        items.removeAll { if case .kept(let note) = $0 { note.id == id } else { false } }
    }

    static func unique(_ items: [RemoteStreamItem]) -> [RemoteStreamItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

struct RemoteStreamRows: View {
    let model: RemoteStreamModel
    var gutter: CGFloat = Metrics.gutter
    @State private var showLogin = false

    var body: some View {
        switch model.phase {
        case .idle, .loading:
            NoteSkeleton()
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await model.reload() } })
                .padding(.top, 24)
        case .loaded:
            if model.items.isEmpty {
                FeedPlaceholder(
                    title: model.feed == .trending ? "아직 받은 다른 서버 노트가 없어요" : "아직 다른 서버 최신 노트가 없어요",
                    actionTitle: "다시 시도",
                    action: { Task { await model.reload() } }
                )
                .padding(.top, 24)
            }
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .task { await model.loadMoreIfNeeded(current: item) }
                if index < model.items.count - 1 { Hairline().padding(.horizontal, -gutter) }
            }
            if model.isLoadingMore {
                KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            if model.reachedEnd, model.feed == .trending, !model.items.isEmpty, !AuthStore.shared.isSignedIn {
                Hairline().padding(.horizontal, -gutter)
                FeedPlaceholder(
                    title: "로그인하면 이 서버가 받은 마스토돈 같은 다른 서버의 공개 노트를 볼 수 있어요.",
                    actionTitle: "로그인",
                    action: { showLogin = true }
                )
                .padding(.vertical, 24)
                .loginPrompt(isPresented: $showLogin, message: "다른 서버의 노트를 보려면 로그인하세요")
            }
        }
    }

    @ViewBuilder
    private func row(_ item: RemoteStreamItem) -> some View {
        switch item {
        case .trending(let note):
            TrendingNoteRow(item: note, showsContext: model.feed == .trending)
        case .kept(let note):
            VStack(alignment: .leading, spacing: 0) {
                if item.id == model.firstKeptID {
                    RailHeading("받은 노트")
                        .padding(.top, 20)
                }
                NoteFeedItem(
                    note: note,
                    onChange: { model.replaced($0) },
                    onDelete: { model.removed($0) })
            }
        }
    }
}
