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
        // 로딩→완료(→실패)가 뚝 바뀌지 않고 부드럽게 교차 페이드된다 — 첫 화면(스플래시)의 결을
        // StateView 를 쓰는 모든 면에 한 번에 입힌다. opacity 크로스페이드는 reduce-motion 에서도
        // 안전한 표현(슬라이드/스케일과 달리).
        ZStack {
            switch state {
            case .idle, .loading:
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .transition(.opacity)
            case .loaded(let value):
                content(value)
                    .transition(.opacity)
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
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: phase)
    }

    /// 페이즈 키 — 같은 값 안의 변화(예: loaded 값 갱신)엔 재페이드하지 않고, 로딩↔완료↔실패
    /// 전환에서만 크로스페이드한다.
    private var phase: Int {
        switch state {
        case .idle, .loading: return 0
        case .loaded: return 1
        case .failed: return 2
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
            // 섹션 마커 = 구조 신호일 뿐 — 초록은 주액션·데이터 전용이라 중립(잉크)으로 가라앉힌다.
            // 25곳 섹션 머릿글에서 초록이 한꺼번에 빠져 "초록 과용"의 큰 몫이 정리된다(§10 색 규율).
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.hairlineStrong)
                .frame(width: 3, height: 12 * unit)
            Text(text)
                .typeScale(.eyebrow)
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

// MARK: 절제된 태그 — 회색 캡슐 없이 글자만(§10). 종이 위에 #태그가 그대로 앉는다.

struct MutedChip: View {
    let text: String

    var body: some View {
        Text(text)
            .typeScale(.meta)
            .foregroundStyle(Palette.secondary)
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
    /// 선택적 동작(예: 실행취소) — 있으면 토스트에 버튼이 뜨고 조금 더 오래 떠 있는다.
    private(set) var actionLabel: String?
    private var action: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
        // 시각 전용 채널이면 낙관 토글 실패를 VoiceOver 가 영영 모른다 — 같은 문장을 낭독으로.
        AccessibilityNotification.Announcement(message).post()
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(actionLabel == nil ? 2.4 : 4.5))
            guard !Task.isCancelled else { return }
            self.clear()
        }
    }

    func runAction() {
        action?()
        clear()
    }

    /// 사용자가 다시 입력을 시작하면 '실행취소' 류 동작 토스트는 거둔다 — 그 사이 친 글자를
    /// undo 가 엉뚱하게 되돌리지 않게(동작 없는 평범한 토스트는 그대로 둔다).
    func dismissActionToast() {
        guard actionLabel != nil else { return }
        dismissTask?.cancel()
        clear()
    }

    private func clear() {
        message = nil
        actionLabel = nil
        action = nil
    }
}

/// 루트(탭바 위)에 한 번만 부착한다.
struct ToastHost: ViewModifier {
    private var center: ToastCenter { .shared }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 유리 캡슐의 한 줄 — 13pt 를 바닥으로 시스템 글자 크기 설정을 따른다(고정 크기 우회 종식).
    @ScaledMetric(relativeTo: .footnote) private var textSize: CGFloat = 13

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = center.message {
                HStack(spacing: 14) {
                    Text(message)
                        .font(.system(size: textSize, weight: .medium))
                        .foregroundStyle(.primary)
                    if let label = center.actionLabel {
                        Button(label) { center.runAction() }
                            .font(.system(size: textSize, weight: .semibold))
                            .foregroundStyle(Palette.link)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 74)
                // 동작 버튼이 있을 때만 탭을 받는다(평소 토스트는 통과시켜 밑을 가리지 않음).
                .allowsHitTesting(center.actionLabel != nil)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: center.message)
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
            // 발견 미리보기의 내 좋아요 표식과 어긋나지 않게 함께 반영(멱등 켜기).
            LikeStore.shared.set(username: item.author.username, slug: item.slug, on: true)
        }
    }

    static func bookmark(_ item: FeedItem) {
        let target = !BookmarkStore.shared.contains(item.id)
        perform(
            failure: String(localized: "북마크를 반영하지 못했습니다"),
            done: target
                ? String(localized: "북마크에 추가했습니다")
                : String(localized: "북마크를 해제했습니다")
        ) {
            _ = try await InteractionsAPI.setBookmark(postId: item.id, on: target)
            BookmarkStore.shared.set(
                username: item.author.username, slug: item.slug, id: item.id, on: target)
            // 북마크 = 오프라인 보장 — 카드에서 켜면 기기 사본을 따라 받고, 끄면 정리한다.
            if target {
                await OfflineStore.shared.download(username: item.author.username, slug: item.slug)
            } else {
                OfflineStore.shared.remove(username: item.author.username, slug: item.slug)
            }
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
    /// browse 카드 공용 — 길게 누르면 열지 않고 좋아요·북마크·연결·작가·공유.
    func cardQuickActions(_ item: FeedItem) -> some View {
        modifier(CardQuickActionsModifier(item: item))
    }
}

/// 카드 롱프레스 퀵액션. "컬렉션에 연결"이 시트를 띄워야 해 @State 를 들 수 있는 modifier 로.
/// 연결은 다른 사람 글·내 글 어디서든 — 피드에서 글을 열지 않고 그 자리에서 잇는다(§0).
private struct CardQuickActionsModifier: ViewModifier {
    let item: FeedItem
    @State private var showConnect = false

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: Text("좋아요")) { CardQuickActions.like(item) }
            .accessibilityAction(named: Text("북마크")) { CardQuickActions.bookmark(item) }
            .accessibilityAction(named: Text("컬렉션에 연결")) {
                if AuthStore.shared.isSignedIn { showConnect = true }
            }
            .contextMenu {
                Button {
                    CardQuickActions.like(item)
                } label: {
                    Label("좋아요", systemImage: "heart")
                }
                Button {
                    CardQuickActions.bookmark(item)
                } label: {
                    let on = BookmarkStore.shared.contains(item.id)
                    Label(on ? "북마크 해제" : "북마크", systemImage: on ? "bookmark.slash" : "bookmark")
                }
                if AuthStore.shared.isSignedIn {
                    Button {
                        showConnect = true
                    } label: {
                        Label("컬렉션에 연결", systemImage: "rectangle.stack.badge.plus")
                    }
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
            .sheet(isPresented: $showConnect) {
                ConnectSheet(
                    targetKind: "글", targetTitle: item.title,
                    blockType: .post, refId: item.id)
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
