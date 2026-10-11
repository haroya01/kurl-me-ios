//
//  MockStoreDemoCopy.swift
//  kurl
//

import Foundation

extension MockStoreDemo {
    struct Copy {
        let languageTag: String
        let names: [String]
        let handles: [String]
        let postTitles: [String]
        let postExcerpts: [String]
        let postTags: [[String]]
        let opening: String
        let fastReading: String
        let underlineHeading: String
        let underline: String
        let pullQuote: String
        let threeReads: String
        let photoCaption: String
        let walkingHeading: String
        let walking: String
        let steps: [String]
        let closing: String
        let topQuote: String
        let threadQuote: String
        let pairQuote: String
        let threadNote: String
        let authorReply: String
        let readerReply: String
        let threadRoot: String
        let threadParts: [String]
        let threadThanks: String
        let photosNote: String
        let photoAlts: [String]
        let pollNote: String
        let pollOptions: [String]
        let pollReply: String
        let quoteNote: String
        let linkNote: String
        let linkTitle: String
        let linkDescription: String
        let walkNote: String
        let bookNote: String
        let bookReply: String
        let pathTitle: String
        let pathDescription: String
        let pathWhys: [String]
        let connectionWhy: String
        let weekendTitle: String
        let kitchenTitle: String
        let kitchenWhy: String
        let bios: [String]
        let draftTitle: String
        let draftBody: String
        let draftTag: String
        let published: [(title: String, excerpt: String, tag: String)]
    }

    static var copy: Copy {
        switch lang {
        case "ko": ko
        case "ja": ja
        case "vi": vi
        case "hi": hi
        default: en
        }
    }

    private static var draftImage: String { pic(255, 1200, 800) }

