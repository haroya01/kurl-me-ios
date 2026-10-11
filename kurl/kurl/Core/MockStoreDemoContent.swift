//
//  MockStoreDemoContent.swift
//  kurl
//

import Foundation

extension MockStoreDemo {
    struct Person {
        let id: Int64
        let username: String
        let name: String
        let avatar: String?
    }

    static func pic(_ id: Int, _ width: Int, _ height: Int) -> String {
        "https://picsum.photos/id/\(id)/\(width)/\(height)"
    }

    static let hayoung = Person(id: 21, username: "hayoung", name: "하영", avatar: pic(82, 300, 300))
    static let jiho = Person(id: 22, username: "jiho_reads", name: "지호", avatar: nil)
    static let mirae = Person(id: 23, username: "mirae_kitchen", name: "미래", avatar: pic(63, 300, 300))
    static let dowon = Person(id: 24, username: "dowon", name: "도원", avatar: pic(49, 300, 300))
    static let seojin = Person(id: 25, username: "seojin", name: "서진", avatar: nil)
    static let nari = Person(id: 26, username: "nari", name: "나리", avatar: pic(40, 300, 300))

    static let cast = [hayoung, jiho, mirae, dowon, seojin, nari]

    static func person(_ username: String) -> Person? {
        cast.first { $0.username == username }
    }

    static func avatar(_ username: String) -> String? {
        guard isOn else { return nil }
        return person(username)?.avatar
    }

    static func author(_ p: Person) -> [String: Any] {
        ["id": p.id, "username": p.username, "bio": NSNull(),
         "avatarUrl": p.avatar ?? NSNull(), "displayName": p.name]
    }

