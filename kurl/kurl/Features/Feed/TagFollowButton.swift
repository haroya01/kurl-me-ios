//
//  TagFollowButton.swift
//  kurl
//

import SwiftUI

/// 태그 구독 버튼 — 시리즈 구독과 같은 유리 캡슐 문법(구독 전=그린 유리, 구독 중=맑은 유리).
/// 구독한 태그의 새 글은 구독함 피드로 흘러든다(웹 tag-prefs parity).
struct TagFollowButton: View {
    @State private var model: TagFollowModel
    @State private var showLoginPrompt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tag: String) {
        _model = State(initialValue: TagFollowModel(tag: tag))
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.following ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.following ? "구독 중" : "구독")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(model.following ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: !model.following)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.following)
            .accessibilityLabel(Text("태그 구독"))
            .accessibilityAddTraits(model.following ? [.isSelected] : [])

            // 숨기기(mute) = 구독의 반대 — 더 보기 메뉴에. 숨기면 이 태그 글이 피드에서 빠진다.
            Menu {
                Button(role: model.hidden ? nil : .destructive) {
                    mute()
                } label: {
                    Label(
                        model.hidden ? "숨김 해제" : "이 태그 숨기기",
                        systemImage: model.hidden ? "eye" : "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("태그 더 보기")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.userToggleCount)
        .task { await model.hydrate() }
        .loginPrompt(isPresented: $showLoginPrompt, message: "태그를 구독하면 그 태그의 새 글이 구독함에 모여요.") {
            await model.hydrate()
        }
    }

    private func toggle() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        Task {
            do { try await model.toggle() }
            catch { ToastCenter.shared.show(String(localized: "구독을 반영하지 못했습니다")) }
        }
    }

    private func mute() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        Task {
            do {
                try await model.toggleHidden()
                ToastCenter.shared.show(model.hidden
                    ? String(localized: "이 태그를 숨겼습니다")
                    : String(localized: "숨김을 해제했습니다"))
            } catch {
                ToastCenter.shared.show(String(localized: "반영하지 못했습니다"))
            }
        }
    }
}

@MainActor
@Observable
final class TagFollowModel {
    private(set) var following = false
    private(set) var hidden = false
    /// 햅틱 트리거 — hydrate 가 아닌 사용자 토글에만 증가.
    private(set) var userToggleCount = 0

    private let tag: String

    init(tag: String) {
        self.tag = tag
    }

    private func isThis(_ t: String) -> Bool { t.caseInsensitiveCompare(tag) == .orderedSame }

    /// 구독 표면은 인증 — 비로그인은 hydrate 생략(버튼은 "구독" 기본값).
    func hydrate() async {
        guard AuthStore.shared.isSignedIn else { return }
        let gen = userToggleCount
        if let prefs = try? await InteractionsAPI.tagPrefs(), gen == userToggleCount {
            following = prefs.followed.contains(where: isThis)
            hidden = prefs.hidden.contains(where: isThis)
        }
    }

    func toggle() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !following
        following = target
        do {
            let prefs = try await InteractionsAPI.setTagFollow(tag: tag, on: target)
            guard gen == userToggleCount else { return }
            following = prefs.followed.contains(where: isThis)
            hidden = prefs.hidden.contains(where: isThis)
        } catch {
            guard gen == userToggleCount else { return }
            following = !target
            throw error
        }
    }

    func toggleHidden() async throws {
        userToggleCount += 1
        let gen = userToggleCount
        let target = !hidden
        hidden = target
        do {
            let prefs = try await InteractionsAPI.setTagHidden(tag: tag, on: target)
            guard gen == userToggleCount else { return }
            hidden = prefs.hidden.contains(where: isThis)
            // 숨기면 서버가 구독을 정리할 수 있으니 같이 반영.
            following = prefs.followed.contains(where: isThis)
        } catch {
            guard gen == userToggleCount else { return }
            hidden = !target
            throw error
        }
    }
}
