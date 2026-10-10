//
//  MockBackend.swift
//  kurl
//

import Foundation

/// `--mocks` 모드의 인증 표면 가짜 백엔드. 응답 JSON 은 백엔드 record 와 같은 필드명을 쓰므로
/// 실모드와 동일한 디코더·뷰 바인딩이 그대로 검증된다. 상태(좋아요·팔로우·글)는 메모리에 들고
/// 토글·작성 흐름이 왕복하도록 한다. 공개 읽기(/public/*)는 다루지 않는다 — 실서버로 흘려보냄.
@MainActor
enum MockBackend {

    /// 목 모드에서 이미지 업로드가 돌려주는, 실제로 로드되는 이미지 URL(첨부→표시 검증이 가능하게).
    static let mockUploadedImageURL =
        "https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=1200&q=80"

    // MARK: 상태

    private struct MockPost {
        var id: Int64
        var slug: String
        var title: String
        var status: String
        var markdown: String
        var publishedAt: Date?
        var updatedAt: Date
        var tags: [String] = []
        var excerpt: String?
        var seriesId: Int64?
        var ogImageUrl: String?
        var scheduledAt: Date?
        var contentVersion: Int64 = 0
    }

    /// `--mock-remote-edit <글 id>` — 그 글 본문을 처음 읽어 간 직후 다른 기기가 고친 것처럼 본문·버전을 바꾼다
    /// (편집 충돌 검증용).
    private static var remoteEditTarget: Int64? = {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "--mock-remote-edit"), at + 1 < args.count else { return nil }
        return Int64(args[at + 1])
    }()

    /// 서버 편집 버전 계약 — baseVersion 이 다르면 409(아무것도 안 씀), overwrite 면 검사를 건너뛴다.
    private static func requireEditVersion(_ idx: Int, _ req: [String: Any]) throws {
        let overwrite = req["overwrite"] as? Bool ?? false
        guard !overwrite, let base = (req["baseVersion"] as? NSNumber)?.int64Value,
              base != posts[idx].contentVersion
        else { return }
        throw APIError.server(
            status: 409, code: "POST_EDIT_CONFLICT",
            detail: "post was changed by another save; current content version is \(posts[idx].contentVersion)")
    }

    /// `--published-body-image` — 발행 목 글 본문에 커버 없는 사진 한 줄(글 정보 시트의 "본문 첫 이미지를 커버로" 제안 검증용).
    private static let publishedBodyImage =
        ProcessInfo.processInfo.arguments.contains("--published-body-image") ? "\n\n![](\(mockUploadedImageURL))" : ""

    private static var posts: [MockPost] = draftFixtures([
        MockPost(id: 9001, slug: "p-mock-1", title: "목 초안 — 헥사고날 정리", status: "DRAFT",
                 markdown: "# 헥사고날\n\n포트와 어댑터.", publishedAt: nil, updatedAt: Date(),
                 tags: ["개발"], excerpt: "포트와 어댑터로 다시 그린다."),
        // 초안 네이티브 미리보기(신고 15) 캡처용 — 블록 종류가 두루 든 초안. 기존 9001 은 그대로 둔다
        // (WriteV2IntegrationUITests 가 그 정확한 본문에 의존). 목 데이터 전용 카피.
        MockPost(id: 9003, slug: "p-mock-3", title: "목 초안 — 미리보기 데모", status: "DRAFT",
                 markdown: """
                 # 종이 위의 초안

                 포트와 어댑터로 경계를 다시 그린다. **핵심은 방향**이고, *세부는 어댑터*에 맡긴다. 이름이 곧 `경계`다.

                 > 작고 깊게, 경계는 이름에서 시작한다.

                 ---

                 ## 정리한 것

                 - 포트 이름 짓기
                 - 어댑터 분리
                 - 테스트 경계 세우기

                 ```swift
                 protocol PostPort {
                     func load(_ id: Int) async throws -> Post
                 }
                 ```
                 """,
                 publishedAt: nil, updatedAt: Date(),
                 tags: ["개발"], excerpt: "블록 종류가 두루 든 미리보기 데모."),
        MockPost(id: 9002, slug: "p-mock-2", title: "발행된 목 글", status: "PUBLISHED",
                 markdown: "# 발행됨\n\n본문." + publishedBodyImage, publishedAt: Date().addingTimeInterval(-86_400), updatedAt: Date(),
                 tags: ["회고", "iOS"], excerpt: "한 달간의 작업을 정리했다."),
    ])

    /// `--no-drafts`·`--many-drafts` — 글쓰기 고르기의 '이어 쓰기' 없음·'모두 보기' 검증용.
    private static func draftFixtures(_ base: [MockPost]) -> [MockPost] {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--no-drafts") { return base.filter { $0.status != "DRAFT" } }
        guard args.contains("--many-drafts") else { return base }
        let extra = (1...3).map { n in
            MockPost(
                id: 9200 + Int64(n), slug: "p-mock-extra-\(n)", title: "목 초안 \(n)", status: "DRAFT",
                markdown: "# 목 초안 \(n)\n\n본문.", publishedAt: nil,
                updatedAt: Date().addingTimeInterval(-Double(n) * 3_600))
        }
        return base + extra
    }

    private struct MockNote {
        var id: Int64
        var body: String
        var createdAt: Date
        var likeCount: Int64
        var authorId: Int64
        var username: String
        var editedAt: Date? = nil
        var inReplyToId: Int64? = nil
        var media: [[String: Any]] = []
        var quotedPost: [String: Any]? = nil
        var quotedNoteId: Int64? = nil
        var linkPreview: [String: Any]? = nil
        var contentWarning: String? = nil
        var sensitive = false
        var visibility = "public"
        var poll: MockPoll? = nil
    }

    private struct MockPoll {
        var options: [String]
        var expiresAt: Date
        var multiple = false
        var votes: [Int64]
        var voters: Int64
        var mine: [Int]? = nil
    }

    private static var notes: [MockNote] = [
        // 시리즈 "헥사고날 전환기"의 4편과 5편 사이에 든 노트 — 시리즈 배너·목차·구독함 카드 검증용.
        MockNote(id: 9540, body: "4편을 쓰고 남은 메모. 어댑터를 갈아 끼우던 날, 실패한 테스트가 먼저 경계를 알려 줬다.",
                 createdAt: Date().addingTimeInterval(-216_000), likeCount: 3, authorId: 1, username: "honggildong"),
        MockNote(id: 9530, body: "헥사고날로 옮긴 지 석 달. 남은 것 세 가지를 적어 둔다.",
                 createdAt: Date().addingTimeInterval(-500_000), likeCount: 2, authorId: 2, username: "yuki_dev"),
        MockNote(id: 9501, body: "오늘 헥사고날 포트 이름 짓는 데 한 시간 썼다. 이름이 곧 경계라는 걸 다시 배운다. #아키텍처",
                 createdAt: Date().addingTimeInterval(-1_800), likeCount: 4, authorId: 2, username: "yuki_dev"),
        MockNote(id: 9509, body: "회고 끝나고 점심 어디서 먹을까요?",
                 createdAt: Date().addingTimeInterval(-2_400), likeCount: 2, authorId: 2, username: "yuki_dev",
                 poll: MockPoll(options: ["국밥", "파스타", "샐러드"], expiresAt: Date().addingTimeInterval(21_600),
                                votes: [5, 3, 1], voters: 9)),
        MockNote(id: 9510, body: "Hexagonal ports, named after a long afternoon.",
                 createdAt: Date().addingTimeInterval(-2_700), likeCount: 0, authorId: 3, username: "reader_kim"),
        MockNote(id: 9505, body: "이름 짓는 데 한 시간이면 싸게 먹힌 거다. 우리 팀은 일주일 걸렸다.",
                 createdAt: Date().addingTimeInterval(-3_600), likeCount: 1, authorId: 1, username: "honggildong",
                 editedAt: Date().addingTimeInterval(-3_000), quotedNoteId: 9501),
        MockNote(id: 9502, body: "긴 글로 정리하기 전의 생각 조각을 둘 곳이 필요했는데, 노트가 딱 그 자리다.",
                 createdAt: Date().addingTimeInterval(-7_200), likeCount: 11, authorId: 1, username: "honggildong"),
        MockNote(id: 9503, body: "라이트 모드 캔버스를 순백에서 slate-50 으로 바꿨더니 카드가 비로소 떠 보인다. 배경은 색이 아니라 깊이다. https://kurl.me/about",
                 createdAt: Date().addingTimeInterval(-26_000), likeCount: 7, authorId: 3, username: "reader_kim",
                 linkPreview: [
                    "url": "https://kurl.me/about", "title": "kurl — 짧은 링크와 글이 오래 사는 곳",
                    "description": "링크를 줄이고, 글을 쓰고, 그 사이를 엮는다.",
                    "image": "https://picsum.photos/seed/kurl-about/960/502",
                 ]),
        MockNote(id: 9504, body: "창밖 사진 세 장. 글로 정리하기 전에 남겨 둔다.",
                 createdAt: Date().addingTimeInterval(-40_000), likeCount: 2, authorId: 1, username: "honggildong",
                 media: [
                    ["url": "https://picsum.photos/seed/kurl-note-a/900/700", "altText": "비 오는 창밖",
                     "contentType": "image/jpeg", "width": 900, "height": 700],
                    ["url": "https://picsum.photos/seed/kurl-note-b/600/800", "altText": "젖은 골목",
                     "contentType": "image/jpeg", "width": 600, "height": 800],
                    ["url": "https://picsum.photos/seed/kurl-note-c/800/800", "altText": NSNull(),
                     "contentType": "image/jpeg", "width": 800, "height": 800],
                 ],
                 quotedPost: ["id": 1, "title": "헥사고날 아키텍처, 작은 서비스에 과했을까", "slug": "hexagonal",
                              "authorUsername": "honggildong"]),
        MockNote(id: 9520, body: "경계를 먼저 긋는다는 대목, 우리 팀 회고에 그대로 옮겼다.",
                 createdAt: Date().addingTimeInterval(-400_000), likeCount: 1, authorId: 2, username: "yuki_dev",
                 quotedPost: ["id": 8201, "title": "헥사고날로 갈아탄 지 석 달", "slug": "hexagonal-after-3-months",
                              "authorUsername": "honggildong"]),
        MockNote(id: 9506, body: "마지막 장면에서 주인공이 결국 돌아오지 않는다. 그래서 더 오래 남는다.",
                 createdAt: Date().addingTimeInterval(-90_000), likeCount: 0, authorId: 3, username: "reader_kim",
                 contentWarning: "영화 결말 이야기"),
        MockNote(id: 9507, body: "수술 끝나고 꿰맨 자리. 잘 아물고 있다.",
                 createdAt: Date().addingTimeInterval(-100_000), likeCount: 0, authorId: 2, username: "yuki_dev",
                 media: [
                    ["url": "https://picsum.photos/seed/kurl-note-d/800/600", "altText": "꿰맨 자리",
                     "contentType": "image/jpeg"],
                 ],
                 sensitive: true),
        MockNote(id: 9508, body: "@honggildong 다음 주 회고, 둘이 먼저 맞춰 볼래요?",
                 createdAt: Date().addingTimeInterval(-110_000), likeCount: 0, authorId: 2, username: "yuki_dev",
                 visibility: "direct"),
    ]
    private static var nextNoteId: Int64 = 9600
    private static var likedNotes: Set<Int64> = []
    private static var bookmarkedNotes: [Int64] = []
    private static var showReposts = true
    private static var pinnedNotes: [Int64] = []
    private static var noteLists: [(id: Int64, title: String, members: [String])] = []
    private static var mutedUsers: [String: (notifications: Bool, expiresAt: Date?)] = [:]
    private static var noteFilters: [[String: Any]] = []
    private static var nextFilterId: Int64 = 800
    private static var nextListId: Int64 = 700
    private static let mockUserIds: [String: Int64] = ["honggildong": 1, "yuki_dev": 2, "reader_kim": 3]
    private static var noteHistory: [Int64: [(body: String, at: Date)]] = [
        9505: [("이름 짓는 데 한 시간이면 싸게 먹힌 거다.", Date().addingTimeInterval(-3_600))],
    ]
    private static var repostsHidden: Set<String> = []
    /// 사용자별 리포스트한 노트 id(최신 먼저). 목 세션은 honggildong.
    private static var repostedNotes: [String: [Int64]] = ["honggildong": [9503], "yuki_dev": [9505]]
    private static var noteReplies: [MockNote] = [
        MockNote(id: 9531, body: "하나. 테스트가 빨라졌다.",
                 createdAt: Date().addingTimeInterval(-499_990), likeCount: 0, authorId: 2,
                 username: "yuki_dev", inReplyToId: 9530),
        MockNote(id: 9532, body: "둘. 경계를 먼저 긋게 됐다.",
                 createdAt: Date().addingTimeInterval(-499_980), likeCount: 0, authorId: 2,
                 username: "yuki_dev", inReplyToId: 9531),
        MockNote(id: 9533, body: "셋. 이름 짓는 데 시간을 쓴다.",
                 createdAt: Date().addingTimeInterval(-499_970), likeCount: 0, authorId: 2,
                 username: "yuki_dev", inReplyToId: 9532),
        MockNote(id: 9534, body: "셋째가 제일 공감돼요.",
                 createdAt: Date().addingTimeInterval(-400_000), likeCount: 0, authorId: 3,
                 username: "reader_kim", inReplyToId: 9530),
        // 투표 노트(9509)에 단 답글 — 답글 상세 위쪽 원글 자리의 투표가 투표 뒤 결과로 바뀌는지 검증용.
        MockNote(id: 9542, body: "파스타에 한 표 던지고 갑니다.",
                 createdAt: Date().addingTimeInterval(-2_300), likeCount: 0, authorId: 3,
                 username: "reader_kim", inReplyToId: 9509),
        MockNote(id: 9551, body: "@yuki_dev 이름이 경계라는 말, 오래 남을 것 같아요.",
                 createdAt: Date().addingTimeInterval(-1_200), likeCount: 0, authorId: 3,
                 username: "reader_kim", inReplyToId: 9501),
    ]
    private static var federationEnabled = true
    /// 다른 서버 계정 — 찾으면 생기고, 팔로우 요청 뒤 다시 읽으면 수락된다(마스토돈 기본 계정처럼).
    /// 알림을 끈 대화 — 목은 대화 루트 대신 누른 노트 id로 둔다.
    private static var mutedConversations: Set<Int64> = []
    private static var remoteAccounts: [Int64: [String: Any]] = [
        9810: [
            "id": Int64(9810), "acct": "carol@fosstodon.org", "username": "carol",
            "domain": "fosstodon.org", "displayName": "Carol", "avatarUrl": NSNull(),
            "url": "https://fosstodon.org/@carol", "following": false, "requested": false,
        ],
        9800: [
            "id": Int64(9800), "acct": "mina@mastodon.social", "username": "mina",
            "domain": "mastodon.social", "displayName": "Mina", "avatarUrl": NSNull(),
            "url": "https://mastodon.social/@mina", "following": true, "requested": false,
        ],
        9820: [
            "id": Int64(9820), "acct": "alice@mastodon.social", "username": "alice",
            "domain": "mastodon.social", "displayName": "Alice", "avatarUrl": NSNull(),
            "url": "https://mastodon.social/@alice", "following": false, "requested": false,
        ],
        9830: [
            "id": Int64(9830), "acct": "bob@fosstodon.org", "username": "bob",
            "domain": "fosstodon.org", "displayName": "Bob", "avatarUrl": NSNull(),
            "url": "https://fosstodon.org/@bob", "following": false, "requested": false,
        ],
    ]
    /// 팔로우한 다른 서버 계정(mina)의 노트 — 팔로잉 피드 끝과 그 계정 화면에 보인다.
    private static func remoteNoteView() -> [String: Any] {
        [
            "id": Int64(9600), "body": "Hello from the fediverse 👋 #kurl",
            "createdAt": iso(Date().addingTimeInterval(-1_800)), "editedAt": NSNull(),
            "likeCount": 2, "likedByMe": likedNotes.contains(9600),
            "author": [
                "id": -9800, "username": "mina@mastodon.social", "avatarUrl": NSNull(),
                "displayName": "Mina", "remoteId": 9800, "url": "https://mastodon.social/@mina",
            ] as [String: Any],
            "media": [] as [Any], "quotedPost": NSNull(), "inReplyToId": NSNull(),
            "replyCount": 0, "repostCount": 0, "repostedByMe": false,
            "bookmarkedByMe": bookmarkedNotes.contains(9600), "quoteCount": 0,
            "linkPreview": NSNull(), "mentions": [] as [String], "contentWarning": NSNull(),
            "sensitive": false, "pinned": false, "visibility": "public", "poll": NSNull(),
            "quotedNote": NSNull(),
        ]
    }
    private static var nextRemoteId: Int64 = 9900
    private static var federationNoticeSeen = false
    private static var shortSeq = 0

    // 리더 소셜 하이라이트 + 답글 스레드 — 본 글 리더의 칠하기·탭→스레드·메모·답글 왕복을 검증.
    // 긴 글 픽스처(blockOrder=1 문단 중간)에 메모와 답글을 미리 깔아 둔다.
    private static var highlightRows: [[String: Any]] = [
        ["id": 6001,
         "author": ["id": 2, "username": "haruka", "bio": NSNull(), "avatarUrl": NSNull()],
         "blockOrder": 1, "startOffset": 10, "endOffset": 25,
         "quote": "다시 돌아가라면 또 갈아탄다",
         "note": "이 결정에 가장 공감 — 첫 두 주 비용을 미리 알았어야 했다는 대목.",
         "createdAt": iso(Date().addingTimeInterval(-9_000))],
        // 다중 블록 — 첫 문단 중간부터 둘째 문단 머리까지 가로지른다(④-2 렌더 검증).
        ["id": 6002,
         "author": ["id": 3, "username": "reader_kim", "bio": NSNull(), "avatarUrl": NSNull()],
         "blockOrder": 1, "endBlockOrder": 2, "startOffset": 27, "endOffset": 18,
         "quote": "다만 첫 두 주에 들인 비용을 미리 알았다면, 훨씬 더 작게 시작했을 것이다. 레이어드 구조로 3년을",
         "note": NSNull(),
         "createdAt": iso(Date().addingTimeInterval(-5_000))],
        ["id": 6004,
         "author": ["id": 4, "username": "minji", "bio": NSNull(), "avatarUrl": NSNull()],
         "blockOrder": 1, "startOffset": 30, "endOffset": 51,
         "quote": "첫 두 주에 들인 비용을 미리 알았다면",
         "note": NSNull(),
         "createdAt": iso(Date().addingTimeInterval(-4_500))],
        // 내가 그은 것(author=나) — 리더에서 '내 하이라이트 삭제'를 검증할 앵커(다른 문단, 다른 테스트와
        // 무충돌). 문단 전체를 덮어(중앙 어디를 탭해도 마크에 맞게) 스크롤 위치에 덜 민감하게 한다.
        ["id": 6003,
         "author": ["id": 1, "username": myUsername, "bio": NSNull(), "avatarUrl": NSNull()],
         "blockOrder": 6, "startOffset": 0, "endOffset": 112,
         "quote": "이름이 곧 경계였다. 포트 이름을 짓다 보면 '이건 도메인이 알 바 아니다' 싶은 것이 드러난다. 그걸 바깥으로 밀어내는 게 작업의 절반이었다. 나머지 절반은 그 결정을 팀이 납득하게 만드는 일이었고.",
         "note": "포트 이름 짓기가 설계의 절반이라는 대목, 두고두고 곱씹는다.",
         "createdAt": iso(Date().addingTimeInterval(-4_000))],
    ]
    private static var highlightReplies: [Int: [[String: Any]]] = [
        6001: [
            ["id": 7001, "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
             "body": "저도요. 작게 시작했어야 했다는 데 200% 동의합니다.",
             "createdAt": iso(Date().addingTimeInterval(-7_000))],
            ["id": 7002, "author": ["id": 3, "username": "reader_kim", "bio": NSNull(), "avatarUrl": NSNull()],
             "body": "첫 두 주 비용을 어떻게 줄였는지 더 듣고 싶어요. @minji 님 팀은 어땠나요?",
             "createdAt": iso(Date().addingTimeInterval(-3_000)), "mentions": ["minji"]],
        ]
    ]
    private static var commentRows: [[String: Any]] = [
        commentRow(501, nil, "haruka", "경계를 먼저 긋는다는 말이 오래 남네요.", 86_400),
        commentRow(502, 501, "honggildong", "그 한 줄 쓰려고 두 주를 돌아왔어요.", 80_000),
        commentRow(503, nil, "minji", "포트 이름 짓는 법을 따로 글로 써 주세요.", 70_000),
        commentRow(504, nil, "sori", "레이어드에서 넘어올 때 테스트는 어떻게 옮기셨나요?", 60_000),
        commentRow(505, 504, "honggildong", "도메인부터 단위 테스트로 감싸고 어댑터는 나중에요.", 50_000),
        commentRow(506, nil, "yuki_dev", "어댑터를 바깥으로 미는 순서가 제일 와닿았어요. 저희 팀도 다음 분기에 해 보려고요.", 3_600),
        commentRow(507, 506, "reader_kim", "@yuki_dev 저희도 같은 고민이에요 — 순서를 정리한 표가 있으면 좋겠어요. @nobody_here 도요.", 1_800,
                   mentions: ["yuki_dev"]),
    ]

    private static func commentRow(
        _ id: Int, _ parent: Int?, _ username: String, _ body: String, _ ago: Double, mentions: [String] = []
    ) -> [String: Any] {
        ["id": id, "parentId": parent.map { $0 as Any } ?? NSNull(),
         "author": ["id": id, "username": username, "bio": NSNull(), "avatarUrl": NSNull()],
         "body": body, "createdAt": iso(Date().addingTimeInterval(-ago)), "likeCount": 0, "mentions": mentions]
    }
    private static var nextHighlightId = 6100
    private static var nextHighlightReplyId = 7100

    /// `--empty-feeds` = 구독함·추천을 빈 응답으로 — 빈 안내 화면 검증용.
    private static let emptyFeeds = ProcessInfo.processInfo.arguments.contains("--empty-feeds")

    private static var nextId: Int64 = 9100
    private static var likes: [Int64: (count: Int64, liked: Bool)] = [:]
    private static var bookmarks: Set<Int64> = []
    private static var follows: [String: (following: Bool, count: Int64)] = [:]
    private static var noteBells: Set<String> = []
    private static var feedLanguages: [String] = []
    private static var nextScheduledId: Int64 = 9700
    private static var scheduledNotes: [[String: Any]] = [[
        "id": Int64(9699), "scheduledAt": iso(Date().addingTimeInterval(86_400)),
        "body": "그 답글에 덧붙이려던 생각", "contentWarning": NSNull(), "visibility": "PUBLIC",
        "imageCount": 0, "poll": false, "inReplyToId": Int64(9551), "quotedNoteId": NSNull(), "quotedPostId": NSNull(), "failure": "NOTE_NOT_FOUND",
    ]]
    private static var serverBlocks: [String: (severity: String, reason: String?, at: Date)] = [
        "spam.example": ("SUSPEND", "광고 계정 대량", Date().addingTimeInterval(-86_400)),
    ]

    private static func serverBlockView(
        _ domain: String, _ block: (severity: String, reason: String?, at: Date)
    ) -> [String: Any] {
        ["domain": domain, "severity": block.severity, "reason": block.reason ?? NSNull(), "createdAt": iso(block.at)]
    }

    private static var domainBlocks: [String: Date] = {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "--domain-block"), at + 1 < args.count else { return [:] }
        return [args[at + 1]: Date()]
    }()
    private static var subscriptions: [Int64: (subscribed: Bool, count: Int64)] = [:]
    private static var followedTags: Set<String> = ["아키텍처", "스프링", "리팩터링", "디자인", "kurl"]
    private static var hiddenTags: Set<String> = []
    // 알림 종류별 켬/끔 — 하나 꺼둔 채로 시작해 화면이 섞인 상태를 바로 보여준다(기본은 켜짐).
    private static var blogNotificationPrefs: [String: Bool] = [
        "LIKE": true, "COMMENT": true, "REPLY": true, "MENTION": true,
        "FOLLOW": true, "SERIES_SUBSCRIBE": true, "NEW_POST": false,
        "CONNECTED": true, "PATH_GREW": true,
    ]
    private static var myBio = "경계를 긋는 사람. 헥사고날·도메인 모델링."
    private static var displayNames: [String: String] = ["reader_kim": "김독자"]
    private static var myHideFollowerCount = false
    /// 내 계정은 팔로우를 직접 승인한다 — 이 서버 회원 하나와 다른 서버 계정 하나가 기다린다.
    private static var myLocked = true
    private static var memberRequests: [(username: String, displayName: String?, at: Date)] = [
        ("sori", "소리", Date().addingTimeInterval(-1_200)),
    ]
    private static var remoteRequests: [Int64: Date] = [9810: Date().addingTimeInterval(-3_600)]
    /// 팔로우를 직접 승인하는 작가와, 그 작가에게 보낸 요청.
    private static let lockedAuthors: Set<String> = ["haneul"]
    private static var sentRequests: Set<String> = []
    private static var dismissedSuggestions: Set<String> = []
    /// 지난 가져오기 하나 — 다른 서버에서 옮겨 온 팔로우.
    private static var accountImports: [[String: Any]] = [
        ["id": Int64(31), "kind": "FOLLOWING", "total": 120, "processed": 120, "imported": 116,
         "finished": true, "createdAt": iso(Date().addingTimeInterval(-86_400))],
    ]
    /// 알림 거르기 — 팔로우하지 않는 사람은 거르게 해 두었고, 두 사람의 알림이 걸러져 있다.
    private static var notificationPolicy: [String: String] = [
        "forNotFollowing": "FILTER", "forNotFollowers": "ACCEPT", "forNewAccounts": "ACCEPT",
        "forPrivateMentions": "FILTER",
    ]
    private static var filteredSenders: [[String: Any]] = [
        ["actorUserId": Int64(9301), "actorRemoteId": NSNull(), "username": "promo_bot", "avatarUrl": NSNull(),
         "profileUrl": NSNull(), "count": 3, "lastAt": iso(Date().addingTimeInterval(-1_500))],
        ["actorUserId": NSNull(), "actorRemoteId": Int64(9800), "username": "mina@mastodon.social",
         "avatarUrl": NSNull(), "profileUrl": "https://mastodon.social/@mina", "count": 1,
         "lastAt": iso(Date().addingTimeInterval(-7_200))],
    ]
    private static var myUsername = "honggildong"

    // MARK: 긴 글 픽스처

    /// 읽기 표면(목차·읽기 진행·블록 렌더)을 제대로 보려면 타입이 다양한 긴 글이 필요하다.
    /// 회고·튜토리얼·릴리스 노트·디버깅 — 장르도, 블록 타입(헤딩/코드/이미지/인용/목록/표/구분선/CTA)도
    /// 두루 쓴다. 공개 작가 글 목록·상세가 이 배열을 소스로 슬러그로 찾아 돌려준다.
    private struct MockArticle {
        let slug: String
        let title: String
        let excerpt: String
        let tags: [String]
        let likeCount: Int
        let daysAgo: Double
        let blocks: [[String: Any]]
    }

    private static func mockCode(_ lang: String, _ code: String) -> String {
        (try? JSONSerialization.data(withJSONObject: ["lang": lang, "code": code]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? code
    }

    private static func mockImage(_ url: String, _ caption: String) -> String {
        (try? JSONSerialization.data(withJSONObject: ["url": url, "caption": caption]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? url
    }

    private static func mockList(_ items: [String]) -> String {
        (try? JSONSerialization.data(withJSONObject: items))
            .flatMap { String(data: $0, encoding: .utf8) } ?? items.joined(separator: "\n")
    }

    /// blockOrder 를 인덱스로 자동 부여 — 작성할 땐 순서만 신경 쓰면 된다.
    private static func ordered(_ raw: [[String: Any]]) -> [[String: Any]] {
        raw.enumerated().map { i, b in
            var x = b
            x["blockOrder"] = i
            return x
        }
    }

    private static let articles: [MockArticle] = [
        // 1) 회고 에세이 — 산문 위주 + 인용·목록·구분선.
        MockArticle(
            slug: "hexagonal-after-3-months",
            title: "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
            excerpt: "레이어드를 버린 결정의 회고 — 경계가 준 것과 가져간 것.",
            tags: ["아키텍처", "회고"], likeCount: 42, daysAgo: 2,
            blocks: ordered([
                ["type": "H1", "content": "헥사고날로 갈아탄 지 석 달"],
                ["type": "PARAGRAPH", "content":
                    "결론부터 적는다. 다시 돌아가라면 또 갈아탄다. 다만 첫 두 주에 들인 비용을 미리 알았다면, 훨씬 더 작게 시작했을 것이다."],
                ["type": "PARAGRAPH", "content":
                    "레이어드 구조로 3년을 버텼다. 컨트롤러-서비스-리포지토리, 익숙한 삼층. 문제는 코드가 늘면서 '서비스'가 만물상이 된 거였다. 도메인 규칙과 트랜잭션 경계와 외부 API 호출이 한 클래스에 뒤섞였고, 단위 테스트 한 줄을 돌리려고 스프링 컨텍스트를 통째로 띄우고 있었다."],
                ["type": "QUOTE", "content": "경계가 없으면 모든 변경이 전역 변경이 된다."],
                ["type": "H2", "content": "포트를 먼저 그었다"],
                ["type": "PARAGRAPH", "content":
                    "어댑터부터 짜고 싶은 충동을 눌렀다. 도메인이 바깥에 무엇을 기대하는지 — 그 인터페이스(포트)부터 이름을 지었다. `PublishedPostReader`, `ProfileCacheInvalidator` 처럼."],
                ["type": "PARAGRAPH", "content":
                    "이름이 곧 경계였다. 포트 이름을 짓다 보면 '이건 도메인이 알 바 아니다' 싶은 것이 드러난다. 그걸 바깥으로 밀어내는 게 작업의 절반이었다. 나머지 절반은 그 결정을 팀이 납득하게 만드는 일이었고."],
                ["type": "H2", "content": "무엇이 좋아졌나"],
                ["type": "LIST_BULLET", "content": mockList([
                    "도메인 단위 테스트가 컨텍스트 없이 밀리초 단위로 돈다.",
                    "DB를 MySQL에서 다른 것으로 바꾸는 상상이 더는 무섭지 않다 — 어댑터 하나의 일이니까.",
                    "리뷰가 빨라졌다. PR이 어느 층의 변경인지 디렉토리만 봐도 보인다.",
                ])],
                ["type": "H3", "content": "그리고 가져간 것"],
                ["type": "PARAGRAPH", "content":
                    "공짜는 없었다. 파일 수가 늘었고, 작은 기능 하나에도 포트·어댑터·도메인 세 곳을 건드려야 한다. 신입에게 '왜 이렇게까지 해야 하느냐'를 설명하는 시간도 함께 늘었다."],
                ["type": "DIVIDER"],
                ["type": "PARAGRAPH", "content":
                    "그래서 권하는 건 전면 전환이 아니라 '가장 아픈 슬라이스부터'다. 가장 자주 바뀌고 가장 테스트하기 싫은 모듈 하나를 골라, 거기서만 경계를 그어 보라. 석 달 전의 나에게 해주고 싶은 말이다."],
            ])),

        // 2) 튜토리얼 — 코드·인라인코드·이미지·번호목록·표·인용 전부.
        MockArticle(
            slug: "liquid-glass-without-glass-on-glass",
            title: "Liquid Glass, 유리 위에 유리를 얹지 않기",
            excerpt: "iOS 26 글래스 효과를 쓰며 정한 한 가지 규칙과 그 코드.",
            tags: ["iOS", "SwiftUI"], likeCount: 28, daysAgo: 5,
            blocks: ordered([
                ["type": "H1", "content": "유리 위에 유리를 얹지 않기"],
                ["type": "PARAGRAPH", "content":
                    "Liquid Glass는 강력하다. 하지만 한 화면에 유리를 두 겹 겹치는 순간 둘 다 탁해진다. 우리가 정한 규칙은 한 문장이다 — 한 영역에 유리는 하나."],
                ["type": "H2", "content": "기본형"],
                ["type": "PARAGRAPH", "content":
                    "버튼 하나에 캡슐 유리를 입히는 건 `glassEffect(_:in:)` 한 줄이면 된다."],
                ["type": "CODE", "content": mockCode("swift", """
                Button("구독") { subscribe() }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
                """)],
                ["type": "PARAGRAPH", "content":
                    "`.interactive()`는 눌렀을 때 유리가 살짝 반응하게 한다. 빼면 정적인 유리가 된다."],
                ["type": "H2", "content": "겹치면 생기는 일"],
                ["type": "PARAGRAPH", "content":
                    "유리 패널 안에 또 유리 버튼을 넣으면 뒤 배경을 두 번 샘플링해 대비가 무너진다. 패널은 유리로, 그 안의 주행동은 솔리드로 둔다."],
                ["type": "CODE", "content": mockCode("swift", """
                // 패널은 유리
                VStack { content }
                    .glassEffect(.regular, in: .rect(cornerRadius: Metrics.radius))

                // 그 안의 주행동은 솔리드 캡슐 — 유리 위 유리 금지
                Button("계속") { go() }
                    .background(Palette.accent, in: .capsule)
                """)],
                ["type": "PARAGRAPH", "content":
                    "여러 유리가 한 무리로 움직여야 한다면 `GlassEffectContainer`로 묶는다. 닿을 때 서로 녹아 붙는 모션은 컨테이너가 만든다."],
                ["type": "IMAGE", "content": mockImage(
                    "https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=1200&q=80",
                    "유리 카드가 떠 보이려면 뒤에 흐르는 무언가가 있어야 한다.")],
                ["type": "H3", "content": "체크리스트"],
                ["type": "LIST_NUMBERED", "content": mockList([
                    "한 영역에 유리는 하나인가?",
                    "유리 패널 안의 주행동은 솔리드인가?",
                    "한 무리로 움직이는 유리는 컨테이너로 묶었나?",
                    "어두운 배경 위 흰 글자의 대비는 충분한가?",
                ])],
                ["type": "H2", "content": "언제 쓰지 말까"],
                ["type": "TABLE", "content": """
                | 상황 | 유리 | 대안 |
                | 본문 카드 | X | 종이(solid) |
                | 떠 있는 액션 | O | — |
                | 내비바 위 알약 | O | — |
                | 긴 목록 행 | X | hairline 구분 |
                """],
                ["type": "QUOTE", "content": "유리는 뒤에 흐르는 것이 있을 때만 유리다."],
            ])),

        // 3) 릴리스 노트 — 짧은 섹션 + 목록 + CTA.
        MockArticle(
            slug: "kurl-2-4-release-notes",
            title: "kurl 2.4 — 읽기 진행, 구독함, 그리고 조용한 것들",
            excerpt: "이번 업데이트에서 더하고 고친 것들.",
            tags: ["릴리스노트"], likeCount: 15, daysAgo: 1,
            blocks: ordered([
                ["type": "H1", "content": "kurl 2.4"],
                ["type": "PARAGRAPH", "content":
                    "이번 판은 '읽는 사람'을 위한 것이다. 쓰는 도구는 다음 판에서 손본다."],
                ["type": "H2", "content": "새로운 것"],
                ["type": "LIST_BULLET", "content": mockList([
                    "**읽기 진행** — 글을 스크롤하면 상단에 얇은 막대가 찬다. 완독하면 마크가 한 번 톡 튄다.",
                    "**구독함** — 팔로우한 작가와 구독한 시리즈의 새 글이 한 피드로 모인다.",
                    "**태그 구독** — 관심 태그의 새 글을 구독함으로 흘려보낸다.",
                ])],
                ["type": "H2", "content": "고친 것"],
                ["type": "LIST_BULLET", "content": mockList([
                    "글을 쓰다 가끔 로그아웃되던 문제(새로고침 회전 레이스)를 잡았다.",
                    "무커버 글 상단에 투명한 박스가 떠 보이던 것을 없앴다.",
                    "다크 모드에서 코드 블록 대비를 높였다.",
                ])],
                ["type": "H2", "content": "다음"],
                ["type": "PARAGRAPH", "content":
                    "모바일 글쓰기를 노션처럼 — 버튼을 누르면 본문에 바로 반영되는 WYSIWYG로 바꾸는 작업을 하고 있다."],
                ["type": "CTA_REF", "cta": [
                    "label": "웹에서 전체 변경 보기",
                    "url": "https://kurl.me/blog/release-2-4",
                    "deleted": false,
                ]],
            ])),

        // 4) 디버깅 딥다이브 — 로그 코드블록·인용·번호목록·표·구분선.
        MockArticle(
            slug: "the-night-tokens-vanished",
            title: "토큰이 사라진 밤 — 새로고침 회전 레이스를 쫓다",
            excerpt: "글을 쓰다 로그아웃되는 버그. 범인은 회전하는 리프레시 토큰이었다.",
            tags: ["디버깅", "인증"], likeCount: 67, daysAgo: 9,
            blocks: ordered([
                ["type": "H1", "content": "토큰이 사라진 밤"],
                ["type": "PARAGRAPH", "content":
                    "제보는 늘 같았다. '글 쓰다가 갑자기 로그아웃됐어요.' 그런데 재현이 안 됐다. 서버 로그에도 이렇다 할 에러가 없었다."],
                ["type": "PARAGRAPH", "content":
                    "단서는 둘이었다. 첫째, 블로그 글쓰기에서만 났다. 둘째, 늘 한참 쓰던 중에 났다 — 즉 토큰이 한 번은 갱신될 만큼 시간이 지난 뒤였다."],
                ["type": "QUOTE", "content": "재현이 안 되는 버그는 대개 타이밍 버그다."],
                ["type": "H2", "content": "회전하는 리프레시 토큰"],
                ["type": "PARAGRAPH", "content":
                    "우리는 보안을 위해 리프레시 토큰을 1회용으로 굴린다(rotating refresh). 갱신할 때마다 새 토큰을 발급하고 옛 토큰은 폐기한다. 문제는 '거의 동시에 두 번 갱신'이 일어날 때다."],
                ["type": "CODE", "content": mockCode("text", """
                12:04:01.221  POST /auth/refresh  rt=…a91  -> 200  new rt=…4d2
                12:04:01.233  POST /auth/refresh  rt=…a91  -> 401  (already rotated)
                12:04:01.235  wipe session: refresh failed
                """)],
                ["type": "PARAGRAPH", "content":
                    "두 요청이 같은 옛 토큰(`…a91`)으로 거의 동시에 출발했다. 먼저 도착한 쪽이 회전에 성공했고, 12밀리초 뒤 도착한 둘째는 '이미 회전됨' 401을 받았다. 그리고 우리 코드는 그 401을 '세션 죽음'으로 해석해 전부 지워 버렸다."],
                ["type": "H2", "content": "고친 방법"],
                ["type": "LIST_NUMBERED", "content": mockList([
                    "갱신을 single-flight로 — 동시에 터진 401들은 진행 중인 회전 하나를 기다린다.",
                    "방금 회전된 토큰에는 짧은 유예(grace)를 둬, 경합에서 진 요청도 새 토큰을 받게 했다.",
                    "'세션 죽음' 판정을 리프레시 자체의 401로만 좁혔다.",
                ])],
                ["type": "TABLE", "content": """
                | 항목 | 전 | 후 |
                | 동시 갱신 | 각자 회전 시도 | 하나만 회전, 나머지 대기 |
                | 경합에서 진 요청 | 세션 wipe | grace로 새 토큰 |
                | 로그아웃 제보 | 주 3~4건 | 0건 |
                """],
                ["type": "H3", "content": "남은 교훈"],
                ["type": "PARAGRAPH", "content":
                    "보안 기능(토큰 회전)이 가용성 버그(로그아웃)를 낳았다. 둘은 자주 충돌한다. 그 사이를 메우는 게 grace 같은 작은 완충 장치다."],
                ["type": "DIVIDER"],
                ["type": "PARAGRAPH", "content":
                    "그날 밤 이후로 '재현 안 됨'이라는 말이 덜 무섭다. 안 되는 게 아니라, 우리가 타이밍을 못 맞춘 것뿐이니까."],
            ])),
    ]

    // MARK: 컬렉션(연결 그래프) 목 상태

    struct MockConnection {
        let id: Int64
        let blockType: String
        let why: String?
        var title: String?
        var excerpt: String?
        var slug: String?
        var username: String?
        var quote: String?
        var body: String?
        /// 이 연결이 가리키는 블록 id — 연결 시트가 "이 블록 담긴 곳"을 물을 때(blockType·refId) 대조한다.
        /// 표시용 목 연결은 대부분 nil 이고, 담김 표시를 확인할 씨앗 연결·새로 연결한 것만 채운다.
        var refId: Int64?
    }
    struct MockCollection {
        let id: Int64
        var title: String
        var description: String?
        var visibility: String
        var kind: String = "COLLECTION"
        /// nil 이면 응답에 ordered 를 싣지 않는다 — ordered 를 모르는 서버 모양(옛 kind 로 읽기)을 보인다.
        var ordered: Bool? = nil
        var connections: [MockConnection]
    }

    static var collections: [MockCollection] = [
        MockCollection(
            id: 101, title: "느린 사고", description: "빨리 답하지 않고 오래 머문 글들.", visibility: "PUBLIC",
            ordered: false,
            connections: [
                // 씨앗 연결 — 목 글 9101(헥사고날)이 이 컬렉션에 이미 담겨 있다(refId 9101). 연결 시트를
                // 이 글로 열면 "연결됨"으로 뜨고, "해제"를 누르면 이 연결이 지워진다.
                MockConnection(
                    id: 504, blockType: "POST", why: "결론부터 적는 글. 다시 읽어도 같은 문장에 밑줄 친다.",
                    title: "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
                    excerpt: "결론부터 적는다. 다시 돌아가라면 또 갈아탄다.",
                    slug: "hexagonal-after-3-months", username: "honggildong", refId: 9101),
                MockConnection(
                    id: 501, blockType: "HIGHLIGHT", why: "추상이 먼저가 아니라 경계가 먼저라는 한 문장. 여기서 시작.",
                    title: "헥사고날로 갈아탄 지 석 달", slug: "hexagonal-after-3-months",
                    username: "honggildong", quote: "경계를 먼저 긋고, 구현은 그 바깥으로 민다."),
                MockConnection(
                    id: 502, blockType: "POST", why: "더 지울 게 없을 때 완성된다 — 느린 사고의 다른 얼굴.",
                    title: "토큰이 사라진 밤", excerpt: "디자인 토큰을 지웠더니 오히려 화면이 선명해졌다.",
                    slug: "the-night-tokens-vanished", username: "honggildong"),
                MockConnection(
                    id: 503, blockType: "NOTE", why: nil, username: "yuki_dev",
                    body: "결정을 미루는 건 게으름이 아니라, 더 나은 질문을 기다리는 일일 때가 있다.", refId: 9501),
            ]),
        MockCollection(
            id: 102, title: "경계 긋기", description: "도메인·관계·코드에서 선을 긋는 법.", visibility: "PRIVATE",
            connections: [
                MockConnection(
                    id: 511, blockType: "POST", why: "레이어의 경계 = 관심사의 경계.",
                    title: "유리 위에 유리를 얹지 않기", excerpt: "겹치는 순간 둘 다 탁해진다. 레이어는 하나씩.",
                    slug: "liquid-glass-without-glass-on-glass", username: "honggildong"),
            ]),
        MockCollection(
            id: 103, title: "다시 읽고 싶은", description: nil, visibility: "UNLISTED",
            connections: [
                MockConnection(
                    id: 521, blockType: "NOTE", why: nil,
                    body: "좋은 글은 두 번째 읽을 때 다른 문장이 밑줄 쳐진다."),
            ]),
        // PATH(reading path) — 여러 글의 문장을 가로질러 하나의 논증으로 엮는다. why 가 문장과 문장을 잇는 흐름.
        // 인용은 실제 목 글 블록에 있는 문장이라 탭하면 그 지점으로 딥링크된다.
        MockCollection(
            id: 104, title: "경계를 긋는다는 것", description: "왜 경계가 먼저인가 — 세 문장으로.",
            visibility: "PUBLIC", kind: "PATH", ordered: true,
            connections: [
                MockConnection(
                    id: 531, blockType: "HIGHLIGHT", why: "출발은 늘 여기다 — 경계가 없으면 변경이 전역이 된다.",
                    title: "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
                    slug: "hexagonal-after-3-months", username: "honggildong",
                    quote: "경계가 없으면 모든 변경이 전역 변경이 된다."),
                MockConnection(
                    id: 532, blockType: "HIGHLIGHT", why: "그 경계를 긋느라 갈아탔고, 후회는 없다.",
                    title: "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
                    slug: "hexagonal-after-3-months", username: "honggildong",
                    quote: "다시 돌아가라면 또 갈아탄다"),
                MockConnection(
                    id: 533, blockType: "HIGHLIGHT", why: "경계가 약하면 결국 타이밍이 샌다 — 같은 이야기의 다른 얼굴.",
                    title: "토큰이 사라진 밤",
                    slug: "the-night-tokens-vanished", username: "honggildong",
                    quote: "재현이 안 되는 버그는 대개 타이밍 버그다."),
            ]),
    ]
    static var nextCollectionId: Int64 = 110
    static var nextConnectionId: Int64 = 600

    /// 옵셔널 문자열을 JSON 값으로 — nil 은 NSNull(JSONSerialization 호환).
    private static func orNull(_ v: String?) -> Any { v.map { $0 as Any } ?? NSNull() }

    private static func curator(_ id: Int64, _ username: String) -> [String: Any] {
        ["id": id, "username": username, "bio": NSNull(), "avatarUrl": NSNull()]
    }

    /// 공개 연결 흐름 목 — 비로그인 첫 피드에 인터리브할 최근 공개 연결. 세 실루엣(글·하이라이트·노트)이
    /// 번갈아 오도록 6개, 큐레이터의 산문 why 를 붙여 알고리즘이 아니라 사람의 큐레이션임이 드러나게.
    private static func publicConnectionFeedMock() -> [[String: Any]] {
        [
            [
                "id": 11, "curator": curator(2, "minji"),
                "collectionId": 101, "collectionTitle": "느린 사고",
                "why": "빨리 답하지 않고 오래 머문 글. 세 번째 읽을 때 다른 문장이 밑줄 쳐졌다.",
                "connectedAt": iso(Date().addingTimeInterval(-1_800)),
                "blockType": "POST", "title": "헥사고날로 갈아탄 지 석 달",
                "excerpt": "결론부터 적는다. 다시 돌아가라면 또 갈아탄다.",
                "slug": "hexagonal-after-3-months", "username": "honggildong",
                "quote": NSNull(), "body": NSNull(),
            ],
            [
                "id": 12, "curator": curator(3, "sori"),
                "collectionId": 104, "collectionTitle": "경계를 긋는다는 것",
                "collectionKind": "PATH", "collectionOrdered": true,
                "why": "이 문장 하나로 설계 얘기를 시작하곤 한다. 출발점으로 엮어 둔다.",
                "connectedAt": iso(Date().addingTimeInterval(-9_000)),
                "blockType": "HIGHLIGHT", "title": "헥사고날로 갈아탄 지 석 달",
                "excerpt": NSNull(), "slug": "hexagonal-after-3-months",
                "username": "honggildong",
                "quote": "경계가 없으면 모든 변경이 전역 변경이 된다.", "body": NSNull(),
            ],
            [
                "id": 13, "curator": curator(2, "minji"),
                "collectionId": 103, "collectionTitle": "다시 읽고 싶은",
                "why": NSNull(),
                "connectedAt": iso(Date().addingTimeInterval(-43_200)),
                "blockType": "NOTE", "title": NSNull(), "excerpt": NSNull(),
                "slug": NSNull(), "username": NSNull(), "quote": NSNull(),
                "body": "결정을 미루는 건 게으름이 아니라, 더 나은 질문을 기다리는 일일 때가 있다.",
            ],
            [
                "id": 14, "curator": curator(3, "sori"),
                "collectionId": 102, "collectionTitle": "경계 긋기",
                "why": "레이어링을 관심사 분리로 읽어낸 글. 코드에도 그대로 옮겨 적는다.",
                "connectedAt": iso(Date().addingTimeInterval(-86_400)),
                "blockType": "POST", "title": "유리 위에 유리를 얹지 않기",
                "excerpt": "겹치는 순간 둘 다 탁해진다. 레이어는 하나씩.",
                "slug": "liquid-glass-without-glass-on-glass", "username": "honggildong",
                "quote": NSNull(), "body": NSNull(),
            ],
            [
                "id": 15, "curator": curator(2, "minji"),
                "collectionId": 104, "collectionTitle": "경계를 긋는다는 것",
                "collectionKind": "PATH",
                "why": "재현 안 되는 버그 앞에서 나도 늘 이 문장을 떠올린다.",
                "connectedAt": iso(Date().addingTimeInterval(-172_800)),
                "blockType": "HIGHLIGHT", "title": "토큰이 사라진 밤",
                "excerpt": NSNull(), "slug": "the-night-tokens-vanished",
                "username": "honggildong",
                "quote": "재현이 안 되는 버그는 대개 타이밍 버그다.", "body": NSNull(),
            ],
            [
                "id": 16, "curator": curator(3, "sori"),
                "collectionId": 103, "collectionTitle": "다시 읽고 싶은",
                "why": NSNull(),
                "connectedAt": iso(Date().addingTimeInterval(-259_200)),
                "blockType": "NOTE", "title": NSNull(), "excerpt": NSNull(),
                "slug": NSNull(), "username": NSNull(), "quote": NSNull(),
                "body": "좋은 글은 두 번째 읽을 때 다른 문장이 밑줄 쳐진다.",
            ],
        ]
    }

    /// connectedRefId 를 주면(연결 시트 조회) 그 블록이 이 컬렉션에 이미 담겼는지 보고 담겼으면 그 연결
    /// id 를 connectionId 로 싣는다 — "연결됨" 표시·해제용. 아니면 nil 로 빠져 평소 목록과 같다.
    private static func collectionSummary(
        _ c: MockCollection, connectedRefId: Int64? = nil
    ) -> [String: Any] {
        // 최근 2개 항목 라벨 — 백엔드 preview 와 동일(POST 제목·HIGHLIGHT 인용·NOTE 본문).
        let preview = c.connections.suffix(2).reversed().compactMap { conn -> String? in
            switch conn.blockType {
            case "NOTE": return conn.body
            case "HIGHLIGHT": return conn.quote
            default: return conn.title
            }
        }
        var out: [String: Any] = [
            "id": c.id, "title": c.title,
            "description": orNull(c.description),
            "visibility": c.visibility, "kind": c.kind, "count": c.connections.count,
            "updatedAt": iso(Date()), "preview": Array(preview),
        ]
        if let ordered = c.ordered { out["ordered"] = ordered }
        if let refId = connectedRefId,
           let conn = c.connections.first(where: { $0.refId == refId }) {
            out["connectionId"] = conn.id
        }
        return out
    }

    /// 시리즈 회차 픽스처 — ep-1…ep-6. 회차 nav(position/total/prev/next)를 slug 로 계산해
    /// "끝에서 이어 당기기"·배너 이전/다음·마지막 회차 폴백을 결정론적으로 검증한다.
    private static let episodeTitles = [
        "포트와 어댑터", "도메인을 안으로", "의존성 뒤집기",
        "어댑터 구현", "테스트 전략", "마이그레이션",
    ]

    private static func seriesEpisodeNav(slug: String) -> [String: Any]? {
        guard slug.hasPrefix("ep-"), let n = Int(slug.dropFirst(3)),
              n >= 1, n <= episodeTitles.count else { return nil }
        let i = n - 1
        func link(_ idx: Int) -> [String: Any] {
            ["slug": "ep-\(idx + 1)", "title": episodeTitles[idx]]
        }
        var nav: [String: Any] = [
            "slug": "hexagonal", "title": "헥사고날 전환기",
            "position": n, "total": episodeTitles.count,
        ]
        nav["prev"] = i > 0 ? link(i - 1) : NSNull()
        nav["next"] = i < episodeTitles.count - 1 ? link(i + 1) : NSNull()
        // 글·노트를 함께 센 자리 — 4편과 5편 사이에 노트(9540)가 한 편 든다.
        let items = seriesItems
        guard let at = items.firstIndex(where: { ($0["slug"] as? String) == slug }) else { return nav }
        nav["itemPosition"] = at + 1
        nav["itemTotal"] = items.count
        nav["prevItem"] = at > 0 ? items[at - 1] : NSNull()
        nav["nextItem"] = at < items.count - 1 ? items[at + 1] : NSNull()
        return nav
    }

    /// 시리즈의 글·노트 순서(이웃 링크 모양) — 글 내비·노트 내비가 같은 순서를 읽는다.
    private static var seriesItems: [[String: Any]] {
        var items: [[String: Any]] = episodeTitles.enumerated().map { i, title in
            ["type": "POST", "slug": "ep-\(i + 1)", "noteId": NSNull(), "title": title]
        }
        items.insert(["type": "NOTE", "slug": NSNull(), "noteId": 9540, "title": seriesNoteExcerpt], at: 4)
        return items
    }

    private static let seriesNoteExcerpt = "4편을 쓰고 남은 메모. 어댑터를 갈아 끼우던 날, 실패한 테스트가 먼저 경계를 알려 줬다."

    /// 노트 상세의 시리즈 자리(9540 만).
    private static func noteSeriesTrail(_ noteId: Int64) -> Any {
        guard noteId == 9540 else { return NSNull() }
        let items = seriesItems
        return [
            "slug": "hexagonal", "title": "헥사고날 전환기", "position": 5, "total": items.count,
            "prev": items[3], "next": items[5],
        ] as [String: Any]
    }

    /// 회차 본문 — 화면보다 길어야 스크롤·오버스크롤 당김이 성립한다(문단 여럿).
    private static func episodeBlocks(slug: String) -> [[String: Any]] {
        let n = Int(slug.dropFirst(3)) ?? 1
        let idx = min(max(n - 1, 0), episodeTitles.count - 1)
        let title = episodeTitles[idx]
        return ordered([
            ["type": "H1", "content": "\(n)편 — \(title)"],
            ["type": "PARAGRAPH", "content": "이 회차는 시리즈 '헥사고날 전환기'의 \(n)번째 글이다. 끝까지 읽고 위로 더 당기면 다음 편이 아래에서 딸려 올라온다."],
            ["type": "PARAGRAPH", "content": "레이어드 구조로 3년을 버텼다. 컨트롤러-서비스-리포지토리, 익숙한 삼층. 문제는 코드가 늘면서 '서비스'가 만물상이 된 거였다. 도메인 규칙과 트랜잭션 경계와 외부 API 호출이 한 클래스에 뒤섞였고, 단위 테스트 한 줄을 돌리려고 스프링 컨텍스트를 통째로 띄우고 있었다."],
            ["type": "H2", "content": "경계를 먼저"],
            ["type": "PARAGRAPH", "content": "어댑터부터 짜고 싶은 충동을 눌렀다. 도메인이 바깥에서 무엇을 기대하는지 — 그 인터페이스(포트)부터 이름을 지었다. 이름이 곧 경계였다. 포트 이름을 짓다 보면 '이건 도메인이 알 바 아니다' 싶은 것이 드러난다."],
            ["type": "QUOTE", "content": "경계가 없으면 모든 변경이 전역 변경이 된다."],
            ["type": "PARAGRAPH", "content": "그걸 바깥으로 밀어내는 게 작업의 절반이었다. 나머지 절반은 그 결정을 팀이 납득하게 만드는 일이었고. 세 달이 지난 지금, 다시 돌아가라면 또 갈아탄다."],
            ["type": "PARAGRAPH", "content": "다만 첫 두 주에 들인 비용을 미리 알았다면, 훨씬 더 작게 시작했을 것이다. 가장 아픈 슬라이스부터, 거기서만 경계를 그어 보라. 석 달 전의 나에게 해주고 싶은 말이다."],
        ])
    }

    /// 카드 소속 배치 목 — 잘 알려진 목 피드 글 id 에 소속 공개 컬렉션을 매핑한다. 한 컬렉션(단수 카피)과
    /// 여러 컬렉션(복수 "외 N개") 두 경우를 다 그려 보이게 섞는다. 소속 없는 글은 여기 없다(호출측은 빈 배열).
    private static func postCollectionsMock() -> [[String: Any]] {
        // 리치 소속(#607) — 큐레이터·순서(position/total)까지. 순서 있는 것은 "N편 중 M번째"로,
        // collection 은 큐레이터만(순서 없음). curator 없는 것도 하나 섞어 count 폴백을 확인.
        func c(_ id: Int64, _ title: String, _ kind: String, _ count: Int, _ preview: [String],
               curator: String? = nil, position: Int? = nil, total: Int? = nil,
               ordered: Bool? = nil) -> [String: Any] {
            var d: [String: Any] = [
                "id": id, "title": title, "description": NSNull(),
                "visibility": "PUBLIC", "kind": kind, "count": count,
                "updatedAt": iso(Date()), "preview": preview,
            ]
            if let ordered { d["ordered"] = ordered }
            d["curatorUsername"] = curator.map { $0 as Any } ?? NSNull()
            d["position"] = position.map { $0 as Any } ?? NSNull()
            d["total"] = total.map { $0 as Any } ?? NSNull()
            return d
        }
        return [
            // 여러 컬렉션에 걸린 글 — 순서 있음(자리 앎)·순서 없음(큐레이터만)·큐레이터 없는 것 섞음.
            ["postId": 8201, "collections": [
                c(104, "다시 읽는 아키텍처", "PATH", 5, ["레이어드의 값", "의존 방향 뒤집기"],
                  curator: "minji", position: 2, total: 4, ordered: true),
                c(101, "경계를 긋는 법", "COLLECTION", 12, ["헥사고날로 갈아탄 지 석 달", "포트 이름 짓기"],
                  curator: "sori", ordered: false),
                c(107, "회고 모음", "COLLECTION", 8, []),
            ]],
            // 한 컬렉션에만 걸린 글 — 단수 카피.
            ["postId": 9101, "collections": [
                c(101, "경계를 긋는 법", "COLLECTION", 12, ["헥사고날로 갈아탄 지 석 달"], curator: "sori"),
            ]],
            ["postId": 9102, "collections": [
                c(112, "디버깅 야간 로그", "COLLECTION", 6, ["토큰이 사라진 밤"], curator: "minji"),
                c(104, "다시 읽는 아키텍처", "PATH", 5, [], curator: "minji", position: 3, total: 5),
            ]],
            ["postId": 9002, "collections": [
                c(101, "경계를 긋는 법", "COLLECTION", 12, []),
            ]],
        ]
    }

    /// "이어진 것" 목 — 이 글과 같은 공개 컬렉션에 나란히 엮인 다른 블록(공동 등장 큰 순). 세 실루엣
    /// (글·하이라이트·노트)이 다 나오게 섞어 본문 끝 PostEdges 가 실제로 어떻게 서는지 보이게 한다.
    private static func relatedBlocksMock() -> [[String: Any]] {
        [
            [
                "blockType": "POST", "refId": 8102, "sharedCount": 4,
                "title": "유리 위에 유리를 얹지 않기",
                "excerpt": "겹치는 순간 둘 다 탁해진다. 레이어는 하나씩.",
                "slug": "liquid-glass-without-glass-on-glass", "username": "honggildong",
                "quote": NSNull(), "body": NSNull(),
            ],
            [
                "blockType": "HIGHLIGHT", "refId": 7301, "sharedCount": 2,
                "title": "토큰이 사라진 밤",
                "excerpt": NSNull(),
                "slug": "the-night-tokens-vanished", "username": "honggildong",
                "quote": "재현이 안 되는 버그는 대개 타이밍 버그다.", "body": NSNull(),
            ],
        ]
    }

    /// "이 글을 엮은 사람" 목 — 같은 것을 자기 공개 컬렉션에도 엮은 취향 겹치는 큐레이터(겹침 큰 순).
    private static func kindredCuratorsMock() -> [[String: Any]] {
        [
            [
                "curator": [
                    "id": 2, "username": "minji",
                    "bio": "경계와 느린 사고에 관해 씁니다.", "avatarUrl": NSNull(),
                ],
                "sharedItems": 6,
            ],
            [
                "curator": [
                    "id": 3, "username": "sori",
                    "bio": NSNull(), "avatarUrl": NSNull(),
                ],
                "sharedItems": 4,
            ],
        ]
    }

    private static func collectionDetail(_ c: MockCollection) -> [String: Any] {
        var out: [String: Any] = [
            "id": c.id, "title": c.title,
            "description": orNull(c.description),
            "visibility": c.visibility, "kind": c.kind, "curatorUsername": myUsername,
            "connections": c.connections.map { conn in
                [
                    "id": conn.id, "blockType": conn.blockType,
                    "why": orNull(conn.why), "connectedAt": iso(Date()),
                    "title": orNull(conn.title), "excerpt": orNull(conn.excerpt),
                    "slug": orNull(conn.slug), "username": orNull(conn.username),
                    "quote": orNull(conn.quote), "body": orNull(conn.body),
                    "noteId": conn.blockType == "NOTE" ? (conn.refId.map { $0 as Any } ?? NSNull()) : NSNull(),
                ]
            },
        ]
        if let ordered = c.ordered { out["ordered"] = ordered }
        return out
    }

    // MARK: 라우팅

    /// 처리하면 응답 바디, 아니면 nil → 실네트워크로.
    /// query = 실 클라이언트가 붙인 쿼리 항목(연결 시트의 blockType/refId 같은 것) — 경로만으로 못 가르는
    /// 응답 형태를 여기서 가른다.
    static func respond(
        path: String, method: String, query: [URLQueryItem]? = nil, body: Data?
    ) throws -> Data? {
        let parts = path.split(separator: "/").map(String.init)

        if method == "GET", parts == ["public", "link-preview"],
           let url = query?.first(where: { $0.name == "url" })?.value {
            let host = URL(string: url)?.host() ?? url
            return json([
                "url": url, "title": "\(host) — 링크 미리보기", "description": NSNull(),
                "image": "https://picsum.photos/seed/\(host)/960/502",
            ])
        }

        // 본문 링크 단축 — 붙여넣은 URL 을 kurl 짧은 링크로(POST /links).
        if method == "POST", parts == ["links"] {
            shortSeq += 1
            let code = "mk\(shortSeq)"
            return json([
                "shortCode": code,
                "shortUrl": "https://kurl.me/\(code)",
                "claimToken": NSNull(),
            ])
        }

        // 공개 연결 흐름 — 비로그인 첫 피드에 인터리브. 게이트 없는 공개 표면(미로그인도 본다).
        if method == "GET", parts == ["public", "feed", "connections"] {
            return json([
                "items": publicConnectionFeedMock(), "page": 0, "size": 6, "hasNext": false,
            ])
        }

        // 카드 소속 배치 — 여러 글의 소속 공개 컬렉션을 한 번에(피드 카드 아래 소속 한 올). respond 는 쿼리를
        // 안 넘겨받으므로(경로만) 잘 알려진 목 피드 글 id 에 고정 소속을 매핑해 카드에 줄이 서게 한다. 담긴 곳
        // 없는 글은 응답에 없으면 그만(호출측이 빈 배열로 취급) — 여기선 있는 것만 돌려준다.
        if method == "GET", parts == ["public", "posts", "collections"] {
            return json(postCollectionsMock())
        }

        // "이어진 것" — 이 블록과 같은 공개 컬렉션에 함께 놓인 다른 블록(본문 끝 PostEdges). 공개 표면.
        if method == "GET", parts.count == 6, parts[0] == "public", parts[1] == "graph",
            parts[2] == "blocks", parts[5] == "related" {
            return json(relatedBlocksMock())
        }

        // "이 글을 엮은 사람" — 같은 것을 자기 공개 컬렉션에도 엮은 취향 겹치는 큐레이터. 공개 표면.
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "profiles",
            parts[3] == "kindred" {
            return json(kindredCuratorsMock())
        }

        // 컬렉션 — 내 목록 / 상세 / 생성 / 연결 / 연결끊기 / 삭제.
        if method == "GET", parts == ["users", "me", "collections"] {
            // 연결 시트가 "이 블록을 어디에 남길까"를 물으면(blockType·refId) 이미 담긴 컬렉션에
            // connectionId 를 실어 "연결됨"으로 표시·해제되게 한다. 목 글 9101 은 컬렉션 101 에 이미 담겨 있다.
            let refId = query?.first { $0.name == "refId" }?.value.flatMap(Int64.init)
            return json(collections.map { collectionSummary($0, connectedRefId: refId) })
        }
        if parts.first == "collections" {
            if method == "POST", parts.count == 1 {
                let req = decode(body)
                let ordered = req["ordered"] as? Bool ?? (req["kind"] as? String == "PATH")
                let c = MockCollection(
                    id: nextCollectionId,
                    title: req["title"] as? String ?? "새 컬렉션",
                    description: req["description"] as? String,
                    visibility: req["visibility"] as? String ?? "PRIVATE",
                    kind: ordered ? "PATH" : "COLLECTION",
                    ordered: ordered,
                    connections: [])
                nextCollectionId += 1
                collections.insert(c, at: 0)
                return json(collectionSummary(c))
            }
            if parts.count >= 2, let cid = Int64(parts[1]),
               let idx = collections.firstIndex(where: { $0.id == cid }) {
                if method == "GET", parts.count == 2 {
                    return json(collectionDetail(collections[idx]))
                }
                if method == "PUT", parts.count == 2 {
                    let req = decode(body)
                    collections[idx].title = req["title"] as? String ?? collections[idx].title
                    collections[idx].description = req["description"] as? String
                    collections[idx].visibility =
                        req["visibility"] as? String ?? collections[idx].visibility
                    if let ordered = req["ordered"] as? Bool {
                        collections[idx].ordered = ordered
                        collections[idx].kind = ordered ? "PATH" : "COLLECTION"
                    }
                    return json(collectionSummary(collections[idx]))
                }
                if method == "DELETE", parts.count == 2 {
                    collections.remove(at: idx)
                    return json([:] as [String: Any])
                }
                if method == "POST", parts.count == 3, parts[2] == "connections" {
                    let req = decode(body)
                    let type = req["blockType"] as? String ?? "POST"
                    let why = req["why"] as? String
                    let refId = (req["refId"] as? NSNumber)?.int64Value
                    var conn = MockConnection(
                        id: nextConnectionId, blockType: type, why: why, refId: refId)
                    switch type {
                    case "NOTE": conn.body = "연결한 노트"
                    case "HIGHLIGHT":
                        conn.quote = "연결한 하이라이트"
                        conn.title = "원문 글"
                        conn.username = myUsername
                    default:
                        conn.title = "연결한 글"
                        conn.username = myUsername
                    }
                    nextConnectionId += 1
                    collections[idx].connections.append(conn)
                    return json([:] as [String: Any])
                }
                if method == "DELETE", parts.count == 4, parts[2] == "connections",
                   let connId = Int64(parts[3]) {
                    collections[idx].connections.removeAll { $0.id == connId }
                    return json([:] as [String: Any])
                }
                // 순서 있는 컬렉션의 순서 재배치 — 연결 id 전체를 주어진 순서대로.
                if method == "PUT", parts.count == 4, parts[2] == "connections", parts[3] == "order" {
                    let req = decode(body)
                    let ids = (req["connectionIds"] as? [Any] ?? [])
                        .compactMap { ($0 as? NSNumber)?.int64Value }
                    let byId = Dictionary(
                        uniqueKeysWithValues: collections[idx].connections.map { ($0.id, $0) })
                    let reordered = ids.compactMap { byId[$0] }
                    if reordered.count == collections[idx].connections.count {
                        collections[idx].connections = reordered
                    }
                    return json([:] as [String: Any])
                }
            }
        }

        if method == "GET", parts == ["users", "me", "mutes"] {
            return json(mutedUsers.sorted { $0.key < $1.key }.map { name, mute in
                [
                    "id": mockUserIds[name] ?? 0, "username": name, "avatarUrl": NSNull(),
                    "notifications": mute.notifications,
                    "expiresAt": mute.expiresAt.map(iso) ?? NSNull(),
                ] as [String: Any]
            })
        }
        if parts.count == 3, parts[0] == "users", parts[2] == "mute" {
            let name = parts[1]
            switch method {
            case "PUT":
                let req = decode(body)
                let duration = (req["duration"] as? NSNumber)?.doubleValue
                mutedUsers[name] = (
                    (req["notifications"] as? Bool) ?? true, duration.map { Date().addingTimeInterval($0) }
                )
            case "DELETE":
                mutedUsers[name] = nil
                return json([:])
            default:
                break
            }
            let mute = mutedUsers[name]
            return json([
                "muted": mute != nil, "notifications": mute?.notifications ?? false,
                "expiresAt": mute?.expiresAt.map(iso) ?? NSNull(),
            ])
        }
        if method == "GET", parts == ["users", "me"] {
            return json([
                "id": 1, "email": "mock@kurl.me", "username": myUsername,
                "avatarUrl": NSNull(), "role": "ADMIN",
            ])
        }

        // 태그 구독/숨김 — 웹 tag-prefs parity. url.path 가 디코드돼 parts[4] = 원문 태그.
        if parts == ["users", "me", "tag-prefs"] {
            return json(["followed": Array(followedTags), "hidden": Array(hiddenTags)])
        }
        if parts.count == 5, parts[0] == "users", parts[1] == "me", parts[2] == "tag-prefs" {
            let tag = parts[4]
            if parts[3] == "followed" {
                if method == "PUT" { followedTags.insert(tag) }
                if method == "DELETE" { followedTags.remove(tag) }
            } else if parts[3] == "hidden" {
                if method == "PUT" { hiddenTags.insert(tag) }
                if method == "DELETE" { hiddenTags.remove(tag) }
            }
            return json(["followed": Array(followedTags), "hidden": Array(hiddenTags)])
        }

        // 신고 — 사유 하이브리드 계약(#611): reasonCode(enum) + detail(자유서술, 선택).
        // 목에선 실서버에 진짜 신고가 쌓이지 않게 받아만 준다. 새 바디는 reasonCode 를 담아 온다.
        if method == "POST", parts == ["public", "abuse-reports"] {
            let req = decode(body)
            guard req["reasonCode"] is String else { return nil }
            return json([:] as [String: Any])
        }

        // 프로필 편집 — 사용자 이름·소개글(부분 PUT)·아바타(presign→commit).
        if parts == ["users", "me", "profile"] {
            if method == "PUT" {
                let req = decode(body)
                if let bio = req["bio"] as? String { myBio = bio }
                if let u = (req["username"] as? String)?.trimmingCharacters(in: .whitespaces),
                   !u.isEmpty {
                    myUsername = u.lowercased()
                }
                if let hide = req["hideFollowerCount"] as? Bool { myHideFollowerCount = hide }
                if let locked = req["locked"] as? Bool {
                    if !locked {
                        memberRequests = []
                        remoteRequests = [:]
                    }
                    myLocked = locked
                }
                if let name = req["displayName"] as? String {
                    displayNames["honggildong"] = name.isEmpty ? nil : name
                }
            }
            return json([
                "username": myUsername, "bio": myBio, "theme": "light", "socials": NSNull(),
                "hideFollowerCount": myHideFollowerCount,
                "displayName": displayNames["honggildong"] ?? NSNull(),
                "locked": myLocked,
            ])
        }
        if method == "POST", parts == ["users", "me", "avatar", "presigned-url"] {
            return json([
                "uploadUrl": "https://mock-upload.invalid/put",
                "publicUrl": "https://cdn.kurl.me/mock-avatar.jpg",
                "key": "avatars/1/mock.jpg", "contentType": "image/jpeg",
                "maxBytes": 5_242_880, "presignTtlSeconds": 300,
            ])
        }
        if method == "PUT", parts == ["users", "me", "avatar"] {
            return json(["avatarUrl": "https://cdn.kurl.me/mock-avatar.jpg"])
        }

        // 노트는 공개 읽기까지 목으로 받는다 — 목 세션(honggildong, id 1)의 노트만 좋아요 수가 보인다.
        if method == "GET", parts == ["public", "notes"],
           query?.first(where: { $0.name == "sort" })?.value == "trending" {
            let ranked = topLevelNotes().sorted {
                ($0.likeCount + Int64(replyCount($0.id))) > ($1.likeCount + Int64(replyCount($1.id)))
            }
            return json(["items": ranked.map(noteView), "page": 0, "hasNext": false])
        }
        if method == "GET", parts == ["notes", "bookmarks"] {
            let items = bookmarkedNotes.compactMap { id in allNotes().first { $0.id == id } }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false])
        }
        if parts.count == 3, parts[0] == "notes", parts[2] == "bookmark", let nid = Int64(parts[1]) {
            bookmarkedNotes.removeAll { $0 == nid }
            if method == "PUT" { bookmarkedNotes.insert(nid, at: 0) }
            return json(["bookmarked": method == "PUT"])
        }
        if method == "GET", parts == ["public", "notes", "trending-tags"] {
            return json([
                ["tag": "아키텍처", "accounts": 4, "uses": 9, "history": [0, 1, 1, 2, 1, 2, 2]],
                ["tag": "산책", "accounts": 3, "uses": 5, "history": [1, 0, 0, 1, 0, 1, 2]],
                ["tag": "kurl", "accounts": 2, "uses": 2, "history": [0, 0, 0, 0, 0, 1, 1]],
            ])
        }
        if method == "GET", parts == ["public", "notes", "trending-links"] {
            return json([
                ["url": "https://example.com/slow-web", "title": "느린 웹을 위한 변론", "description": NSNull(),
                 "imageUrl": NSNull(), "accounts": 3, "uses": 4, "history": [0, 0, 1, 0, 1, 1, 1]],
                ["url": "https://blog.example.org/hexagonal", "title": "Hexagonal, three years in", "description": NSNull(),
                 "imageUrl": NSNull(), "accounts": 2, "uses": 2, "history": [0, 0, 0, 0, 1, 0, 1]],
            ])
        }
        if method == "GET", parts == ["public", "notes", "links"] {
            let hits = Array(allNotes().filter { $0.visibility == "public" }.prefix(2)).map(noteView)
            return json(["items": hits, "page": 0, "hasNext": false])
        }
        if method == "GET", parts == ["public", "notes", "search"] {
            let q = (query?.first(where: { $0.name == "q" })?.value ?? "").lowercased()
            let hits = q.isEmpty
                ? []
                : allNotes().filter { $0.visibility == "public" && $0.body.lowercased().contains(q) }
                    .sorted { $0.createdAt > $1.createdAt }
            return json(["items": hits.map(noteView), "page": 0, "hasNext": false])
        }
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "notes", parts[2] == "tags" {
            let needle = "#" + parts[3].lowercased()
            let items = allNotes().filter { $0.body.lowercased().contains(needle) }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false])
        }
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "notes", parts[3] == "posts",
           let nid = Int64(parts[2]) {
            return json(["items": quotingPosts[nid] ?? [], "page": 0, "size": 20, "hasNext": false])
        }
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "posts", parts[3] == "quotes",
           let pid = Int64(parts[2]) {
            let items = allNotes().filter { ($0.quotedPost?["id"] as? Int).map(Int64.init) == pid }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false, "total": items.count])
        }
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "notes", parts[3] == "quotes",
           let nid = Int64(parts[2]) {
            let items = allNotes().filter { $0.quotedNoteId == nid }.map(noteView)
            return json(["items": items, "page": 0, "hasNext": false])
        }
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "notes", parts[3] == "history",
           let nid = Int64(parts[2]), let note = allNotes().first(where: { $0.id == nid }) {
            let current: [String: Any] = [
                "body": note.body, "contentWarning": note.contentWarning ?? NSNull(),
                "sensitive": note.sensitive, "at": iso(note.editedAt ?? note.createdAt),
            ]
            let earlier: [[String: Any]] = (noteHistory[nid] ?? []).reversed().map { version in
                ["body": version.body, "contentWarning": NSNull(), "sensitive": false, "at": iso(version.at)]
            }
            return json(["noteId": nid, "versions": [current] + earlier])
        }
        if parts == ["notes", "filters"] {
            if method == "POST" {
                var filter = decode(body)
                filter["id"] = nextFilterId
                filter["wholeWord"] = filter["wholeWord"] ?? false
                filter["expiresAt"] = NSNull()
                nextFilterId += 1
                noteFilters.insert(filter, at: 0)
                return json(filter)
            }
            return json(noteFilters)
        }
        if parts.count == 3, parts[0] == "notes", parts[1] == "filters", let fid = Int64(parts[2]) {
            if method == "DELETE" {
                noteFilters.removeAll { ($0["id"] as? Int64) == fid }
                return json([:])
            }
            var filter = decode(body)
            filter["id"] = fid
            filter["expiresAt"] = NSNull()
            noteFilters = noteFilters.map { ($0["id"] as? Int64) == fid ? filter : $0 }
            return json(filter)
        }
        if parts == ["notes", "lists"] {
            if method == "POST" {
                let title = decode(body)["title"] as? String ?? ""
                noteLists.append((nextListId, title, []))
                nextListId += 1
                return json(["id": nextListId - 1, "title": title, "memberCount": 0])
            }
            return json(noteLists.map { ["id": $0.id, "title": $0.title, "memberCount": $0.members.count] })
        }
        if parts.count >= 3, parts[0] == "notes", parts[1] == "lists", let lid = Int64(parts[2]),
           let index = noteLists.firstIndex(where: { $0.id == lid }) {
            if parts.count == 3, method == "PATCH" {
                noteLists[index].title = decode(body)["title"] as? String ?? noteLists[index].title
                let list = noteLists[index]
                return json(["id": list.id, "title": list.title, "memberCount": list.members.count])
            }
            if parts.count == 3, method == "DELETE" {
                noteLists.remove(at: index)
                return json([String: Any]())
            }
            if parts.count == 4, parts[3] == "members" {
                return json(noteLists[index].members.map { name -> [String: Any] in
                    ["id": mockUserIds[name] ?? 99, "username": name, "avatarUrl": NSNull()]
                })
            }
            if parts.count == 5, parts[3] == "members" {
                noteLists[index].members.removeAll { $0 == parts[4] }
                if method == "PUT" { noteLists[index].members.insert(parts[4], at: 0) }
                return json([String: Any]())
            }
            if parts.count == 4, parts[3] == "notes" {
                let members = Set(noteLists[index].members)
                let items = topLevelNotes().filter { members.contains($0.username) && $0.visibility != "direct" }
                return json(["items": items.map(noteView), "page": 0, "hasNext": false])
            }
        }
        if method == "GET", parts.count == 3, parts[0] == "notes", parts[1] == "list-memberships" {
            return json(["listIds": noteLists.filter { $0.members.contains(parts[2]) }.map(\.id)])
        }
        if parts.count == 3, parts[0] == "notes", parts[2] == "pin", let nid = Int64(parts[1]) {
            pinnedNotes.removeAll { $0 == nid }
            if method == "PUT" { pinnedNotes.insert(nid, at: 0) }
            return json(["pinned": method == "PUT"])
        }
        if parts == ["notes", "feed-preferences"] {
            if method == "PUT" {
                let req = decode(body)
                if let on = req["showReposts"] as? Bool { showReposts = on }
                if let codes = req["languages"] as? [String] { feedLanguages = codes }
            }
            return json(["showReposts": showReposts, "languages": feedLanguages])
        }
        if parts.count == 3, parts[0] == "notes", parts[1] == "repost-visibility" {
            if method == "PUT" { repostsHidden.insert(parts[2]) }
            if method == "DELETE" { repostsHidden.remove(parts[2]) }
            return json(["hidden": repostsHidden.contains(parts[2])])
        }
        if method == "GET", parts == ["notes", "following"] {
            let followed: Set<Int64> = [1, 2]
            var items = topLevelNotes().filter { followed.contains($0.authorId) }.map(noteView)
            if showReposts, !repostsHidden.contains("yuki_dev"),
               let reposted = notes.first(where: { $0.id == 9503 }) {
                var view = noteView(reposted)
                view["repostedBy"] = ["id": 2, "username": "yuki_dev", "avatarUrl": NSNull()] as [String: Any]
                items.insert(view, at: min(1, items.count))
            }
            items.append(remoteNoteView())
            return json(["items": items, "page": 0, "hasNext": false])
        }
        if method == "GET", parts == ["notes", "federated"] {
            return json(["items": [remoteNoteView()], "page": 0, "hasNext": false])
        }
        if method == "GET", parts.count == 4, parts[0] == "federation", parts[1] == "accounts",
           parts[3] == "notes" {
            var withMedia = remoteNoteView()
            withMedia["id"] = Int64(9601)
            withMedia["body"] = "오늘 찍은 파도 소리와 영상"
            withMedia["media"] = [
                ["url": "https://files.mastodon.social/waves.mp4", "altText": "밀려오는 파도",
                 "contentType": "video/mp4"],
                ["url": "https://files.mastodon.social/waves.mp3", "altText": "파도 소리",
                 "contentType": "audio/mpeg"],
            ] as [Any]
            let items = parts[2] == "9800" ? [withMedia, remoteNoteView()] : []
            return json(["items": items, "page": 0, "hasNext": false])
        }
        if method == "GET", parts == ["public", "notes"] {
            return json(["items": topLevelNotes().filter { $0.visibility == "public" }.map(noteView),
                         "page": 0, "hasNext": false])
        }
        if method == "GET", parts == ["notes", "direct"] {
            let items = allNotes().filter {
                $0.visibility == "direct" && ($0.authorId == 1 || $0.body.contains("@honggildong"))
            }
            return json(["items": items.sorted { $0.createdAt > $1.createdAt }.map(noteView),
                         "page": 0, "hasNext": false])
        }
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "profiles",
           parts[3] == "notes" {
            let own = topLevelNotes().filter { $0.username == parts[2] }
            let pinned = pinnedNotes.compactMap { id in own.first { $0.id == id } }
            let rest = own.filter { !pinnedNotes.contains($0.id) }
            return json([
                "items": (pinned + rest).map(noteView),
                "page": 0, "hasNext": false,
            ])
        }
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "profiles",
           parts[3] == "reposts" {
            let ids = repostedNotes[parts[2]] ?? []
            return json([
                "items": ids.compactMap { id in allNotes().first { $0.id == id } }.map(noteView),
                "page": 0, "hasNext": false,
            ])
        }
        if method == "GET", parts.count == 3, parts[0] == "public", parts[1] == "notes",
           let nid = Int64(parts[2]) {
            guard let note = allNotes().first(where: { $0.id == nid }) else {
                return json(["status": 404])
            }
            let parts = selfChain(note)
            let partIds = Set(parts.map(\.id))
            return json([
                "note": noteView(note),
                "parent": note.inReplyToId.flatMap { pid in allNotes().first { $0.id == pid } }
                    .map(noteView) ?? NSNull(),
                "replies": allNotes().filter { $0.inReplyToId == nid && !partIds.contains($0.id) }
                    .sorted { $0.createdAt < $1.createdAt }.map(noteView),
                "continuation": parts.map(noteView),
                "series": noteSeriesTrail(nid),
            ])
        }
        if method == "POST", parts == ["notes", "images", "presign"] {
            return json([
                "uploadUrl": "https://mock-upload.invalid/put",
                "key": "note-images/1/\(UUID().uuidString).jpg",
                "publicUrl": "https://cdn.kurl.me/mock-note.jpg", "maxBytes": 5_242_880,
            ])
        }
        if method == "POST", parts == ["notes"] {
            return json(noteView(createMockNote(decode(body))))
        }
        if method == "POST", parts == ["notes", "threads"] {
            var created: [[String: Any]] = []
            var previous: MockNote?
            for var draft in (decode(body)["notes"] as? [[String: Any]]) ?? [] {
                if let previous {
                    draft["inReplyToId"] = NSNumber(value: previous.id)
                    draft["visibility"] = previous.visibility
                }
                let note = createMockNote(draft)
                created.append(noteView(note))
                previous = note
            }
            return json(created)
        }
        if method == "POST", parts.count == 4, parts[0] == "notes", parts[2] == "poll", parts[3] == "votes",
           let nid = Int64(parts[1]), let idx = notes.firstIndex(where: { $0.id == nid }),
           var poll = notes[idx].poll {
            let choices = ((decode(body)["choices"] as? [NSNumber]) ?? []).map(\.intValue)
            guard poll.mine == nil else { return json(pollView(notes[idx]) ?? [:]) }
            for choice in choices where poll.votes.indices.contains(choice) { poll.votes[choice] += 1 }
            poll.voters += 1
            poll.mine = choices
            notes[idx].poll = poll
            return json(pollView(notes[idx]) ?? [:])
        }
        if method == "PATCH", parts.count == 2, parts[0] == "notes", let nid = Int64(parts[1]) {
            let req = decode(body)
            let text = req["body"] as? String ?? ""
            if let idx = notes.firstIndex(where: { $0.id == nid }) {
                noteHistory[nid, default: []].append((notes[idx].body, notes[idx].editedAt ?? notes[idx].createdAt))
                notes[idx].body = text
                notes[idx].editedAt = Date()
                if let warning = req["contentWarning"] as? String {
                    notes[idx].contentWarning = warning.isEmpty ? nil : warning
                }
                if let sensitive = req["sensitive"] as? Bool { notes[idx].sensitive = sensitive }
                return json(noteView(notes[idx]))
            }
            if let idx = noteReplies.firstIndex(where: { $0.id == nid }) {
                noteReplies[idx].body = text
                noteReplies[idx].editedAt = Date()
                return json(noteView(noteReplies[idx]))
            }
            return json(["status": 404])
        }

        if method == "GET", parts == ["notes", "like-status"] {
            return json(["likedIds": Array(likedNotes)])
        }

        if method == "DELETE", parts.count == 2, parts[0] == "notes" {
            let nid = Int64(parts[1]) ?? 0
            notes.removeAll { $0.id == nid }
            noteReplies.removeAll { $0.id == nid }
            likedNotes.remove(nid)
            return json([:] as [String: Any])
        }

        if parts.count == 3, parts[0] == "notes", parts[2] == "repost", let nid = Int64(parts[1]) {
            var mine = (repostedNotes["honggildong"] ?? []).filter { $0 != nid }
            if method == "PUT" { mine.insert(nid, at: 0) }
            repostedNotes["honggildong"] = mine
            return json(["reposted": method == "PUT", "repostCount": repostCount(nid)])
        }

        if parts.count == 3, parts[0] == "notes", parts[2] == "like" {
            let nid = Int64(parts[1]) ?? 0
            if let idx = notes.firstIndex(where: { $0.id == nid }) {
                if method == "PUT", !likedNotes.contains(nid) {
                    likedNotes.insert(nid)
                    notes[idx].likeCount += 1
                }
                if method == "DELETE", likedNotes.contains(nid) {
                    likedNotes.remove(nid)
                    notes[idx].likeCount -= 1
                }
                return json(["liked": likedNotes.contains(nid), "likeCount": notes[idx].likeCount])
            }
            return json(["liked": method == "PUT", "likeCount": 0])
        }

        if parts == ["notes", "scheduled"] {
            if method == "POST" {
                let req = decode(body)
                let note = req["note"] as? [String: Any] ?? [:]
                let id = nextScheduledId
                nextScheduledId += 1
                let item: [String: Any] = [
                    "id": id, "scheduledAt": req["scheduledAt"] as? String ?? iso(Date()),
                    "body": note["body"] ?? NSNull(), "contentWarning": note["contentWarning"] ?? NSNull(),
                    "visibility": note["visibility"] ?? NSNull(),
                    "imageCount": (note["images"] as? [Any])?.count ?? 0, "poll": note["poll"] != nil,
                    "inReplyToId": note["inReplyToId"] ?? NSNull(), "quotedNoteId": note["quotedNoteId"] ?? NSNull(),
                    "quotedPostId": note["quotedPostId"] ?? NSNull(), "failure": NSNull(),
                ]
                scheduledNotes.append(item)
                return json(item)
            }
            return json(scheduledNotes)
        }
        if parts.count == 3, parts[0] == "notes", parts[1] == "scheduled", let sid = Int64(parts[2]) {
            if method == "DELETE" {
                scheduledNotes.removeAll { ($0["id"] as? Int64) == sid }
                return json([:])
            }
            let req = decode(body)
            guard let at = scheduledNotes.firstIndex(where: { ($0["id"] as? Int64) == sid }) else {
                return json([:])
            }
            scheduledNotes[at]["scheduledAt"] = req["scheduledAt"] as? String ?? iso(Date())
            scheduledNotes[at]["failure"] = NSNull()
            return json(scheduledNotes[at])
        }
        if parts.count == 3, parts[0] == "notes", parts[2] == "conversation-mute",
           let nid = Int64(parts[1]) {
            if method == "PUT" { mutedConversations.insert(nid) } else { mutedConversations.remove(nid) }
            return json(["muted": method == "PUT"])
        }
        if method == "GET", parts == ["federation", "accounts", "lookup"] {
            var handle = (query?.first(where: { $0.name == "acct" })?.value ?? "")
                .trimmingCharacters(in: .whitespaces)
            if handle.hasPrefix("@") { handle.removeFirst() }
            let pieces = handle.split(separator: "@").map(String.init)
            guard pieces.count == 2 else { return json([:] as [String: Any]) }
            let acct = "\(pieces[0])@\(pieces[1].lowercased())"
            if let known = remoteAccounts.values.first(where: { ($0["acct"] as? String) == acct }) {
                return json(withDomainBlock(known))
            }
            let id = nextRemoteId
            nextRemoteId += 1
            let account: [String: Any] = [
                "id": id, "acct": acct, "username": pieces[0], "domain": pieces[1].lowercased(),
                "displayName": pieces[0].capitalized, "avatarUrl": NSNull(),
                "url": "https://\(pieces[1].lowercased())/@\(pieces[0])",
                "following": false, "requested": false,
            ]
            remoteAccounts[id] = account
            return json(withDomainBlock(account))
        }
        if method == "GET", parts.count == 3, parts[0] == "federation", parts[1] == "accounts",
           let id = Int64(parts[2]), var account = remoteAccounts[id] {
            if (account["requested"] as? Bool) == true {
                account["requested"] = false
                account["following"] = true
                remoteAccounts[id] = account
            }
            return json(withDomainBlock(account))
        }
        if parts.count == 4, parts[0] == "federation", parts[1] == "accounts", parts[3] == "follow",
           let id = Int64(parts[2]), var account = remoteAccounts[id] {
            account["requested"] = method == "POST"
            account["following"] = false
            remoteAccounts[id] = account
            return json(withDomainBlock(account))
        }
        if method == "GET", parts == ["federation", "following"] {
            let followed = remoteAccounts.values
                .filter { ($0["requested"] as? Bool) == true || ($0["following"] as? Bool) == true }
                .sorted { (($0["id"] as? Int64) ?? 0) > (($1["id"] as? Int64) ?? 0) }
            return json(followed.map(withDomainBlock))
        }
        if method == "GET", parts == ["admin", "federation", "servers"] {
            return json(serverBlocks.sorted { $0.key < $1.key }.map { domain, block in
                serverBlockView(domain, block)
            })
        }
        if parts.count == 4, parts[0] == "admin", parts[1] == "federation", parts[2] == "servers" {
            let domain = parts[3].lowercased()
            if method == "DELETE" {
                serverBlocks[domain] = nil
                return json([:])
            }
            let req = decode(body)
            let reason = (req["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            serverBlocks[domain] = (
                (req["severity"] as? String) ?? "LIMIT", reason, serverBlocks[domain]?.at ?? Date()
            )
            return json(serverBlockView(domain, serverBlocks[domain]!))
        }
        if method == "GET", parts == ["federation", "domain-blocks"] {
            return json(domainBlocks.sorted { $0.key < $1.key }.map { domain, at in
                ["domain": domain, "createdAt": iso(at)] as [String: Any]
            })
        }
        if parts.count == 3, parts[0] == "federation", parts[1] == "domain-blocks" {
            let domain = parts[2].lowercased()
            if method == "DELETE" {
                domainBlocks[domain] = nil
                return json([:])
            }
            domainBlocks[domain] = domainBlocks[domain] ?? Date()
            for (id, var account) in remoteAccounts where (account["domain"] as? String) == domain {
                account["following"] = false
                account["requested"] = false
                remoteAccounts[id] = account
            }
            return json(["domain": domain, "createdAt": iso(domainBlocks[domain] ?? Date())])
        }

        if parts == ["federation", "settings"] {
            if method == "PUT" {
                let req = decode(body)
                if let enabled = req["enabled"] as? Bool { federationEnabled = enabled }
                if (req["noticeSeen"] as? Bool) == true { federationNoticeSeen = true }
            }
            return json([
                "enabled": federationEnabled, "noticeSeen": federationNoticeSeen,
                "handle": "@honggildong@kurl.me",
            ])
        }

        if method == "GET", parts == ["posts", "analytics", "overview"] {
            return json(analyticsOverview())
        }

        if method == "GET", parts == ["posts", "analytics", "posts"] {
            // 기본 제목("발행된 목 글" 등)은 UITest 가 고정한다 — 스토어 캡처(--store-demo)에서만
            // 있을 법한 글(일상·문학·홍보, 시스템 언어를 따름)로 갈아끼운다. 숫자는 공용.
            let titles = MockStoreDemo.isOn ? MockStoreDemo.analyticsRows : [
                MockStoreDemo.Row(slug: "p-mock-2", title: "발행된 목 글"),
                MockStoreDemo.Row(slug: "p-mock-1", title: "목 초안 — 헥사고날 정리"),
                MockStoreDemo.Row(slug: "p-mock-3", title: "조용한 웹로그라는 결정"),
            ]
            return json([
                "items": [
                    ["postId": 9002, "slug": titles[0].slug, "title": titles[0].title,
                     "viewCount": 812, "likeCount": 41, "followsGained": 6],
                    ["postId": 9001, "slug": titles[1].slug, "title": titles[1].title,
                     "viewCount": 287, "likeCount": 19, "followsGained": 2],
                    ["postId": 9003, "slug": titles[2].slug, "title": titles[2].title,
                     "viewCount": 145, "likeCount": 12, "followsGained": 0],
                ],
                "page": 0, "hasNext": false,
            ])
        }

        if method == "GET", parts == ["posts", "analytics", "series"] {
            let titles = MockStoreDemo.isOn
                ? MockStoreDemo.seriesTitles : ["헥사고날 전환기", "iOS 앱 만들기"]
            return json([
                ["seriesId": 1, "slug": "hexagonal", "title": titles[0],
                 "postCount": 6, "subscriberCount": 14, "totalViews": 1930, "totalLikes": 72],
                ["seriesId": 2, "slug": "ios-build", "title": titles[1],
                 "postCount": 3, "subscriberCount": 7, "totalViews": 640, "totalLikes": 25],
            ])
        }

        // 시리즈 상세 분석 — 구독자 추이 + 회차 funnel.
        if method == "GET", parts.count == 4, parts[0] == "posts", parts[1] == "analytics",
           parts[2] == "series", let id = Int64(parts[3]) {
            return json(seriesDetailFixture(id: id))
        }

        if method == "GET", parts.count == 3, parts[0] == "posts", parts[2] == "stats" {
            return json(readStatsFixture())
        }

        if method == "GET", parts.count == 3, parts[0] == "posts", parts[2] == "analytics" {
            return json(postAnalyticsFixture(id: Int64(parts[1]) ?? 9002))
        }

        if method == "PATCH", parts.count == 2, parts[0] == "posts" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            let req = decode(body)
            try requireEditVersion(idx, req)
            if let title = req["title"] as? String { posts[idx].title = title }
            if let excerpt = req["excerpt"] as? String { posts[idx].excerpt = excerpt.isEmpty ? nil : excerpt }
            if let tags = req["tags"] as? [String] { posts[idx].tags = tags }
            if let cover = req["ogImageUrl"] as? String { posts[idx].ogImageUrl = cover.isEmpty ? nil : cover }
            posts[idx].contentVersion += 1
            posts[idx].updatedAt = Date()
            return json(postView(posts[idx]))
        }

        if method == "GET", parts == ["posts"] {
            return json(posts.sorted { $0.updatedAt > $1.updatedAt }.map(postView))
        }

        if method == "POST", parts == ["posts"] {
            let req = decode(body)
            let post = MockPost(
                id: nextId, slug: req["slug"] as? String ?? "p-mock",
                title: req["title"] as? String ?? "무제", status: "DRAFT",
                markdown: "", publishedAt: nil, updatedAt: Date())
            nextId += 1
            posts.append(post)
            return json(postView(post))
        }

        if parts.count == 3, parts[0] == "posts", parts[2] == "markdown" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            if method == "PUT" {
                let req = decode(body)
                try requireEditVersion(idx, req)
                posts[idx].markdown = req["markdown"] as? String ?? ""
                posts[idx].contentVersion += 1
                posts[idx].updatedAt = Date()
            }
            let response = json(["markdown": posts[idx].markdown, "contentVersion": posts[idx].contentVersion])
            if method == "GET", remoteEditTarget == posts[idx].id {
                remoteEditTarget = nil
                posts[idx].markdown += "\n\n다른 기기에서 고친 문단."
                posts[idx].contentVersion += 1
                posts[idx].updatedAt = Date()
            }
            return response
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "publish" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts[idx].status = "PUBLISHED"
            posts[idx].publishedAt = Date()
            return json(postView(posts[idx]))
        }

        // 발행 취소 — 라이브 글을 비공개(UNPUBLISHED)로. 글은 남고 상태만 바뀐다(웹 계약과 동일).
        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "unpublish" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts[idx].status = "UNPUBLISHED"
            return json(postView(posts[idx]))
        }

        // 글 삭제 — 204(빈 응답). 목 저장소에서 그 글을 걷어낸다.
        if method == "DELETE", parts.count == 2, parts[0] == "posts" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts.remove(at: idx)
            return json([:])
        }

        // 프로필 고정 세트 전체 교체 — 목은 순서만 받아 ack(공개 목록 픽스처는 정적이라 재정렬 생략).
        if method == "PUT", parts == ["posts", "pins"] {
            return json([:])
        }

        // 관리자 모더레이션 — 목 me 가 ADMIN 이라 메뉴가 열린다. 내리기·편집·삭제 전부 ack.
        if parts.count >= 2, parts[0] == "admin", parts[1] == "posts" {
            return json([:])
        }

        if parts.count == 3, parts[0] == "posts", parts[2] == "like" {
            let pid = Int64(parts[1]) ?? 0
            var state = likes[pid] ?? (count: 3, liked: false)
            if method == "PUT" { if !state.liked { state.count += 1 }; state.liked = true }
            if method == "DELETE" { if state.liked { state.count -= 1 }; state.liked = false }
            likes[pid] = state
            return json(["likeCount": state.count, "liked": state.liked])
        }

        if parts.count == 3, parts[0] == "posts", parts[2] == "bookmark" {
            let pid = Int64(parts[1]) ?? 0
            if method == "PUT" { bookmarks.insert(pid) }
            if method == "DELETE" { bookmarks.remove(pid) }
            return json(["bookmarked": bookmarks.contains(pid)])
        }

        if parts.count == 3, parts[0] == "users", parts[2] == "follow" {
            let username = parts[1]
            var state = follows[username] ?? (following: username == "yuki_dev", count: 12)
            let locked = lockedAuthors.contains(username) || (username == myUsername && myLocked)
            if method == "PUT", locked, !state.following {
                sentRequests.insert(username)
            } else if method == "PUT" {
                if !state.following { state.count += 1 }
                state.following = true
            }
            if method == "DELETE" {
                if state.following { state.count -= 1 }
                state.following = false
                sentRequests.remove(username)
                noteBells.remove(username)
            }
            follows[username] = state
            // 내 프로필 토글이 켜져 있으면 내 작가 페이지에선 카운트 키를 빼고 플래그만 내린다(실서버 계약).
            let hidden = username == myUsername && myHideFollowerCount
            var payload: [String: Any] = [
                "following": state.following, "hideFollowerCount": hidden,
                "notifyNotes": noteBells.contains(username),
                "requested": sentRequests.contains(username), "locked": locked,
            ]
            if !hidden {
                payload["followerCount"] = state.count
                payload["followingCount"] = 5
            }
            return json(payload)
        }

        if parts.count == 4, parts[0] == "users", parts[2] == "follow", parts[3] == "notes" {
            let username = parts[1]
            let following = follows[username]?.following ?? (username == "yuki_dev")
            if method == "PUT", following { noteBells.insert(username) }
            if method == "DELETE" { noteBells.remove(username) }
            return json(["notifyNotes": noteBells.contains(username)])
        }

        if parts.count == 3, parts[0] == "series", parts[2] == "subscription" {
            let sid = Int64(parts[1]) ?? 0
            var state = subscriptions[sid] ?? (subscribed: false, count: 7)
            if method == "PUT" { if !state.subscribed { state.count += 1 }; state.subscribed = true }
            if method == "DELETE" { if state.subscribed { state.count -= 1 }; state.subscribed = false }
            subscriptions[sid] = state
            return json(["subscribed": state.subscribed, "subscriberCount": state.count])
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "comments" {
            return json(["id": 1, "body": decode(body)["body"] as? String ?? ""])
        }

        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "posts",
           parts[3] == "comments" {
            return json(commentRows)
        }

        // 공개 작가 글 목록 — 실서버 미목이라 작가 페이지 검증 불가했음.
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "profiles",
           parts[3] == "posts" {
            let username = parts[2]
            // 긴 글 픽스처를 그대로 목록으로 — 카드를 누르면 같은 슬러그의 상세가 열린다.
            let posts = articles.enumerated().map { i, a -> [String: Any] in
                [
                    "id": 8100 + i, "slug": a.slug, "title": a.title, "excerpt": a.excerpt,
                    "ogImageUrl": NSNull(), "languageTag": "ko", "tags": a.tags,
                    "likeCount": a.likeCount, "pinned": i == 0, "lastEditedAt": NSNull(),
                    "publishedAt": iso(Date().addingTimeInterval(-a.daysAgo * 86_400)),
                ]
            }
            return json([
                "author": [
                    // honggildong = 목 로그인 유저(내 프로필), 그 외는 남(신고 노출 검증용).
                    "id": username == "honggildong" ? 1 : 2, "username": username,
                    "displayName": displayNames[username] as Any? ?? NSNull(),
                    "bio": "경계를 긋는 사람. 헥사고날·도메인 모델링.",
                    "avatarUrl": username == "yuki_dev"
                        ? "https://picsum.photos/seed/kurl-yuki/600/600" as Any : NSNull(),
                ],
                "posts": posts,
            ])
        }

        // 공개 작가 컬렉션 목록 — 프로필 컬렉션 레일의 소스(PUBLIC 만, 최근 손댄 순).
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "profiles",
           parts[3] == "collections" {
            let publicOnly = collections.filter { $0.visibility == "PUBLIC" }
            return json(publicOnly.map { collectionSummary($0) })
        }

        // 공개 작가 시리즈 목록.
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "profiles",
           parts[3] == "series" {
            return json([
                "author": ["id": 1, "username": parts[2], "bio": NSNull(), "avatarUrl": NSNull()],
                "series": [
                    ["id": 7, "slug": "hexagonal", "title": "헥사고날 전환기", "postCount": 6, "tags": ["아키텍처"]],
                    ["id": 8, "slug": "ios-build", "title": "iOS 앱 만들기", "postCount": 3, "tags": ["iOS"]],
                ],
            ])
        }

        // 공개 글 상세 — 긴 글 픽스처를 슬러그로 찾아 블록을 통째로 돌려준다(목차·읽기 표면 검증).
        // 모르는 슬러그는 짧은 기본 글로 폴백(작가 페이지를 거치지 않은 직접 진입도 살게).
        if method == "GET", parts.count == 5, parts[0] == "public", parts[1] == "profiles",
           parts[3] == "posts" {
            let username = parts[2]
            let slug = parts[4]
            let article = articles.first { $0.slug == slug }
            // 시리즈 회차(ep-1…ep-6) 는 본문 + 회차 nav(position/total/prev/next)를 실어 준다 —
            // 끝에서 이어 당기기·배너 이전/다음 검증용 결정론적 픽스처.
            let seriesNav = seriesEpisodeNav(slug: slug)
            var blocks = article?.blocks ?? (seriesNav != nil
                ? episodeBlocks(slug: slug) : ordered([
                ["type": "H1", "content": "헥사고날로 가는 길"],
                ["type": "PARAGRAPH", "content": "레이어드에서 갈아탄 이유와 그 결정의 기록."],
                ["type": "H2", "content": "포트와 어댑터"],
                ["type": "PARAGRAPH", "content": "경계를 먼저 긋고, 구현은 그 바깥으로 민다."],
            ]))
            let japanese = slug == "kyoukai-wo-hiku"
            if japanese {
                blocks = ordered([
                    ["type": "PARAGRAPH", "content": "境界を先に引き、実装はその外側へ押し出す。三か月使ってみて、**変更が一か所に留まる**ことを実感した。"],
                    ["type": "H2", "content": "ポートとアダプター"],
                    ["type": "LIST_BULLET", "content": "- ドメインはフレームワークを知らない\n- [x] アダプターは差し替えられる"],
                    ["type": "CODE", "content": #"{"lang":"swift","code":"protocol PostStore { func save() }"}"#],
                    ["type": "QUOTE", "content": "境界がなければ、すべての変更が全体の変更になる。"],
                    ["type": "TABLE", "content": "| 層 | 役割 |\n|---|---|\n| ドメイン | 規則を持つ |"],
                ])
            }
            if slug == "walk-notes" {
                blocks = ordered([
                    ["type": "PARAGRAPH", "content": "이 글은 유키의 노트 한 줄에서 시작했다."],
                    ["type": "EMBED", "content": "\(Config.blogBase)/@yuki_dev/notes/9501"],
                    ["type": "PARAGRAPH", "content": "포트 이름을 고르는 일은 경계를 고르는 일이다."],
                ])
            }
            // `--longpost` — 실사용급 초장문 재현(진입 렉 프로파일링용): 본문을 40배로 편다.
            if ProcessInfo.processInfo.arguments.contains("--longpost") {
                blocks = ordered(Array(repeating: blocks, count: 40).flatMap { $0 })
            }
            return json([
                "author": [
                    "id": username == "honggildong" ? 1 : 2, "username": username,
                    "bio": NSNull(), "avatarUrl": NSNull(),
                ],
                "post": [
                    "id": 8201, "slug": slug,
                    "title": japanese ? "境界を先に引く" : seriesNav?["title"] as? String ?? article?.title ?? "헥사고날로 가는 길",
                    "excerpt": article?.excerpt ?? "경계를 긋는 이야기",
                    "ogImageUrl": NSNull(), "languageTag": japanese ? "ja" : "ko",
                    "tags": article?.tags ?? ["아키텍처"], "likeCount": article?.likeCount ?? 8,
                    "pinned": false, "lastEditedAt": NSNull(),
                    "publishedAt": iso(Date().addingTimeInterval(
                        -(article?.daysAgo ?? 1) * 86_400)),
                ],
                "blocks": blocks,
                "series": seriesNav.map { $0 as Any } ?? NSNull(),
            ])
        }

        // 공개 시리즈 상세 — 실서버 미목이라 fall-through 하면 404(시리즈 진행 화면 검증 불가).
        // ids 8001~ 는 `--seed-read` 로 읽음 시드와 짝지어 진행/체크 상태를 그려본다.
        if method == "GET", parts.count == 5, parts[0] == "public", parts[1] == "profiles",
           parts[3] == "series" {
            let username = parts[2]
            let titles = [
                ("포트와 어댑터", "경계를 먼저 긋고, 구현은 그 바깥으로 민다."),
                ("도메인을 안으로", "비즈니스 규칙이 프레임워크를 모르게 한다."),
                ("의존성 뒤집기", "화살표의 방향이 설계의 방향이다."),
                ("어댑터 구현", "DB·HTTP·큐는 전부 바깥의 디테일."),
                ("테스트 전략", "도메인은 단위로, 어댑터는 슬라이스로."),
                ("마이그레이션", "한 슬라이스씩, 멈추지 않고 갈아탄다."),
            ]
            let posts = titles.enumerated().map { i, t -> [String: Any] in
                [
                    "id": 8001 + i, "slug": "ep-\(i + 1)", "title": t.0, "excerpt": t.1,
                    "ogImageUrl": NSNull(), "languageTag": "ko", "tags": ["아키텍처"],
                    "likeCount": 5 - i, "pinned": false, "lastEditedAt": NSNull(),
                    "publishedAt": iso(Date().addingTimeInterval(-Double(titles.count - i) * 86_400)),
                ]
            }
            return json([
                "author": ["id": 1, "username": username, "bio": NSNull(), "avatarUrl": NSNull()],
                "series": [
                    // 수정 후 재로드가 새 제목·주소를 반영하게 override 를 우선 읽는다(없으면 기본값).
                    "id": 7, "slug": seriesTitles[7]?.0 ?? parts[4],
                    "title": seriesTitles[7]?.1 ?? "헥사고날 전환기",
                    "postCount": titles.count, "itemCount": titles.count + 1, "tags": ["아키텍처"],
                ],
                "posts": posts,
                "items": {
                    var items: [[String: Any]] = posts.map { ["type": "POST", "post": $0, "note": NSNull()] }
                    items.insert([
                        "type": "NOTE", "post": NSNull(),
                        "note": [
                            "id": 9540, "body": seriesNoteExcerpt, "contentWarning": NSNull(),
                            "excerpt": seriesNoteExcerpt,
                            "createdAt": iso(Date().addingTimeInterval(-2.5 * 86_400)),
                        ] as [String: Any],
                    ], at: 4)
                    return items
                }(),
            ])
        }

        // 발견 시리즈 — 최신 피드에 끼워 넣는 시리즈 카드(웹 메인 피드 패리티)의 소스.
        if method == "GET", parts == ["public", "series"] {
            return json([
                [
                    "id": 1,
                    "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
                    "slug": "hexagonal", "title": "헥사고날 전환기", "postCount": 6, "itemCount": 7,
                    "lastPublishedAt": iso(Date().addingTimeInterval(-86_400)),
                    "posts": [
                        // 앞장은 사진 커버(사진 변형), 뒷장은 무이미지(종이 변형) — 둘 다 확인용.
                        // 방향성 슬라이드(넘김) 데모/테스트가 여러 번 전진·순환하도록 4장.
                        [
                            "slug": "ep-1", "title": "포트와 어댑터",
                            "ogImageUrl": "https://picsum.photos/seed/hexa1/900/1100",
                        ],
                        ["slug": "ep-2", "title": "도메인을 안으로", "ogImageUrl": NSNull()],
                        [
                            "slug": "ep-3", "title": "의존성 뒤집기",
                            "ogImageUrl": "https://picsum.photos/seed/hexa3/900/1100",
                        ],
                        ["slug": "ep-4", "title": "어댑터를 갈아 끼우다", "ogImageUrl": NSNull()],
                    ],
                ],
                [
                    "id": 2,
                    "author": ["id": 2, "username": "narae", "bio": NSNull(), "avatarUrl": NSNull()],
                    "slug": "liquid-glass", "title": "iOS 앱 만들기", "postCount": 3,
                    "lastPublishedAt": iso(Date().addingTimeInterval(-3 * 86_400)),
                    "posts": [
                        [
                            "slug": "e1", "title": "리퀴드 글래스, 종이 본문",
                            "ogImageUrl": "https://picsum.photos/seed/glass2/900/1100",
                        ],
                        ["slug": "e2", "title": "탭바와 몰입", "ogImageUrl": NSNull()],
                    ],
                    "itemCount": 4,
                    "items": [
                        [
                            "type": "POST", "slug": "e1", "noteId": NSNull(), "title": "리퀴드 글래스, 종이 본문",
                            "ogImageUrl": "https://picsum.photos/seed/glass2/900/1100",
                        ],
                        [
                            "type": "NOTE", "slug": NSNull(), "noteId": 9540,
                            "title": "글래스는 크롬에만, 본문은 종이에. 이 한 줄로 디자인 회의가 끝났다.",
                            "ogImageUrl": NSNull(),
                        ],
                        ["type": "POST", "slug": "e2", "noteId": NSNull(), "title": "탭바와 몰입", "ogImageUrl": NSNull()],
                    ],
                ],
            ])
        }

        if method == "GET", parts == ["bookmarks"] {
            return json([
                // 발견 흐름에도 뜨는 글 — 미리보기 카드가 담긴 상태(채워진 북마크)로 보이게.
                ["id": 8201, "username": "honggildong", "title": "헥사고날로 갈아탄 지 석 달",
                 "slug": "hexagonal-after-3-months"],
                ["id": 9002, "username": "honggildong", "title": "발행된 목 글", "slug": "p-mock-2"],
                ["id": 9001, "username": "honggildong", "title": "목 초안 — 헥사고날 정리", "slug": "p-mock-1"],
            ])
        }

        if method == "GET", parts == ["users", "me", "likes"] {
            return json([
                // 발견 흐름에도 뜨는 글 — 미리보기 카드에 내 좋아요 표식이 보이게.
                feedItem(id: 8201, title: "헥사고날로 갈아탄 지 석 달", slug: "hexagonal-after-3-months"),
                feedItem(id: 9002, title: "발행된 목 글", slug: "p-mock-2"),
            ])
        }

        if method == "GET", parts == ["users", "me", "subscribed-series"] {
            return json([[
                "id": 1, "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
                "slug": "hexagonal", "title": "헥사고날 전환기", "postCount": 6, "itemCount": 7,
                "lastPublishedAt": iso(Date().addingTimeInterval(-86_400)),
                "posts": [["slug": "p-mock-2", "title": "발행된 목 글"]],
            ]])
        }

        if method == "GET", parts == ["feed", "following"] {
            // `--empty-feeds` = 빈 구독함/추천 안내 화면 스크린샷 검증용.
            let items = emptyFeeds ? [] : [feedItem(id: 9002, title: "발행된 목 글", slug: "p-mock-2")]
            // 구독한 시리즈에 들어온 노트 — 글보다 늦게 나와 글 앞에 선다.
            let seriesNotes: [[String: Any]] = emptyFeeds ? [] : [[
                "id": 9540,
                "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
                "body": seriesNoteExcerpt, "contentWarning": NSNull(), "excerpt": seriesNoteExcerpt,
                "createdAt": iso(Date().addingTimeInterval(-3_000)),
                "series": ["id": 7, "slug": "hexagonal", "title": "헥사고날 전환기"],
            ]]
            return json([
                "items": items, "page": 0, "size": 20, "hasNext": false, "seriesNotes": seriesNotes,
            ])
        }

        if method == "GET", parts == ["feed", "for-you"] {
            let items = emptyFeeds ? [] : [
                feedItem(id: 9101, title: "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
                         slug: "hexagonal-after-3-months",
                         excerpt: "레이어드를 버린 결정의 회고 — 경계가 준 것과 가져간 것.",
                         tags: ["아키텍처", "회고"]),
                feedItem(id: 9102, title: "토큰이 사라진 밤 — 새로고침 회전 레이스를 쫓다",
                         slug: "the-night-tokens-vanished",
                         excerpt: "글을 쓰다 로그아웃되는 버그. 범인은 회전하는 리프레시 토큰이었다.",
                         tags: ["디버깅", "인증"]),
            ]
            return json(["items": items, "page": 0, "size": 20, "hasNext": false])
        }

        // 공개 하이라이트 목록(+replyCount) — 본 글 리더가 문단에 칠한다.
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "posts",
           parts[3] == "highlights" {
            let items = highlightRows.map { row -> [String: Any] in
                var x = row
                x["replyCount"] = highlightReplies[(row["id"] as? Int) ?? -1]?.count ?? 0
                return x
            }
            return json(items)
        }
        // 하이라이트 생성(+선택적 메모) — 작성자는 나.
        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "highlights" {
            let req = decode(body)
            nextHighlightId += 1
            let row: [String: Any] = [
                "id": nextHighlightId,
                "author": ["id": 1, "username": myUsername, "bio": NSNull(), "avatarUrl": NSNull()],
                "blockOrder": req["blockOrder"] as? Int ?? 0,
                "endBlockOrder": req["endBlockOrder"] as? Int ?? (req["blockOrder"] as? Int ?? 0),
                "startOffset": req["startOffset"] as? Int ?? 0,
                "endOffset": req["endOffset"] as? Int ?? 0,
                "quote": req["quote"] as? String ?? "",
                "note": req["note"] ?? NSNull(),
                "createdAt": iso(Date()),
            ]
            highlightRows.append(row)
            return json(row)
        }
        // 하이라이트 삭제.
        if method == "DELETE", parts.count == 2, parts[0] == "highlights", let hid = Int(parts[1]) {
            highlightRows.removeAll { ($0["id"] as? Int) == hid }
            highlightReplies[hid] = nil
            return json([:] as [String: Any])
        }
        // 답글 — 목록 / 작성 / 삭제.
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "highlights",
           parts[3] == "replies", let hid = Int(parts[2]) {
            return json(highlightReplies[hid] ?? [])
        }
        // "이 문장이 담긴 컬렉션" — 이 하이라이트를 담은 공개 컬렉션(목: 순서 있는 104 + 101).
        if method == "GET", parts.count == 4, parts[0] == "public", parts[1] == "highlights",
           parts[3] == "collections" {
            let containing = collections.filter {
                $0.visibility == "PUBLIC" && [104, 101].contains($0.id)
            }
            return json(containing.map { collectionSummary($0) })
        }
        if method == "POST", parts.count == 3, parts[0] == "highlights", parts[2] == "replies",
           let hid = Int(parts[1]) {
            let req = decode(body)
            nextHighlightReplyId += 1
            let reply: [String: Any] = [
                "id": nextHighlightReplyId,
                "author": ["id": 1, "username": myUsername, "bio": NSNull(), "avatarUrl": NSNull()],
                "body": req["body"] as? String ?? "",
                "createdAt": iso(Date()),
            ]
            highlightReplies[hid, default: []].append(reply)
            return json(reply)
        }
        if method == "DELETE", parts.count == 2, parts[0] == "highlight-replies", let rid = Int(parts[1]) {
            for (hid, list) in highlightReplies {
                highlightReplies[hid] = list.filter { ($0["id"] as? Int) != rid }
            }
            return json([:] as [String: Any])
        }

        if method == "GET", parts == ["users", "me", "highlights"] {
            return json([
                ["id": 5001, "quote": "경계를 먼저 긋고, 구현은 그 바깥으로 민다.", "blockOrder": 2,
                 "postUsername": "honggildong", "postSlug": "p-mock-2", "postTitle": "발행된 목 글",
                 "createdAt": iso(Date().addingTimeInterval(-7200))],
                ["id": 5002, "quote": "좋은 추상은 더 지울 게 없을 때 완성된다.", "blockOrder": 5,
                 "postUsername": "honggildong", "postSlug": "p-mock-1", "postTitle": "목 초안 — 헥사고날 정리",
                 "createdAt": iso(Date().addingTimeInterval(-172_800))],
                // 같은 글(p-mock-2)에 둘째 구절 — 글별 그룹(한 헤더 아래 여러 구절)을 그려보기 위함.
                ["id": 5003, "quote": "테스트가 빨라지면 설계가 빨라진다.", "blockOrder": 7,
                 "postUsername": "honggildong", "postSlug": "p-mock-2", "postTitle": "발행된 목 글",
                 "createdAt": iso(Date().addingTimeInterval(-10_000))],
            ])
        }

        if method == "GET", parts == ["users", "me", "reading-history"] {
            return json([
                "items": [
                    ["postId": 9002, "username": "honggildong", "avatarUrl": NSNull(),
                     "title": "헥사고날로 갈아탄 지 석 달", "slug": "hexagonal-after-3-months",
                     "excerpt": "레이어드를 버린 결정의 회고 — 경계가 준 것과 가져간 것.",
                     "ogImageUrl": NSNull(), "readAt": iso(Date().addingTimeInterval(-3600))],
                    ["postId": 9101, "username": "haneul", "avatarUrl": NSNull(),
                     "title": "좋은 글쓰기의 조건", "slug": "good-writing", "excerpt": "문장은 짧게, 생각은 깊게.",
                     "ogImageUrl": NSNull(), "readAt": iso(Date().addingTimeInterval(-90_000))],
                ],
                "page": 0, "size": 20, "hasNext": false,
            ])
        }

        // 읽기 기록 한 건 잊기 / 전체 지우기 — UI 가 낙관적으로 처리하므로 204 만 돌려준다.
        if method == "DELETE", parts.count >= 3, parts[0] == "users", parts[1] == "me",
            parts[2] == "reading-history" {
            return Data()
        }

        if parts.count == 3, parts[0] == "comments", parts[2] == "like" {
            let cid = Int64(parts[1]) ?? 0
            if method == "POST" { likedComments.insert(cid) }
            if method == "DELETE" { likedComments.remove(cid) }
            return json(["likeCount": likedComments.contains(cid) ? 3 : 2, "liked": likedComments.contains(cid)])
        }

        if method == "GET", parts.count == 4, parts[0] == "posts", parts[2] == "comments", parts[3] == "liked" {
            return json(Array(likedComments))
        }

        if method == "DELETE", parts.count == 2, parts[0] == "comments" {
            return json([:] as [String: Any])
        }

        if parts == ["users", "me", "imports"] {
            if method == "POST" {
                let req = decode(body)
                let lines = ((req["csv"] as? String) ?? "").split(separator: "\n").count
                let started: [String: Any] = [
                    "id": Int64(32 + accountImports.count), "kind": ((req["kind"] as? String) ?? "following").uppercased(),
                    "total": lines, "processed": 0, "imported": 0, "finished": false, "createdAt": iso(Date()),
                ]
                accountImports.insert(started, at: 0)
                return json(started)
            }
            accountImports = accountImports.map { item in
                guard item["finished"] as? Bool == false, let total = item["total"] as? Int else { return item }
                var next = item
                let processed = min(total, (item["processed"] as? Int ?? 0) + max(1, total / 2))
                next["processed"] = processed
                next["imported"] = processed
                next["finished"] = processed >= total
                return next
            }
            return json(accountImports)
        }
        if method == "GET", parts == ["users", "me", "mention-candidates"] {
            let q = (query?.first(where: { $0.name == "q" })?.value ?? "").lowercased()
            let people: [[String: Any]] = [
                ["username": "yuki_dev", "displayName": "유키", "avatarUrl": NSNull(), "following": true],
                ["username": "reader_kim", "displayName": "김독자", "avatarUrl": NSNull(), "following": true],
                ["username": "haruka", "displayName": NSNull(), "avatarUrl": NSNull(), "following": false],
                ["username": "minji", "displayName": "민지", "avatarUrl": NSNull(), "following": false],
            ]
            let found = people.filter { person in
                guard !q.isEmpty else { return person["following"] as? Bool == true }
                let name = (person["username"] as? String) ?? ""
                let display = ((person["displayName"] as? String) ?? "").lowercased()
                return name.hasPrefix(q) || display.hasPrefix(q)
            }
            return json(found)
        }

        if parts.count >= 3, parts[0] == "users", parts[1] == "me", parts[2] == "suggestions" {
            if method == "DELETE", parts.count == 4 {
                dismissedSuggestions.insert(parts[3])
                return json([:] as [String: Any])
            }
            let all: [[String: Any]] = [
                ["username": "haneul", "displayName": "하늘", "avatarUrl": NSNull(), "bio": "프로덕트 디자이너",
                 "mutuals": 3, "reason": "FRIENDS", "locked": true],
                ["username": "minji", "displayName": NSNull(), "avatarUrl": NSNull(), "bio": NSNull(),
                 "mutuals": 1, "reason": "FRIENDS", "locked": false],
                ["username": "narae", "displayName": "나래", "avatarUrl": NSNull(), "bio": NSNull(),
                 "mutuals": 0, "reason": "POPULAR", "locked": false],
            ]
            return json(all.filter { !dismissedSuggestions.contains($0["username"] as? String ?? "") })
        }
        if method == "GET", parts.count == 4, parts[0] == "users", parts[1] == "me", parts[2] == "exports" {
            let csv: String
            switch parts[3] {
            case "following":
                csv = "Account address,Show boosts,Notify on new posts,Languages\nyuki_dev@kurl.me,true,true,\nmina@mastodon.social,true,false,\n"
            case "blocks": csv = ""
            case "mutes": csv = "Account address,Hide notifications\n"
            case "domain-blocks": csv = "spam.example\n"
            case "bookmarks": csv = "https://kurl.me/ap/notes/9501\n"
            case "lists": csv = "\"friends, close\",yuki_dev@kurl.me\n"
            default: return nil
            }
            return Data(csv.utf8)
        }
        if parts == ["notifications", "policy"] {
            if method == "PUT" {
                for (key, value) in decode(body) {
                    if let level = value as? String { notificationPolicy[key] = level }
                }
            }
            return json(notificationPolicy)
        }
        if method == "GET", parts == ["notifications", "requests"] {
            return json(filteredSenders)
        }
        if method == "POST", parts.count == 3, parts[0] == "notifications", parts[1] == "requests" {
            let req = decode(body)
            let user = (req["actorUserId"] as? NSNumber)?.int64Value
            let remote = (req["actorRemoteId"] as? NSNumber)?.int64Value
            filteredSenders.removeAll {
                ($0["actorUserId"] as? Int64) == user && user != nil
                    || ($0["actorRemoteId"] as? Int64) == remote && remote != nil
            }
            return json([:] as [String: Any])
        }
        if method == "GET", parts == ["users", "me", "follow-requests"] {
            return json(memberRequests.map { request -> [String: Any] in
                ["username": request.username, "displayName": request.displayName ?? NSNull(),
                 "avatarUrl": NSNull(), "requestedAt": iso(request.at)]
            })
        }
        if method == "POST", parts.count == 5, parts[0] == "users", parts[2] == "follow-requests" {
            let username = parts[3]
            guard memberRequests.contains(where: { $0.username == username }) else { return nil }
            memberRequests.removeAll { $0.username == username }
            return json([:] as [String: Any])
        }
        if method == "GET", parts == ["federation", "follow-requests"] {
            return json(remoteRequests.sorted { $0.value > $1.value }.compactMap { id, at -> [String: Any]? in
                guard let account = remoteAccounts[id] else { return nil }
                return ["id": id, "acct": account["acct"] ?? "", "username": account["username"] ?? "",
                        "domain": account["domain"] ?? "", "displayName": account["displayName"] ?? NSNull(),
                        "avatarUrl": NSNull(), "url": account["url"] ?? "", "requestedAt": iso(at)]
            })
        }
        if method == "POST", parts.count == 4, parts[0] == "federation", parts[1] == "follow-requests",
           let id = Int64(parts[2]) {
            guard remoteRequests.removeValue(forKey: id) != nil else { return nil }
            return json([:] as [String: Any])
        }

        if method == "GET", parts == ["notifications"] {
            let requestItems: [[String: Any]] =
                memberRequests.enumerated().map { index, request -> [String: Any] in
                    ["id": 700 + index, "type": "FOLLOW_REQUEST", "actorUsername": request.username,
                     "actorAvatarUrl": NSNull(),
                     "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "count": 1, "read": false, "createdAt": iso(request.at)]
                }
                + remoteRequests.keys.sorted().map { id -> [String: Any] in
                    ["id": 750 + Int(id - 9800), "type": "FOLLOW_REQUEST",
                     "actorUsername": remoteAccounts[id]?["acct"] ?? "", "actorAvatarUrl": NSNull(),
                     "actorProfileUrl": remoteAccounts[id]?["url"] ?? "", "actorRemoteId": id,
                     "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "count": 1, "read": false, "createdAt": iso(remoteRequests[id] ?? Date())]
                }
            let fixedItems: [[String: Any]] = [
                ["id": 1, "type": "LIKE", "actorUsername": "reader_kim", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "read": false, "createdAt": iso(Date().addingTimeInterval(-600))],
                ["id": 2, "type": "COMMENT", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": NSNull(),
                 "commentId": 506,
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "read": false, "createdAt": iso(Date().addingTimeInterval(-3600))],
                ["id": 3, "type": "FOLLOW", "actorUsername": "stranger99", "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "read": true, "createdAt": iso(Date().addingTimeInterval(-86_400))],
                ["id": 4, "type": "SERIES_SUBSCRIBE", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": 1, "seriesSlug": "hexagonal", "seriesTitle": "헥사고날 전환기",
                 "read": true, "createdAt": iso(Date().addingTimeInterval(-172_800))],
                ["id": 5, "type": "REPLY", "actorUsername": "reader_kim", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                 "commentId": 507,
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "read": true, "createdAt": iso(Date().addingTimeInterval(-259_200))],
                ["id": 6, "type": "MENTION", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                 "highlightId": 6001,
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "read": true, "createdAt": iso(Date().addingTimeInterval(-345_600))],
                ["id": 7, "type": "NEW_POST", "actorUsername": "honggildong", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "read": true, "createdAt": iso(Date().addingTimeInterval(-432_000))],
                ["id": 12, "type": "NOTE_LIKE", "actorUsername": "alice@mastodon.social", "actorAvatarUrl": NSNull(),
                 "actorProfileUrl": "https://mastodon.social/@alice", "actorRemoteId": Int64(9820),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "noteId": 9502, "noteExcerpt": "긴 글로 정리하기 전의 생각 조각을 둘 곳이 필요했는데, 노트가 딱 그 자리다.",
                 "count": 4, "read": false, "createdAt": iso(Date().addingTimeInterval(-300))],
                ["id": 11, "type": "NOTE_REPLY", "actorUsername": "reader_kim", "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "noteId": 9502, "noteExcerpt": "긴 글로 정리하기 전의 생각 조각을 둘 곳이 필요했는데, 노트가 딱 그 자리다.",
                 "sourceNoteId": 9551, "sourceExcerpt": "이름이 경계라는 말, 오래 남을 것 같아요.",
                 "count": 1, "read": false, "createdAt": iso(Date().addingTimeInterval(-450))],
                ["id": 13, "type": "NOTE_MENTION", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "noteId": 9501, "noteExcerpt": "오늘 헥사고날 포트 이름 짓는 데 한 시간 썼다.",
                 "count": 1, "read": false, "createdAt": iso(Date().addingTimeInterval(-600))],
                ["id": 14, "type": "NOTE_POST", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "noteId": 9501, "noteExcerpt": "오늘 헥사고날 포트 이름 짓는 데 한 시간 썼다.",
                 "count": 1, "read": false, "createdAt": iso(Date().addingTimeInterval(-700))],
                ["id": 15, "type": "NOTE_EDIT", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "noteId": 9501, "noteExcerpt": "오늘 헥사고날 포트 이름 짓는 데 한 시간 썼다.",
                 "count": 1, "read": true, "createdAt": iso(Date().addingTimeInterval(-800))],
                ["id": 10, "type": "REMOTE_FOLLOW", "actorUsername": "bob@fosstodon.org", "actorAvatarUrl": NSNull(),
                 "actorProfileUrl": "https://fosstodon.org/@bob", "actorRemoteId": Int64(9830),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "count": 1, "read": true, "createdAt": iso(Date().addingTimeInterval(-900))],
                // 연결 그래프 — 내 글이 큐레이터 컬렉션에 엮임(딥링크=컬렉션 101 "느린 사고").
                ["id": 8, "type": "CONNECTED", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "collectionId": 101, "collectionName": "느린 사고",
                 "read": false, "createdAt": iso(Date().addingTimeInterval(-1200))],
                // 연결 그래프 — 내 글이 엮인 컬렉션(104)에 새 글이 이어짐. actor 없이 시스템 발행.
                ["id": 9, "type": "PATH_GREW", "actorUsername": NSNull(), "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "collectionId": 104, "collectionName": "경계를 긋는다는 것",
                 "read": false, "createdAt": iso(Date().addingTimeInterval(-2400))],
                ["id": 16, "type": "COMMENT_LIKE", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                 "commentId": 506,
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "count": 3, "read": false, "createdAt": iso(Date().addingTimeInterval(-400_000))],
                ["id": 17, "type": "HIGHLIGHT", "actorUsername": "reader_kim", "actorAvatarUrl": NSNull(),
                 "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": NSNull(),
                 "highlightId": 6001,
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "count": 2, "read": false, "createdAt": iso(Date().addingTimeInterval(-410_000))],
                ["id": 18, "type": "POST_QUOTE", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "noteId": 9501, "noteExcerpt": "오늘 헥사고날 포트 이름 짓는 데 한 시간 썼다.",
                 "count": 1, "read": true, "createdAt": iso(Date().addingTimeInterval(-420_000))],
                ["id": 19, "type": "NOTE_EMBED", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                 "postId": 9003, "postSlug": "yuki-notes-roundup", "postTitle": "이번 주 노트 모음",
                 "postAuthorUsername": "yuki_dev",
                 "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                 "count": 1, "read": true, "createdAt": iso(Date().addingTimeInterval(-430_000))],
            ]
            return json([
                "items": requestItems + fixedItems,
                "nextCursor": NSNull(), "hasMore": false,
            ])
        }

        if method == "GET", parts == ["notifications", "unread-count"] {
            return json(["count": 2])
        }

        if method == "POST", parts.count == 3, parts[0] == "notifications", parts[2] == "read" {
            return json([:] as [String: Any])
        }

        if method == "POST", parts == ["notifications", "read-all"] {
            return json(["count": 0])
        }

        // 알림 종류별 켬/끔 — GET 은 7타입 맵, PUT 은 한 타입씩(웹·앱 공통 계약).
        if parts == ["notifications", "blog-preferences"] {
            if method == "PUT" {
                let req = decode(body)
                if let type = req["type"] as? String, let enabled = req["enabled"] as? Bool {
                    blogNotificationPrefs[type] = enabled
                }
                return json([:] as [String: Any])
            }
            if method == "GET" {
                return json(blogNotificationPrefs)
            }
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "preview-token" {
            return json(["token": "mock-preview-token"])
        }

        if method == "POST", parts.count == 3, parts[0] == "posts", parts[2] == "schedule" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts[idx].status = "SCHEDULED"
            posts[idx].scheduledAt = Date().addingTimeInterval(3600)
            return json(postView(posts[idx]))
        }

        if method == "GET", parts.count == 3, parts[0] == "posts", parts[2] == "revisions" {
            return json([
                ["id": 1, "versionNumber": 2, "titleSnapshot": "두 번째 저장", "createdAt": iso(Date().addingTimeInterval(-3600))],
                ["id": 2, "versionNumber": 1, "titleSnapshot": "첫 저장", "createdAt": iso(Date().addingTimeInterval(-7200))],
            ])
        }

        if method == "POST", parts.count == 5, parts[0] == "posts", parts[2] == "revisions", parts[4] == "restore" {
            guard let idx = posts.firstIndex(where: { String($0.id) == parts[1] }) else { return nil }
            posts[idx].markdown = "# 복원된 본문 v\(parts[3])\n\n리비전에서 돌아왔다."
            posts[idx].contentVersion += 1
            return json(postView(posts[idx]))
        }

        if method == "POST", parts == ["series"] {
            let req = decode(body)
            let id = nextSeriesId
            nextSeriesId += 1
            createdSeries.append((id, req["slug"] as? String ?? "s-\(id)", req["title"] as? String ?? "시리즈"))
            seriesMembers[id] = []
            return json(["series": ["id": id, "slug": req["slug"] as? String ?? "s", "title": req["title"] as? String ?? "시리즈", "postCount": 0, "createdAt": iso(Date()), "updatedAt": iso(Date())], "posts": []])
        }

        if method == "GET", parts == ["series"] {
            return json((mockSeries + createdSeries).map { ["id": $0.0, "slug": $0.1, "title": $0.2, "postCount": seriesMembers[$0.0]?.count ?? 0, "createdAt": iso(Date()), "updatedAt": iso(Date())] })
        }

        if method == "GET", parts.count == 2, parts[0] == "series" {
            let sid = Int64(parts[1]) ?? 0
            // 공개 상세(id 7)로 들어온 주인 시리즈 — 순서 편집이 다룰 회차를 그 화면과 같은 6편으로 준다
            // (초안 한 편 섞어 발행 전 회차 표식까지 확인 가능하게). 나머지 id 는 실제 멤버십을 읽는다.
            if sid == 7 {
                let member = seriesFixtureMembers()
                var items = member.map(ownerPostItem)
                items.insert(ownerNoteItem(9540), at: 4)
                return json([
                    "series": ["id": 7, "slug": seriesTitles[7]?.0 ?? "hexagonal",
                               "title": seriesTitles[7]?.1 ?? "헥사고날 전환기",
                               "postCount": member.count, "createdAt": iso(Date()), "updatedAt": iso(Date())],
                    "posts": member,
                    "items": ownerItems[7] ?? items,
                ])
            }
            let members = (seriesMembers[sid] ?? []).compactMap { id in posts.first { $0.id == id } }
            return json([
                "series": ["id": sid, "slug": seriesTitles[sid]?.0 ?? "s",
                           "title": seriesTitles[sid]?.1 ?? "시리즈",
                           "postCount": members.count, "createdAt": iso(Date()), "updatedAt": iso(Date())],
                "posts": members.map(postView),
                "items": ownerItems[sid] ?? members.map(postView).map(ownerPostItem),
            ])
        }

        // 이름·주소 수정 — PATCH(바뀐 것만 온다). 목은 제목·slug 만 기억해 재로드 시 반영한다.
        if method == "PATCH", parts.count == 2, parts[0] == "series" {
            let sid = Int64(parts[1]) ?? 0
            let req = decode(body)
            let prev = seriesTitles[sid] ?? (sid == 7 ? "hexagonal" : "s", sid == 7 ? "헥사고날 전환기" : "시리즈")
            let newSlug = (req["slug"] as? String).map { $0.isEmpty ? prev.0 : $0 } ?? prev.0
            let newTitle = (req["title"] as? String).map { $0.isEmpty ? prev.1 : $0 } ?? prev.1
            seriesTitles[sid] = (newSlug, newTitle)
            return json([
                "series": ["id": sid, "slug": newSlug, "title": newTitle,
                           "postCount": seriesMembers[sid]?.count ?? 0,
                           "createdAt": iso(Date()), "updatedAt": iso(Date())],
                "posts": [],
            ])
        }

        // 시리즈 삭제 — 소속만 풀고 204. 목은 멤버십·제목 override 만 비운다.
        if method == "DELETE", parts.count == 2, parts[0] == "series" {
            let sid = Int64(parts[1]) ?? 0
            for i in posts.indices where posts[i].seriesId == sid { posts[i].seriesId = nil }
            seriesMembers[sid] = []
            seriesTitles[sid] = nil
            return json([:])
        }

        // 항목 지정(글·노트 한 순서) — 목은 주인 상세가 다시 읽을 항목만 기억한다.
        if method == "PUT", parts.count == 3, parts[0] == "series", parts[2] == "items" {
            let sid = Int64(parts[1]) ?? 0
            let requested = (decode(body)["items"] as? [[String: Any]]) ?? []
            let members = seriesFixtureMembers() + posts.map(postView)
            ownerItems[sid] = requested.compactMap { item -> [String: Any]? in
                guard let id = (item["id"] as? NSNumber)?.int64Value else { return nil }
                if (item["type"] as? String) == "NOTE" { return ownerNoteItem(id) }
                return members.first { ($0["id"] as? NSNumber)?.int64Value == id }.map(ownerPostItem)
            }
            return json(["series": ["id": sid, "slug": "s", "title": "시리즈", "postCount": 0, "createdAt": iso(Date()), "updatedAt": iso(Date())], "posts": []])
        }

        if method == "PUT", parts.count == 3, parts[0] == "series", parts[2] == "posts" {
            let sid = Int64(parts[1]) ?? 0
            let ids = (decode(body)["postIds"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.int64Value }
            seriesMembers[sid] = ids
            for i in posts.indices {
                if ids.contains(posts[i].id) { posts[i].seriesId = sid }
                else if posts[i].seriesId == sid { posts[i].seriesId = nil }
            }
            return json(["series": ["id": sid, "slug": "s", "title": "시리즈", "postCount": ids.count, "createdAt": iso(Date()), "updatedAt": iso(Date())], "posts": []])
        }

        if method == "POST", parts.count == 4, parts[0] == "posts", parts[2] == "images", parts[3] == "presign" {
            return json([
                "uploadUrl": "https://mock-upload.invalid/put",
                // 실제로 로드되는 이미지 — 예전 cdn.kurl.me/mock-cover.jpg 는 404 라 목 모드에서 썸네일이 안 떴다.
                "publicUrl": Self.mockUploadedImageURL,
                "key": "mock/cover.jpg", "contentType": "image/jpeg", "maxBytes": 5_242_880,
            ])
        }

        if method == "POST", parts.count == 4, parts[0] == "posts", parts[2] == "images", parts[3] == "commit" {
            return json(["imageUrl": Self.mockUploadedImageURL, "key": "mock/cover.jpg"])
        }

        return nil
    }

    private static let mockSeries: [(Int64, String, String)] = [
        (1, "hexagonal", "헥사고날 전환기"),
        (2, "ios-build", "iOS 앱 만들기"),
    ]
    private static var seriesMembers: [Int64: [Int64]] = [1: [9002], 2: []]
    /// 수정으로 바뀐 (slug, title) — 재로드 시 새 이름·주소가 반영되게 override 로 보관(초기값은 nil).
    private static var seriesTitles: [Int64: (String, String)] = [:]
    /// 주인 순서 편집이 다룰 회차 6편(공개 상세 id 7 과 같은 목록) — 마지막 한 편은 초안으로 두어
    /// 발행 전 회차 표식까지 확인 가능하게 한다. `.onMove` 로 순서를 바꾸고 저장해 왕복을 검증한다.
    private static func seriesFixtureMembers() -> [[String: Any]] {
        let titles = [
            "포트와 어댑터", "도메인을 안으로", "의존성 뒤집기",
            "어댑터 구현", "테스트 전략", "마이그레이션",
        ]
        return titles.enumerated().map { i, t in
            let draft = i == titles.count - 1
            return [
                "id": 8001 + i, "slug": "ep-\(i + 1)", "title": t, "status": draft ? "DRAFT" : "PUBLISHED",
                "languageTag": "ko",
                "publishedAt": draft ? NSNull() : iso(Date().addingTimeInterval(-Double(titles.count - i) * 86_400)),
                "scheduledAt": NSNull(), "excerpt": NSNull(), "ogImageUrl": NSNull(),
                "seriesId": 7, "seriesOrder": i, "viewCount": 42, "likeCount": 5 - i,
                "tags": ["아키텍처"], "createdAt": iso(Date()), "updatedAt": iso(Date()),
            ]
        }
    }
    /// 항목 지정으로 바뀐 주인 항목 — 없으면 기본(글 + 7번 시리즈의 노트 한 편).
    private static var ownerItems: [Int64: [[String: Any]]] = [:]

    private static func ownerPostItem(_ post: [String: Any]) -> [String: Any] {
        [
            "type": "POST", "note": NSNull(),
            "post": ["id": post["id"] ?? 0, "title": post["title"] ?? "", "status": post["status"] ?? "PUBLISHED"],
        ]
    }

    private static func ownerNoteItem(_ id: Int64) -> [String: Any] {
        let body = allNotes().first { $0.id == id }?.body ?? ""
        return ["type": "NOTE", "post": NSNull(), "note": ["id": id, "excerpt": body]]
    }

    private static var createdSeries: [(Int64, String, String)] = []
    private static var nextSeriesId: Int64 = 100
    private static var likedComments: Set<Int64> = []

    /// 노트를 카드로 실은 글 — 9501(유키의 포트 이름 노트)을 "walk-notes" 글이 싣는다.
    private static var quotingPosts: [Int64: [[String: Any]]] {
        [9501: [feedItem(id: 9201, title: "이름이 곧 경계다", slug: "walk-notes", excerpt: "유키의 노트에서 시작한 글.")]]
    }

    private static func feedItem(
        id: Int64, title: String, slug: String,
        excerpt: String = "결론부터 적는다. 경계를 먼저 긋고, 구현은 그 바깥으로 민다.",
        tags: [String] = ["아키텍처"]
    ) -> [String: Any] {
        [
            "id": id,
            "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
            "slug": slug, "title": title, "excerpt": excerpt,
            "ogImageUrl": NSNull(), "languageTag": "ko", "tags": tags,
            "publishedAt": iso(Date().addingTimeInterval(-3600)),
            "viewCount": 42, "likeCount": 3,
        ]
    }

    // MARK: 픽스처

    private static func allNotes() -> [MockNote] { notes + noteReplies }

    /// 작성자가 자기 노트에 이어 단 답글 사슬(이어 쓰기) — 한 노트에 둘이면 먼저 단 것을 따라간다.
    private static func selfChain(_ root: MockNote) -> [MockNote] {
        var chain: [MockNote] = []
        var current = root.id
        while chain.count < 9,
              let next = allNotes().filter({ $0.inReplyToId == current && $0.authorId == root.authorId })
                .min(by: { $0.createdAt < $1.createdAt }) {
            chain.append(next)
            current = next.id
        }
        return chain
    }

    private static func replyCount(_ id: Int64) -> Int {
        noteReplies.filter { $0.inReplyToId == id }.count
    }

    private static func topLevelNotes() -> [MockNote] {
        notes.filter { $0.inReplyToId == nil && mutedUsers[$0.username] == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    private static func createMockNote(_ req: [String: Any]) -> MockNote {
        let images = (req["images"] as? [[String: Any]]) ?? []
        var note = MockNote(
            id: nextNoteId, body: req["body"] as? String ?? "",
            createdAt: Date(), likeCount: 0, authorId: 1, username: "honggildong",
            inReplyToId: (req["inReplyToId"] as? NSNumber)?.int64Value,
            media: images.map { image in
                ["url": "https://picsum.photos/seed/kurl-note/800/600",
                 "altText": (image["altText"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? NSNull(),
                 "contentType": "image/jpeg"]
            })
        note.quotedNoteId = (req["quotedNoteId"] as? NSNumber)?.int64Value
        note.contentWarning = (req["contentWarning"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        note.sensitive = (req["sensitive"] as? Bool) ?? false
        note.visibility = (req["visibility"] as? String) ?? "public"
        if let poll = req["poll"] as? [String: Any], let options = poll["options"] as? [String] {
            note.poll = MockPoll(
                options: options,
                expiresAt: Date().addingTimeInterval((poll["expiresIn"] as? NSNumber)?.doubleValue ?? 86_400),
                multiple: (poll["multiple"] as? Bool) ?? false,
                votes: options.map { _ in 0 }, voters: 0)
        }
        if let quoted = (req["quotedPostId"] as? NSNumber)?.int64Value {
            note.quotedPost = [
                "id": quoted, "title": "인용한 글", "slug": "quoted", "authorUsername": "honggildong",
            ]
        }
        nextNoteId += 1
        if note.inReplyToId == nil { notes.insert(note, at: 0) } else { noteReplies.append(note) }
        return note
    }

    private static func noteView(_ n: MockNote) -> [String: Any] {
        var view = baseNoteView(n)
        if n.inReplyToId == nil {
            let chain = selfChain(n)
            if let next = chain.first {
                view["thread"] = ["total": chain.count + 1, "preview": [baseNoteView(next)]] as [String: Any]
            }
        }
        return view
    }

    private static func baseNoteView(_ n: MockNote) -> [String: Any] {
        [
            "id": n.id, "body": n.body, "createdAt": iso(n.createdAt),
            "editedAt": n.editedAt.map(iso) ?? NSNull(),
            "likeCount": n.likeCount,
            "likedByMe": likedNotes.contains(n.id),
            "author": [
                "id": n.authorId, "username": n.username, "avatarUrl": NSNull(),
                "displayName": displayNames[n.username] ?? NSNull(),
            ],
            "media": n.media,
            "quotedPost": n.quotedPost ?? NSNull(),
            "inReplyToId": n.inReplyToId ?? NSNull(),
            "replyCount": replyCount(n.id),
            "repostCount": repostCount(n.id),
            "repostedByMe": repostedNotes["honggildong"]?.contains(n.id) == true,
            "bookmarkedByMe": bookmarkedNotes.contains(n.id),
            "quoteCount": allNotes().filter { $0.quotedNoteId == n.id }.count + (quotingPosts[n.id]?.count ?? 0),
            "linkPreview": n.linkPreview ?? NSNull(),
            "mentions": ["honggildong", "yuki_dev", "reader_kim"].filter { n.body.lowercased().contains("@" + $0) },
            "contentWarning": n.contentWarning ?? NSNull(),
            "sensitive": n.sensitive || n.contentWarning != nil,
            "pinned": pinnedNotes.contains(n.id),
            "visibility": n.visibility,
            "poll": pollView(n) ?? NSNull(),
            "conversationMuted": mutedConversations.contains(n.id),
            "quotedNote": n.quotedNoteId.flatMap { qid in allNotes().first { $0.id == qid } }
                .map { q -> [String: Any] in
                    [
                        "id": q.id, "body": q.body, "createdAt": iso(q.createdAt),
                        "author": ["id": q.authorId, "username": q.username, "avatarUrl": NSNull()],
                        "media": q.media,
                        "contentWarning": q.contentWarning ?? NSNull(),
                        "sensitive": q.sensitive || q.contentWarning != nil,
                    ]
                } ?? NSNull(),
        ]
    }

    private static func pollView(_ n: MockNote) -> [String: Any]? {
        guard let poll = n.poll else { return nil }
        let mine = n.authorId == 1
        return [
            "expiresAt": iso(poll.expiresAt), "expired": poll.expiresAt <= Date(), "multiple": poll.multiple,
            "votesCount": poll.votes.reduce(0, +), "votersCount": poll.voters,
            "options": zip(poll.options, poll.votes).map { ["title": $0, "votesCount": $1] },
            "voted": mine || poll.mine != nil, "ownVotes": poll.mine ?? [],
        ]
    }

    private static func repostCount(_ noteId: Int64) -> Int {
        repostedNotes.values.filter { $0.contains(noteId) }.count
    }

    private static func postView(_ p: MockPost) -> [String: Any] {
        [
            "id": p.id, "slug": p.slug, "title": p.title, "status": p.status,
            "languageTag": "ko",
            "publishedAt": p.publishedAt.map(iso) ?? NSNull(),
            "scheduledAt": p.scheduledAt.map(iso) ?? NSNull(),
            "excerpt": p.excerpt ?? NSNull(),
            "ogImageUrl": p.ogImageUrl ?? NSNull(),
            "seriesId": p.seriesId ?? NSNull(),
            "contentVersion": p.contentVersion,
            "viewCount": 42, "likeCount": 3, "tags": p.tags,
            "createdAt": iso(p.updatedAt), "updatedAt": iso(p.updatedAt),
        ]
    }

    private static func postAnalyticsFixture(id: Int64) -> [String: Any] {
        let p = posts.first { $0.id == id }
        let calendar = Calendar(identifier: .gregorian)
        let daily: [[String: Any]] = (0..<30).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return ["date": fmt.string(from: day), "views": Int.random(in: 4...60)]
        }
        return [
            "postId": id, "slug": p?.slug ?? "p-mock", "title": p?.title ?? "글",
            "status": p?.status ?? "PUBLISHED",
            "lifetimeViews": 812, "lifetimeLikes": 41, "windowDays": 30, "windowViews": 624,
            "lifetimeLinkClicks": 57, "windowLinkClicks": 38, "lifetimeFollows": 9, "windowFollows": 4,
            "daily": daily,
        ]
    }

    private static func seriesDetailFixture(id: Int64) -> [String: Any] {
        let known: [Int64: (slug: String, title: String, titles: [String], subs: Int64, views: Int64, likes: Int64)] = [
            1: ("hexagonal", "헥사고날 전환기",
                ["포트와 어댑터", "도메인을 안으로", "의존성 뒤집기", "어댑터 구현", "테스트 전략", "마이그레이션"],
                14, 1930, 72),
            2: ("ios-build", "iOS 앱 만들기",
                ["Xcode 세팅", "첫 화면", "배포까지"],
                7, 640, 25),
        ]
        let s = known[id] ?? ("series", "시리즈", ["1화", "2화", "3화", "4화"], 9, 800, 30)
        let count = s.titles.count

        let calendar = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        // 구독자 추이 — 30일 완만 상승(누적).
        let subscriberDaily: [[String: Any]] = (0..<30).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let progress = Double(30 - back) / 30.0
            return ["date": fmt.string(from: day), "views": Int(Double(s.subs) * (0.45 + 0.55 * progress))]
        }
        // 회차 funnel — 고유 독자 완만 감소 + 다음 화 read-through(이어 읽은 수).
        var members: [[String: Any]] = []
        var readers = Int64(Double(s.views) / Double(max(count, 1)) * 0.62)
        for (i, title) in s.titles.enumerated() {
            let isLast = i == count - 1
            let next = isLast ? 0 : Int64(Double(readers) * Double.random(in: 0.62...0.86))
            members.append([
                "postId": 8000 + i + 1, "slug": "ep-\(i + 1)", "title": title, "episode": i + 1,
                "views": Int64(Double(readers) * 1.35), "likes": max(1, readers / 14),
                "follows": max(0, readers / 40), "uniqueReaders": readers, "continuedToNext": next,
            ])
            readers = isLast ? readers : max(8, next + Int64.random(in: 0...6))
        }
        return [
            "series": [
                "seriesId": id, "slug": s.slug, "title": s.title,
                "postCount": count, "subscriberCount": s.subs,
                "totalViews": s.views, "totalLikes": s.likes,
            ],
            "windowDays": 30,
            "subscriberDaily": subscriberDaily,
            "members": members,
        ]
    }

    private static func readStatsFixture() -> [String: Any] {
        [
            "timezone": "Asia/Seoul",
            "totalVisits": 812, "humanVisits": 781, "botVisits": 31, "uniqueVisits": 596,
            "firstVisitAt": NSNull(), "lastVisitAt": NSNull(), "peakHour": 21,
            "dailyVisits": [], "hourVisits": [], "heatmap": [],
            "countryVisits": [
                ["country": "KR", "count": 540], ["country": "US", "count": 121],
                ["country": "JP", "count": 58], ["country": "GB", "count": 22],
                ["country": "DE", "count": 11],
            ],
            "deviceVisits": [
                ["device": "mobile", "count": 498], ["device": "desktop", "count": 271],
                ["device": "tablet", "count": 43],
            ],
            "browserVisits": [],
            "referrerHostVisits": [
                ["host": "google.com", "count": 96], ["host": "t.co", "count": 71],
            ],
            "sourceChannelVisits": [
                ["source": "direct", "count": 402], ["source": "social", "count": 214],
                ["source": "search", "count": 118], ["source": "referral", "count": 47],
            ],
            "utmCampaignVisits": [], "utmSourceVisits": [],
        ]
    }

    private static func analyticsOverview() -> [String: Any] {
        let calendar = Calendar(identifier: .gregorian)
        let daily: [[String: Any]] = (0..<30).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return ["date": fmt.string(from: day), "views": Int.random(in: 8...90)]
        }
        return [
            "totalPosts": 24, "publishedPosts": 21,
            "lifetimeViews": 5421, "lifetimeLikes": 132,
            "windowDays": 30, "windowViews": 1284,
            "lifetimeLinkClicks": 310, "windowLinkClicks": 57,
            "lifetimeFollows": 48, "windowFollows": 6,
            "daily": daily,
            "referrers": [
                ["host": "google.com", "views": 412],
                ["host": "t.co", "views": 187],
                ["host": "news.hada.io", "views": 96],
                ["host": "kurl.me", "views": 44],
            ],
        ]
    }

    // MARK: 유틸

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func decode(_ body: Data?) -> [String: Any] {
        guard let body,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func withDomainBlock(_ account: [String: Any]) -> [String: Any] {
        var shown = account
        shown["domainBlocked"] = domainBlocks[(account["domain"] as? String) ?? ""] != nil
        return shown
    }

    private static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
    }
}
