import SwiftUI

/// 글 상세의 좋아요·북마크 — 우하단에 떠 있는 유리 독(DESIGN.md §1)과, 본문이 끝난 자리의 줄.
/// 둘은 한 모델을 보고, 줄이 화면에 들어오면 독이 물러나 동시에 보이지 않는다.
/// 댓글 진입은 본문 끝 인라인 한 곳뿐이라 여기는 토글만 든다.
/// 독의 활성 상태는 캡슐 전체가 그린(700) 유리로 차오르고, 토글은 낙관(즉시 반영 →
/// 실패 시 서버 응답/원상태로 복귀). 로그아웃 상태에서 누르면 그 자리 로그인.
struct EngagementDock: View {
    enum Placement { case floating, bodyEnd }

    nonisolated static let floatingBottomGap: CGFloat = 10

    nonisolated static func yieldsToBodyEnd(rowTop: CGFloat, viewport: CGFloat, bottomInset: CGFloat) -> Bool {
        viewport > 0 && rowTop < viewport - bottomInset - floatingBottomGap
    }

    nonisolated static func bodyEndIsBelow(bodyBottom: CGFloat, viewport: CGFloat, bottomInset: CGFloat) -> Bool {
        viewport > 0 && bodyBottom >= viewport - bottomInset - floatingBottomGap
    }

    private let model: EngagementModel
    private let placement: Placement
    @State private var showLoginPrompt = false
    @State private var loginMessage: LocalizedStringKey = "좋아요를 누르려면 로그인하세요"
    @State private var showConnect = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @Namespace private var glassNS

    /// "연결" 시트가 잇는 대상(글 제목·글 id). 없으면 연결 버튼을 감춘다.
    private let connectTarget: (title: String, postId: Int64)?

    init(
        model: EngagementModel, placement: Placement = .floating,
        connectTarget: (title: String, postId: Int64)? = nil
    ) {
        self.model = model
        self.placement = placement
        self.connectTarget = connectTarget
    }

    var body: some View {
        Group {
            switch placement {
            case .floating: floating
            case .bodyEnd: bodyEnd
            }
        }
        .loginPrompt(isPresented: $showLoginPrompt, message: loginMessage) {
            await model.hydrate()
        }
        .sheet(isPresented: $showConnect) {
            if let target = connectTarget {
                ConnectSheet(
                    targetKind: "글", targetTitle: target.title,
                    blockType: .post, refId: target.postId)
            }
        }
    }

    // 햅틱과 내 상태 불러오기는 떠 있는 독 한 곳에서만 — 줄과 독이 함께 마운트돼 있어 양쪽에 달면 두 번 울리고 두 번 요청한다.
    private var floating: some View {
        // spacing 0 — 연결·좋아요·북마크는 성격이 다른 독립 컨트롤이라 서로 녹아 붙으면 안 된다.
        // clusterSpacing(18) 안에선 하트를 누르는 순간 인터랙티브 유리가 부풀어 세 디스크가 한
        // 캡슐로 이어 붙어(누른 버튼이 이웃까지 함께 반응) 버튼 독립성이 깨졌다. 0 = 실제로 닿을
        // 때만 녹인다(작성 도구줄·분석 칩과 같은 규율).
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 12) {
                // 연결 = §0의 핵심 동사. 좋아요·북마크와 나란히 1급 인게이지로 둔다 —
                // 읽다가 그 자리에서 컬렉션에 잇는다(쉽고 명확한 만들기 경로).
                if connectTarget != nil { connect }
                like
                bookmark
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task(id: AuthStore.shared.isSignedIn) { await model.hydrate() }
    }

    private var bodyEnd: some View {
        HStack(spacing: 26) {
            endLike
            Spacer(minLength: 0)
            if connectTarget != nil { endConnect }
            endBookmark
        }
        .animation(reduceMotion ? nil : Motion.move, value: model.likeCount)
    }

