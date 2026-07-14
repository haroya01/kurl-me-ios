//
//  PostAnalyticsView.swift
//  kurl
//

import SwiftUI

/// 글 하나의 분석(facet) — "이 글이 어디서 얼마나 읽혔나"에 들어가는 화면.
/// 개요와 같은 문법: 기간 칩 + 윈도우 히어로 + 일별 추이 + 수명 합계. 글 보기로 탈출구.
struct PostAnalyticsView: View {
    let post: TopPostView

    @State private var phase: LoadState<PostAnalyticsDetail> = .idle
    @State private var days = 30
    /// 기간 칩 연타 경쟁 가드 — 요청 시점 세대를 캡처해 늦게 도착한 옛 기간 응답을 버린다.
    @State private var loadGeneration = 0
    /// 독자 분석(고유·유입·국가·기기) — 기간과 무관한 전체. 실패해도 화면은 산다.
    @State private var readStats: PostReadStats?

    // 분석 화면 고유 크기들 — 사다리에 딱 맞는 롤이 없어 크기를 보존하되 Dynamic Type 는 얹는다.
    @ScaledMetric(relativeTo: .title2) private var postTitleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .largeTitle) private var bigStatSize: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var linkSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var sectionTitleSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var countSize: CGFloat = 13
    @ScaledMetric(relativeTo: .title3) private var statValueSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var chipLabelSize: CGFloat = 12

    var body: some View {
        ReadingColumn(spacing: 0) {
            Text(post.title)
                .font(.system(size: postTitleSize, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            switch phase {
            case .idle, .loading:
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            case .failed:
                ContentUnavailableView {
                    Label("분석을 불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("잠시 후 다시 시도해 주세요.")
                } actions: {
                    Button("다시 시도") { Task { await load() } }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 40)
            case .loaded(let detail):
                content(detail)
            }
        }
        .navigationTitle("글 분석")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ detail: PostAnalyticsDetail) -> some View {
        HStack(alignment: .center) {
            RailHeading("최근 \(detail.windowDays)일")
            Spacer()
            GlassEffectContainer(spacing: 0) {  // 0 = 닿을 때만 — 칩이 서로 녹아 붙지 않게
                HStack(spacing: 8) {
                    ForEach([7, 30, 90], id: \.self) { option in
                        Button {
                            changeWindow(option)
                        } label: {
                            Text("\(option)일")
                                .font(.system(
                                    size: chipLabelSize, weight: days == option ? .semibold : .regular))
                                .foregroundStyle(
                                    days == option
                                        ? AnyShapeStyle(Color(uiColor: .systemBackground))
                                        : AnyShapeStyle(.secondary))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .selectorPill(selected: days == option)
                    }
                }
            }
        }
        .padding(.top, 22)

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(detail.windowViews.formatted())
                .font(.system(size: bigStatSize, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text("조회")
                .typeScale(.body)
                .foregroundStyle(Palette.secondary)
        }
        .padding(.top, 6)

        // 윈도우 보조지표 — 아이콘 군집 대신 담백한 한 줄(§10 절제, 개요·목록과 한 결).
        MetaLine([
            String(localized: "팔로우 +\(detail.windowFollows)"),
            String(localized: "링크 클릭 \(detail.windowLinkClicks)"),
        ])
            .padding(.top, 4)

        if !detail.daily.isEmpty {
            DailyTrendChart(points: detail.daily)
        }

        Hairline().padding(.top, 22)
        HStack(spacing: 0) {
            stat("누적 조회", detail.lifetimeViews)
            stat("좋아요", detail.lifetimeLikes)
            stat("팔로우", detail.lifetimeFollows)
            stat("링크 클릭", detail.lifetimeLinkClicks)
        }
        .padding(.vertical, 16)
        Hairline()

        // 글 합계 링크 클릭이 어느 링크에서 나왔는지 — 링크가 있을 때만.
        if !detail.linkBreakdown.isEmpty {
            linkBreakdownSection(detail.linkBreakdown)
        }

        if let readStats { readersSection(readStats) }

        // 분석에서 글로 — 막다른 길 금지.
        if let username = AuthStore.shared.me?.username, !username.isEmpty {
            NavigationLink(value: Route.post(username: username, slug: detail.slug)) {
                HStack(spacing: 6) {
                    Text("글 보기")
                        .font(.system(size: linkSize, weight: .medium))
                        .foregroundStyle(Palette.link)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.link)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        Color.clear.frame(height: 32)
    }

    /// 글 안 링크별 클릭 — 합계가 어느 kurl 링크에서 나왔는지(클릭 내림차순). 짧은 코드가
    /// 링크의 정체성이라 mono 로 앞에 두고, 목적지 호스트를 담백한 보조 줄로 둔다(웹 글 분석 parity).
    @ViewBuilder
    private func linkBreakdownSection(_ links: [PostLinkClick]) -> some View {
        RailHeading("링크별 클릭")
            .padding(.top, 24)
            .padding(.bottom, 6)
        ForEach(links) { link in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "kurl.me/\(link.shortCode)")
                        .font(.system(size: linkSize, design: .monospaced))
                        .foregroundStyle(Palette.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: destinationHost(link.destinationUrl))
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Text(verbatim: link.clicks.formatted())
                    .font(.system(size: countSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
            }
            .padding(.vertical, 10)
            // 짧은 코드·목적지·클릭 수가 한 요소로 읽히게 — 세 Text 를 합친다.
            .accessibilityElement(children: .combine)
        }
        Hairline()
    }

    /// 목적지 URL 에서 표시용 호스트만 — www. 는 떼고, 파싱 실패 시 원문 그대로.
    private func destinationHost(_ raw: String) -> String {
        guard let host = URL(string: raw)?.host, !host.isEmpty else { return raw }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// 독자 분석 — 웹과 같은 PostReadStats. 고유 방문 헤드라인 + 유입 채널·국가·기기 막대.
    @ViewBuilder
    private func readersSection(_ stats: PostReadStats) -> some View {
        RailHeading("독자")
            .padding(.top, 24)
            .padding(.bottom, 10)
        HStack(spacing: 0) {
            stat("고유 방문", stats.uniqueVisits)
            stat("사람", stats.humanVisits)
            stat("봇", stats.botVisits)
        }
        .padding(.bottom, 4)

        breakdown("유입 채널", stats.sourceChannelVisits.map { (sourceLabel($0.source), $0.count) })
        breakdown("국가", stats.countryVisits.map { ($0.country.uppercased(), $0.count) })
        breakdown("기기", stats.deviceVisits.map { (deviceLabel($0.device), $0.count) })
    }

    /// 막대 목록 — 상위 5개를 비율 막대로(유입 경로와 같은 문법). 비면 그리지 않는다.
    @ViewBuilder
    private func breakdown(_ title: LocalizedStringKey, _ items: [(label: String, count: Int64)]) -> some View {
        if !items.isEmpty {
            let top = Array(items.prefix(5))
            let maxCount = top.map(\.count).max() ?? 1
            Text(title)
                .font(.system(size: sectionTitleSize, weight: .semibold))
                .foregroundStyle(Palette.heading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(Array(top.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Text(item.label)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.body)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.accent.opacity(0.25))
                            .frame(
                                width: max(2, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)),
                                height: 8)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    Text("\(item.count)")
                        .font(.system(size: countSize).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .frame(height: 26)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(item.label) \(item.count)"))
            }
        }
    }

    private func sourceLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "direct": String(localized: "직접")
        case "social": String(localized: "소셜")
        case "search": String(localized: "검색")
        case "referral": String(localized: "추천")
        case "internal": String(localized: "내부")
        case "newsletter": String(localized: "뉴스레터")
        default: raw
        }
    }

    private func deviceLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "mobile": String(localized: "모바일")
        case "desktop": String(localized: "데스크톱")
        case "tablet": String(localized: "태블릿")
        default: raw
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: Int64) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted())
                .font(.system(size: statValueSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func changeWindow(_ newDays: Int) {
        guard newDays != days else { return }
        days = newDays
        Task { await load() }
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        if case .idle = phase { phase = .loading }
        // 독자 분석은 기간과 무관 — 한 번만 가져온다(윈도우 칩 전환마다 재요청 금지).
        let statsReq: Task<PostReadStats, Error>? =
            readStats == nil ? Task { try await AnalyticsAPI.readStats(postId: post.postId) } : nil
        do {
            let detail = try await AnalyticsAPI.postAnalytics(postId: post.postId, days: days)
            guard generation == loadGeneration else { return }
            phase = .loaded(detail)
        } catch {
            guard generation == loadGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
        if let statsReq { readStats = try? await statsReq.value }
    }
}
