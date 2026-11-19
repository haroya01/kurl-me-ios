import SwiftUI

/// 다른 서버 글 행은 노트를 가져온 뒤 `openNoteRoute` 로 밀어 연다. Route 목적지를 등록하는 스택은 이것으로 감싼다.
struct RouteStack<Root: View>: View {
    @State private var path = NavigationPath()
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack(path: $path) { root }
            .environment(\.openNoteRoute) { path.append($0) }
    }
}
