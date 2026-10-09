//
//  SeriesBanner.swift
//  kurl
//

import SwiftUI

/// 글 상단의 시리즈 배너 — 웹 SeriesNav 의 네이티브 번역(그린 좌측 룰 + 진행 스테퍼 +
/// 접이식 회차 목록). 읽기 전에 "이 글이 여정의 몇 번째인지"를 세우는 자리라 본문(종이)
/// 문법을 쓴다 — 유리 금지. 회차 목록은 첫 펼침에만 가져온다(안 펼치면 네트워크 0).
struct SeriesBanner: View {
    let nav: SeriesTrail
    let username: String
    /// 지금 보는 편(목록에서 강조하고 링크를 끊는다) — 글이든 노트든 SeriesEntry.id 로 가린다.
    let currentId: String
    /// 글 회차 전환 — 이전/다음이 글이면 끝에서 당기기와 같은 제자리 교체(가로 슬라이드 금지).
    /// nil 이면(덱 임베드·노트 상세) 글도 푸시로 연다. 노트는 늘 푸시(노트 상세는 다른 화면).
    var goToEpisode: ((String) -> Void)? = nil

    @State private var expanded = false
    @State private var episodes: [SeriesEntry]?
    @State private var loadFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 핵심 읽기면이라 고정 pt 금지 — typeScale 못 쓰는 자리(monospacedDigit·소형 라벨)는 배수로 키운다.
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: Route.series(username: username, slug: nav.slug)) {
                HStack(spacing: 8) {
                    Text(nav.title)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.heading)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: String(format: "%02d / %02d", nav.position, nav.total))
                        .font(.system(size: 12 * metaUnit).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("시리즈 \(nav.title) — \(nav.position)/\(nav.total)")

            // 진행 스테퍼 — 현재 회차까지 채움. 너무 긴 시리즈는 칸이 실이 되니 생략.
            if nav.total <= 24 {
                HStack(spacing: 3) {
                    ForEach(0..<nav.total, id: \.self) { index in
                        Capsule()
                            .fill(index < nav.position ? Palette.accentMarker : Palette.hairlineStrong)
                            .frame(height: 3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 10)
                .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                Button {
                    toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("이 시리즈 목차")
                            .typeScale(.meta)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10 * metaUnit, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .foregroundStyle(expanded ? Palette.link : Palette.secondary)
                    .expandTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? Text("회차 목록 접기") : Text("회차 목록 펼치기"))

                Spacer(minLength: 8)

                // 이전/다음 편 — 글이면 끝에서 당기기와 같은 제자리 교체, 노트면 노트 상세로. 없는 방향은 비활성.
                episodeArrow(systemName: "chevron.left", link: nav.prev, label: String(localized: "이전 편"))
                episodeArrow(systemName: "chevron.right", link: nav.next, label: String(localized: "다음 편"))
            }
            .padding(.top, 10)

            if expanded {
                episodeList
                    .padding(.top, 8)
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.accentMarker)
                .frame(width: 2.5)
        }
    }

    @ViewBuilder
    private var episodeList: some View {
        if let episodes {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    if episode.id == currentId {
                        episodeRow(index: index, episode: episode, current: true)
                    } else {
                        NavigationLink(value: episode.route(username: username)) {
                            episodeRow(index: index, episode: episode, current: false)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
        } else if loadFailed {
            Text("목록을 불러오지 못했습니다")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.vertical, 6)
        } else {
            ProgressView()
                .tint(Palette.accent)
                .padding(.vertical, 6)
        }
    }

    private func episodeRow(index: Int, episode: SeriesEntry, current: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: String(format: "%02d", index + 1))
                .font(.system(size: 11 * metaUnit).monospacedDigit())
                .foregroundStyle(current ? Palette.link : Palette.secondary)
            if case .note = episode {
                SeriesNoteMark(size: 10 * metaUnit, current: current)
            }
            Text(episode.title)
                .font(.system(size: 13 * metaUnit, weight: current ? .semibold : .regular))
                .foregroundStyle(current ? Palette.link : Palette.body)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(episodeLabel(index: index, episode: episode, current: current))
    }

    private func episodeLabel(index: Int, episode: SeriesEntry, current: Bool) -> Text {
        let kind = episode.isNoteEntry ? String(localized: "노트") : String(localized: "글")
        return current
            ? Text("\(index + 1)편 — \(kind) \(episode.title), 현재 편")
            : Text("\(index + 1)편 — \(kind) \(episode.title)")
    }

    /// 배너의 이전/다음 편 원형 버튼 — 글이고 제자리 교체가 있으면 교체, 아니면 그 편으로 푸시. 없으면(끝) 비활성.
    @ViewBuilder
    private func episodeArrow(systemName: String, link: SeriesItemLink?, label: String) -> some View {
        let icon = Image(systemName: systemName)
            .font(.system(size: 13 * metaUnit, weight: .semibold))
            .foregroundStyle(link != nil ? Palette.link : Palette.faint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        if let link, !link.isNote, let slug = link.slug, let go = goToEpisode {
            Button { go(slug) } label: { icon }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(label) — \(link.title)"))
        } else if let link, let route = link.route(username: username) {
            NavigationLink(value: route) { icon }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    link.isNote ? Text("\(label) — 노트 \(link.title)") : Text("\(label) — \(link.title)"))
        } else {
            icon
                .accessibilityLabel(Text("\(label) 없음"))
        }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            expanded.toggle()
        }
        guard expanded, episodes == nil else { return }
        Task {
            do {
                let detail = try await BlogAPI.seriesDetail(username: username, slug: nav.slug)
                episodes = detail.entries
            } catch {
                loadFailed = true
            }
        }
    }
}

