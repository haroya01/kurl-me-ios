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

struct AnalyticsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AnalyticsEntry

    var body: some View {
        Group {
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
                    .widgetType(.caption, weight: .bold)
            } else {
                empty
            }
        }
        // 탭하면 앱의 분석 분면으로 바로 — 위젯 URL 은 스킴 등록 없이 자기 앱 onOpenURL 로 간다.
        .widgetURL(URL(string: "kurlwidget://analytics"))
    }

    /// 잠금화면 원형 — 윈도우 조회수 한 숫자.
    private func circular(_ s: WidgetSnapshot) -> some View {
        VStack(spacing: 0) {
            Text(s.windowViews.formatted())
                .widgetType(.headline, weight: .bold, monospacedDigit: true)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("조회")
                .widgetType(.micro, weight: .medium)
        }
    }

    /// 잠금화면 사각 — 헤더 + 숫자 + 미니 추이.
    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("최근 \(s.windowDays)일 조회")
                .widgetType(.caption, weight: .semibold)
            Text(s.windowViews.formatted())
                .widgetType(.headline, weight: .bold, monospacedDigit: true)
                .lineLimit(1)
            bars(s.dailyViews)
                .frame(height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text("앱을 열면 여기에\n최근 지표가 떠요.")
                .widgetType(.footnote)
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
                .widgetType(.caption, weight: .bold)
                .foregroundStyle(WidgetPalette.secondary)
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text(s.windowViews.formatted())
                .widgetType(.figure, weight: .bold, monospacedDigit: true)
                .foregroundStyle(WidgetPalette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("최근 \(s.windowDays)일 조회")
                .widgetType(.caption)
                .foregroundStyle(WidgetPalette.secondary)
            trend(s.dailyViews, height: 26)
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
                    .widgetType(.figure, weight: .bold, monospacedDigit: true)
                    .foregroundStyle(WidgetPalette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("최근 \(s.windowDays)일 조회")
                    .widgetType(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                trend(s.dailyViews, height: 24)
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
                .widgetType(.caption)
                .foregroundStyle(WidgetPalette.secondary)
            Spacer(minLength: 4)
            Text(value.formatted())
                .widgetType(.metricSmall, weight: .semibold, monospacedDigit: true)
                .foregroundStyle(WidgetPalette.ink)
        }
        .frame(width: 118)
    }

    /// 미니 막대 추이 — 잠금화면 사각 전용(그 크기에선 막대가 곡선보다 읽힌다).
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

    /// 부드러운 조회 곡선 + 옅은 면 — 앱 분석 화면의 시그니처(곡선·그린 그라데이션)를 위젯
    /// 크기로 압축한다. 홈 위젯(소·중형)의 추이는 전부 이 곡선으로, 막대는 잠금화면만.
    @ViewBuilder
    private func trend(_ values: [Int64], height: CGFloat) -> some View {
        if values.count > 1 {
            ZStack {
                TrendCurve(values: values, closed: true)
                    .fill(
                        LinearGradient(
                            colors: [
                                WidgetPalette.accent.opacity(0.26),
                                WidgetPalette.accent.opacity(0.03),
                            ],
                            startPoint: .top, endPoint: .bottom))
                TrendCurve(values: values, closed: false)
                    .stroke(
                        WidgetPalette.accent,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(height: height)
        }
    }
}

/// 일별 조회를 중점 보간(quad)으로 잇는 곡선 — closed 면 바닥까지 닫아 면 채움용 경로가 된다.
private struct TrendCurve: Shape {
    let values: [Int64]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let peak = CGFloat(max(values.max() ?? 1, 1))
        let stepX = rect.width / CGFloat(values.count - 1)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.minX + CGFloat(index) * stepX,
                y: rect.maxY - rect.height * CGFloat(value) / peak)
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let prev = points[index - 1]
            let mid = CGPoint(x: (prev.x + points[index].x) / 2, y: (prev.y + points[index].y) / 2)
            path.addQuadCurve(to: mid, control: prev)
        }
        path.addLine(to: points[points.count - 1])
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
