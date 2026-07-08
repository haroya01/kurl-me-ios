//
//  PostDetailViewModel.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class PostDetailViewModel {
    let username: String
    let slug: String
    /// 발견 덱의 댓글 시트처럼 "이미 읽은 글"을 다시 여는 표면은 비콘을 쏘지 않는다 —
    /// 조회수 이중 집계 방지. 덱 자체는 체류 시간 기준으로 따로 쏜다.
    private let recordsView: Bool

    private(set) var phase: LoadState<PublicPostDetail> = .idle
    /// 네트워크가 죽어 기기 사본으로 렌더 중 — 상단에 조용한 배지 하나만 세운다.
    private(set) var isOfflineCopy = false
    private(set) var comments: [Comment] = []
    /// 공개 댓글 API 실패 — "댓글 0"으로 위장하지 않고 재시도 행을 세우기 위한 구분.
    private(set) var commentsFailed = false
    /// 보는 사람이 좋아요한 댓글 id — 공개 목록과 별도의 인증 엔드포인트로 hydrate(#538 패턴).
    private(set) var likedCommentIds: Set<Int64> = []
    /// 낙관 카운트 보정(댓글 id → 증감) — 서버 likeCount 는 공개 목록 재로드 때만 갱신되므로.
    private(set) var commentLikeDelta: [Int64: Int64] = [:]
    /// 댓글별 토글 세대 — 비행 중 재로드/연타의 스테일 echo 를 버린다.
    private var commentToggleGen: [Int64: Int] = [:]

    /// 오프라인 사본을 띄운 동안만 도는 연결 감시 — 배너의 "연결되면 갱신" 약속을 지킨다.
    private var pathMonitor: NWPathMonitor?
    /// 감시 시작 직후 오는 현재 상태 콜백이 실패 직후 헛 재시도가 되지 않게,
    /// 한 번이라도 끊긴 상태를 본 뒤의 회복만 재로드 트리거로 삼는다.
    private var sawUnsatisfiedPath = false
    /// 오프라인 사본 갱신 중 재진입 방지 — 이 경로는 phase 를 .loading 으로 바꾸지 않아서
    /// (사본을 계속 보여준다) phase 가드가 못 잡는다.
    private var offlineRefreshInFlight = false

    init(username: String, slug: String, recordsView: Bool = true) {
        self.username = username
        self.slug = slug
        self.recordsView = recordsView
    }

    func load() async {
        // 재시도 가능해야 한다 — loaded/loading 만 막고 idle/failed 에선 진입.
        // 단 오프라인 사본을 띄운 loaded 는 예외로 재진입 허용 — 연결 회복 시 최신으로 간다.
        if case .loading = phase { return }
        if case .loaded = phase, !isOfflineCopy { return }
        let refreshingOfflineCopy = isOfflineCopy
        if refreshingOfflineCopy {
            guard !offlineRefreshInFlight else { return }
            offlineRefreshInFlight = true
        } else {
            phase = .loading
        }
        defer { offlineRefreshInFlight = false }
        do {
            let raw = try await BlogAPI.postDetailData(username: username, slug: slug)
            let detail = try JSONDecoder.blog.decode(PublicPostDetail.self, from: raw)
            isOfflineCopy = false
            stopConnectivityWatch()
            phase = .loaded(detail)
            // 북마크로 저장된 글이면 사본을 방금 본 최신으로 갈아 둔다(read-through).
            // 바이트가 사본 그대로면 스킵 — save 는 본문 재디코드·이미지 프리페치·위젯
            // 스냅샷 재빌드까지 끌고 오는 무거운 경로다. LRU 시계는 data() 읽기가 감는다.
            if OfflineStore.shared.contains(username: username, slug: slug),
               OfflineStore.shared.data(username: username, slug: slug) != raw {
                OfflineStore.shared.save(raw: raw, username: username, slug: slug)
            }
            if recordsView {
                // 조회 비콘은 fire-and-forget — 댓글 로드를 왕복 시간만큼 세우지 않는다.
                Task { [username, slug] in
                    await BlogAPI.recordView(username: username, slug: slug)
                }
            }
            await loadComments(postId: detail.post.id)
        } catch {
            // 사본을 이미 띄운 채의 갱신 실패 — 화면을 실패로 덮지 않고 그대로 둔다.
            if refreshingOfflineCopy { return }
            // 네트워크 실패 → 기기 사본 폴백. 댓글·좋아요는 온라인 전용으로 비워 둔다.
            if let data = OfflineStore.shared.data(username: username, slug: slug),
               let detail = try? JSONDecoder.blog.decode(PublicPostDetail.self, from: data) {
                isOfflineCopy = true
                phase = .loaded(detail)
                startConnectivityWatch()
                return
            }
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func loadComments(postId: Int64) async {
        do {
            comments = try await BlogAPI.comments(postId: postId)
            commentsFailed = false
        } catch {
            comments = []
            commentsFailed = true
        }
        commentLikeDelta = [:]
        commentToggleGen = [:]
        if AuthStore.shared.isSignedIn {
            likedCommentIds = Set((try? await InteractionsAPI.likedCommentIds(postId: postId)) ?? [])
        }
    }

    /// 댓글만 다시 — 실패 행의 재시도가 부른다(본문은 이미 떠 있다).
    func reloadComments() async {
        guard case .loaded(let detail) = phase else { return }
        await loadComments(postId: detail.post.id)
    }

    // MARK: 오프라인 사본 → 온라인 갱신

    /// 오프라인 폴백에 들어갈 때만 시작 — 경로가 살아나면 load() 재진입으로 본문·댓글을 채운다.
    private func startConnectivityWatch() {
        guard pathMonitor == nil else { return }
        sawUnsatisfiedPath = false
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard satisfied else {
                    self.sawUnsatisfiedPath = true
                    return
                }
                guard self.isOfflineCopy, self.sawUnsatisfiedPath else { return }
                await self.load()
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func stopConnectivityWatch() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func displayLikeCount(_ comment: Comment) -> Int64 {
        max(0, (comment.likeCount ?? 0) + (commentLikeDelta[comment.id] ?? 0))
    }

    func toggleCommentLike(_ comment: Comment) async {
        let gen = (commentToggleGen[comment.id] ?? 0) + 1
        commentToggleGen[comment.id] = gen
        let on = !likedCommentIds.contains(comment.id)
        // 낙관 반영
        if on { likedCommentIds.insert(comment.id) } else { likedCommentIds.remove(comment.id) }
        commentLikeDelta[comment.id, default: 0] += on ? 1 : -1
        do {
            let status = try await InteractionsAPI.setCommentLike(commentId: comment.id, on: on)
            guard gen == commentToggleGen[comment.id] else { return }
            // delta 기준은 "현재 배열의 likeCount" — 비행 중 목록이 갈렸어도 이중 반영되지 않게.
            let base = comments.first(where: { $0.id == comment.id })?.likeCount ?? comment.likeCount ?? 0
            commentLikeDelta[comment.id] = status.likeCount - base
            if status.liked { likedCommentIds.insert(comment.id) } else { likedCommentIds.remove(comment.id) }
        } catch {
            guard gen == commentToggleGen[comment.id] else { return }
            if on { likedCommentIds.remove(comment.id) } else { likedCommentIds.insert(comment.id) }
            commentLikeDelta[comment.id, default: 0] += on ? -1 : 1
            ToastCenter.shared.show(String(localized: "좋아요를 반영하지 못했습니다"))
        }
    }

    func deleteComment(_ comment: Comment) async throws {
        try await InteractionsAPI.deleteComment(commentId: comment.id)
        comments.removeAll { $0.id == comment.id || $0.parentId == comment.id }
    }

    /// 댓글 작성 → 공개 목록 재로드(생성 응답 형태에 의존하지 않는다).
    func postComment(body: String, parentId: Int64? = nil) async throws {
        guard case .loaded(let detail) = phase else { return }
        try await InteractionsAPI.createComment(postId: detail.post.id, body: body, parentId: parentId)
        await loadComments(postId: detail.post.id)
    }
}