    static func iso(hoursAgo: Double) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-hoursAgo * 3_600))
    }

    struct Post {
        let id: Int64
        let author: Person
        let slug: String
        let title: String
        let excerpt: String
        let tags: [String]
        let cover: String?
        let hoursAgo: Double
    }

    static let walkingPace = Post(
        id: 9301, author: hayoung, slug: "walking-pace", title: "걷는 속도로 읽기",
        excerpt: "퇴근길 한 정거장을 걸으며 생긴 읽기 습관에 대해.",
        tags: ["에세이"], cover: pic(301, 600, 600), hoursAgo: 2)
    static let potatoSoup = Post(
        id: 9302, author: mirae, slug: "sunday-potato-soup", title: "일요일 아침의 감자수프",
        excerpt: "냉장고에 남은 감자 세 알과 양파 하나로 끓였다. 생각보다 간단하다.",
        tags: ["요리"], cover: pic(292, 600, 600), hoursAgo: 5)
    static let rereadBooks = Post(
        id: 9303, author: jiho, slug: "reread-three-books", title: "올해 다시 읽은 책 세 권",
        excerpt: "처음 읽었을 땐 지나쳤던 문장들을 다시 만났다.",
        tags: ["책"], cover: pic(24, 600, 600), hoursAgo: 20)
    static let lisbon = Post(
        id: 9304, author: dowon, slug: "lisbon-tram-28", title: "리스본에서 보낸 사흘, 트램 28번을 타고",
        excerpt: "언덕이 많은 도시라 걷다 지치면 트램에 올랐다. 창밖으로 지나간 골목들.",
        tags: ["여행"], cover: pic(419, 600, 600), hoursAgo: 26)
    static let sideProject = Post(
        id: 9305, author: seojin, slug: "side-project-one-year", title: "사이드 프로젝트를 1년 동안 이어 간 방법",
        excerpt: "의지보다 습관이었다. 매일 30분, 작게 커밋하기.",
        tags: ["개발", "회고"], cover: nil, hoursAgo: 50)
    static let rainSongs = Post(
        id: 9306, author: nari, slug: "rainy-day-songs", title: "비 오는 날 듣는 노래 열 곡",
        excerpt: "창밖에 비가 오면 꺼내 듣는 목록. 첫 곡은 늘 같다.",
        tags: ["음악"], cover: pic(171, 600, 600), hoursAgo: 75)
    static let bookstore = Post(
        id: 9307, author: hayoung, slug: "last-day-of-bookstore", title: "동네 서점이 문을 닫던 날",
        excerpt: "마지막 날 산 책 한 권과 사장님이 건넨 말.",
        tags: ["에세이"], cover: nil, hoursAgo: 98)
    static let transcription = Post(
        id: 9308, author: jiho, slug: "transcription-100-days", title: "필사 노트 100일째",
        excerpt: "하루 한 문단씩 옮겨 적은 백 일의 기록.",
        tags: ["기록"], cover: pic(20, 600, 600), hoursAgo: 140)

    static let posts = [
        walkingPace, potatoSoup, rereadBooks, lisbon, sideProject, rainSongs, bookstore, transcription,
    ]

    static func feedItem(_ p: Post) -> [String: Any] {
        ["id": p.id, "author": author(p.author), "slug": p.slug, "title": p.title, "excerpt": p.excerpt,
         "ogImageUrl": p.cover ?? NSNull(), "languageTag": "ko", "tags": p.tags,
         "publishedAt": iso(hoursAgo: p.hoursAgo), "viewCount": 0, "likeCount": 0]
    }

    static func listItem(_ p: Post, pinned: Bool = false) -> [String: Any] {
        ["id": p.id, "slug": p.slug, "title": p.title, "excerpt": p.excerpt,
         "ogImageUrl": p.cover ?? NSNull(), "languageTag": "ko", "tags": p.tags,
         "likeCount": 0, "pinned": pinned, "lastEditedAt": NSNull(),
         "publishedAt": iso(hoursAgo: p.hoursAgo)]
    }

    static func ordered(_ raw: [[String: Any]]) -> [[String: Any]] {
        raw.enumerated().map { i, block in
            var b = block
            b["blockOrder"] = i
            return b
        }
    }

    static func jsonString(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static let walkingPaceBlocks: [[String: Any]] = ordered([
        ["type": "PARAGRAPH", "content":
            "퇴근길에 한 정거장 먼저 내려서 걷기 시작한 지 두 달이 됐다. 처음엔 운동 삼아 시작했는데, 요즘은 그날 읽은 글을 천천히 곱씹는 시간이 됐다."],
        ["type": "PARAGRAPH", "content":
            "빨리 읽은 글은 빨리 잊힌다. 화면을 내리는 속도로 읽으면 문장은 눈을 스칠 뿐 마음에 닿지 않는다. 그래서 요즘은 하루에 한 편만, 걷는 속도로 읽으려고 한다."],
        ["type": "H2", "content": "밑줄을 긋는 이유"],
        ["type": "PARAGRAPH", "content":
            "좋은 문장을 만나면 형광펜을 긋는다. 나중에 다시 찾으려는 이유도 있지만, 긋는 동안 그 문장을 한 번 더 읽게 되기 때문이다. 손이 문장을 따라가는 사이 생각도 같이 느려진다."],
        ["type": "QUOTE", "content": "천천히 읽은 문장만 오래 남는다."],
        ["type": "PARAGRAPH", "content":
            "지난주에는 같은 글을 세 번 읽었다. 처음엔 줄거리를, 두 번째엔 문장을, 세 번째엔 그 글을 쓴 사람의 마음을 읽었다. 읽을 때마다 밑줄이 다른 곳에 그어졌다."],
        ["type": "IMAGE", "content": jsonString([
            "url": pic(301, 1200, 800), "caption": "집 앞 산책로. 은행잎이 다 지기 전에 한 장."])],
        ["type": "H2", "content": "걸으면서 다시 읽기"],
        ["type": "PARAGRAPH", "content":
            "걷는 동안에는 휴대폰을 꺼내지 않는다. 대신 그날 밑줄 친 문장 하나를 머릿속에 두고 걷는다. 신호를 기다리다가, 골목을 돌다가 그 문장이 문득 다른 뜻으로 읽힐 때가 있다."],
        ["type": "LIST_BULLET", "content": jsonString([
            "하루에 한 편만 읽는다.",
            "마음에 남은 문장은 그 자리에서 긋는다.",
            "걷는 동안 그 문장을 한 번 더 떠올린다.",
        ])],
        ["type": "PARAGRAPH", "content":
            "느리게 읽는다고 덜 읽는 건 아니었다. 읽은 만큼 남았고, 남은 만큼 다시 쓰고 싶어졌다. 이 글도 그렇게 걸으면서 쓴 것이다."],
    ])

    static func blocks(for p: Post) -> [[String: Any]] {
        if p.id == walkingPace.id { return walkingPaceBlocks }
        return ordered([
            ["type": "PARAGRAPH", "content": p.excerpt],
        ])
    }

    static func highlight(
        _ id: Int, _ by: Person, block: Int, _ quote: String, note: String? = nil, hoursAgo: Double
    ) -> [String: Any] {
        let content = walkingPaceBlocks[block]["content"] as? String ?? ""
        let range = (content as NSString).range(of: quote)
        return [
            "id": id,
            "author": ["id": by.id, "username": by.username, "bio": NSNull(),
                       "avatarUrl": by.avatar ?? NSNull(), "displayName": by.name],
            "blockOrder": block, "startOffset": range.location, "endOffset": range.location + range.length,
            "quote": quote, "note": note ?? NSNull(), "createdAt": iso(hoursAgo: hoursAgo),
        ]
    }

    static let threadHighlightId = 6201

    static func reply(_ id: Int, _ by: Person, _ body: String, hoursAgo: Double, likes: Int = 0) -> [String: Any] {
        ["id": id,
         "author": ["id": by.id, "username": by.username, "bio": NSNull(),
                    "avatarUrl": by.avatar ?? NSNull(), "displayName": by.name],
         "body": body, "createdAt": iso(hoursAgo: hoursAgo), "likeCount": likes]
    }

    static func belonging(_ collectionId: Int64, _ title: String, curator: Person, position: Int, total: Int)
        -> [String: Any] {
        ["id": collectionId, "title": title, "description": NSNull(), "visibility": "PUBLIC", "kind": "PATH",
         "count": total, "updatedAt": iso(hoursAgo: 1), "preview": [] as [String],
         "curatorUsername": curator.username, "position": position, "total": total]
    }

    static let pathTitle = "천천히 읽기 입문"
}