    static let ko = Copy(
        languageTag: "ko",
        names: ["하영", "지호", "미래", "도원", "서진", "나리"],
        handles: ["hayoung", "jiho_reads", "mirae_kitchen", "dowon", "seojin", "nari"],
        postTitles: [
            "걷는 속도로 읽기", "일요일 아침의 감자수프", "올해 다시 읽은 책 세 권", "리스본에서 보낸 사흘, 트램 28번을 타고",
            "사이드 프로젝트를 1년 동안 이어 간 방법", "비 오는 날 듣는 노래 열 곡", "동네 서점이 문을 닫던 날", "필사 노트 100일째",
        ],
        postExcerpts: [
            "퇴근길 한 정거장을 걸으며 생긴 읽기 습관에 대해.",
            "냉장고에 남은 감자 세 알과 양파 하나로 끓였다. 생각보다 간단하다.",
            "처음 읽었을 땐 지나쳤던 문장들을 다시 만났다.",
            "언덕이 많은 도시라 걷다 지치면 트램에 올랐다. 창밖으로 지나간 골목들.",
            "의지보다 습관이었다. 매일 30분, 작게 커밋하기.",
            "창밖에 비가 오면 꺼내 듣는 목록. 첫 곡은 늘 같다.",
            "마지막 날 산 책 한 권과 사장님이 건넨 말.",
            "하루 한 문단씩 옮겨 적은 백 일의 기록.",
        ],
        postTags: [["에세이"], ["요리"], ["책"], ["여행"], ["개발", "회고"], ["음악"], ["에세이"], ["기록"]],
        opening: "퇴근길에 한 정거장 먼저 내려서 걷기 시작한 지 두 달이 됐다. 처음엔 운동 삼아 시작했는데, 요즘은 그날 읽은 글을 천천히 곱씹는 시간이 됐다.",
        fastReading: "빨리 읽은 글은 빨리 잊힌다. 화면을 내리는 속도로 읽으면 문장은 눈을 스칠 뿐 마음에 닿지 않는다. 그래서 요즘은 하루에 한 편만, 걷는 속도로 읽으려고 한다.",
        underlineHeading: "밑줄을 긋는 이유",
        underline: "좋은 문장을 만나면 형광펜을 긋는다. 나중에 다시 찾으려는 이유도 있지만, 긋는 동안 그 문장을 한 번 더 읽게 되기 때문이다. 손이 문장을 따라가는 사이 생각도 같이 느려진다.",
        pullQuote: "천천히 읽은 문장만 오래 남는다.",
        threeReads: "지난주에는 같은 글을 세 번 읽었다. 처음엔 줄거리를, 두 번째엔 문장을, 세 번째엔 그 글을 쓴 사람의 마음을 읽었다. 읽을 때마다 밑줄이 다른 곳에 그어졌다.",
        photoCaption: "집 앞 산책로. 은행잎이 다 지기 전에 한 장.",
        walkingHeading: "걸으면서 다시 읽기",
        walking: "걷는 동안에는 휴대폰을 꺼내지 않는다. 대신 그날 밑줄 친 문장 하나를 머릿속에 두고 걷는다. 신호를 기다리다가, 골목을 돌다가 그 문장이 문득 다른 뜻으로 읽힐 때가 있다.",
        steps: ["하루에 한 편만 읽는다.", "마음에 남은 문장은 그 자리에서 긋는다.", "걷는 동안 그 문장을 한 번 더 떠올린다."],
        closing: "느리게 읽는다고 덜 읽는 건 아니었다. 읽은 만큼 남았고, 남은 만큼 다시 쓰고 싶어졌다. 이 글도 그렇게 걸으면서 쓴 것이다.",
        topQuote: "빨리 읽은 글은 빨리 잊힌다.",
        threadQuote: "긋는 동안 그 문장을 한 번 더 읽게 되기 때문이다.",
        pairQuote: "읽을 때마다 밑줄이 다른 곳에 그어졌다.",
        threadNote: "연필로 밑줄 긋는 습관이 딱 이래서 생겼어요.",
        authorReply: "저도 종이책 읽을 땐 늘 연필을 쥐고 있어요. 화면에서도 그게 되니까 좋더라고요.",
        readerReply: "밑줄 그은 문장만 모아 두고 가끔 다시 넘겨 봐요. 같은 문장이 다르게 읽혀요.",
        threadRoot: "오늘 읽은 글에서 건진 문장 세 개. 하나씩 이어서 적어 둔다.",
        threadParts: ["하나. 빨리 읽은 글은 빨리 잊힌다.", "둘. 천천히 읽은 문장만 오래 남는다.", "셋. 읽을 때마다 밑줄이 다른 곳에 그어졌다."],
        threadThanks: "제 글에서 골라 주셨네요. 고마워요.",
        photosNote: "리스본 골목에서 찍은 사진 몇 장. 긴 글은 주말에 정리해서 올릴게요.",
        photoAlts: ["좁은 돌길 골목", "빨래가 걸린 골목", "언덕 위 집들"],
        pollNote: "다음 주말에 끓일 수프 골라 주세요.",
        pollOptions: ["단호박", "양파", "토마토"],
        pollReply: "단호박이요. 지난번 사진 보고 계속 생각났어요.",
        quoteNote: "이 글 읽고 오늘은 정말 한 편만 읽었다. 대신 세 번.",
        linkNote: "느린 웹에 관한 좋은 글. 북마크해 두고 두 번 읽었다.",
        linkTitle: "느린 웹을 위한 변론",
        linkDescription: "빠른 것만 남은 웹에서 천천히 머무는 페이지를 만드는 일.",
        walkNote: "산책로 은행잎이 거의 다 떨어졌다. 내일은 조금 일찍 나가 봐야지. #산책",
        bookNote: "여행 가방에 넣어 갈 얇은 책 한 권 추천받아요.",
        bookReply: "필사하기 좋은 산문집이면 좋겠어요.",
        pathTitle: "천천히 읽기 입문",
        pathDescription: "처음 오는 분께 권하는 순서. 한 편씩 천천히.",
        pathWhys: [
            "여기서 시작하면 좋아요. 왜 천천히 읽는지부터.",
            "이 문장 하나만 기억해도 충분해요.",
            "같은 책이 왜 다르게 읽히는지, 다시 읽기의 실제.",
            "읽고 난 뒤엔 이렇게 짧게 남겨 두면 된다.",
            "마지막은 조금 긴 글로.",
        ],
        connectionWhy: "마지막은 조금 긴 글로. 서점이 사라진 자리에 남은 것들.",
        weekendTitle: "주말에 읽을 글",
        kitchenTitle: "요리 노트",
        kitchenWhy: "다음 주말에 해 볼 것.",
        bios: ["산책하고, 읽고, 씁니다.", "다시 읽는 사람."],
        draftTitle: "늦가을 아침 산책",
        draftBody: """
        오늘은 평소보다 한 시간 일찍 나섰다. 해가 낮게 깔려서 **골목마다 그림자가 길었다.**

        ## 오늘 걸은 길

        - [x] 집 앞 은행나무길
        - [x] 하천 따라 다리 두 개
        - [ ] 시장 골목 빵집

        > 천천히 걸어야 보이는 것들이 있다.

        ![나무 사이로 난 길](\(draftImage) "돌아오는 길")

        > [!TIP]
        > 은행잎은 오전 열 시 전에 가야 아직 쓸려 나가지 않았다.
        """,
        draftTag: "산책",
        published: [
            ("베란다 텃밭 정리", "겨울이 오기 전에 화분을 정리했다.", "일상"),
            ("필름 카메라 첫 롤", "서른여섯 장 중에 건진 건 일곱 장.", "사진"),
        ])

