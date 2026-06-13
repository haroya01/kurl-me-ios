//
//  Components.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SafariServices
import SwiftUI

// MARK: 인앱 사파리 (미리보기 등 — 앱 밖으로 내쫓지 않는다)

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Palette.accent)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: 로딩/에러/빈 상태

enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

/// 콜드 로딩의 브랜드 박자 — 스플래시의 3-bar draw-in 을 잔잔히 되감는다.
/// 풀스크린 첫 로드 전용(페이지네이션 푸터 스피너는 그대로 — 절제).
/// reduce-motion 은 정지 마크.
struct KurlLoadingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = [false, false, false]

    var body: some View {
        KurlMark(drawn: reduceMotion ? [true, true, true] : drawn)
            .frame(width: 34, height: 21)
            .opacity(0.9)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    for i in 0..<3 {
                        withAnimation(.easeOut(duration: 0.24)) { drawn[i] = true }
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                    try? await Task.sleep(for: .milliseconds(620))
                    withAnimation(.easeIn(duration: 0.18)) { drawn = [false, false, false] }
                    try? await Task.sleep(for: .milliseconds(280))
                }
            }
            .accessibilityLabel(Text("불러오는 중"))
    }
}

struct StateView<Value, Content: View>: View {
    let state: LoadState<Value>
    var retry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            KurlLoadingMark()
                .frame(maxWidth: .infinity, minHeight: 280)
        case .loaded(let value):
            content(value)
        case .failed(let message):
            ContentUnavailableView {
                Label(String(localized: "불러오지 못했습니다"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                if let retry {
                    Button(String(localized: "다시 시도"), action: retry)
                        .foregroundStyle(Palette.accent)
                }
            }
        }
    }
}

// MARK: 읽기 컬럼 (정중앙 max-w-2xl)

struct ReadingColumn<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        // 콘텐츠가 유리 크롬 밑으로 흐를 때의 가장자리 — soft 가 기본 정책(AGENTS.md §1).
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Palette.pageBg)
    }
}

// MARK: 섹션 라벨 — RailHeading (그린 마커 + 13px bold)

struct RailHeading: View {
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .footnote) private var unit: CGFloat = 1
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.accentMarker)
                .frame(width: 3, height: 12 * unit)
            Text(text)
                .font(.system(size: 13 * unit, weight: .bold))
                .foregroundStyle(Palette.heading)
        }
        // 섹션 제목 — VoiceOver 헤딩 로터로 화면을 점프할 수 있어야 한다(25곳 일괄).
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: 1px hairline (slate-100)

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

// MARK: 절제된 칩 (slate, 초록 캡슐 금지)

struct MutedChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.chipText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Palette.chipBg, in: Capsule())
    }
}

// MARK: 작가 아바타

struct AvatarView: View {
    let author: Author
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let urlString = author.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // 사진과 배경 사이 경계 한 가닥 — 밝은 사진이 흰 종이에 번져 보이지 않게.
        .overlay(Circle().strokeBorder(Palette.hairlineStrong.opacity(0.5), lineWidth: 0.5))
    }

    private var initials: some View {
        Circle()
            .fill(Palette.chipBg)
            .overlay(
                Text(author.username.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            )
    }
}
// MARK: 상대 시간

extension Date {
    var relativeShort: String {
        // 1분 미만은 "0초 후" 같은 미래형 라운딩이 나온다 — 방금 전으로 바닥을 깐다.
        if abs(timeIntervalSinceNow) < 60 {
            return String(localized: "방금 전")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var mediumDate: String {
        formatted(.dateTime.year().month(.abbreviated).day())
    }
}

// MARK: 토스트 — 낙관 토글 실패의 조용한 한 줄

/// 낙관 토글(좋아요·팔로우·구독…)이 실패해 원상복귀할 때 한 줄로 알린다.
/// alert 만큼 무겁지 않게 — 하단 캡슐 하나가 잠시 떴다 사라진다.
@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()
    private(set) var message: String?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String) {
        self.message = message
        // 시각 전용 채널이면 낙관 토글 실패를 VoiceOver 가 영영 모른다 — 같은 문장을 낭독으로.
        AccessibilityNotification.Announcement(message).post()
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
}

/// 루트(탭바 위)에 한 번만 부착한다.
struct ToastHost: ViewModifier {
    private var center: ToastCenter { .shared }

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = center.message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 74)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: center.message)
    }
}

