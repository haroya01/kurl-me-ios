import SwiftUI

struct LoadMoreTail: View {
    var loading: Bool
    var failed: Bool
    var padding: CGFloat = 14
    let retry: () -> Void

    var body: some View {
        if failed {
            HStack(spacing: 12) {
                Text("더 불러오지 못했어요")
                    .typeScale(.body)
                    .foregroundStyle(Palette.secondary)
                Button(action: retry) {
                    Text("다시 시도")
                        .typeScale(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .expandTapTarget(12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("loadMore.retry")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, padding)
        } else if loading {
            KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, padding)
        }
    }
}