/// 글 끝의 시리즈 연결 — 완독 직후가 다음 편으로 넘어가는 자연스러운 순간이라,
/// 상단 배너가 갖지 못한 "이어서 읽기"를 여기 카드 하나에 몰아준다. 마지막 편이면
/// 전체 보기 링크만 남는다(웹 SeriesNext 와 같은 규칙).
struct SeriesNextCard: View {
    let nav: SeriesTrail
    let username: String
    /// 다음 편이 글이면 끝에서 당기기·배너 버튼과 같은 제자리 교체(가로 슬라이드 금지).
    /// nil 이거나 다음 편이 노트면 그 편으로 푸시.
    var goToEpisode: ((String) -> Void)? = nil

    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Hairline()
                .padding(.bottom, 6)

            if let next = nav.next {
                nextEpisodeButton(next)
            }

            NavigationLink(value: Route.series(username: username, slug: nav.slug)) {
                Text("시리즈 전체 보기 (\(nav.total)편)")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .expandTapTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func nextEpisodeButton(_ next: SeriesItemLink) -> some View {
        if !next.isNote, let slug = next.slug, let go = goToEpisode {
            Button { go(slug) } label: { nextEpisodeLabel(next) }
                .buttonStyle(RowButtonStyle())
                .accessibilityLabel("다음 편 — \(next.title)")
        } else if let route = next.route(username: username) {
            NavigationLink(value: route) {
                nextEpisodeLabel(next)
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel(next.isNote ? "다음 편 — 노트 \(next.title)" : "다음 편 — \(next.title)")
        }
    }

    private func nextEpisodeLabel(_ next: SeriesItemLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("다음 편")
                .typeScale(.eyebrow)
                .foregroundStyle(Palette.link)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: String(format: "%02d", nav.position + 1))
                            .font(.system(size: 12 * metaUnit).monospacedDigit())
                            .foregroundStyle(Palette.secondary)
                        if next.isNote {
                            SeriesNoteMark(size: 11 * metaUnit, current: false)
                        }
                    }
                    Text(next.title)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16 * metaUnit, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .stroke(Palette.cardBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
    }
}

/// 시리즈 목차에서 노트 편을 글과 가르는 작은 표식 — 노트 탭과 같은 말풍선에 "노트" 한 마디.
struct SeriesNoteMark: View {
    let size: CGFloat
    let current: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "text.bubble")
                .font(.system(size: size, weight: .semibold))
            Text("노트")
                .font(.system(size: size, weight: .semibold))
        }
        .foregroundStyle(current ? Palette.link : Palette.faint)
        .accessibilityHidden(true)
    }
}