    static let en = Copy(
        languageTag: "en",
        names: ["Clara", "Owen", "Maya", "Theo", "Sam", "June"],
        handles: ["clara", "owen_reads", "maya_kitchen", "theo", "sam", "june"],
        postTitles: [
            "Reading at walking pace", "Sunday morning potato soup", "Three books I reread this year",
            "Three days in Lisbon, on the 28 tram", "How I kept a side project going for a year",
            "Ten songs for rainy days", "The day our neighborhood bookshop closed", "100 days of copying out passages",
        ],
        postExcerpts: [
            "A reading habit that grew out of getting off the bus one stop early.",
            "Three leftover potatoes and one onion. It's simpler than it sounds.",
            "Sentences I walked straight past the first time.",
            "The city is all hills, so when my legs gave out I took the tram. The alleys that slid past the window.",
            "Habit, not willpower. Thirty minutes a day, small commits.",
            "What I put on when it rains. The first song never changes.",
            "The last book I bought there, and what the owner said as he handed it over.",
            "One paragraph a day, copied by hand, for a hundred days.",
        ],
        postTags: [["Essay"], ["Cooking"], ["Books"], ["Travel"], ["Dev", "Retrospective"], ["Music"], ["Essay"], ["Journal"]],
        opening: "Two months ago I started getting off the bus one stop early and walking the rest of the way home. It began as exercise. These days it's when I turn over whatever I read that day.",
        fastReading: "What you read fast, you forget fast. Read at the speed you scroll and the sentences brush past your eyes without ever landing. So lately I read one piece a day, at walking pace.",
        underlineHeading: "Why I underline",
        underline: "When I find a good sentence, I highlight it. Partly so I can find it again, but mostly because drawing the line makes me read it one more time. While my hand follows the sentence, my thinking slows down with it.",
        pullQuote: "Only the sentences you read slowly stay with you.",
        threeReads: "Last week I read the same piece three times. First for the story, then for the sentences, then for the person who wrote it. Each time I underlined somewhere different.",
        photoCaption: "The path outside my building, before the last ginkgo leaves fall.",
        walkingHeading: "Rereading on foot",
        walking: "I keep my phone in my pocket while I walk. Instead I carry one sentence I underlined that day. Waiting at a light or turning a corner, it sometimes reads differently all of a sudden.",
        steps: ["Read one piece a day.", "Underline what stays with you, right then.", "Bring that sentence back to mind on the walk."],
        closing: "Reading slowly didn't mean reading less. More of it stayed, and the more that stayed, the more I wanted to write. I wrote this on foot too.",
        topQuote: "What you read fast, you forget fast.",
        threadQuote: "drawing the line makes me read it one more time.",
        pairQuote: "Each time I underlined somewhere different.",
        threadNote: "This is exactly why I started keeping a pencil handy.",
        authorReply: "I always have a pencil when I read on paper. Nice that it works on a screen too.",
        readerReply: "I keep just the underlined sentences and flip through them now and then. The same line reads differently each time.",
        threadRoot: "Three sentences I kept from today's reading. One at a time.",
        threadParts: [
            "One. What you read fast, you forget fast.",
            "Two. Only the sentences you read slowly stay with you.",
            "Three. Each time I underlined somewhere different.",
        ],
        threadThanks: "You picked these from my post. Thank you.",
        photosNote: "A few shots from the alleys in Lisbon. I'll write it up properly this weekend.",
        photoAlts: ["A narrow cobbled alley", "Laundry strung across an alley", "Houses up the hill"],
        pollNote: "Help me pick next weekend's soup.",
        pollOptions: ["Pumpkin", "Onion", "Tomato"],
        pollReply: "Pumpkin. I haven't stopped thinking about your last photo.",
        quoteNote: "Read this and really did stick to one piece today. Three times, though.",
        linkNote: "A good piece on the slow web. Bookmarked it and read it twice.",
        linkTitle: "In defense of the slow web",
        linkDescription: "On making pages people can linger on, in a web that only rewards speed.",
        walkNote: "The ginkgo leaves on my route are almost gone. Heading out a bit earlier tomorrow. #walking",
        bookNote: "Looking for one thin book to pack for a trip. Any ideas?",
        bookReply: "A collection of short essays would be perfect for copying out.",
        pathTitle: "A slow reading starter",
        pathDescription: "The order I suggest for first-timers. One piece at a time.",
        pathWhys: [
            "Start here. It explains why slow at all.",
            "If you keep one sentence, keep this one.",
            "Rereading in practice, and why the same book reads differently.",
            "After reading, a short note like this is plenty.",
            "End with something a little longer.",
        ],
        connectionWhy: "End with something a little longer. What's left where a bookshop used to be.",
        weekendTitle: "Weekend reading",
        kitchenTitle: "Kitchen notes",
        kitchenWhy: "To try next weekend.",
        bios: ["I walk, then I write about it.", "Mostly rereading."],
        draftTitle: "A late autumn morning walk",
        draftBody: """
        I left an hour earlier than usual today. The sun sat low, so **every alley had a long shadow.**

        ## Where I walked

        - [x] The ginkgo street outside my place
        - [x] Two bridges along the stream
        - [ ] The bakery in the market lane

        > Some things only show up when you walk slowly.

        ![A path between the trees](\(draftImage) "On the way back")

        > [!TIP]
        > Go before ten, before the leaves get swept.
        """,
        draftTag: "Walking",
        published: [
            ("Putting the balcony garden to bed", "Tidied the pots before winter.", "Life"),
            ("My first roll of film", "Seven keepers out of thirty-six.", "Photos"),
        ])

