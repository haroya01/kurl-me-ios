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
        MockPost(id: 9002, slug: "p-mock-2", title: "발행된 목 글", status: "PUBLISHED",
                 markdown: "# 발행됨\n\n본문.", publishedAt: Date().addingTimeInterval(-86_400), updatedAt: Date()),
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

    /// `--empty-feeds` = 구독함·추천을 빈 응답으로 — 빈 안내 화면 검증용.
    private static let emptyFeeds = ProcessInfo.processInfo.arguments.contains("--empty-feeds")

    private static var nextId: Int64 = 9100
    private static var likes: [Int64: (count: Int64, liked: Bool)] = [:]
    private static var bookmarks: Set<Int64> = []
    private static var follows: [String: (following: Bool, count: Int64)] = [:]
    private static var subscriptions: [Int64: (subscribed: Bool, count: Int64)] = [:]
    private static var followedTags: Set<String> = ["아키텍처"]
    private static var hiddenTags: Set<String> = []
    private static var myBio = "경계를 긋는 사람. 헥사고날·도메인 모델링."
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
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))

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
    }
    struct MockCollection {
        let id: Int64
        var title: String
        var description: String?
        var visibility: String
        var connections: [MockConnection]
    }

    static var collections: [MockCollection] = [
        MockCollection(
            id: 101, title: "느린 사고", description: "빨리 답하지 않고 오래 머문 글들.", visibility: "PUBLIC",
            connections: [
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
    ]
    static var nextCollectionId: Int64 = 110
    static var nextConnectionId: Int64 = 600

    /// 옵셔널 문자열을 JSON 값으로 — nil 은 NSNull(JSONSerialization 호환).
    private static func orNull(_ v: String?) -> Any { v.map { $0 as Any } ?? NSNull() }

    private static func collectionSummary(_ c: MockCollection) -> [String: Any] {
        [
            "id": c.id, "title": c.title,
            "description": orNull(c.description),
            "visibility": c.visibility, "count": c.connections.count,
            "updatedAt": iso(Date()),
        ]
    }

    private static func collectionDetail(_ c: MockCollection) -> [String: Any] {
        [
            "id": c.id, "title": c.title,
            "description": orNull(c.description),
            "visibility": c.visibility, "curatorUsername": myUsername,
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
    static func respond(path: String, method: String, body: Data?) -> Data? {
        let parts = path.split(separator: "/").map(String.init)

        // 컬렉션 — 내 목록 / 상세 / 생성 / 연결 / 연결끊기 / 삭제.
        if method == "GET", parts == ["users", "me", "collections"] {
            return json(collections.map(collectionSummary))
        }
        if parts.first == "collections" {
            if method == "POST", parts.count == 1 {
                let req = decode(body)
                let c = MockCollection(
                    id: nextCollectionId,
                    title: req["title"] as? String ?? "새 컬렉션",
                    description: req["description"] as? String,
                    visibility: req["visibility"] as? String ?? "PRIVATE",
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
                if method == "DELETE", parts.count == 2 {
                    collections.remove(at: idx)
                    return json([:] as [String: Any])
                }
                if method == "POST", parts.count == 3, parts[2] == "connections" {
                    let req = decode(body)
                    let type = req["blockType"] as? String ?? "POST"
                    let why = req["why"] as? String
                    var conn = MockConnection(
                        id: nextConnectionId, blockType: type, why: why)
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

        // 신고 — 202, 본문 없음. 목에선 실서버에 진짜 신고가 쌓이지 않게 받아만 준다.
        if method == "POST", parts == ["public", "abuse-reports"] {
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
            }
            return json(["username": myUsername, "bio": myBio, "theme": "light", "socials": NSNull()])
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
            return json([
                "items": [
                    ["postId": 9002, "slug": "p-mock-2", "title": "발행된 목 글",
                     "viewCount": 812, "likeCount": 41, "followsGained": 6],
                    ["postId": 9001, "slug": "p-mock-1", "title": "목 초안 — 헥사고날 정리",
                     "viewCount": 287, "likeCount": 19, "followsGained": 2],
                    ["postId": 9003, "slug": "p-mock-3", "title": "조용한 웹로그라는 결정",
                     "viewCount": 145, "likeCount": 12, "followsGained": 0],
                ],
                "page": 0, "hasNext": false,
            ])
        }

        if method == "GET", parts == ["posts", "analytics", "series"] {
            return json([
                ["seriesId": 1, "slug": "hexagonal", "title": "헥사고날 전환기",
                 "postCount": 6, "subscriberCount": 14, "totalViews": 1930, "totalLikes": 72],
                ["seriesId": 2, "slug": "ios-build", "title": "iOS 앱 만들기",
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
            return json(["following": state.following, "followerCount": state.count, "followingCount": 5])
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
            let blocks = article?.blocks ?? ordered([
                ["type": "H1", "content": "헥사고날로 가는 길"],
                ["type": "PARAGRAPH", "content": "레이어드에서 갈아탄 이유와 그 결정의 기록."],
                ["type": "H2", "content": "포트와 어댑터"],
                ["type": "PARAGRAPH", "content": "경계를 먼저 긋고, 구현은 그 바깥으로 민다."],
            ])
            return json([
                "author": [
                    "id": username == "honggildong" ? 1 : 2, "username": username,
                    "bio": NSNull(), "avatarUrl": NSNull(),
                ],
                "post": [
                    "id": 8201, "slug": slug, "title": article?.title ?? "헥사고날로 가는 길",
                    "excerpt": article?.excerpt ?? "경계를 긋는 이야기",
                    "ogImageUrl": NSNull(), "languageTag": "ko",
                    "tags": article?.tags ?? ["아키텍처"], "likeCount": article?.likeCount ?? 8,
                    "pinned": false, "lastEditedAt": NSNull(),
                    "publishedAt": iso(Date().addingTimeInterval(
                        -(article?.daysAgo ?? 1) * 86_400)),
                ],
                "blocks": blocks,
                "series": NSNull(),
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
                    "id": 7, "slug": parts[4], "title": "헥사고날 전환기",
                    "postCount": titles.count, "tags": ["아키텍처"],
                ],
                "posts": posts,
            ])
        }

        if method == "GET", parts == ["bookmarks"] {
            return json([
                ["id": 9002, "username": "honggildong", "title": "발행된 목 글", "slug": "p-mock-2"],
                ["id": 9001, "username": "honggildong", "title": "목 초안 — 헥사고날 정리", "slug": "p-mock-1"],
            ])
        }

        if method == "GET", parts == ["users", "me", "likes"] {
            return json([feedItem(id: 9002, title: "발행된 목 글", slug: "p-mock-2")])
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
                feedItem(id: 9002, title: "발행된 목 글", slug: "p-mock-2"),
                feedItem(id: 9101, title: "헥사고날로 가는 길", slug: "hexagonal-road"),
            ]
            return json(["items": items, "page": 0, "size": 20, "hasNext": false])
        }

        if method == "GET", parts == ["users", "me", "highlights"] {
            return json([
                ["id": 5001, "quote": "경계를 먼저 긋고, 구현은 그 바깥으로 민다.", "blockOrder": 2,
                 "postUsername": "honggildong", "postSlug": "p-mock-2", "postTitle": "발행된 목 글",
                 "createdAt": iso(Date().addingTimeInterval(-7200))],
                ["id": 5002, "quote": "좋은 추상은 더 지울 게 없을 때 완성된다.", "blockOrder": 5,
                 "postUsername": "honggildong", "postSlug": "p-mock-1", "postTitle": "목 초안 — 헥사고날 정리",
                 "createdAt": iso(Date().addingTimeInterval(-172_800))],
            ])
        }

        if method == "GET", parts == ["users", "me", "reading-history"] {
            return json([
                "items": [
                    ["postId": 9002, "username": "honggildong", "avatarUrl": NSNull(),
                     "title": "발행된 목 글", "slug": "p-mock-2", "excerpt": "목 발췌",
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
            let members = (seriesMembers[sid] ?? []).compactMap { id in posts.first { $0.id == id } }
            return json([
                "series": ["id": sid, "slug": "s", "title": "시리즈", "postCount": members.count, "createdAt": iso(Date()), "updatedAt": iso(Date())],
                "posts": members.map(postView),
            ])
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
                "publicUrl": "https://cdn.kurl.me/mock-cover.jpg",
                "key": "mock/cover.jpg", "contentType": "image/jpeg", "maxBytes": 5_242_880,
            ])
        }

        if method == "POST", parts.count == 4, parts[0] == "posts", parts[2] == "images", parts[3] == "commit" {
            return json(["imageUrl": "https://cdn.kurl.me/mock-cover.jpg", "key": "mock/cover.jpg"])
        }

        return nil
    }

    private static let mockSeries: [(Int64, String, String)] = [
        (1, "hexagonal", "헥사고날 전환기"),
        (2, "ios-build", "iOS 앱 만들기"),
    ]
    private static var seriesMembers: [Int64: [Int64]] = [1: [9002], 2: []]
    private static var createdSeries: [(Int64, String, String)] = []
    private static var nextSeriesId: Int64 = 100
    private static var likedComments: Set<Int64> = []

    private static func feedItem(id: Int64, title: String, slug: String) -> [String: Any] {
        [
            "id": id,
            "author": ["id": 1, "username": "honggildong", "bio": NSNull(), "avatarUrl": NSNull()],
            "slug": slug, "title": title, "excerpt": "목 발췌",
            "ogImageUrl": NSNull(), "languageTag": "ko", "tags": ["목"],
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
