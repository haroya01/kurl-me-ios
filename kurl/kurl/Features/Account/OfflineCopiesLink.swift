import SwiftUI

struct OfflineCopiesLink: View {
    var body: some View {
        if !OfflineStore.shared.cachedKeys.isEmpty {
            NavigationLink {
                BookmarksView()
            } label: {
                Text("기기에 저장된 글 보기")
                    .typeScale(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                    .expandTapTarget(12)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.offlineCopies")
        }
    }
}