extension MockBackend {
    static var storeDemoDisplayNames: [String: String] {
        Dictionary(uniqueKeysWithValues: MockStoreDemo.cast.map { ($0.username, $0.name) })
    }

    static var storeDemoPosts: [MockPost] {
        [
            MockPost(
                id: 9401, slug: "late-autumn-walk", title: "늦가을 아침 산책", status: "DRAFT",
                markdown: """
                오늘은 평소보다 한 시간 일찍 나섰다. 해가 낮게 깔려서 **골목마다 그림자가 길었다.**

                ## 오늘 걸은 길

                - [x] 집 앞 은행나무길
                - [x] 하천 따라 다리 두 개
                - [ ] 시장 골목 빵집

                > 천천히 걸어야 보이는 것들이 있다.

                ![나무 사이로 난 길](\(MockStoreDemo.pic(255, 1200, 800)) "돌아오는 길")

                > [!TIP]
                > 은행잎은 오전 열 시 전에 가야 아직 쓸려 나가지 않았다.
                """,
                publishedAt: nil, updatedAt: Date().addingTimeInterval(-600),
                tags: ["산책"], excerpt: "오늘은 평소보다 한 시간 일찍 나섰다."),
            MockPost(
                id: 9402, slug: "balcony-garden", title: "베란다 텃밭 정리", status: "PUBLISHED",
                markdown: "겨울이 오기 전에 화분을 정리했다.",
                publishedAt: Date().addingTimeInterval(-3 * 86_400), updatedAt: Date().addingTimeInterval(-3 * 86_400),
                tags: ["일상"], excerpt: "겨울이 오기 전에 화분을 정리했다."),
            MockPost(
                id: 9403, slug: "first-film-camera", title: "필름 카메라 첫 롤", status: "PUBLISHED",
                markdown: "서른여섯 장 중에 건진 건 일곱 장.",
                publishedAt: Date().addingTimeInterval(-9 * 86_400), updatedAt: Date().addingTimeInterval(-9 * 86_400),
                tags: ["사진"], excerpt: "서른여섯 장 중에 건진 건 일곱 장."),
        ]
    }

