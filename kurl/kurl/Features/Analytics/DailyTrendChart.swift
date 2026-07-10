//
//  DailyTrendChart.swift
//  kurl
//

import Accessibility
import Charts
import SwiftUI

/// 일별 조회 추이 — 작가 분석·글 분석이 공유한다. 30/90일을 막대 수십 개 + 빽빽한 날짜
/// 라벨로 그리던 것을, 부드러운 영역+선(브랜드 그린 그라데이션)으로. 날짜 축은 자동 sparse
/// (≈4틱)라 7·30·90일 어디서도 라벨이 겹치지 않는다. 본문을 스크럽하면 그날의 값이 뜬다(살아 있는 절제).
struct DailyTrendChart: View {
    let points: [AuthorAnalyticsOverview.DailyPoint]
    /// 접근성·오디오 그래프에 쓰는 지표 이름(기본 "조회"). 구독자 추이면 "구독자".
    let metricName: String

    // 스크럽 말풍선 라벨 — 사다리 밖 소형 크기라 보존하되 Dynamic Type 는 얹는다.
    // (차트 축 라벨은 레이아웃을 이루는 고정 소형이라 스케일 제외.)
    @ScaledMetric(relativeTo: .caption2) private var scrubDateSize: CGFloat = 10
    @ScaledMetric(relativeTo: .subheadline) private var scrubValueSize: CGFloat = 13

    /// day 파싱을 마친 점. tuple 대신 Equatable 구조체라 onChange(of: data) 비교가 재할당 없이 된다.
    private struct ChartPoint: Equatable {
        let date: Date
        let views: Int64
    }

    // 스크럽 중 chartXSelection 이 매 프레임 body 를 다시 돌리는데, day 는 DateFormatter
    // 파싱이라 computed 로 두면 프레임당 창 크기(최대 90일)×접근 횟수만큼 재파싱한다 — init 에서 한 번만.
    private let data: [ChartPoint]

    @State private var selectedDate: Date?

    init(points: [AuthorAnalyticsOverview.DailyPoint], metricName: String = String(localized: "조회")) {
        self.points = points
        self.metricName = metricName
        self.data = points.compactMap { p in p.day.map { ChartPoint(date: $0, views: p.views) } }
    }

    private var selected: ChartPoint? {
        guard let selectedDate else { return nil }
        return data.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.date) { pt in
                AreaMark(x: .value("날짜", pt.date), y: .value("조회", pt.views))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Palette.accent.opacity(0.26), Palette.accent.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))

                LineMark(x: .value("날짜", pt.date), y: .value("조회", pt.views))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let selected {
                RuleMark(x: .value("선택", selected.date))
                    .foregroundStyle(Palette.hairlineStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        VStack(spacing: 1) {
                            Text(selected.date, format: .dateTime.month().day())
                                .font(.system(size: scrubDateSize))
                                .foregroundStyle(Palette.secondary)
                            Text("\(selected.views)")
                                .font(.system(size: scrubValueSize, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }

                PointMark(x: .value("날짜", selected.date), y: .value("조회", selected.views))
                    .foregroundStyle(Palette.accent)
                    .symbolSize(64)
            }
        }
        .chartXSelection(value: $selectedDate)
        // 기간(7/30/90일)을 바꾸면 옛 날짜를 가리키던 스크럽 선택이 남아 엉뚱한 값을 띄운다 — 데이터가 갈리면 초기화.
        .onChange(of: data) { selectedDate = nil }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel()
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(height: 150)
        .padding(.top, 14)
        .accessibilityLabel(Text("일별 \(metricName) 추이"))
        // 오디오 그래프 — VoiceOver 로터에서 추이를 소리 높낮이로 훑을 수 있다.
        .accessibilityChartDescriptor(DailyViewsChartDescriptor(points: points, metricName: metricName))
    }
}

/// 일별 조회 차트의 오디오 그래프 서술자 — 시각 추이와 같은 데이터를 소리로.
private struct DailyViewsChartDescriptor: AXChartDescriptorRepresentable {
    let points: [AuthorAnalyticsOverview.DailyPoint]
    let metricName: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "날짜"),
            categoryOrder: points.map(\.date))
        let maxViews = points.map(\.views).max() ?? 0
        let yAxis = AXNumericDataAxisDescriptor(
            title: metricName,
            range: 0...Double(max(maxViews, 1)),
            gridlinePositions: []
        ) { value in
            "\(metricName) \(Int(value))"
        }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "일별 \(metricName)"),
            isContinuous: false,
            dataPoints: points.map {
                AXDataPoint(x: $0.date, y: Double($0.views))
            })
        return AXChartDescriptor(
            title: String(localized: "일별 \(metricName) 추이"),
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series])
    }
}