    static let ja = Copy(
        languageTag: "ja",
        names: ["遥", "湊", "美咲", "健太", "直人", "小春"],
        handles: ["haruka_walks", "minato_reads", "misaki_kitchen", "kenta", "naoto", "koharu"],
        postTitles: [
            "歩く速さで読む", "日曜の朝のじゃがいもスープ", "今年読み返した三冊", "リスボンの三日間、28番トラムに乗って",
            "個人開発を一年続けられた理由", "雨の日に聴く十曲", "町の本屋が閉まった日", "書き写しノート100日目",
        ],
        postExcerpts: [
            "ひと駅手前で降りて歩くようになって、読み方が変わった話。",
            "冷蔵庫に残っていたじゃがいも三つと玉ねぎひとつで作った。思ったより簡単。",
            "最初に読んだときは素通りしていた文に、もう一度出会えた。",
            "坂の多い街で、歩き疲れたらトラムに乗った。窓の外を流れていった路地のこと。",
            "意志より習慣だった。毎日三十分、小さくコミットする。",
            "雨が降ると流すプレイリスト。一曲目はいつも同じ。",
            "最後の日に買った一冊と、店主がかけてくれた言葉。",
            "一日一段落ずつ書き写した、百日の記録。",
        ],
        postTags: [["エッセイ"], ["料理"], ["本"], ["旅"], ["開発", "ふりかえり"], ["音楽"], ["エッセイ"], ["記録"]],
        opening: "会社帰りにひと駅手前で降りて歩くようになって、二か月になる。最初は運動のつもりだったけれど、いまはその日に読んだ文章をゆっくり反芻する時間になった。",
        fastReading: "速く読んだ文章は、速く忘れる。画面をスクロールする速さで読むと、文は目の前を通り過ぎるだけで、心までは届かない。だから最近は一日に一本だけ、歩く速さで読むようにしている。",
        underlineHeading: "線を引く理由",
        underline: "いい文に出会うと、蛍光ペンで線を引く。あとで探すためでもあるけれど、線を引くあいだにもう一度その文を読むことになるからだ。手が文をなぞるあいだ、考えも一緒にゆっくりになる。",
        pullQuote: "ゆっくり読んだ文だけが、長く残る。",
        threeReads: "先週は同じ文章を三回読んだ。一回目は筋を、二回目は文を、三回目は書いた人の気持ちを読んだ。読むたびに、線を引く場所が変わった。",
        photoCaption: "家の前の散歩道。イチョウが散りきる前に一枚。",
        walkingHeading: "歩きながら読み返す",
        walking: "歩いているあいだはスマホを出さない。そのかわり、その日線を引いた一文を頭に置いて歩く。信号を待っているとき、角を曲がったとき、その文がふと違う意味に読めることがある。",
        steps: ["一日に一本だけ読む。", "心に残った文は、その場で線を引く。", "歩きながら、その文をもう一度思い出す。"],
        closing: "ゆっくり読むからといって、読む量が減ったわけではなかった。読んだぶんだけ残って、残ったぶんだけまた書きたくなった。この文章も、そうやって歩きながら書いた。",
        topQuote: "速く読んだ文章は、速く忘れる。",
        threadQuote: "線を引くあいだにもう一度その文を読むことになるからだ。",
        pairQuote: "読むたびに、線を引く場所が変わった。",
        threadNote: "鉛筆で線を引く癖、まさにこれが理由でした。",
        authorReply: "紙の本を読むときはいつも鉛筆を持っています。画面でも同じことができるのがうれしいです。",
        readerReply: "線を引いた文だけ集めておいて、ときどき読み返しています。同じ文が違って読めます。",
        threadRoot: "今日読んだ文章から拾った三つの文。ひとつずつ続けて書いておく。",
        threadParts: ["ひとつ。速く読んだ文章は、速く忘れる。", "ふたつ。ゆっくり読んだ文だけが、長く残る。", "みっつ。読むたびに、線を引く場所が変わった。"],
        threadThanks: "わたしの文章から選んでくれたんですね。ありがとうございます。",
        photosNote: "リスボンの路地で撮った写真を何枚か。長い記事は週末にまとめます。",
        photoAlts: ["石畳の細い路地", "洗濯物が干された路地", "坂の上の家並み"],
        pollNote: "来週末に作るスープ、選んでください。",
        pollOptions: ["かぼちゃ", "玉ねぎ", "トマト"],
        pollReply: "かぼちゃで。前の写真を見てからずっと気になっていて。",
        quoteNote: "これを読んで、今日は本当に一本だけ読んだ。そのかわり三回。",
        linkNote: "スローウェブについてのいい記事。ブックマークして二回読んだ。",
        linkTitle: "スローウェブの弁護",
        linkDescription: "速さばかりが残ったウェブで、ゆっくりとどまれるページをつくること。",
        walkNote: "散歩道のイチョウがほとんど散った。明日はもう少し早く出てみよう。#散歩",
        bookNote: "旅行かばんに入れていく薄い本を一冊、おすすめしてほしいです。",
        bookReply: "書き写しやすいエッセイ集だとうれしいです。",
        pathTitle: "ゆっくり読む入門",
        pathDescription: "初めての人にすすめる順番。一本ずつゆっくり。",
        pathWhys: [
            "ここから始めるのがおすすめです。なぜゆっくり読むのかから。",
            "この一文だけ覚えておけば十分です。",
            "同じ本がなぜ違って読めるのか、読み返しの実際。",
            "読んだあとは、こんなふうに短く残しておけばいい。",
            "最後は少し長めの文章で。",
        ],
        connectionWhy: "最後は少し長めの文章で。本屋がなくなった場所に残ったもの。",
        weekendTitle: "週末に読みたい記事",
        kitchenTitle: "料理メモ",
        kitchenWhy: "来週末に作ってみる。",
        bios: ["歩いて、読んで、書いています。", "読み返すのが好きです。"],
        draftTitle: "晩秋の朝の散歩",
        draftBody: """
        今日はいつもより一時間早く家を出た。日が低くて、**路地ごとに影が長かった。**

        ## 今日歩いた道

        - [x] 家の前のイチョウ並木
        - [x] 川沿いの橋をふたつ
        - [ ] 市場の路地のパン屋

        > ゆっくり歩かないと見えないものがある。

        ![木々のあいだの道](\(draftImage) "帰り道")

        > [!TIP]
        > イチョウの葉は、朝十時前に行かないと掃かれてしまう。
        """,
        draftTag: "散歩",
        published: [
            ("ベランダ菜園の片づけ", "冬が来る前に鉢を片づけた。", "暮らし"),
            ("フィルムカメラ最初の一本", "三十六枚のうち、残せたのは七枚。", "写真"),
        ])

