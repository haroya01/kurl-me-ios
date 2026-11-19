import SwiftUI

@MainActor
@Observable
final class TopicsModel {
    private(set) var topics: [Topic] = []
    private(set) var settled = false
    private(set) var failed = false
    private var loading = false
    private let limit: Int
    private let load: (Int) async throws -> [Topic]

    init(limit: Int, load: @escaping (Int) async throws -> [Topic] = FederationAPI.topics) {
        self.limit = limit
        self.load = load
    }

    func loadIfNeeded() async {
        guard !settled else { return }
        await reload()
    }

    func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            topics = try await load(limit)
            failed = false
        } catch {
            if error.isCancellation { return }
            failed = topics.isEmpty
        }
        settled = true
    }
}

struct TopicRow: View {
    static let rankColumn: CGFloat = 22
    static let rankGap: CGFloat = 8

    let row: TopicBoard.Row
    @ScaledMetric(relativeTo: .caption) private var rankWidth = TopicRow.rankColumn

    var body: some View {
        NavigationLink(value: row.topic.route) {
            HStack(alignment: .firstTextBaseline, spacing: Self.rankGap) {
                Text(verbatim: "\(row.rank)")
                    .typeScale(.meta)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
                    .frame(width: rankWidth, alignment: .leading)
                TopicRowText(topic: row.topic)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityIdentifier("topic.\(row.topic.id)")
    }
}

private struct TopicRowText: View {
    let topic: Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let meta = topic.meta() {
                Text(verbatim: meta)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Text(verbatim: topic.title)
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(topic.people)명이 이야기 중")
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
    }
}

struct TopicRows: View {
    let board: TopicBoard

    var body: some View {
        ForEach(board.own) { row in
            TopicRow(row: row)
                .rowDivider(row.id != board.own.first?.id)
        }
        if board.headsOthers {
            RailHeading("다른 언어")
                .padding(.top, 18)
                .padding(.bottom, 2)
        }
        ForEach(board.others) { row in
            TopicRow(row: row)
                .rowDivider(row.id != board.others.first?.id)
        }
    }
}

struct TopicSection: View {
    let board: TopicBoard
    @ScaledMetric(relativeTo: .caption) private var rankWidth = TopicRow.rankColumn

    var body: some View {
        if !board.isEmpty {
            RailHeading("지금 도는 이야기")
                .padding(.top, 14)
                .padding(.bottom, 2)
            TopicRows(board: board)
            if board.hasMore { more }
        }
    }

    private var more: some View {
        NavigationLink(value: Route.topics) {
            HStack(spacing: 3) {
                Text("더 보기")
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .typeScale(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.secondary)
            .padding(.leading, rankWidth + TopicRow.rankGap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .rowDivider(true)
        .accessibilityIdentifier("topic.more")
    }
}

struct TopicListView: View {
    @State private var model = TopicsModel(limit: FederationAPI.topicListLimit)

    var body: some View {
        ReadingColumn(spacing: 0, background: Palette.readingBg, gutter: Metrics.noteGutter) {
            if !model.settled {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if model.failed {
                ErrorState(retry: { Task { await model.reload() } })
                    .padding(.top, 24)
            } else if model.topics.isEmpty {
                FeedPlaceholder(
                    title: "지금 도는 이야기가 없어요",
                    actionTitle: "다시 시도",
                    action: { Task { await model.reload() } }
                )
                .padding(.top, 24)
            } else {
                TopicRows(board: TopicBoard(model.topics))
            }
        }
        .reservesTabBarSpace()
        .navigationTitle("지금 도는 이야기")
        .navigationBarTitleDisplayMode(.inline)
        .brandRefreshable { await model.reload() }
        .task { await model.loadIfNeeded() }
    }
}
