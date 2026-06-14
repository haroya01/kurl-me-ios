//
//  AccountView.swift
//  kurl
//

import SwiftUI

/// 계정 탭 — 조용한 웹로그 톤 그대로. 로그아웃 상태는 한 단락 + 로그인 두 줄(Apple/Google),
/// 로그인 상태는 정체(아바타·이름·이메일)와 로그아웃만. 기능 나열식 설정 화면 금지.
struct AccountView: View {
    private var auth: AuthStore { .shared }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    @State private var showCard = false
    @State private var showNotifications = false
    @State private var unreadCount: Int64 = 0

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0) {
                Group {
                    if auth.isSignedIn {
                        signedIn
                            .transition(.opacity.combined(with: .offset(y: 7)))
                    } else {
                        signedOut
                            .transition(.opacity)
                    }
                }
                // 로그인 성공은 의미 있는 순간 — 정체 카드가 한 호흡 착지한다.
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: auth.isSignedIn)
                // 정체 패널(유리)이 설 자리 — 옅은 브랜드 안개가 유리 뒤로 흐른다.
                // (ReadingColumn 의 pageBg 안쪽이어야 보인다. 가터를 음수로 물려 전폭.)
                .background(alignment: .top) {
                    BrandMist()
                        .frame(height: 300)
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                        .padding(.horizontal, -Metrics.gutter)
                }
            }
            .navigationTitle("내 계정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(.brand)
                    .accessibilityLabel("설정")
                }
                if auth.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNotifications = true
                        } label: {
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
                        .tint(.brand)
                        .accessibilityLabel("알림")
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
                    Task { unreadCount = (try? await NotificationsAPI.unreadCount()) ?? 0 }
                }
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                if signedIn {
                    Task { unreadCount = (try? await NotificationsAPI.unreadCount()) ?? 0 }
                } else {
                    unreadCount = 0
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // 며칠 만에 돌아와도 미읽음 점이 그제 상태로 남지 않게.
                if newPhase == .active, auth.isSignedIn {
                    Task { unreadCount = (try? await NotificationsAPI.unreadCount()) ?? unreadCount }
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .task {
                if auth.isSignedIn {
                    unreadCount = (try? await NotificationsAPI.unreadCount()) ?? 0
                }
                if Config.consumeLaunchValue(after: "--open") == "notifications" {
                    showNotifications = true
                }
            }
        }
        // 명함은 웹의 것을 그대로 — u/ 페이지(테마·소셜·방문 통계)를 인앱으로 연다.
        .sheet(isPresented: $showCard) {
            if let username = auth.me?.username,
               let url = URL(
                   string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/u/\(username)") {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: 로그아웃 상태

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("계정")
                .padding(.top, 28)

            // 환대의 유리 패널 — 안개 위에 뜬 한 장. 본문 타이포는 유리 위 시맨틱.
            VStack(alignment: .leading, spacing: 0) {
                Text("kurl에 로그인")
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.primary)

                Text("좋아요와 북마크, 구독, 그리고 글쓰기까지 — 웹과 같은 계정 하나로 이어집니다.")
                    .font(.system(size: 15 * unit))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.top, 8)

                // Apple/Google 버튼 한 쌍은 공유 컴포넌트 — 글쓰기 게이트·웰컴·로그인 시트와 같은 출처.
                AuthProviderButtons()
                    .padding(.top, 24)

                Text("로그인은 시스템 브라우저에서 안전하게 진행됩니다.")
                    .font(.system(size: 12 * metaUnit))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.panelRadius))
            .padding(.top, 16)
        }
    }

    // MARK: 로그인 상태

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            RailHeading("계정")
                .padding(.top, 28)

            // 정체 카드 — 안개 위에 뜬 유리 한 장.
            HStack(spacing: 13) {
                AvatarView(
                    author: Author(
                        id: 0,
                        username: auth.me?.username ?? "kurl",
                        bio: nil,
                        avatarUrl: auth.me?.avatarUrl
                    ),
                    size: 56
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.me?.username ?? "kurl")
                        .font(.system(size: 18 * unit, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(.primary)
                    Text(auth.me?.email ?? "")
                        .font(.system(size: 13 * unit))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.panelRadius))
            .padding(.top, 16)

            // 내 페이지의 두 얼굴 — 블로그(글)와 명함(링크 모음). 같은 정체, 다른 문.
            HStack(spacing: 10) {
                NavigationLink(value: Route.author(username: auth.me?.username ?? "")) {
                    pageChip("내 블로그", systemImage: "book")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled((auth.me?.username ?? "").isEmpty)

                Button {
                    showCard = true
                } label: {
                    pageChip("내 명함", systemImage: "person.crop.rectangle")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled((auth.me?.username ?? "").isEmpty)
            }
            .padding(.top, 10)

            // 프로필 편집 — 소개글·아바타. 명함(테마·소셜)은 웹 u/ 의 것이라 여기선 안 건드린다.
            libraryRow("프로필 편집", icon: "person.crop.circle") {
                ProfileEditView(currentAvatarUrl: auth.me?.avatarUrl)
            }
            .padding(.top, 18)

            // 노트(짧은 글) — 1급 피드 탭에서 강등, 여기서 들어간다.
            RailHeading("둘러보기")
                .padding(.top, 28)
                .padding(.bottom, 4)
            libraryRow("노트", icon: "text.bubble") { NotesPage(active: true) }

            // 서재 — 행동(좋아요·북마크·구독)의 모아 보기.
            RailHeading("서재")
                .padding(.top, 28)
                .padding(.bottom, 4)
            libraryRow("북마크", icon: "bookmark") { BookmarksView() }
            Hairline()
            libraryRow("좋아요한 글", icon: "heart") { LikedPostsView() }
            Hairline()
            libraryRow("구독한 시리즈", icon: "square.stack.3d.up") { SubscribedSeriesView() }

            Hairline()
                .padding(.top, 24)

            Button("로그아웃", role: .destructive) {
                auth.signOut()
            }
            .font(.system(size: 15 * unit))
            .padding(.top, 18)
        }
        .task { await auth.loadMe() }
    }

    private func pageChip(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13 * unit, weight: .semibold))
            Text(title)
                .font(.system(size: 14 * unit, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .contentShape(Capsule())
    }

    private func libraryRow(
        _ title: LocalizedStringKey, icon: String, @ViewBuilder destination: @escaping () -> some View
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.accentMarker)
                    .frame(width: 22 * unit)
                Text(title)
                    .font(.system(size: 15 * unit, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12 * metaUnit, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

#Preview {
    AccountView()
}
