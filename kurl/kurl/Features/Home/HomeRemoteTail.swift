import SwiftUI

struct HomeRemoteTail<Fallback: View>: View {
    let model: RemoteStreamModel
    let follows: Int
    @ViewBuilder var fallback: Fallback

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                if follows > 0 {
                    KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                } else {
                    NoteSkeleton()
                }
            case .failed:
                if follows > 0 { retry } else { fallback }
            case .loaded:
                if model.items.isEmpty {
                    if follows == 0 { fallback }
                } else {
                    rows
                }
            }
        }
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var rows: some View {
        if follows > 0 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
        RailHeading("다른 서버 최신")
            .padding(.top, 20)
            .accessibilityIdentifier("home.remoteTail")
        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
            RemoteStreamRow(item: item, model: model, headsKept: false)
                .modifier(QuietAppear(index: follows + index))
                .task { await model.loadMoreIfNeeded(current: item) }
            if index < model.items.count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
        }
        if model.isLoadingMore {
            KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
        }
    }

    private var retry: some View {
        Button {
            Task { await model.reload() }
        } label: {
            Text("더 불러오지 못했어요. 다시 시도")
                .typeScale(.meta)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
