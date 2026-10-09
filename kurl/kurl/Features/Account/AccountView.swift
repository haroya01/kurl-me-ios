//
//  AccountView.swift
//  kurl
//

import SwiftUI

/// 계정 탭 — 들어오면 내 블로그(내가 발행한 글)가 바로 뜬다. 서재(내가 모은 것)는 오른쪽 헤더
/// 버튼으로, 설정·프로필·로그아웃은 왼쪽 톱니(SettingsView)로.
struct AccountView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNotifications = false
    // 피드 탭 벨과 UnreadStore 공유 — 각자 fetch 해 같은 GET 이 2회 나가지 않게.
    private var unreadCount: Int64 { UnreadStore.shared.count }
    // me 로드가 실패했는가 — 로그인 상태의 스피너가 재시도 없는 막다른 길이 되지 않게.
    @State private var meLoadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    if let username = auth.me?.username, !username.isEmpty {
                        // 내 계정 = 내 블로그 — 들어오면 내가 발행한 글이 바로 뜬다.
                        AuthorBlogView(username: username)
                    } else if meLoadFailed {
                        // me 로드 실패(오프라인 등) — StateView 실패 상태와 같은 결의 재시도 길.
                        ErrorState(retry: { Task { await reloadMe() } })
                    } else {
                        // me 로딩 중 — 잠깐의 빈자리를 막다른 길로 두지 않는다.
                        KurlLoadingMark()
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }
                } else {
                    SignedOutState(
                        systemImage: "person.crop.circle",
                        description: "내 글과 노트, 라이브러리가 여기 모여요.",
                        message: "kurl에 로그인하세요")
                        .navigationTitle("내 계정")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        // 설정 스택은 하단바를 접는다(SettingsView 안 .hidesTabBar) — 하단 행이
                        // 바에 가리지 않게, iOS 관습대로.
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.primary)
                    .accessibilityLabel("설정")
                }
                if auth.isSignedIn {
                    // 서재 — 내가 모은 것(북마크·좋아요·구독·하이라이트·컬렉션·기록·노트).
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            LibraryView()
                        } label: {
                            Image(systemName: "books.vertical")
                        }
                        .tint(.primary)
                        .accessibilityLabel("서재")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        // 값 기반 링크로 인박스를 민다 — 인박스 안의 딥링크(글·컬렉션)가 같은 스택에서
                        // 이어 밀리게 하려면 벨도 값 목적지를 써야 한다(isPresented 목적지는 값 푸시와 충돌).
                        NavigationLink(value: Route.notifications) {
                            Image(systemName: "bell")
                                .overlay(alignment: .topTrailing) {
                                    if unreadCount > 0 {
                                        Circle()
                                            .fill(Palette.accent)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 3, y: -2)
                                            // 미읽음 점은 톡 떠오르고 사라진다 — 피드 벨과 같은 결.
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                        }
                        .tint(.primary)
                        .accessibilityLabel("알림")
                        .accessibilityValue(
                            unreadCount > 0 ? Text("읽지 않음 \(unreadCount)") : Text(""))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: unreadCount > 0)
                    }
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationsView()
            }
            .onChange(of: showNotifications) { _, open in
                // 알림에서 돌아오면 미읽음 점 갱신 — 모두 읽었는데 점이 남지 않게.
                if !open, auth.isSignedIn {
                    Task { await UnreadStore.shared.refresh() }
                }
            }
            .onChange(of: auth.isSignedIn) { _, _ in
                Task { await UnreadStore.shared.refresh() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // 며칠 만에 돌아와도 미읽음 점이 그제 상태로 남지 않게.
                if newPhase == .active, auth.isSignedIn {
                    Task { await UnreadStore.shared.refresh() }
                    // 오프라인에서 me 로드가 비었으면 복귀 시 다시 채운다.
                    if auth.me == nil {
                        Task { await reloadMe() }
                    }
                }
            }
            // 푸시된 상세는 탭바 숨김을 추적하지 않는다(탭 루트 전용).
            .navigationDestination(for: Route.self) {
                RouteView(route: $0)
            }
            .task {
                await reloadMe()
                if auth.isSignedIn {
                    await UnreadStore.shared.refresh()
                }
                if Config.consumeLaunchValue(after: "--open") == "notifications" {
                    showNotifications = true
                }
            }
        }
    }

    /// me 로드 + 실패 판정 — 로그인인데 me 가 비면 실패로 보고 재시도 화면을 연다.
    private func reloadMe() async {
        meLoadFailed = false
        await auth.loadMe()
        meLoadFailed = auth.isSignedIn && auth.me == nil
    }
}

#Preview {
    AccountView()
}
