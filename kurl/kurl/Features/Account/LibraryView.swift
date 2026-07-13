//
//  LibraryView.swift
//  kurl
//

import SwiftUI

/// 서재 — 내가 모은 것(북마크·좋아요·구독·하이라이트·컬렉션·기록·노트)을 한 목록으로.
/// 내 계정(= 내 블로그) 화면의 오른쪽 헤더 버튼으로 들어온다.
struct LibraryView: View {
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                libraryRow("북마크") { BookmarksView() }
                Hairline()
                libraryRow("좋아요한 글") { LikedPostsView() }
                Hairline()
                libraryRow("구독한 시리즈") { SubscribedSeriesView() }
                Hairline()
                libraryRow("구독한 태그") { SubscribedTagsView() }
                Hairline()
                libraryRow("내 하이라이트") { MyHighlightsView() }
                Hairline()
                libraryRow("컬렉션") { CollectionsListView() }
                Hairline()
                libraryRow("읽기 기록") { MyReadingHistoryView() }
                Hairline()
                libraryRow("노트") { NotesPage(active: true) }
            }
            .padding(.top, 8)
        }
        .navigationTitle("서재")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 서재 행 — 아이콘 없이 라벨 타이포로, 셰브론은 흐린 한 점의 어포던스로만. Hairline 로 묶어 한 목록.
    private func libraryRow(
        _ title: LocalizedStringKey, @ViewBuilder destination: @escaping () -> some View
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16 * unit))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12 * metaUnit, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}