    private static func demoNote(
        _ id: Int64, _ by: MockStoreDemo.Person, minutesAgo: Double, _ body: String, replyTo: Int64? = nil
    ) -> MockNote {
        MockNote(
            id: id, body: body, createdAt: Date().addingTimeInterval(-minutesAgo * 60), likeCount: 0,
            authorId: by.id, username: by.username, inReplyToId: replyTo)
    }

    private static func photo(_ id: Int, _ alt: String, _ width: Int, _ height: Int) -> [String: Any] {
        ["url": MockStoreDemo.pic(id, width, height), "altText": alt, "contentType": "image/jpeg",
         "width": width, "height": height]
    }

    static var storeDemoNotes: [MockNote] {
        typealias S = MockStoreDemo
        let thread = demoNote(9701, S.nari, minutesAgo: 12, "오늘 읽은 글에서 건진 문장 세 개. 하나씩 이어서 적어 둔다.")
        var photos = demoNote(9702, S.dowon, minutesAgo: 40, "리스본 골목에서 찍은 사진 몇 장. 긴 글은 주말에 정리해서 올릴게요.")
        photos.media = [
            photo(322, "좁은 돌길 골목", 900, 1200),
            photo(308, "빨래가 걸린 골목", 1200, 900),
            photo(369, "언덕 위 집들", 1200, 900),
        ]
        var poll = demoNote(9703, S.mirae, minutesAgo: 70, "다음 주말에 끓일 수프 골라 주세요.")
        poll.poll = MockPoll(
            options: ["단호박", "양파", "토마토"], expiresAt: Date().addingTimeInterval(20 * 3_600),
            votes: [14, 9, 6], voters: 29)
        var quote = demoNote(9704, S.jiho, minutesAgo: 130, "이 글 읽고 오늘은 정말 한 편만 읽었다. 대신 세 번.")
        quote.quotedPost = [
            "id": S.walkingPace.id, "title": S.walkingPace.title, "slug": S.walkingPace.slug,
            "authorUsername": S.hayoung.username,
        ]
        var link = demoNote(9705, S.seojin, minutesAgo: 200, "느린 웹에 관한 좋은 글. 북마크해 두고 두 번 읽었다.")
        link.linkPreview = [
            "url": "https://blog.kurl.me/@seojin/slow-web", "title": "느린 웹을 위한 변론",
            "description": "빠른 것만 남은 웹에서 천천히 머무는 페이지를 만드는 일.",
            "image": S.pic(48, 960, 502),
        ]
        let walk = demoNote(9706, S.hayoung, minutesAgo: 320, "산책로 은행잎이 거의 다 떨어졌다. 내일은 조금 일찍 나가 봐야지. #산책")
        let book = demoNote(9707, S.dowon, minutesAgo: 1_500, "여행 가방에 넣어 갈 얇은 책 한 권 추천받아요.")
        return [thread, photos, poll, quote, link, walk, book]
    }

    static var storeDemoNoteReplies: [MockNote] {
        typealias S = MockStoreDemo
        return [
            demoNote(9711, S.nari, minutesAgo: 11.9, "하나. 빨리 읽은 글은 빨리 잊힌다.", replyTo: 9701),
            demoNote(9712, S.nari, minutesAgo: 11.8, "둘. 천천히 읽은 문장만 오래 남는다.", replyTo: 9711),
            demoNote(9713, S.nari, minutesAgo: 11.7, "셋. 읽을 때마다 밑줄이 다른 곳에 그어졌다.", replyTo: 9712),
            demoNote(9721, S.hayoung, minutesAgo: 8, "제 글에서 골라 주셨네요. 고마워요.", replyTo: 9701),
            demoNote(9731, S.jiho, minutesAgo: 30, "단호박이요. 지난번 사진 보고 계속 생각났어요.", replyTo: 9703),
            demoNote(9741, S.nari, minutesAgo: 1_400, "필사하기 좋은 산문집이면 좋겠어요.", replyTo: 9707),
        ]
    }

