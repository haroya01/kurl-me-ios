//
//  AnalyticsWidget.swift
//  kurlWidget
//

import SwiftUI
import WidgetKit

struct AnalyticsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct AnalyticsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AnalyticsEntry {
        AnalyticsEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (AnalyticsEntry) -> Void) {
        completion(AnalyticsEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnalyticsEntry>) -> Void) {
        // 데이터는 앱이 분석 화면을 열 때 갱신된다 — 위젯은 시간마다 다시 그리기만.
        let entry = AnalyticsEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct AnalyticsWidget: Widget {
    let kind = "AnalyticsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AnalyticsProvider()) { entry in
            AnalyticsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("블로그 분석")
        .description("최근 조회수와 누적 지표를 홈 화면에서.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular,
        ])
    }
}

/// 브랜드 그린 — 위젯 타깃엔 앱 Palette 가 없어 최소한만 미러링.
private enum WidgetPalette {
    static let accent = Color(red: 0x05 / 255.0, green: 0x96 / 255.0, blue: 0x69 / 255.0)
    static let ink = Color.primary
    static let secondary = Color.secondary
}

struct AnalyticsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AnalyticsEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemMedium: medium(snapshot)
            case .accessoryCircular: circular(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            default: small(snapshot)
            }
        } else if family == .accessoryCircular || family == .accessoryRectangular {
            // 잠금화면엔 긴 안내문이 안 선다 — 마크 한 점으로만.
            Text(verbatim: "kurl")
                .font(.system(size: 12, weight: .bold))
        } else {
            empty
        }
    }

    /// 잠금화면 원형 — 윈도우 조회수 한 숫자.
    private func circular(_ s: WidgetSnapshot) -> some View {
        VStack(spacing: 0) {
            Text(s.windowViews.formatted())
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("조회")
                .font(.system(size: 9, weight: .medium))
        }
    }

    /// 잠금화면 사각 — 헤더 + 숫자 + 미니 추이.
    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("최근 \(s.windowDays)일 조회")
                .font(.system(size: 11, weight: .semibold))
            Text(s.windowViews.formatted())
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .lineLimit(1)
            bars(s.dailyViews)
                .frame(height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text("앱에서 분석을 한 번 열면\n여기에 지표가 떠요.")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(WidgetPalette.accent)
                .frame(width: 3, height: 10)
            Text("kurl 분석")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WidgetPalette.secondary)
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text(s.windowViews.formatted())
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundStyle(WidgetPalette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("최근 \(s.windowDays)일 조회")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.secondary)
            bars(s.dailyViews)
                .frame(height: 22)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                Text(s.windowViews.formatted())
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(WidgetPalette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("최근 \(s.windowDays)일 조회")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetPalette.secondary)
                bars(s.dailyViews)
                    .frame(height: 22)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                stat("발행한 글", s.publishedPosts)
                stat("누적 조회", s.lifetimeViews)
                stat("좋아요", s.lifetimeLikes)
                stat("팔로워", s.lifetimeFollows)
            }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: Int64) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.secondary)
            Spacer(minLength: 4)
            Text(value.formatted())
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(WidgetPalette.ink)
        }
        .frame(width: 118)
    }

    /// 미니 막대 추이 — 데이터가 비면 그리지 않는다.
    @ViewBuilder
    private func bars(_ values: [Int64]) -> some View {
        if !values.isEmpty {
            let peak = max(values.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(WidgetPalette.accent.opacity(0.7))
                        .frame(height: max(2, 22 * CGFloat(v) / CGFloat(peak)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
