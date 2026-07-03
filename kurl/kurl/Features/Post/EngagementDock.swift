//
//  EngagementDock.swift
//  kurl
//

import SwiftUI

/// 글 상세의 좋아요·북마크 — 우하단에 떠 있는 유리 독(AGENTS.md §1).
/// 단독 상세와 덱 임베드가 이 문법 하나를 쓴다 — 같은 화면에 두 인게이지 UI 금지.
/// 댓글 진입도 본문 끝 인라인 한 곳뿐이라 독은 토글만 든다.
/// 활성 상태는 캡슐 전체가 그린(700) 유리로 차오르고, 토글은 낙관(즉시 반영 →
/// 실패 시 서버 응답/원상태로 복귀). 로그아웃 상태에서 누르면 그 자리 로그인.
struct EngagementDock: View {
    @State private var model: EngagementModel
    @State private var showLoginPrompt = false
    @State private var showConnect = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNS

    /// "연결" 시트가 잇는 대상(글 제목·글 id). 없으면 연결 버튼을 감춘다.
    private let connectTarget: (title: String, postId: Int64)?

    init(
        postId: Int64, initialLikeCount: Int64,
        offlineRef: (username: String, slug: String)? = nil,
        connectTarget: (title: String, postId: Int64)? = nil
    ) {
        self.connectTarget = connectTarget
        _model = State(
            initialValue: EngagementModel(
                postId: postId, likeCount: initialLikeCount, offlineRef: offlineRef))
    }

    var body: some View {
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
        .loginPrompt(isPresented: $showLoginPrompt, message: "좋아한 글은 내 라이브러리에 쌓여요") {
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

    private var connect: some View {
        Button {
            guard AuthStore.shared.isSignedIn else { showLoginPrompt = true; return }
            showConnect = true
        } label: {
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
    }

    private var like: some View {
        Button {
            interact(failure: String(localized: "좋아요를 반영하지 못했습니다")) {
                try await model.toggleLike()
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: model.liked ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolEffect(.bounce, value: reduceMotion ? false : model.liked)
                if model.likeCount > 0 {
                    Text("\(model.likeCount)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.liked)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.likeCount)
        .accessibilityLabel(Text("좋아요"))
        .accessibilityValue(Text("\(model.likeCount)"))
        .accessibilityAddTraits(model.liked ? [.isSelected] : [])

    }

    private var bookmark: some View {
        Button {
            interact(failure: String(localized: "북마크를 반영하지 못했습니다")) {
                try await model.toggleBookmark()
            }
        } label: {
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.bookmarked)
        .accessibilityLabel(Text("북마크"))
        .accessibilityAddTraits(model.bookmarked ? [.isSelected] : [])
    }

    private func interact(failure: String, _ action: @escaping () async throws -> Void) {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
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

    private let postId: Int64
    /// 오프라인 저장 짝지 — 북마크 켜짐=기기 사본 확보, 꺼짐=사본 제거.
    private let offlineRef: (username: String, slug: String)?

    init(postId: Int64, likeCount: Int64, offlineRef: (username: String, slug: String)? = nil) {
        self.postId = postId
        self.likeCount = likeCount
        self.offlineRef = offlineRef
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
        }
        if let bookmark = try? await InteractionsAPI.bookmarkStatus(postId: postId),
           gen == userToggleCount {
            bookmarked = bookmark.bookmarked
            BookmarkStore.shared.set(postId, on: bookmark.bookmarked)
        }
    }

    func toggleLike() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !liked
        liked = target
        likeCount += target ? 1 : -1
        do {
            let status = try await InteractionsAPI.setLike(postId: postId, on: target)
            // 연타로 더 새 토글이 나갔으면 이 echo 는 스테일 — 버린다.
            guard gen == userToggleCount else { return }
            liked = status.liked
            likeCount = status.likeCount
        } catch {
            guard gen == userToggleCount else { return }
            liked = !target
            likeCount += target ? -1 : 1
            throw error
        }
    }

    func toggleBookmark() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !bookmarked
        bookmarked = target
        BookmarkStore.shared.set(postId, on: target)
        do {
            let status = try await InteractionsAPI.setBookmark(postId: postId, on: target)
            guard gen == userToggleCount else { return }
            bookmarked = status.bookmarked
            BookmarkStore.shared.set(postId, on: status.bookmarked)
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
            BookmarkStore.shared.set(postId, on: !target)
            throw error
        }
    }
}