    static var storeDemoHighlights: [[String: Any]] {
        typealias S = MockStoreDemo
        return [
            S.highlight(6202, S.jiho, block: 1, "빨리 읽은 글은 빨리 잊힌다.", hoursAgo: 1.5),
            S.highlight(6203, S.mirae, block: 1, "빨리 읽은 글은 빨리 잊힌다.", hoursAgo: 1.2),
            S.highlight(6204, S.dowon, block: 1, "빨리 읽은 글은 빨리 잊힌다.", hoursAgo: 0.8),
            S.highlight(
                S.threadHighlightId, S.nari, block: 3, "긋는 동안 그 문장을 한 번 더 읽게 되기 때문이다.",
                note: "연필로 밑줄 긋는 습관이 딱 이래서 생겼어요.", hoursAgo: 1),
            S.highlight(6205, S.seojin, block: 5, "읽을 때마다 밑줄이 다른 곳에 그어졌다.", hoursAgo: 0.6),
            S.highlight(6206, S.jiho, block: 5, "읽을 때마다 밑줄이 다른 곳에 그어졌다.", hoursAgo: 0.5),
        ]
    }

    static var storeDemoHighlightReplies: [Int: [[String: Any]]] {
        typealias S = MockStoreDemo
        return [
            S.threadHighlightId: [
                S.reply(7201, S.hayoung, "저도 종이책 읽을 땐 늘 연필을 쥐고 있어요. 화면에서도 그게 되니까 좋더라고요.",
                        hoursAgo: 0.7, likes: 4),
                S.reply(7202, S.jiho, "밑줄 그은 문장만 모아 두고 가끔 다시 넘겨 봐요. 같은 문장이 다르게 읽혀요.",
                        hoursAgo: 0.4, likes: 2),
            ],
        ]
    }

    static var storeDemoCollections: [MockCollection] {
        typealias S = MockStoreDemo
        return [
            MockCollection(
                id: 104, title: S.pathTitle, description: "처음 오는 분께 권하는 순서. 한 편씩 천천히.",
                visibility: "PUBLIC", kind: "PATH",
                connections: [
                    MockConnection(
                        id: 801, blockType: "POST", why: "여기서 시작하면 좋아요. 왜 천천히 읽는지부터.",
                        title: S.walkingPace.title, excerpt: S.walkingPace.excerpt,
                        slug: S.walkingPace.slug, username: S.hayoung.username, refId: S.walkingPace.id),
                    MockConnection(
                        id: 802, blockType: "HIGHLIGHT", why: "이 문장 하나만 기억해도 충분해요.",
                        title: S.walkingPace.title, slug: S.walkingPace.slug, username: S.hayoung.username,
                        quote: "천천히 읽은 문장만 오래 남는다."),
                    MockConnection(
                        id: 803, blockType: "POST", why: "같은 책이 왜 다르게 읽히는지, 다시 읽기의 실제.",
                        title: S.rereadBooks.title, excerpt: S.rereadBooks.excerpt,
                        slug: S.rereadBooks.slug, username: S.jiho.username, refId: S.rereadBooks.id),
                    MockConnection(
                        id: 804, blockType: "NOTE", why: "읽고 난 뒤엔 이렇게 짧게 남겨 두면 된다.",
                        username: S.nari.username,
                        body: "오늘 읽은 글에서 건진 문장 세 개. 하나씩 이어서 적어 둔다.", refId: 9701),
                    MockConnection(
                        id: 805, blockType: "POST", why: "마지막은 조금 긴 글로.",
                        title: S.bookstore.title, excerpt: S.bookstore.excerpt,
                        slug: S.bookstore.slug, username: S.hayoung.username, refId: S.bookstore.id),
                ],
                curator: S.jiho.username),
            MockCollection(
                id: 101, title: "주말에 읽을 글", description: nil, visibility: "PUBLIC",
                connections: [
                    MockConnection(
                        id: 811, blockType: "POST", why: nil, title: S.lisbon.title, excerpt: S.lisbon.excerpt,
                        slug: S.lisbon.slug, username: S.dowon.username, refId: S.lisbon.id),
                    MockConnection(
                        id: 812, blockType: "POST", why: nil, title: S.potatoSoup.title,
                        excerpt: S.potatoSoup.excerpt, slug: S.potatoSoup.slug, username: S.mirae.username,
                        refId: S.potatoSoup.id),
                ]),
            MockCollection(
                id: 102, title: "요리 노트", description: nil, visibility: "PRIVATE",
                connections: [
                    MockConnection(
                        id: 821, blockType: "POST", why: "다음 주말에 해 볼 것.", title: S.potatoSoup.title,
                        excerpt: S.potatoSoup.excerpt, slug: S.potatoSoup.slug, username: S.mirae.username,
                        refId: S.potatoSoup.id),
                ]),
        ]
    }