// MARK: 카드 길게 누르기 — 열지 않고도 하트·북마크

/// 카드 컨텍스트 메뉴의 빠른 행동. 토글이 아니라 멱등 "켜기"다 — 카드에는 내 상태가
/// 없으므로(목록 응답에 likedByMe 없음) 끄기를 약속할 수 없다. 이미 켜져 있었으면 무해.
@MainActor
enum CardQuickActions {
    static func like(_ item: FeedItem) {
        perform(
            failure: String(localized: "좋아요를 반영하지 못했습니다"),
            done: String(localized: "좋아요했습니다")
        ) {
            _ = try await InteractionsAPI.setLike(postId: item.id, on: true)
        }
    }

    static func bookmark(_ item: FeedItem) {
        perform(
            failure: String(localized: "북마크를 반영하지 못했습니다"),
            done: String(localized: "북마크에 추가했습니다")
        ) {
            _ = try await InteractionsAPI.setBookmark(postId: item.id, on: true)
            // 북마크 = 오프라인 보장 — 카드에서 켜도 기기 사본을 따라 받는다.
            await OfflineStore.shared.download(username: item.author.username, slug: item.slug)
        }
    }

    static func shareURL(_ item: FeedItem) -> URL? {
        URL(
            string:
                "\(Config.apiBase)/\(Config.preferredLanguageTag)/p/\(item.author.username)/\(item.slug)"
        )
    }

    private static func perform(
        failure: String, done: String, _ action: @escaping () async throws -> Void
    ) {
        guard AuthStore.shared.isSignedIn else {
            ToastCenter.shared.show(String(localized: "로그인이 필요합니다"))
            return
        }
        Task {
            do {
                try await action()
                ToastCenter.shared.show(done)
            } catch {
                ToastCenter.shared.show(failure)
            }
        }
    }
}

extension View {
    /// browse 카드 공용 — 길게 누르면 열지 않고 좋아요·북마크·작가·공유.
    func cardQuickActions(_ item: FeedItem) -> some View {
        contextMenu {
            Button {
                CardQuickActions.like(item)
            } label: {
                Label("좋아요", systemImage: "heart")
            }
            Button {
                CardQuickActions.bookmark(item)
            } label: {
                Label("북마크", systemImage: "bookmark")
            }
            NavigationLink(value: Route.author(username: item.author.username)) {
                Label("작가 블로그", systemImage: "person.crop.circle")
            }
            if let url = CardQuickActions.shareURL(item) {
                ShareLink(item: url) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

// MARK: 히트 영역 확장 (44pt 터치 타깃)

extension View {
    /// 시각 크기는 그대로 두고 탭 영역만 넓힌다 — 버튼 *라벨* 안쪽에 부착할 것.
    /// (패딩으로 contentShape 를 키운 뒤 음수 패딩으로 레이아웃만 되돌린다.)
    func expandTapTarget(_ inset: CGFloat = 12) -> some View {
        padding(inset)
            .contentShape(Rectangle())
            .padding(-inset)
    }
}

// MARK: 전환 모션 (§10.7 — 조용하지만 살아 있게)

/// 카드 → 글 상세 zoom 전환의 출발점. 피드처럼 같은 글이 숨은 페이지에도 떠 있는 표면은
/// active 가 아닐 때 등록하지 않는다(같은 네임스페이스에 중복 id 등록 방지).
struct ZoomSource: ViewModifier {
    let active: Bool
    let id: String
    let ns: Namespace.ID

    func body(content: Content) -> some View {
        if active {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}

/// 첫 화면 카드들이 한 장씩 조용히 떠오르는 입장(§10.7 — 과시 없는 생기).
/// 스태거는 첫 8장까지만 — 그 아래는 스크롤로 만나므로 지연 없이 나타난다.
/// reduce-motion 이면 정지 상태로 그려진다.
struct QuietAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 7)
            .onAppear {
                guard !shown else { return }
                guard index < 8 else {
                    shown = true
                    return
                }
                withAnimation(.easeOut(duration: 0.32).delay(Double(index) * 0.04)) {
                    shown = true
                }
            }
    }
}

/// 스크롤 가장자리에서 카드가 살짝 가라앉았다 떠오르는 입장감. reduce-motion 이면 끈다.
struct CardScrollFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var axis: Axis = .vertical

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if axis == .horizontal {
            content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.45)
                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
            }
        } else {
            content.scrollTransition(.interactive) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.65)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
            }
        }
    }
}