    private var endLike: some View {
        Button(action: toggleLike) {
            HStack(spacing: 5) {
                NoteGlyphView(glyph: .heart, active: model.liked, size: Self.rowGlyph * unit)
                    .modifier(GlyphPop(trigger: reduceMotion ? false : model.liked))
                if model.likeCount > 0 {
                    Text("\(model.likeCount)")
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(model.likeCount)))
                }
            }
            .typeScale(.lede)
            .foregroundStyle(model.liked ? Palette.accent : Palette.ink)
            .expandTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("좋아요"))
        .accessibilityValue(Text(model.likeCount > 0 ? "\(model.likeCount)" : ""))
        .accessibilityAddTraits(model.liked ? [.isSelected] : [])
        .accessibilityIdentifier("end.like")
    }

    private var endConnect: some View {
        Button(action: openConnect) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 19 * unit))
                .foregroundStyle(Palette.ink)
                .frame(height: Self.rowGlyph * unit)
                .expandTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("컬렉션에 연결"))
        .accessibilityIdentifier("end.connect")
    }

    private var endBookmark: some View {
        Button(action: toggleBookmark) {
            NoteGlyphView(glyph: .bookmark, active: model.bookmarked, size: Self.rowGlyph * unit)
                .modifier(GlyphPop(trigger: reduceMotion ? false : model.bookmarked))
                .foregroundStyle(model.bookmarked ? Palette.accent : Palette.ink)
                .expandTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("북마크"))
        .accessibilityAddTraits(model.bookmarked ? [.isSelected] : [])
        .accessibilityIdentifier("end.bookmark")
    }

    private static let rowGlyph: CGFloat = 22

    private var connect: some View {
        Button(action: openConnect) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCapsule(prominent: false)
        .glassEffectID("connect", in: glassNS)
        .glassEffectTransition(.materialize)
        .accessibilityLabel(Text("컬렉션에 연결"))
        .accessibilityIdentifier("dock.connect")
    }

    private var like: some View {
        Button(action: toggleLike) {
            VStack(spacing: 3) {
                Image(systemName: model.liked ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolEffect(.bounce, value: reduceMotion ? false : model.liked)
            }
            .foregroundStyle(model.liked ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            // 고정 52 원판 — 카운트가 0→1 로 뜰 때 캡슐이 커지며 독 전체가 밀려 재배치되던
            // "좋아요 시 UI 깨짐"의 원인. 하트+숫자는 이 안에 들어오므로 크기를 고정한다.
            .frame(width: 52, height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(prominent: model.liked)
        .glassEffectID("like", in: glassNS)
        .glassEffectTransition(.materialize)
        .animation(reduceMotion ? nil : Motion.move, value: model.liked)
        .accessibilityLabel(Text("좋아요"))
        .accessibilityIdentifier("dock.like")
        .accessibilityAddTraits(model.liked ? [.isSelected] : [])

    }

    private var bookmark: some View {
        Button(action: toggleBookmark) {
            Image(systemName: model.bookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 16, weight: .semibold))
                .symbolEffect(.bounce, value: reduceMotion ? false : model.bookmarked)
                .foregroundStyle(model.bookmarked ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCapsule(prominent: model.bookmarked)
        .glassEffectID("bookmark", in: glassNS)
        .glassEffectTransition(.materialize)
        .animation(reduceMotion ? nil : Motion.move, value: model.bookmarked)
        .accessibilityLabel(Text("북마크"))
        .accessibilityIdentifier("dock.bookmark")
        .accessibilityAddTraits(model.bookmarked ? [.isSelected] : [])
    }

    private func openConnect() {
        guard AuthStore.shared.isSignedIn else { askLogin("컬렉션에 연결하려면 로그인하세요"); return }
        showConnect = true
    }

    private func toggleLike() {
        interact(failure: String(localized: "좋아요를 반영하지 못했어요"), login: "좋아요를 누르려면 로그인하세요") {
            try await model.toggleLike()
        }
    }

    private func toggleBookmark() {
        interact(failure: String(localized: "북마크를 반영하지 못했어요"), login: "북마크하려면 로그인하세요") {
            try await model.toggleBookmark()
        }
    }

    private func askLogin(_ message: LocalizedStringKey) {
        loginMessage = message
        showLoginPrompt = true
    }

    private func interact(
        failure: String, login: LocalizedStringKey, _ action: @escaping () async throws -> Void
    ) {
        guard AuthStore.shared.isSignedIn else {
            askLogin(login)
            return
        }
        Task {
            do { try await action() } catch { ToastCenter.shared.show(failure) }
        }
    }
}

@MainActor
@Observable
final class EngagementModel {
    private(set) var liked = false
    private(set) var likeCount: Int64
    private(set) var bookmarked = false
    /// 햅틱 트리거 — 서버 hydrate 가 아닌 사용자 토글에만 증가.
    private(set) var userToggleCount = 0

    let postId: Int64
    /// 오프라인 저장 짝지 — 북마크 켜짐=기기 사본 확보, 꺼짐=사본 제거.
    private let offlineRef: (username: String, slug: String)?

    init(postId: Int64, likeCount: Int64, offlineRef: (username: String, slug: String)? = nil) {
        self.postId = postId
        self.likeCount = likeCount
        self.offlineRef = offlineRef
    }

    /// 발견 미리보기는 postId 없이 username/slug 로 여부를 대조한다 — 독의 토글도 ref 로 함께
    /// 반영해 상세에서 담은 글이 미리보기 카드에도 곧바로 채워지게(단일 진실원).
    private func syncBookmarkStore(on: Bool) {
        if let ref = offlineRef {
            BookmarkStore.shared.set(username: ref.username, slug: ref.slug, id: postId, on: on)
        } else {
            BookmarkStore.shared.set(postId, on: on)
        }
    }

    private func syncLikeStore(on: Bool) {
        if let ref = offlineRef {
            LikeStore.shared.set(username: ref.username, slug: ref.slug, on: on)
        }
    }

    /// 로그인 상태일 때만 내 상태(liked/bookmarked)를 서버에서 가져온다.
    /// 응답 적용 전 세대 검사 — 비행 중 사용자가 토글했으면 스테일 스냅샷을 버린다.
    func hydrate() async {
        guard AuthStore.shared.isSignedIn else {
            liked = false
            bookmarked = false
            return
        }
        let gen = userToggleCount
        if let like = try? await InteractionsAPI.likeStatus(postId: postId), gen == userToggleCount {
            liked = like.liked
            likeCount = like.likeCount
            syncLikeStore(on: like.liked)
        }
        if let bookmark = try? await InteractionsAPI.bookmarkStatus(postId: postId),
           gen == userToggleCount {
            bookmarked = bookmark.bookmarked
            syncBookmarkStore(on: bookmark.bookmarked)
        }
    }

    func toggleLike() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !liked
        liked = target
        likeCount += target ? 1 : -1
        syncLikeStore(on: target)
        do {
            let status = try await InteractionsAPI.setLike(postId: postId, on: target)
            // 연타로 더 새 토글이 나갔으면 이 echo 는 스테일 — 버린다.
            guard gen == userToggleCount else { return }
            liked = status.liked
            likeCount = status.likeCount
            syncLikeStore(on: status.liked)
        } catch {
            guard gen == userToggleCount else { return }
            liked = !target
            likeCount += target ? -1 : 1
            syncLikeStore(on: !target)
            throw error
        }
    }

    func toggleBookmark() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !bookmarked
        bookmarked = target
        syncBookmarkStore(on: target)
        do {
            let status = try await InteractionsAPI.setBookmark(postId: postId, on: target)
            guard gen == userToggleCount else { return }
            bookmarked = status.bookmarked
            syncBookmarkStore(on: status.bookmarked)
            // 북마크 = 오프라인 보장 — 켜지면 기기 사본 확보, 꺼지면 정리.
            if let ref = offlineRef {
                if status.bookmarked {
                    Task {
                        await OfflineStore.shared.download(username: ref.username, slug: ref.slug)
                    }
                } else {
                    OfflineStore.shared.remove(username: ref.username, slug: ref.slug)
                }
            }
        } catch {
            guard gen == userToggleCount else { return }
            bookmarked = !target
            syncBookmarkStore(on: !target)
            throw error
        }
    }
}
