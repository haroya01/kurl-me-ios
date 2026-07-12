//
//  LibraryWidget.swift
//  kurlWidget
//

import SwiftUI
import WidgetKit

/// 앱의 LibrarySnapshot 과 같은 JSON 을 읽는 위젯 쪽 미러 — App Group defaults 의 키·필드명이
/// 계약이다(앱 쪽 kurl/Core/LibrarySnapshot.swift 와 짝, 한쪽 바꾸면 같이).
/// 위젯은 네트워크·Keychain 을 만지지 않는다: 앱이 남긴 서재 스냅샷만 그린다.
struct LibrarySnapshot: Codable {
    struct Item: Codable, Hashable {
        let username: String
        let title: String
        let slug: String
        let savedAt: Date
    }

    let items: [Item]
    let totalCount: Int
    let updatedAt: Date

    static let appGroupId = "group.focustime.kurl"
    private static let key = "library-snapshot"

    static func load() -> LibrarySnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
    }

    /// placeholder / 미리보기용 — 갤러리에선 redacted 로 뜨니 문장 자체는 자리만 잡는다.
    static let sample = LibrarySnapshot(
        items: [
            Item(username: "sunwoo",
                 title: "느리게 읽는 법 — 속독을 버리고 얻은 것",
                 slug: "slow-reading", savedAt: Date().addingTimeInterval(-3600)),
            Item(username: "hana",
                 title: "작은 블로그가 오래 사랑받는 이유",
                 slug: "small-and-loved", savedAt: Date().addingTimeInterval(-3 * 86_400)),
            Item(username: "minjae",
                 title: "밑줄 그은 문장으로 남는 책",
                 slug: "underlines", savedAt: Date().addingTimeInterval(-8 * 86_400)),
        ],
        totalCount: 12,
        updatedAt: Date())
}

struct LibraryEntry: TimelineEntry {
    let date: Date
    let snapshot: LibrarySnapshot?
    /// 작은 위젯의 "한 장"이 가리키는 항목 — 타임라인이 하루 동안 이 값을 조용히 돌린다.
    let featuredIndex: Int
}

struct LibraryProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibraryEntry {
        LibraryEntry(date: .now, snapshot: .sample, featuredIndex: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (LibraryEntry) -> Void) {
        completion(LibraryEntry(date: .now, snapshot: LibrarySnapshot.load() ?? .sample, featuredIndex: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryEntry>) -> Void) {
        let snapshot = LibrarySnapshot.load()
        guard let snapshot, !snapshot.items.isEmpty else {
            // 비었으면 안내 한 장만 — 앱이 북마크를 남기면 다음 갱신에 채워진다.
            let entry = LibraryEntry(date: .now, snapshot: snapshot, featuredIndex: 0)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
            return
        }
        // 작은 위젯의 "한 장"이 하루 동안 서재를 조용히 돈다 — 전부 로컬, 네트워크 0.
        let rotate = min(snapshot.items.count, 8)
        let step: TimeInterval = 3 * 3600
        let now = Date()
        let entries = (0 ..< max(rotate, 1)).map { index in
            LibraryEntry(
                date: now.addingTimeInterval(Double(index) * step),
                snapshot: snapshot,
                featuredIndex: index % snapshot.items.count)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Double(rotate) * step))))
    }
}

struct LibraryWidget: Widget {
    let kind = "LibraryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LibraryProvider()) { entry in
            LibraryWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("서재")
        .description("북마크한 글이 홈 화면에 한 장씩.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LibraryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LibraryEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.items.isEmpty {
            switch family {
            case .systemMedium: shelf(snapshot)
            default: one(snapshot)
            }
        } else {
            empty
        }
    }

    /// 종이 언어의 눈썹 — 그린 한 가닥 + 라벨(분석 위젯과 같은 가족 문법).
    private var header: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(WidgetPalette.accent)
                .frame(width: 3, height: 10)
            Text("서재")
                .widgetType(.caption, weight: .bold)
                .foregroundStyle(WidgetPalette.secondary)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            VStack(alignment: .leading, spacing: 2) {
                Text("글을 북마크하면")
                Text("여기 한 장씩 꽂혀요.")
            }
            .widgetType(.footnote)
            .foregroundStyle(WidgetPalette.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 작은 위젯 — "한 장". 회전 인덱스가 가리키는 저장글 하나를 종이처럼 조용히.
    private func one(_ snapshot: LibrarySnapshot) -> some View {
        let item = snapshot.items[min(entry.featuredIndex, snapshot.items.count - 1)]
        return VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .widgetType(.headline, weight: .semibold)
                    .tracking(-0.3)
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                Text(verbatim: "@\(item.username)")
                    .widgetType(.footnote)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if snapshot.totalCount > 1 {
                Text("\(snapshot.totalCount)편 보관")
                    .widgetType(.caption, weight: .medium)
                    .foregroundStyle(WidgetPalette.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 중간 위젯 — "선반". 최근 저장 순 세 줄, hairline 으로 묶어 한 목록(서재 화면과 리듬을 맞춘다).
    /// 한 줄 = 제목(늘어나며 잘림) + 작가 — 세 줄이 162pt 안에 앉게 단행으로.
    private func shelf(_ snapshot: LibrarySnapshot) -> some View {
        let rows = Array(snapshot.items.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                header
                Spacer(minLength: 4)
                Text("\(snapshot.totalCount)편 보관")
                    .widgetType(.caption, weight: .medium)
                    .foregroundStyle(WidgetPalette.secondary.opacity(0.7))
            }
            Spacer(minLength: 8)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(WidgetPalette.hairline)
                            .frame(height: 1)
                    }
                    shelfRow(item)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shelfRow(_ item: LibrarySnapshot.Item) -> some View {
        HStack(spacing: 8) {
            Text(item.title)
                .widgetType(.rowTitle, weight: .semibold)
                .tracking(-0.2)
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "@\(item.username)")
                .widgetType(.footnote)
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
    }
}