    static let vi = Copy(
        languageTag: "vi",
        names: ["Lan", "Minh", "Thảo", "Quân", "Huy", "Vy"],
        handles: ["lan", "minh_doc", "thao_bep", "quan", "huy", "vy"],
        postTitles: [
            "Đọc theo nhịp bước chân", "Súp khoai tây sáng Chủ nhật", "Ba cuốn sách mình đọc lại năm nay",
            "Ba ngày ở Lisbon, trên chuyến tàu điện số 28", "Mình giữ dự án riêng suốt một năm như thế nào",
            "Mười bài hát cho ngày mưa", "Ngày hiệu sách đầu ngõ đóng cửa", "Sổ chép tay, ngày thứ 100",
        ],
        postExcerpts: [
            "Thói quen đọc bắt đầu từ việc xuống xe sớm một trạm.",
            "Ba củ khoai còn trong tủ lạnh và một củ hành. Đơn giản hơn mình tưởng.",
            "Gặp lại những câu lần đầu mình đã lướt qua.",
            "Thành phố nhiều dốc, đi mỏi chân thì mình lên tàu điện. Những con hẻm trôi qua ngoài cửa sổ.",
            "Không phải ý chí mà là thói quen. Mỗi ngày 30 phút, commit thật nhỏ.",
            "Danh sách mình bật mỗi khi trời mưa. Bài đầu tiên chưa bao giờ đổi.",
            "Cuốn sách cuối cùng mình mua ở đó và câu bác chủ tiệm nói lúc đưa sách.",
            "Mỗi ngày chép lại một đoạn, ghi chép của một trăm ngày.",
        ],
        postTags: [["Tản văn"], ["Nấu ăn"], ["Sách"], ["Du lịch"], ["Lập trình", "Nhìn lại"], ["Âm nhạc"], ["Tản văn"], ["Ghi chép"]],
        opening: "Đã hai tháng từ khi mình bắt đầu xuống xe sớm một trạm trên đường đi làm về rồi đi bộ. Lúc đầu chỉ để vận động, giờ đó là lúc mình chậm rãi nghĩ lại những gì đã đọc trong ngày.",
        fastReading: "Đọc nhanh thì quên cũng nhanh. Đọc bằng tốc độ cuộn màn hình, chữ chỉ lướt qua mắt mà không chạm tới lòng. Nên dạo này mỗi ngày mình chỉ đọc một bài, theo nhịp bước chân.",
        underlineHeading: "Vì sao mình gạch chân",
        underline: "Gặp câu hay, mình tô dạ quang. Một phần để sau này tìm lại, nhưng chủ yếu là vì trong lúc tô, mình đọc câu đó thêm một lần nữa. Khi tay lần theo câu chữ, suy nghĩ cũng chậm lại theo.",
        pullQuote: "Chỉ những câu đọc chậm mới ở lại lâu.",
        threeReads: "Tuần trước mình đọc cùng một bài ba lần. Lần đầu đọc cốt truyện, lần hai đọc câu chữ, lần ba đọc tấm lòng người viết. Mỗi lần đọc, chỗ gạch chân lại khác.",
        photoCaption: "Con đường trước nhà. Chụp trước khi lá bạch quả rụng hết.",
        walkingHeading: "Vừa đi vừa đọc lại",
        walking: "Lúc đi bộ mình không lấy điện thoại ra. Thay vào đó, mình mang theo trong đầu một câu đã gạch chân hôm ấy. Đứng chờ đèn đỏ hay rẽ qua góc phố, có khi câu ấy bỗng mang một nghĩa khác.",
        steps: ["Mỗi ngày chỉ đọc một bài.", "Câu nào đọng lại thì gạch ngay lúc đó.", "Trên đường đi, nhớ lại câu ấy thêm một lần."],
        closing: "Đọc chậm không có nghĩa là đọc ít hơn. Đọc bao nhiêu thì đọng lại bấy nhiêu, và càng đọng lại nhiều thì mình càng muốn viết. Bài này cũng được viết trong lúc đi bộ như thế.",
        topQuote: "Đọc nhanh thì quên cũng nhanh.",
        threadQuote: "trong lúc tô, mình đọc câu đó thêm một lần nữa.",
        pairQuote: "Mỗi lần đọc, chỗ gạch chân lại khác.",
        threadNote: "Thói quen gạch bút chì của mình cũng vì lý do này.",
        authorReply: "Đọc sách giấy là mình luôn cầm bút chì. Trên màn hình cũng làm được vậy nên thích lắm.",
        readerReply: "Mình gom riêng những câu đã gạch rồi thỉnh thoảng lật lại. Cùng một câu mà mỗi lần đọc một khác.",
        threadRoot: "Ba câu nhặt được từ bài đọc hôm nay. Ghi nối tiếp từng câu một.",
        threadParts: ["Một. Đọc nhanh thì quên cũng nhanh.", "Hai. Chỉ những câu đọc chậm mới ở lại lâu.", "Ba. Mỗi lần đọc, chỗ gạch chân lại khác."],
        threadThanks: "Bạn chọn từ bài của mình à. Cảm ơn nhé.",
        photosNote: "Vài tấm chụp trong mấy con hẻm ở Lisbon. Bài dài để cuối tuần mình viết.",
        photoAlts: ["Con hẻm lát đá nhỏ hẹp", "Con hẻm phơi quần áo", "Những ngôi nhà trên dốc"],
        pollNote: "Cuối tuần sau nấu súp gì, mọi người chọn giúp mình nhé.",
        pollOptions: ["Bí đỏ", "Hành tây", "Cà chua"],
        pollReply: "Bí đỏ đi. Từ hôm xem ảnh lần trước mình cứ nghĩ mãi.",
        quoteNote: "Đọc bài này xong, hôm nay mình đúng là chỉ đọc một bài. Nhưng đọc ba lần.",
        linkNote: "Một bài hay về web chậm. Mình lưu lại và đọc hai lần.",
        linkTitle: "Lời bênh vực cho web chậm",
        linkDescription: "Làm những trang để người ta dừng lại lâu, giữa một nền web chỉ còn tốc độ.",
        walkNote: "Lá bạch quả trên đường đi dạo gần rụng hết rồi. Mai phải ra sớm hơn chút. #dibo",
        bookNote: "Ai gợi ý giúp mình một cuốn sách mỏng để mang theo đi du lịch với.",
        bookReply: "Tuyển tập tản văn ngắn thì hợp để chép tay lắm.",
        pathTitle: "Nhập môn đọc chậm",
        pathDescription: "Thứ tự mình gợi ý cho người mới. Từng bài một, thật chậm.",
        pathWhys: [
            "Bắt đầu từ đây là hợp nhất. Trước hết là vì sao nên đọc chậm.",
            "Chỉ cần nhớ câu này là đủ.",
            "Vì sao cùng một cuốn sách lại đọc ra khác, chuyện đọc lại.",
            "Đọc xong, ghi ngắn như thế này là được.",
            "Cuối cùng là một bài dài hơn một chút.",
        ],
        connectionWhy: "Cuối cùng là một bài dài hơn một chút. Những gì còn lại ở chỗ hiệu sách từng đứng.",
        weekendTitle: "Đọc cuối tuần",
        kitchenTitle: "Sổ tay nấu ăn",
        kitchenWhy: "Cuối tuần sau thử làm.",
        bios: ["Đi bộ, đọc, rồi viết.", "Thích đọc lại."],
        draftTitle: "Buổi sáng cuối thu đi dạo",
        draftBody: """
        Hôm nay mình ra khỏi nhà sớm hơn thường lệ một tiếng. Nắng xuống thấp nên **con hẻm nào cũng có bóng đổ dài.**

        ## Hôm nay đã đi

        - [x] Hàng bạch quả trước nhà
        - [x] Hai cây cầu dọc con suối
        - [ ] Tiệm bánh trong hẻm chợ

        > Có những thứ chỉ hiện ra khi ta đi chậm.

        ![Con đường giữa hàng cây](\(draftImage) "Đường về")

        > [!TIP]
        > Đi trước mười giờ, kẻo lá bị quét mất.
        """,
        draftTag: "Đi bộ",
        published: [
            ("Dọn vườn rau ban công", "Dọn mấy chậu cây trước khi đông tới.", "Đời sống"),
            ("Cuộn phim đầu tiên", "Ba mươi sáu kiểu, giữ lại được bảy.", "Ảnh"),
        ])

