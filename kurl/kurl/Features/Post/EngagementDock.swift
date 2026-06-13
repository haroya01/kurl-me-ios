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
    @State private var showTwoFactorHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNS

    init(postId: Int64, initialLikeCount: Int64, offlineRef: (username: String, slug: String)? = nil) {
        _model = State(
            initialValue: EngagementModel(
                postId: postId, likeCount: initialLikeCount, offlineRef: offlineRef))
    }

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
            VStack(spacing: 12) {
                like
                bookmark
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task(id: AuthStore.shared.isSignedIn) { await model.hydrate() }
        .alert("로그인이 필요합니다", isPresented: $showLoginPrompt) {
            Button("Apple로 로그인") { appleHere() }
            Button("Google로 로그인") { signInHere() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("좋아요와 북마크는 kurl 계정으로 이어집니다.")
        }
        .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactorHint) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("내 계정 탭에서 로그인을 완료해 주세요.")
        }
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
            .frame(width: 52)
            .frame(minHeight: 52)
            .padding(.vertical, model.likeCount > 0 ? 7 : 0)
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

    private func signInHere() {
        Task {
            // 2FA 계정은 TOTP 입력 UI 가 계정 탭에 있어 여기서 끝까지 못 간다 — 안내만.
            if (try? await AuthStore.shared.signIn()) == .twoFactorRequired {
                showTwoFactorHint = true
            } else if AuthStore.shared.isSignedIn {
                await model.hydrate()
            }
        }
    }

    private func appleHere() {
        Task {
            if (try? await AuthStore.shared.signInWithApple()) == .twoFactorRequired {
                showTwoFactorHint = true
            } else if AuthStore.shared.isSignedIn {
                await model.hydrate()
            }
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
        do {
            let status = try await InteractionsAPI.setBookmark(postId: postId, on: target)
            guard gen == userToggleCount else { return }
            bookmarked = status.bookmarked
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
            throw error
        }
    }
}
