//
//  MockSelfTest.swift
//  kurl
//

import Foundation

/// `--mocks --selftest` 로 실행되는 배선 검증 — 버튼이 부르는 것과 같은 API 레이어 경로
/// (WriteAPI/InteractionsAPI/AnalyticsAPI → APIClient → MockBackend)를 프로그램으로 돌리고
/// 결과를 Documents/selftest.log 에 남긴다. simctl 이 터치를 못 넣는 한계의 우회로.
@MainActor
enum MockSelfTest {

    static func runIfRequested() {
        guard Config.useMocks,
              ProcessInfo.processInfo.arguments.contains("--selftest")
        else { return }
        Task { await run() }
    }

    private static func run() async {
        var lines: [String] = []
        func log(_ s: String) { lines.append(s) }

        do {
            // 글쓰기 — 작성 → 본문 저장 → 왕복 로드 → 발행 → 목록 반영
            let created = try await WriteAPI.createDraft(title: "셀프테스트 글")
            log("write.create: id=\(created.id) status=\(created.status)")
            let canonical = try await WriteAPI.replaceMarkdown(
                postId: created.id, markdown: "# 제목\n\n첫 문단\n\n- 항목 하나\n- 항목 둘")
            log("write.save: roundtrip=\(canonical.hasPrefix("# 제목"))")
            let reloaded = try await WriteAPI.markdown(postId: created.id)
            log("write.reload: matches=\(reloaded == canonical)")
            let patched = try await WriteAPI.updateMetadata(
                postId: created.id, title: "셀프테스트 글(수정)",
                excerpt: "소개글 한 단락", tags: ["테스트", "셀프"])
            log("write.meta: title=\(patched.title.hasSuffix("(수정)")) tags=\(patched.tags ?? []) excerpt=\(patched.excerpt != nil)")
            let preview = try await WriteAPI.previewURL(slug: "p-mock-1", postId: created.id)
            log("write.preview: url=\(preview?.absoluteString.contains("preview=") == true)")
            let series = try await WriteAPI.mySeries()
            try await WriteAPI.assign(postId: created.id, from: nil, to: series.first?.id)
            let afterAssign = try await WriteAPI.myPosts().first { $0.id == created.id }
            log("write.series: list=\(series.count) assigned=\(afterAssign?.seriesId != nil)")
            let revisions = try await WriteAPI.revisions(postId: created.id)
            try await WriteAPI.restoreRevision(postId: created.id, version: 1)
            let restored = try await WriteAPI.markdown(postId: created.id)
            log("write.revisions: count=\(revisions.count) restored=\(restored.contains("복원된"))")
            let cover = try await WriteAPI.uploadImage(postId: created.id, jpegData: Data([0xFF, 0xD8]))
            try await WriteAPI.updateCover(postId: created.id, url: cover.url, key: cover.key)
            log("write.cover: url=\(cover.url.hasSuffix(".jpg"))")
            let scheduled = try await WriteAPI.schedule(postId: created.id, at: Date().addingTimeInterval(3600))
            log("write.schedule: status=\(scheduled.status)")
            let published = try await WriteAPI.publish(postId: created.id)
            log("write.publish: status=\(published.status)")
            let mine = try await WriteAPI.myPosts()
            log("write.list: count=\(mine.count) hasNew=\(mine.contains { $0.id == created.id })")

            // 인터랙션 — 좋아요/북마크/팔로우/구독 토글 + 댓글
            let liked = try await InteractionsAPI.setLike(postId: 9001, on: true)
            let unliked = try await InteractionsAPI.setLike(postId: 9001, on: false)
            log("engage.like: on=\(liked.liked)(\(liked.likeCount)) off=\(unliked.liked)(\(unliked.likeCount))")
            let bookmarked = try await InteractionsAPI.setBookmark(postId: 9001, on: true)
            log("engage.bookmark: on=\(bookmarked.bookmarked)")
            let follow = try await InteractionsAPI.setFollow(username: "honggildong", on: true)
            log("engage.follow: on=\(follow.following) count=\(follow.followerCount)")
            let sub = try await InteractionsAPI.setSubscription(seriesId: 1, on: true)
            log("engage.subscribe: on=\(sub.subscribed) count=\(sub.subscriberCount)")
            try await InteractionsAPI.createComment(postId: 9001, body: "셀프테스트 댓글")
            log("engage.comment: posted")

            // 서재·팔로잉 — 모아 보기 면
            let bookmarks = try await LibraryAPI.bookmarks()
            let likedList = try await LibraryAPI.likedPosts()
            let subscribed = try await LibraryAPI.subscribedSeries()
            let followingFeed = try await LibraryAPI.followingFeed()
            log("library: bookmarks=\(bookmarks.count) liked=\(likedList.count) series=\(subscribed.count) following=\(followingFeed.items.count)")

            // 댓글 인터랙션
            let cLiked = try await InteractionsAPI.setCommentLike(commentId: 77, on: true)
            let cIds = try await InteractionsAPI.likedCommentIds(postId: 9001)
            try await InteractionsAPI.createComment(postId: 9001, body: "답글", parentId: 77)
            try await InteractionsAPI.deleteComment(commentId: 77)
            log("comments: like=\(cLiked.liked)(\(cLiked.likeCount)) likedIds=\(cIds.count) replyPosted deleted")

            // 분석 — 디코드 + 데이터 형태
            let overview = try await AnalyticsAPI.overview()
            log("analytics: windowViews=\(overview.windowViews) daily=\(overview.daily.count) referrers=\(overview.referrers.count) linkClicks=\(overview.windowLinkClicks)")
            let perf = try await AnalyticsAPI.postPerformance()
            log("analytics.posts: items=\(perf.items.count) top=\(perf.items.first?.viewCount ?? -1)")
            let rows = try await AnalyticsAPI.seriesAnalytics()
            log("analytics.series: rows=\(rows.count)")

            log("SELFTEST OK")
        } catch {
            log("SELFTEST FAIL: \(error)")
        }

        let text = lines.joined(separator: "\n")
        print(text)
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? text.write(to: dir.appendingPathComponent("selftest.log"), atomically: true, encoding: .utf8)
        }
    }
}
