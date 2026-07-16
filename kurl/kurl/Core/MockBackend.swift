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
    }

    private static var posts: [MockPost] = [
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
                 markdown: "# 발행됨\n\n본문.", publishedAt: Date().addingTimeInterval(-86_400), updatedAt: Date(),
                 tags: ["회고", "iOS"], excerpt: "한 달간의 작업을 정리했다."),
    ]
    private struct MockNote {
        var id: Int64
        var body: String
        var createdAt: Date
        var likeCount: Int64
        var authorId: Int64
        var username: String
    }

    private static var notes: [MockNote] = [
        MockNote(id: 9501, body: "오늘 헥사고날 포트 이름 짓는 데 한 시간 썼다. 이름이 곧 경계라는 걸 다시 배운다.",
                 createdAt: Date().addingTimeInterval(-1_800), likeCount: 4, authorId: 2, username: "yuki_dev"),
        MockNote(id: 9502, body: "긴 글로 정리하기 전의 생각 조각을 둘 곳이 필요했는데, 노트가 딱 그 자리다.",
                 createdAt: Date().addingTimeInterval(-7_200), likeCount: 11, authorId: 1, username: "honggildong"),
        MockNote(id: 9503, body: "라이트 모드 캔버스를 순백에서 slate-50 으로 바꿨더니 카드가 비로소 떠 보인다. 배경은 색이 아니라 깊이다.",
                 createdAt: Date().addingTimeInterval(-26_000), likeCount: 7, authorId: 3, username: "reader_kim"),
    ]
    private static var nextNoteId: Int64 = 9600
    private static var likedNotes: Set<Int64> = []
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
         "blockOrder": 1, "endBlockOrder": 2, "startOffset": 30, "endOffset": 18,
         "quote": "다만 첫 두 주에 들인 비용을 미리 알았다면, 훨씬 더 작게 시작했을 것이다. 레이어드 구조로 3년을",
         "note": NSNull(),
         "createdAt": iso(Date().addingTimeInterval(-5_000))],
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
             "body": "첫 두 주 비용을 어떻게 줄였는지 더 듣고 싶어요.",
             "createdAt": iso(Date().addingTimeInterval(-3_000))],
        ]
    ]
    private static var nextHighlightId = 6100
    private static var nextHighlightReplyId = 7100

    /// `--empty-feeds` = 구독함·추천을 빈 응답으로 — 빈 안내 화면 검증용.
    private static let emptyFeeds = ProcessInfo.processInfo.arguments.contains("--empty-feeds")

    /// `--discover-global` = 발견 연결·하이라이트 흐름을 전역 폴백(source="global")으로 — 팔로우 0
    /// 콜드스타트에서 서버가 전역 공개 흐름으로 내려주는 모드를 목으로 재현한다(맥락 캡션 검증용).
    private static let discoverGlobal = ProcessInfo.processInfo.arguments.contains("--discover-global")

    /// `--discover-no-source` = 발견 응답에서 `source` 필드를 아예 빼 옛 서버(계약 미배포)를 재현 —
    /// 디코딩이 옵셔널로 following 을 유지해 캡션 없이 기존 동작 그대로인지 검증한다(무회귀).
    private static let discoverNoSource = ProcessInfo.processInfo.arguments.contains("--discover-no-source")

    private static var nextId: Int64 = 9100
    private static var likes: [Int64: (count: Int64, liked: Bool)] = [:]
    private static var bookmarks: Set<Int64> = []
    private static var follows: [String: (following: Bool, count: Int64)] = [:]
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
    private static var myHideFollowerCount = false
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
                    .glassEffect(.regular, in: .rect(cornerRadius: Metrics.radiusCard))

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
        var connections: [MockConnection]
    }

    static var collections: [MockCollection] = [
        MockCollection(
            id: 101, title: "느린 사고", description: "빨리 답하지 않고 오래 머문 글들.", visibility: "PUBLIC",
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
                    id: 503, blockType: "NOTE", why: nil,
                    body: "결정을 미루는 건 게으름이 아니라, 더 나은 질문을 기다리는 일일 때가 있다."),
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
            visibility: "PUBLIC", kind: "PATH",
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

    /// 발견 흐름 목 — 팔로우한 큐레이터(minji·sori)가 공개 컬렉션에 최근 이은 것.
    private static func discoverFeedMock() -> [[String: Any]] {
        [
            [
                "id": 1, "curator": curator(2, "minji"),
                "collectionId": 101, "collectionTitle": "느린 사고",
                "why": "구현보다 경계를 먼저 세우는 사람의 기록. 두고두고 다시 본다.",
                "connectedAt": iso(Date().addingTimeInterval(-3600)),
                "blockType": "POST", "title": "헥사고날로 갈아탄 지 석 달",
                "excerpt": "결론부터 적는다. 다시 돌아가라면 또 갈아탄다.",
                "slug": "hexagonal-after-3-months", "username": "honggildong",
                "quote": NSNull(), "body": NSNull(),
            ],
            [
                "id": 2, "curator": curator(3, "sori"),
                "collectionId": 201, "collectionTitle": "오늘의 문장",
                "collectionKind": "PATH",
                "why": "재현 안 되는 버그 앞에서 나도 늘 이 문장을 떠올린다.",
                "connectedAt": iso(Date().addingTimeInterval(-7200)),
                "blockType": "HIGHLIGHT", "title": "토큰이 사라진 밤",
                "excerpt": NSNull(), "slug": "the-night-tokens-vanished",
                "username": "honggildong",
                "quote": "재현이 안 되는 버그는 대개 타이밍 버그다.", "body": NSNull(),
            ],
            [
                "id": 3, "curator": curator(2, "minji"),
                "collectionId": 102, "collectionTitle": "경계 긋기",
                "why": NSNull(),
                "connectedAt": iso(Date().addingTimeInterval(-86_400)),
                "blockType": "NOTE", "title": NSNull(), "excerpt": NSNull(),
                "slug": NSNull(), "username": NSNull(), "quote": NSNull(),
                "body": "결정을 미루는 건 게으름이 아니라, 더 나은 질문을 기다리는 일일 때가 있다.",
            ],
            [
                "id": 4, "curator": curator(3, "sori"),
                "collectionId": 202, "collectionTitle": "다시 읽고 싶은",
                "why": "레이어링을 관심사 분리로 읽어낸 글. 코드에도 그대로 적용된다.",
                "connectedAt": iso(Date().addingTimeInterval(-172_800)),
                "blockType": "POST", "title": "유리 위에 유리를 얹지 않기",
                "excerpt": "겹치는 순간 둘 다 탁해진다. 레이어는 하나씩.",
                "slug": "liquid-glass-without-glass-on-glass", "username": "honggildong",
                "quote": NSNull(), "body": NSNull(),
            ],
        ]
    }

    /// 남들 하이라이트 흐름 목 — 팔로우한 큐레이터(minji·sori)가 공개 글에서 최근 칠한 구절.
    /// 발견 세 번째 흐름(하이라이트 탭)이 목 모드에서 실서버 없이 렌더되게 한다.
    private static func highlightsFeedMock() -> [[String: Any]] {
        [
            [
                "id": 5001, "postId": 9101, "curator": curator(2, "minji"),
                "postSlug": "hexagonal-after-3-months", "postTitle": "헥사고날로 갈아탄 지 석 달",
                "postAuthorUsername": "honggildong",
                "blockOrder": 1, "startOffset": 0, "endOffset": 24,
                "quote": "경계가 없으면 모든 변경이 전역 변경이 된다.",
                "note": "출발은 늘 여기다.",
                "createdAt": iso(Date().addingTimeInterval(-5_400)), "replyCount": 2,
            ],
            [
                "id": 5002, "postId": 9102, "curator": curator(3, "sori"),
                "postSlug": "the-night-tokens-vanished", "postTitle": "토큰이 사라진 밤",
                "postAuthorUsername": "honggildong",
                "blockOrder": 6, "startOffset": 0, "endOffset": 20,
                "quote": "재현이 안 되는 버그는 대개 타이밍 버그다.",
                "note": NSNull(),
                "createdAt": iso(Date().addingTimeInterval(-93_600)), "replyCount": 0,
            ],
        ]
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
                "collectionKind": "PATH",
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
        return nav
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
        // 리치 소속(#607) — 큐레이터·순서(position/total)까지. path 는 "N번째 / 전체 M"으로,
        // collection 은 큐레이터만(순서 없음). curator 없는 것도 하나 섞어 count 폴백을 확인.
        func c(_ id: Int64, _ title: String, _ kind: String, _ count: Int, _ preview: [String],
               curator: String? = nil, position: Int? = nil, total: Int? = nil) -> [String: Any] {
            var d: [String: Any] = [
                "id": id, "title": title, "description": NSNull(),
                "visibility": "PUBLIC", "kind": kind, "count": count,
                "updatedAt": iso(Date()), "preview": preview,
            ]
            d["curatorUsername"] = curator.map { $0 as Any } ?? NSNull()
            d["position"] = position.map { $0 as Any } ?? NSNull()
            d["total"] = total.map { $0 as Any } ?? NSNull()
            return d
        }
        return [
            // 여러 컬렉션에 걸린 글 — 길(순서 있음)·묶음(큐레이터만)·큐레이터 없는 것 섞음.
            ["postId": 8201, "collections": [
                c(104, "다시 읽는 아키텍처", "PATH", 5, ["레이어드의 값", "의존 방향 뒤집기"],
                  curator: "minji", position: 2, total: 4),
                c(101, "경계를 긋는 법", "COLLECTION", 12, ["헥사고날로 갈아탄 지 석 달", "포트 이름 짓기"],
                  curator: "sori"),
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
        [
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
                ]
            },
        ]
    }

    // MARK: 라우팅

    /// 처리하면 응답 바디, 아니면 nil → 실네트워크로.
    /// query = 실 클라이언트가 붙인 쿼리 항목(연결 시트의 blockType/refId 같은 것) — 경로만으로 못 가르는
    /// 응답 형태를 여기서 가른다.
    static func respond(
        path: String, method: String, query: [URLQueryItem]? = nil, body: Data?
    ) -> Data? {
        let parts = path.split(separator: "/").map(String.init)

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

        // 발견 — 팔로우한 큐레이터의 연결 흐름(Phase 2). --discover-global 이면 전역 폴백으로 알린다.
        // --discover-no-source 면 source 를 아예 빼 옛 서버(계약 미배포)를 재현한다.
        if method == "GET", parts == ["feed", "connections"] {
            var payload: [String: Any] = [
                "items": discoverFeedMock(), "page": 0, "size": 20, "hasNext": false,
            ]
            if !discoverNoSource { payload["source"] = discoverGlobal ? "global" : "following" }
            return json(payload)
        }

        // 남들 하이라이트 — 팔로우한 큐레이터가 칠한 공개 하이라이트 피드(발견 세 번째 흐름).
        // --discover-global 이면 전역 폴백으로 알린다(source="global").
        if method == "GET", parts == ["highlights", "feed"] {
            var payload: [String: Any] = [
                "items": highlightsFeedMock(), "page": 0, "size": 20, "hasNext": false,
            ]
            if !discoverNoSource { payload["source"] = discoverGlobal ? "global" : "following" }
            return json(payload)
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
                let c = MockCollection(
                    id: nextCollectionId,
                    title: req["title"] as? String ?? "새 컬렉션",
                    description: req["description"] as? String,
                    visibility: req["visibility"] as? String ?? "PRIVATE",
                    kind: req["kind"] as? String ?? "COLLECTION",
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
                // 길(PATH) 순서 재배치 — 연결 id 전체를 주어진 순서대로.
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
            }
            return json([
                "username": myUsername, "bio": myBio, "theme": "light", "socials": NSNull(),
                "hideFollowerCount": myHideFollowerCount,
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

        // 노트는 공개 읽기까지 목으로 받는다 — 실서버에 아직 배포 전이라 fall-through 하면 404.
        if method == "GET", parts == ["public", "notes"] {
            return json([
                "items": notes.sorted { $0.createdAt > $1.createdAt }.map(noteView),
                "page": 0, "hasNext": false,
            ])
        }

        if method == "POST", parts == ["notes"] {
            let note = MockNote(
                id: nextNoteId, body: decode(body)["body"] as? String ?? "",
                createdAt: Date(), likeCount: 0, authorId: 1, username: "honggildong")
            nextNoteId += 1
            notes.insert(note, at: 0)
            return json(noteView(note))
        }

        if method == "GET", parts == ["notes", "like-status"] {
            return json(["likedIds": Array(likedNotes)])
        }

        if method == "DELETE", parts.count == 2, parts[0] == "notes" {
            let nid = Int64(parts[1]) ?? 0
            notes.removeAll { $0.id == nid }
            likedNotes.remove(nid)
            return json([:] as [String: Any])
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
            if let title = req["title"] as? String { posts[idx].title = title }
            if let excerpt = req["excerpt"] as? String { posts[idx].excerpt = excerpt.isEmpty ? nil : excerpt }
            if let tags = req["tags"] as? [String] { posts[idx].tags = tags }
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
                posts[idx].markdown = decode(body)["markdown"] as? String ?? ""
                posts[idx].updatedAt = Date()
            }
            return json(["markdown": posts[idx].markdown])
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
            var state = follows[username] ?? (following: false, count: 12)
            if method == "PUT" { if !state.following { state.count += 1 }; state.following = true }
            if method == "DELETE" { if state.following { state.count -= 1 }; state.following = false }
            follows[username] = state
            // 내 프로필 토글이 켜져 있으면 내 작가 페이지에선 카운트 키를 빼고 플래그만 내린다(실서버 계약).
            let hidden = username == myUsername && myHideFollowerCount
            var payload: [String: Any] = ["following": state.following, "hideFollowerCount": hidden]
            if !hidden {
                payload["followerCount"] = state.count
                payload["followingCount"] = 5
            }
            return json(payload)
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
                    "bio": "경계를 긋는 사람. 헥사고날·도메인 모델링.", "avatarUrl": NSNull(),
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
            let blocks = article?.blocks ?? (seriesNav != nil
                ? episodeBlocks(slug: slug) : ordered([
                ["type": "H1", "content": "헥사고날로 가는 길"],
                ["type": "PARAGRAPH", "content": "레이어드에서 갈아탄 이유와 그 결정의 기록."],
                ["type": "H2", "content": "포트와 어댑터"],
                ["type": "PARAGRAPH", "content": "경계를 먼저 긋고, 구현은 그 바깥으로 민다."],
            ]))
            return json([
                "author": [
                    "id": username == "honggildong" ? 1 : 2, "username": username,
                    "bio": NSNull(), "avatarUrl": NSNull(),
                ],
                "post": [
                    "id": 8201, "slug": slug,
                    "title": seriesNav?["title"] as? String ?? article?.title ?? "헥사고날로 가는 길",
                    "excerpt": article?.excerpt ?? "경계를 긋는 이야기",
                    "ogImageUrl": NSNull(), "languageTag": "ko",
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
                    "postCount": titles.count, "tags": ["아키텍처"],
                ],
                "posts": posts,
            ])
        }

        // 발견 시리즈 — 최신 피드에 끼워 넣는 시리즈 카드(웹 메인 피드 패리티)의 소스.
        if method == "GET", parts == ["public", "series"] {
            return json([
                [
                    "id": 1,
                    "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
                    "slug": "hexagonal", "title": "헥사고날 전환기", "postCount": 6,
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
                "slug": "hexagonal", "title": "헥사고날 전환기", "postCount": 6,
                "lastPublishedAt": iso(Date().addingTimeInterval(-86_400)),
                "posts": [["slug": "p-mock-2", "title": "발행된 목 글"]],
            ]])
        }

        if method == "GET", parts == ["feed", "following"] {
            // `--empty-feeds` = 빈 구독함/추천 안내 화면 스크린샷 검증용.
            let items = emptyFeeds ? [] : [feedItem(id: 9002, title: "발행된 목 글", slug: "p-mock-2")]
            return json(["items": items, "page": 0, "size": 20, "hasNext": false])
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
        // "이 문장이 속한 길" — 이 하이라이트를 담은 공개 길/컬렉션(목: PATH 104 + 컬렉션 101).
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

        if method == "GET", parts == ["notifications"] {
            return json([
                "items": [
                    ["id": 1, "type": "LIKE", "actorUsername": "reader_kim", "actorAvatarUrl": NSNull(),
                     "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "read": false, "createdAt": iso(Date().addingTimeInterval(-600))],
                    ["id": 2, "type": "COMMENT", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                     "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
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
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "read": true, "createdAt": iso(Date().addingTimeInterval(-259_200))],
                    ["id": 6, "type": "MENTION", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                     "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "read": true, "createdAt": iso(Date().addingTimeInterval(-345_600))],
                    ["id": 7, "type": "NEW_POST", "actorUsername": "honggildong", "actorAvatarUrl": NSNull(),
                     "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "read": true, "createdAt": iso(Date().addingTimeInterval(-432_000))],
                    // 연결 그래프 — 내 글이 큐레이터 컬렉션에 엮임(딥링크=컬렉션 101 "느린 사고").
                    ["id": 8, "type": "CONNECTED", "actorUsername": "yuki_dev", "actorAvatarUrl": NSNull(),
                     "postId": 9002, "postSlug": "p-mock-2", "postTitle": "발행된 목 글", "postAuthorUsername": "honggildong",
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "collectionId": 101, "collectionName": "느린 사고",
                     "read": false, "createdAt": iso(Date().addingTimeInterval(-1200))],
                    // 연결 그래프 — 내가 엮인 길(PATH 104)에 새 글이 이어짐. actor 없이 시스템 발행.
                    ["id": 9, "type": "PATH_GREW", "actorUsername": NSNull(), "actorAvatarUrl": NSNull(),
                     "postId": NSNull(), "postSlug": NSNull(), "postTitle": NSNull(), "postAuthorUsername": NSNull(),
                     "seriesId": NSNull(), "seriesSlug": NSNull(), "seriesTitle": NSNull(),
                     "collectionId": 104, "collectionName": "경계를 긋는다는 것",
                     "read": false, "createdAt": iso(Date().addingTimeInterval(-2400))],
                ],
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
                return json([
                    "series": ["id": 7, "slug": seriesTitles[7]?.0 ?? "hexagonal",
                               "title": seriesTitles[7]?.1 ?? "헥사고날 전환기",
                               "postCount": member.count, "createdAt": iso(Date()), "updatedAt": iso(Date())],
                    "posts": member,
                ])
            }
            let members = (seriesMembers[sid] ?? []).compactMap { id in posts.first { $0.id == id } }
            return json([
                "series": ["id": sid, "slug": seriesTitles[sid]?.0 ?? "s",
                           "title": seriesTitles[sid]?.1 ?? "시리즈",
                           "postCount": members.count, "createdAt": iso(Date()), "updatedAt": iso(Date())],
                "posts": members.map(postView),
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
    private static var createdSeries: [(Int64, String, String)] = []
    private static var nextSeriesId: Int64 = 100
    private static var likedComments: Set<Int64> = []

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

    private static func noteView(_ n: MockNote) -> [String: Any] {
        [
            "id": n.id, "body": n.body, "createdAt": iso(n.createdAt), "likeCount": n.likeCount,
            "author": ["id": n.authorId, "username": n.username, "avatarUrl": NSNull()],
        ]
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

    private static func json(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
    }
}
