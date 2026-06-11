//
//  PostDetailView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct PostDetailView: View {
    @State private var model: PostDetailViewModel

    init(username: String, slug: String) {
        _model = State(initialValue: PostDetailViewModel(username: username, slug: slug))
    }

    /// 헤더를 지나면 제목이 내비바로 스며들고(아이폰 리딩 앱 문법), 커버가 있으면
    /// 그 동안 내비바 배경을 숨겨 커버가 상단을 다 쓴다.
    @State private var showNavTitle = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch model.phase {
                case .idle, .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { Task { await model.load() } }
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(.top, 80)
                case .loaded(let detail):
                    // 커버는 엣지-투-엣지(컬럼 밖) — 본문 컬럼만 읽기 폭으로 좁힌다.
                    if let urlString = detail.post.ogImageUrl, let url = URL(string: urlString) {
                        StretchyCover(url: url)
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content(detail)
                    }
                    .frame(maxWidth: Metrics.readingColumn)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Metrics.gutter)
                }
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: hasCover ? .top : [])
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > (hasCover ? 300 : 110)
        } action: { _, passed in
            withAnimation(.easeInOut(duration: 0.18)) { showNavTitle = passed }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(loadedTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .opacity(showNavTitle ? 1 : 0)
            }
            ToolbarItem(placement: .primaryAction) {
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .toolbarBackground(
            hasCover && !showNavTitle ? .hidden : .automatic, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private var hasCover: Bool {
        if case .loaded(let detail) = model.phase { return detail.post.ogImageUrl != nil }
        return false
    }

    private var loadedTitle: String {
        if case .loaded(let detail) = model.phase { return detail.post.title }
        return ""
    }

    /// 네이티브 공유 시트용 공개 URL — 웹과 같은 주소.
    private var shareURL: URL? {
        guard case .loaded(let detail) = model.phase else { return nil }
        return URL(
            string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/p/\(detail.author.username)/\(detail.post.slug)")
    }

    // 읽기 흐름 우선: 커버 → 제목 → 작가 한 줄 → 본문. 태그와 좋아요는 다 읽은 뒤
    // 자연스럽게 만나도록 본문 끝으로 — 헤더에 끼어 있던 인터랙션 바가 진입을 막지 않는다.
    @ViewBuilder
    private func content(_ detail: PublicPostDetail) -> some View {
        header(detail)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(detail.blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 20)

        if !detail.post.tags.isEmpty {
            FlowTags(tags: detail.post.tags)
                .padding(.top, 26)
        }
        EngagementBar(postId: detail.post.id, initialLikeCount: detail.post.likeCount)
            .padding(.top, 8)
        if let nav = detail.series { seriesNav(nav, username: detail.author.username) }
        comments
        Color.clear.frame(height: 40)
    }

    private func header(_ detail: PublicPostDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: detail.post.ogImageUrl != nil ? 22 : 18)

            Text(detail.post.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink(value: Route.author(username: detail.author.username)) {
                HStack(spacing: 9) {
                    AvatarView(author: detail.author, size: 28)
                    Text(detail.author.username)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if let date = detail.post.publishedAt {
                        Text("·").foregroundStyle(Palette.faint)
                        Text(date.mediumDate)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            Hairline().padding(.top, 18)
        }
    }

    private func seriesNav(_ nav: PostSeriesNav, username: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Hairline()
            NavigationLink(value: Route.series(username: username, slug: nav.slug)) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1).fill(Palette.accentMarker).frame(width: 3, height: 12)
                    Text(nav.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.heading)
                    Spacer()
                    Text("\(nav.position) / \(nav.total)")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 16) {
                if let prev = nav.prev {
                    navLink(username: username, slug: prev.slug, title: prev.title,
                            caption: "이전 글", systemImage: "chevron.left", trailing: false)
                }
                Spacer(minLength: 0)
                if let next = nav.next {
                    navLink(username: username, slug: next.slug, title: next.title,
                            caption: "다음 글", systemImage: "chevron.right", trailing: true)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private func navLink(username: String, slug: String, title: String,
                         caption: LocalizedStringKey, systemImage: String, trailing: Bool) -> some View {
        NavigationLink(value: Route.post(username: username, slug: slug)) {
            VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
                Label(caption, systemImage: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
                    .labelStyle(.titleAndIcon)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.body)
                    .lineLimit(2)
                    .multilineTextAlignment(trailing ? .trailing : .leading)
            }
            .frame(maxWidth: 180, alignment: trailing ? .trailing : .leading)
        }
        .buttonStyle(.plain)
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 16) {
            Hairline()
            RailHeading("댓글 \(model.comments.count)")
            ForEach(model.comments) { comment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        AvatarView(author: comment.author, size: 24)
                        Text(comment.author.username)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        if let date = comment.createdAt {
                            Text(date.relativeShort)
                                .font(.system(size: 12)).foregroundStyle(Palette.faint)
                        }
                    }
                    Text(comment.body)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.body)
                        .padding(.leading, 32)
                }
            }
            CommentComposer(model: model)
        }
        .padding(.vertical, 16)
    }
}

/// 댓글 입력 한 줄 — 조용한 인라인 컴포저. 로그아웃 상태에서 보내려 하면 그 자리 로그인.
private struct CommentComposer: View {
    let model: PostDetailViewModel

    @State private var body_ = ""
    @State private var sending = false
    @State private var showLoginPrompt = false
    @State private var showTwoFactorHint = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("댓글을 남겨보세요", text: $body_, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 12))
            Button {
                send()
            } label: {
                if sending {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Palette.accent : Palette.faint)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend || sending)
        }
        .padding(.top, 4)
        .alert("로그인이 필요합니다", isPresented: $showLoginPrompt) {
            Button("로그인") { signInHere() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("댓글은 kurl 계정으로 남겨집니다.")
        }
        .alert("2단계 인증이 설정된 계정입니다", isPresented: $showTwoFactorHint) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("내 계정 탭에서 로그인을 완료해 주세요.")
        }
    }

    private var canSend: Bool {
        !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        guard !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await model.postComment(
                    body: body_.trimmingCharacters(in: .whitespacesAndNewlines))
                body_ = ""
                focused = false
            } catch {
                // 전송 실패 — 입력은 보존, 버튼이 다시 활성화된다.
            }
        }
    }

    private func signInHere() {
        Task {
            if (try? await AuthStore.shared.signIn()) == .twoFactorRequired {
                showTwoFactorHint = true
            }
        }
    }
}

/// 엣지-투-엣지 커버 — 당겨 내리면 늘어나는 네이티브 stretchy 헤더.
/// 카드 zoom 전환의 도착점이기도 하다.
private struct StretchyCover: View {
    let url: URL

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .scrollView).minY
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Palette.hairline)
            }
            .saturation(0.85)
            .overlay(Palette.coverVeil)
            .frame(width: geo.size.width, height: geo.size.height + max(0, minY))
            .clipped()
            .offset(y: min(0, -minY))
        }
        .frame(height: 300)
    }
}

/// 태그 줄바꿈 래핑 — muted 칩.
struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    NavigationLink(value: Route.tag(tag)) { MutedChip(text: tag) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}