    static let hi = Copy(
        languageTag: "hi",
        names: ["अनन्या", "रोहन", "मीरा", "अर्जुन", "कबीर", "ईशा"],
        handles: ["ananya", "rohan_reads", "meera_kitchen", "arjun", "kabir", "isha"],
        postTitles: [
            "क़दमों की रफ़्तार से पढ़ना", "रविवार सुबह का आलू सूप", "इस साल दोबारा पढ़ीं तीन किताबें",
            "लिस्बन के तीन दिन, ट्राम 28 में", "साइड प्रोजेक्ट को साल भर कैसे चलाया",
            "बारिश के दिन के दस गाने", "जिस दिन मोहल्ले की किताबों की दुकान बंद हुई", "नक़ल वाली कॉपी का सौवाँ दिन",
        ],
        postExcerpts: [
            "एक स्टॉप पहले उतरकर पैदल चलने से बनी पढ़ने की आदत के बारे में।",
            "फ्रिज में बचे तीन आलू और एक प्याज़ से बनाया। जितना सोचा था, उससे आसान।",
            "पहली बार जिन वाक्यों से यूँ ही गुज़र गया था, उनसे फिर मुलाक़ात हुई।",
            "चढ़ाई वाला शहर है, थक जाने पर ट्राम पकड़ ली। खिड़की के बाहर से गुज़रती गलियाँ।",
            "इच्छाशक्ति नहीं, आदत। रोज़ 30 मिनट, छोटे-छोटे कमिट।",
            "बारिश होते ही जो प्लेलिस्ट चलती है। पहला गाना हमेशा वही रहता है।",
            "आख़िरी दिन ख़रीदी एक किताब और दुकानदार की कही बात।",
            "रोज़ एक पैराग्राफ़ हाथ से उतारा, सौ दिनों का हिसाब।",
        ],
        postTags: [["निबंध"], ["खाना"], ["किताबें"], ["यात्रा"], ["डेवलपमेंट", "सीख"], ["संगीत"], ["निबंध"], ["डायरी"]],
        opening: "दफ़्तर से लौटते हुए एक स्टॉप पहले उतरकर पैदल चलना शुरू किए दो महीने हो गए। शुरू में यह कसरत के लिए था, अब यह दिन भर में पढ़ी चीज़ों को धीरे-धीरे दोहराने का वक़्त बन गया है।",
        fastReading: "जल्दी पढ़ा हुआ जल्दी भूल जाता है। स्क्रीन स्क्रॉल करने की रफ़्तार से पढ़ें तो वाक्य आँखों के आगे से निकल जाते हैं, मन तक नहीं पहुँचते। इसलिए आजकल मैं दिन में बस एक लेख पढ़ती हूँ, क़दमों की रफ़्तार से।",
        underlineHeading: "रेखा क्यों खींचती हूँ",
        underline: "अच्छा वाक्य मिलते ही मैं उस पर हाइलाइटर चला देती हूँ। बाद में ढूँढने के लिए भी, पर ज़्यादा इसलिए कि रेखा खींचते हुए वह वाक्य एक बार और पढ़ लेती हूँ। हाथ जब वाक्य के साथ चलता है, तो सोच भी धीमी हो जाती है।",
        pullQuote: "धीरे पढ़े वाक्य ही देर तक साथ रहते हैं।",
        threeReads: "पिछले हफ़्ते मैंने एक ही लेख तीन बार पढ़ा। पहली बार कहानी, दूसरी बार वाक्य, तीसरी बार लिखने वाले का मन। हर बार रेखा किसी और जगह खिंची।",
        photoCaption: "घर के सामने वाला रास्ता। जिन्को के सारे पत्ते झड़ने से पहले।",
        walkingHeading: "चलते-चलते दोबारा पढ़ना",
        walking: "चलते समय मैं फ़ोन नहीं निकालती। उसकी जगह उस दिन रेखांकित किया एक वाक्य मन में लेकर चलती हूँ। सिग्नल पर रुकते या मोड़ मुड़ते हुए कभी-कभी वह वाक्य अचानक किसी और मतलब में पढ़ा जाता है।",
        steps: ["दिन में बस एक लेख पढ़ना।", "जो वाक्य मन में रह जाए, उसे उसी वक़्त रेखांकित करना।", "चलते हुए उस वाक्य को एक बार फिर याद करना।"],
        closing: "धीरे पढ़ने का मतलब कम पढ़ना नहीं निकला। जितना पढ़ा, उतना याद रहा, और जितना याद रहा, उतना ही फिर लिखने का मन हुआ। यह लेख भी ऐसे ही चलते-चलते लिखा है।",
        topQuote: "जल्दी पढ़ा हुआ जल्दी भूल जाता है।",
        threadQuote: "रेखा खींचते हुए वह वाक्य एक बार और पढ़ लेती हूँ।",
        pairQuote: "हर बार रेखा किसी और जगह खिंची।",
        threadNote: "पेंसिल से रेखा खींचने की मेरी आदत भी इसी वजह से है।",
        authorReply: "काग़ज़ की किताब पढ़ते समय मेरे हाथ में हमेशा पेंसिल रहती है। स्क्रीन पर भी यह हो पाता है, अच्छा लगता है।",
        readerReply: "मैं रेखांकित वाक्य अलग रख लेता हूँ और कभी-कभी पलट लेता हूँ। वही वाक्य हर बार अलग लगता है।",
        threadRoot: "आज पढ़े लेख से चुने तीन वाक्य। एक-एक करके लिख रही हूँ।",
        threadParts: ["एक। जल्दी पढ़ा हुआ जल्दी भूल जाता है।", "दो। धीरे पढ़े वाक्य ही देर तक साथ रहते हैं।", "तीन। हर बार रेखा किसी और जगह खिंची।"],
        threadThanks: "मेरे लेख से चुने हैं आपने। शुक्रिया।",
        photosNote: "लिस्बन की गलियों में खींची कुछ तस्वीरें। लंबा लेख इस वीकेंड लिखूँगा।",
        photoAlts: ["पत्थरों वाली तंग गली", "कपड़े सूखती गली", "पहाड़ी पर बने घर"],
        pollNote: "अगले वीकेंड कौन-सा सूप बनाऊँ, आप बताइए।",
        pollOptions: ["कद्दू", "प्याज़", "टमाटर"],
        pollReply: "कद्दू। पिछली तस्वीर देखने के बाद से वही दिमाग़ में है।",
        quoteNote: "यह पढ़कर आज सच में बस एक लेख पढ़ा। हाँ, तीन बार।",
        linkNote: "स्लो वेब पर एक अच्छा लेख। बुकमार्क करके दो बार पढ़ा।",
        linkTitle: "स्लो वेब के पक्ष में",
        linkDescription: "सिर्फ़ रफ़्तार वाले वेब में ऐसे पन्ने बनाना जिन पर लोग ठहर सकें।",
        walkNote: "रास्ते के जिन्को के पत्ते लगभग झड़ गए। कल थोड़ा जल्दी निकलूँगी। #सैर",
        bookNote: "सफ़र में ले जाने के लिए कोई पतली-सी किताब सुझाइए।",
        bookReply: "छोटे निबंधों का संग्रह हो तो नक़ल करने के लिए बढ़िया रहेगा।",
        pathTitle: "धीरे पढ़ने की शुरुआत",
        pathDescription: "पहली बार आने वालों के लिए सुझाया क्रम। एक-एक लेख, धीरे-धीरे।",
        pathWhys: [
            "यहीं से शुरू करना अच्छा है। पहले यह कि धीरे क्यों पढ़ें।",
            "बस यह एक वाक्य याद रहे, इतना काफ़ी है।",
            "वही किताब अलग क्यों लगती है, दोबारा पढ़ने का असली अनुभव।",
            "पढ़ने के बाद ऐसा छोटा-सा नोट लिख लेना काफ़ी है।",
            "आख़िर में थोड़ा लंबा लेख।",
        ],
        connectionWhy: "आख़िर में थोड़ा लंबा लेख। दुकान के जाने के बाद जो बचा रहा।",
        weekendTitle: "वीकेंड पर पढ़ने के लिए",
        kitchenTitle: "रसोई के नोट्स",
        kitchenWhy: "अगले वीकेंड बनाकर देखना है।",
        bios: ["चलती हूँ, फिर उस पर लिखती हूँ।", "दोबारा पढ़ना पसंद है।"],
        draftTitle: "पतझड़ के आख़िर की एक सुबह",
        draftBody: """
        आज रोज़ से एक घंटा पहले घर से निकलना हुआ। धूप नीची थी, इसलिए **हर गली में परछाइयाँ लंबी थीं।**

        ## आज का रास्ता

        - [x] घर के सामने जिन्को वाली सड़क
        - [x] नदी किनारे के दो पुल
        - [ ] बाज़ार वाली गली की बेकरी

        > कुछ चीज़ें धीरे चलने पर ही दिखती हैं।

        ![पेड़ों के बीच का रास्ता](\(draftImage) "लौटते हुए")

        > [!TIP]
        > दस बजे से पहले जाना, वरना पत्ते झाड़ दिए जाते हैं।
        """,
        draftTag: "सैर",
        published: [
            ("बालकनी गार्डन की सफ़ाई", "सर्दी से पहले गमले समेट दिए।", "ज़िंदगी"),
            ("फ़िल्म कैमरे का पहला रोल", "छत्तीस में से सात तस्वीरें रखने लायक निकलीं।", "तस्वीरें"),
        ])
}