    static func storeDemoResponse(_ parts: [String]) -> Any? {
        typealias S = MockStoreDemo
        switch parts {
        case ["public", "posts"], ["feed", "following"]:
            return ["items": S.posts.map(S.feedItem), "page": 0, "size": 20, "hasNext": false,
                    "seriesNotes": [] as [Any]]
        case ["public", "series"], ["users", "me", "blocks"]:
            return [] as [Any]
        case ["public", "feed", "connections"]:
            let event: [String: Any] = [
                "id": 31, "curator": S.author(S.jiho), "collectionId": 104, "collectionTitle": S.pathTitle,
                "collectionKind": "PATH", "why": "마지막은 조금 긴 글로. 서점이 사라진 자리에 남은 것들.",
                "connectedAt": S.iso(hoursAgo: 3), "blockType": "POST", "title": S.bookstore.title,
                "excerpt": S.bookstore.excerpt, "slug": S.bookstore.slug, "username": S.hayoung.username,
                "quote": NSNull(), "body": NSNull(),
            ]
            return ["items": [event], "page": 0, "size": 6, "hasNext": false]
        case ["public", "posts", "collections"]:
            return [
                ["postId": S.walkingPace.id,
                 "collections": [S.belonging(104, S.pathTitle, curator: S.jiho, position: 1, total: 5)]],
                ["postId": S.rereadBooks.id,
                 "collections": [S.belonging(104, S.pathTitle, curator: S.jiho, position: 3, total: 5)]],
            ]
        default:
            break
        }
        if parts.count == 5, parts[0] == "public", parts[1] == "profiles", parts[3] == "posts",
           let post = S.posts.first(where: { $0.slug == parts[4] }) {
            return [
                "author": S.author(post.author),
                "post": S.listItem(post),
                "blocks": S.blocks(for: post),
                "series": NSNull(),
            ]
        }
        if parts.count == 4, parts[0] == "public", parts[1] == "profiles", parts[3] == "posts",
           let person = S.person(parts[2]) {
            return [
                "author": S.author(person),
                "posts": S.posts.filter { $0.author.username == person.username }.map { S.listItem($0) },
            ]
        }
        if parts.count == 6, parts[0] == "public", parts[1] == "graph", parts[5] == "related" {
            return [
                ["blockType": "POST", "refId": S.rereadBooks.id, "sharedCount": 3,
                 "title": S.rereadBooks.title, "excerpt": S.rereadBooks.excerpt,
                 "slug": S.rereadBooks.slug, "username": S.jiho.username, "quote": NSNull(), "body": NSNull()],
                ["blockType": "POST", "refId": S.bookstore.id, "sharedCount": 2,
                 "title": S.bookstore.title, "excerpt": S.bookstore.excerpt,
                 "slug": S.bookstore.slug, "username": S.hayoung.username, "quote": NSNull(), "body": NSNull()],
            ]
        }
        if parts.count == 4, parts[0] == "public", parts[1] == "profiles", parts[3] == "kindred" {
            let kindred: [(S.Person, String?, Int)] = [
                (S.hayoung, "산책하고, 읽고, 씁니다.", 6), (S.nari, nil, 4), (S.jiho, "다시 읽는 사람.", 3),
            ]
            return kindred.filter { $0.0.username != parts[2] }.prefix(2).map { person, bio, shared in
                ["curator": ["id": person.id, "username": person.username, "bio": bio ?? NSNull(),
                             "avatarUrl": person.avatar ?? NSNull()],
                 "sharedItems": shared] as [String: Any]
            }
        }
        return nil
    }
}
