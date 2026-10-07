//
//  NotesTabView.swift
//  kurl
//

import SwiftUI

struct NotesTabView: View {
    @State private var choice = NoteFeedChoice.shared
    @State private var notes = NotesViewModel(feed: NoteFeedChoice.shared.kind)
    @State private var showFollowingLogin = false
    @State private var composingNote = false
    @State private var notesPosted = 0
    @State private var showLoginSheet = false
    @State private var loadedSignedIn: Bool?
    @State private var atRoot = true
    @Environment(\.tabBarVisibility) private var tabBarVisibility

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0, background: Palette.readingBg, tracksTabBar: true, gutter: Metrics.noteGutter) {
                Color.clear.frame(height: 8)
                composePlaceholder
                content
            }
            .onAppear { atRoot = true }
            .onDisappear { atRoot = false }
            .navigationTitle(choice.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu { NoteFeedPicker() }
            .onChange(of: choice.selectionKey) {
                Task { await notes.show(.init(choice.kind)) }
            }
            .sensoryFeedback(.selection, trigger: choice.selectionKey)
            .sheet(isPresented: Bindable(NoteListsStore.shared).managing) {
                NoteListsSheet()
            }
            .sheet(isPresented: Bindable(ScheduledNotesStore.shared).showing) {
                NavigationStack { ScheduledNotesView() }
            }
            .onChange(of: NoteFeedPreferences.shared.changes) {
                if choice.kind == .following { Task { await notes.reload() } }
            }
            .onChange(of: NoteFeedPreferences.shared.mutes) {
                Task { await notes.reload() }
            }
            .onChange(of: NoteFeedPreferences.shared.languageChanges) {
                if choice.kind == .everyone || choice.kind == .trending { Task { await notes.reload() } }
            }
            .navigationDestination(for: Route.self) {
                RouteView(route: $0)
            }
            .noteTextLinks()
            .task(id: AuthStore.shared.isSignedIn) {
                let signedIn = AuthStore.shared.isSignedIn
                if loadedSignedIn == signedIn { return }
                loadedSignedIn = signedIn
                await NoteFeedPreferences.shared.hydrateIfNeeded()
                await NoteListsStore.shared.reload()
                await NoteFilterStore.shared.reload()
                await notes.reload()
            }
            .brandRefreshable {
                await notes.reload()
            }
            .sheet(isPresented: $composingNote) {
                NoteComposeSheet(mode: .new(quote: nil, inReplyToId: nil)) { note in
                    notes.inserted(note)
                    notesPosted += 1
                }
            }
            .loginPrompt(isPresented: $showLoginSheet, message: "로그인하고 노트 쓰기")
            .background {
                Color.clear.loginPrompt(isPresented: $showFollowingLogin, message: "로그인하고 팔로잉 피드 보기")
            }
            .sensoryFeedback(.success, trigger: notesPosted)
        }
        .overlay(alignment: .bottomTrailing) { composeButton }
    }

    private func compose() {
        if AuthStore.shared.isSignedIn {
            composingNote = true
        } else {
            showLoginSheet = true
        }
    }

    private var composeButton: some View {
        let hidden = !atRoot || (tabBarVisibility?.hidden ?? false)
        return ZStack {
            if !hidden {
                GlassFAB(systemImage: "plus", label: "노트 쓰기", action: compose)
                    .accessibilityIdentifier("notes.fab")
                    .transition(.offset(y: 132).combined(with: .opacity))
            }
        }
        .padding(.trailing, Metrics.gutter)
        .padding(.bottom, 14)
    }

    private var composePlaceholder: some View {
        let me = AuthStore.shared.me
        return Button(action: compose) {
            HStack(alignment: .center, spacing: 12) {
                if let me, AuthStore.shared.isSignedIn {
                    AvatarView(
                        author: Author(id: me.id ?? 0, username: me.username ?? "", bio: nil, avatarUrl: me.avatarUrl),
                        size: 36)
                } else {
                    Circle().fill(Palette.hairline).frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let name = me?.username, AuthStore.shared.isSignedIn {
                        Text(name)
                            .typeScale(.note)
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                    }
                    Text(AuthStore.shared.isSignedIn ? "지금 떠오른 생각을 짧게 남겨 보세요" : "로그인하고 노트 쓰기")
                        .typeScale(.note)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("노트 쓰기")
        .accessibilityIdentifier("notes.compose")
        .overlay(alignment: .bottom) { Hairline().padding(.horizontal, -Metrics.noteGutter) }
    }

    @ViewBuilder
    private var content: some View {
        if choice.kind == .following, !AuthStore.shared.isSignedIn {
            FeedPlaceholder(
                title: "팔로우한 사람의 노트만 모아 봐요",
                message: "로그인하면 블로그와 노트에서 팔로우한 사람의 노트가 여기 모여요.",
                actionTitle: "로그인",
                prominent: true,
                action: { showFollowingLogin = true }
            )
            .padding(.top, 56)
        } else if choice.kind == .bookmarks, !AuthStore.shared.isSignedIn {
            FeedPlaceholder(
                title: "나만 보는 북마크",
                message: "로그인하면 북마크한 노트를 여기서 다시 볼 수 있어요.",
                actionTitle: "로그인",
                prominent: true,
                action: { showFollowingLogin = true }
            )
            .padding(.top, 56)
        } else if choice.kind == .direct, !AuthStore.shared.isSignedIn {
            FeedPlaceholder(
                title: "나에게 온 개인 멘션",
                message: "로그인하면 멘션한 사람만 보는 노트가 여기 모여요.",
                actionTitle: "로그인",
                prominent: true,
                action: { showFollowingLogin = true }
            )
            .padding(.top, 56)
        } else {
            feed
        }
    }

    @ViewBuilder
    private var emptyFeed: some View {
        switch choice.kind {
        case .everyone:
            FeedPlaceholder(
                title: "아직 노트가 없어요",
                message: "제목도 형식도 없이, 지금 떠오른 한 줄을 남기는 자리예요.",
                actionTitle: "첫 노트 쓰기",
                prominent: true,
                action: compose
            )
        case .following:
            FeedPlaceholder(
                title: "팔로우한 사람의 노트가 여기 모여요",
                message: "블로그에서 팔로우한 사람도 함께 보여요. 인기 노트에서 시작해 보세요.",
                actionTitle: "인기 노트 보기",
                prominent: true,
                action: { choice.kind = .trending }
            )
        case .bookmarks:
            FeedPlaceholder(
                title: "북마크한 노트가 없어요",
                message: "노트의 … 메뉴나 상세의 북마크로 모아 둘 수 있어요. 북마크는 나만 봐요.",
                actionTitle: "인기 노트 보기",
                prominent: true,
                action: { choice.kind = .trending }
            )
        case .list:
            FeedPlaceholder(
                title: "이 리스트에 아직 노트가 없어요",
                message: "프로필의 … 메뉴에서 \"리스트에 추가\"로 사람을 담으면 그 사람들의 노트가 여기 모여요.",
                actionTitle: "리스트 관리",
                prominent: true,
                action: { NoteListsStore.shared.managing = true }
            )
        case .direct:
            FeedPlaceholder(
                title: "개인 멘션이 없어요",
                message: "공개 범위를 \"멘션한 사람만\"으로 정한 노트가 여기 모여요. 나와 멘션된 회원만 봐요.",
                actionTitle: "노트 쓰기",
                prominent: true,
                action: compose
            )
        case .trending:
            FeedPlaceholder(
                title: "이번 주에 쓴 노트가 아직 없어요",
                message: "일주일 안에 쓴 노트 중 반응을 많이 받은 노트가 먼저 올라와요.",
                actionTitle: "첫 노트 쓰기",
                prominent: true,
                action: compose
            )
        }
    }

    @ViewBuilder
    private var feed: some View {
        switch notes.phase {
        case .idle, .loading:
            KurlLoadingMark().frame(maxWidth: .infinity, minHeight: 320)
        case .failed(let message):
            ErrorState(message: message, retry: { Task { await notes.reload() } })
        case .loaded:
            if notes.items.isEmpty {
                emptyFeed.padding(.top, 56)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
                            note: note,
                            onChange: { notes.replaced($0) },
                            onDelete: { notes.removed($0) },
                            onQuoted: { notes.inserted($0) },
                            repostedBy: note.repostedBy?.username
                        )
                        .modifier(QuietAppear(index: index))
                        .task { await notes.loadMoreIfNeeded(current: note) }
                        if index < notes.items.count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
                    }
                    if notes.isLoadingMore {
                        KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
                .environment(\.noteFilterContext, notes.filterContext)
            }
        }
    }
}
