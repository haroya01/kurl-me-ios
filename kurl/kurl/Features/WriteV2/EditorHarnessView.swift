//
//  EditorHarnessView.swift
//  kurl — WriteV2 (격리 하네스)
//
//  ComposeView 를 전혀 안 건드리고 새 WYSIWYG 에디터를 단독 실행·검증하는 화면.
//  실행 경로 둘:
//   1) Xcode Canvas — 이 파일 하단 #Preview("WriteV2 하네스").
//   2) 런치 플래그 `--screen editor2` — RootView 에 한 줄만 더하면(선택) simctl 스샷용 진입로.
//      Config.launchValue(after:) 규칙은 기존과 동일. (Phase 1 은 RootView 를 안 고친다 —
//      아래 EditorHarnessRoot 를 그 분기에 연결하는 한 줄이 유일한 통합 지점이다.)
//
//  하네스는 하단에 "마크다운 보기" 토글을 둔다 — 왕복(블록→마크다운)을 눈으로 확인하는 검증 장치다
//  (에디터 본체엔 원시 마크다운이 안 보이지만, 하네스는 직렬화 결과를 따로 띄워 대조한다).
//

import SwiftUI

/// simctl 진입용 루트 래퍼 — RootView 의 `--screen` 분기에서 이걸 반환하면 된다(선택 통합).
struct EditorHarnessRoot: View {
    var body: some View {
        EditorHarnessView(document: EditorDocument(blocks: EditorSample.blocks))
    }
}

struct EditorHarnessView: View {
    @State private var document: EditorDocument
    @State private var showMarkdown = false

    init(document: EditorDocument) {
        _document = State(initialValue: document)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            WysiwygEditorView(document: document)

            // 검증용 유리 캡슐(§1 크롬만 유리) — 삽입 툴바 + 왕복 직렬화 결과 대조.
            VStack(spacing: 10) {
                if showMarkdown {
                    markdownInspector
                }
                insertToolbar
                Button {
                    withAnimation(.snappy(duration: 0.22)) { showMarkdown.toggle() }
                } label: {
                    Label(
                        showMarkdown ? "마크다운 닫기" : "마크다운 보기",
                        systemImage: showMarkdown ? "chevron.down" : "curlybraces"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .foregroundStyle(Palette.link)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
            }
        }
    }

    /// 삽입 툴바(§1 크롬 유리) — 포커스 블록 뒤에 링크·구분선·이미지·표를 넣는다.
    private var insertToolbar: some View {
        HStack(spacing: 18) {
            Button {
                document.insertLink(url: "https://kurl.me", label: "kurl 링크")
            } label: { Image(systemName: "link") }
            Button {
                document.insertNonText(.divider)
            } label: { Image(systemName: "minus") }
            Button {
                // 실제로 로드되는 이미지 — 죽은 주소는 하네스·캡처에 에러 카드만 남긴다.
                document.insertNonText(
                    .image(url: "https://picsum.photos/seed/kurl-insert/1200/800", alt: ""))
            } label: { Image(systemName: "photo") }
            Button {
                document.insertNonText(.table(.blank))
            } label: { Image(systemName: "tablecells") }
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Palette.link)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }

    private var markdownInspector: some View {
        ScrollView {
            Text(document.markdown)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxHeight: 220)
        .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusControl)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

/// 하네스 샘플 — Phase 2 블록 8종 WYSIWYG 증명(문단·제목·인용·코드·구분선·리스트·이미지·표).
/// 데모 카피는 하네스 전용 — 스토어 캡처가 이 화면을 쓰므로 "있을 법한 글"(아침 산책 에세이)로,
/// 시스템 언어(스토어 5개 언어)를 따라간다. 이미지는 실제로 로드되는 주소여야 한다 —
/// 예전 kurl.me/sample.jpg 는 404 라 캡처마다 "불러오지 못했어요"가 박혔다.
enum EditorSample {
    static var blocks: [EditorBlock] {
        let lang = MockStoreDemo.lang
        let sampleImage = "https://picsum.photos/seed/kurl-walk/1200/800"
        switch lang {
        case "ja":
            return [
                .heading(1, "朝の散歩で拾った文章"),
                .paragraph("路地の先のパン屋の匂いが**今日の始まり**を知らせる。*ゆっくり*歩くことにした。"),
                .paragraph("昨日読んだ[記事](https://blog.kurl.me)が頭に残っていて、歩きながら数行を書き留めた。"),
                .divider,
                .heading(2, "今日持ち帰ったもの"),
                .listItem("銀杏の木の下のベンチ — 次は本を持ってこよう。", ordered: false, indent: 0),
                .listItem("角のカフェの新しい豆(酸味がいい)。", ordered: false, indent: 1),
                .listItem("帰ったら30分だけ書く。", ordered: true, indent: 0),
                .listItem("写真を整理する。", ordered: true, indent: 0),
                .image(url: sampleImage, alt: "散歩道"),
                .quote("速く通り過ぎると見えないものがある。"),
                .table(EditorTable(
                    rows: [["曜日", "歩数"], ["土", "6,200"], ["日", "8,940"]],
                    alignments: [.leading, .trailing]
                )),
            ]
        case "vi":
            return [
                .heading(1, "Những câu nhặt được trên đường đi bộ buổi sáng"),
                .paragraph("Mùi bánh mì cuối ngõ báo hiệu **một ngày bắt đầu**. Tôi quyết định đi *thật chậm*."),
                .paragraph("[Bài viết](https://blog.kurl.me) đọc hôm qua cứ vương vấn, nên tôi vừa đi vừa chép lại vài dòng."),
                .divider,
                .heading(2, "Hôm nay mang về"),
                .listItem("Chiếc ghế dưới hàng cây — lần sau sẽ mang theo sách.", ordered: false, indent: 0),
                .listItem("Cà phê mới ở quán góc phố (chua thanh, rất ngon).", ordered: false, indent: 1),
                .listItem("Về nhà viết 30 phút.", ordered: true, indent: 0),
                .listItem("Dọn lại album ảnh.", ordered: true, indent: 0),
                .image(url: sampleImage, alt: "đường đi bộ"),
                .quote("Có những thứ chỉ hiện ra khi ta đi chậm lại."),
                .table(EditorTable(
                    rows: [["Ngày", "Số bước"], ["T7", "6.200"], ["CN", "8.940"]],
                    alignments: [.leading, .trailing]
                )),
            ]
        case "hi":
            return [
                .heading(1, "सुबह की सैर में मिले वाक़्य"),
                .paragraph("गली के छोर की बेकरी की ख़ुशबू **दिन की शुरुआत** बताती है। मैंने *धीरे* चलना चुना।"),
                .paragraph("कल पढ़ा [लेख](https://blog.kurl.me) दिमाग़ में घूमता रहा, तो चलते-चलते कुछ पंक्तियाँ उतार लीं।"),
                .divider,
                .heading(2, "आज क्या साथ लाया"),
                .listItem("पेड़ के नीचे वाली बेंच — अगली बार किताब लाऊँगा।", ordered: false, indent: 0),
                .listItem("नुक्कड़ कैफ़े की नई कॉफ़ी (हल्की खटास, बढ़िया)।", ordered: false, indent: 1),
                .listItem("लौटकर 30 मिनट लिखना।", ordered: true, indent: 0),
                .listItem("तस्वीरें समेटना।", ordered: true, indent: 0),
                .image(url: sampleImage, alt: "सैर का रास्ता"),
                .quote("तेज़ी से गुज़र जाओ तो कुछ चीज़ें दिखती ही नहीं।"),
                .table(EditorTable(
                    rows: [["दिन", "क़दम"], ["शनि", "6,200"], ["रवि", "8,940"]],
                    alignments: [.leading, .trailing]
                )),
            ]
        case "en":
            return [
                .heading(1, "Sentences picked up on a morning walk"),
                .paragraph("The smell from the bakery at the end of the alley announces **the start of the day**. I decided to walk *slowly*."),
                .paragraph("The [post](https://blog.kurl.me) I read yesterday kept circling back, so I copied a few lines as I walked."),
                .divider,
                .heading(2, "What I brought home"),
                .listItem("The bench under the ginkgo — bring a book next time.", ordered: false, indent: 0),
                .listItem("New beans at the corner café (lovely acidity).", ordered: false, indent: 1),
                .listItem("Write for 30 minutes after getting back.", ordered: true, indent: 0),
                .listItem("Sort the photos.", ordered: true, indent: 0),
                .image(url: sampleImage, alt: "walking path"),
                .quote("Some things stay invisible when you pass them quickly."),
                .table(EditorTable(
                    rows: [["Day", "Steps"], ["Sat", "6,200"], ["Sun", "8,940"]],
                    alignments: [.leading, .trailing]
                )),
            ]
        default:
            return [
                .heading(1, "아침 산책에서 주운 문장들"),
                .paragraph("골목 끝 빵집 냄새가 **오늘의 시작**을 알린다. *천천히* 걷기로 했다."),
                .paragraph("어제 읽은 [글](https://blog.kurl.me)이 계속 맴돌아서, 걸으며 몇 줄을 옮겨 적었다."),
                .divider,
                .heading(2, "오늘 담아온 것"),
                .listItem("은행나무 아래 벤치 — 다음엔 책을 들고 올 것.", ordered: false, indent: 0),
                .listItem("모퉁이 카페의 새 원두(산미가 좋다).", ordered: false, indent: 1),
                .listItem("돌아와서 30분 글쓰기.", ordered: true, indent: 0),
                .listItem("사진 정리.", ordered: true, indent: 0),
                .image(url: sampleImage, alt: "산책길"),
                .quote("빠르게 지나치면 보이지 않는 것들이 있다."),
                .table(EditorTable(
                    rows: [["요일", "걸음"], ["토", "6,200"], ["일", "8,940"]],
                    alignments: [.leading, .trailing]
                )),
            ]
        }
    }
}

#Preview("WriteV2 하네스") {
    EditorHarnessView(document: EditorDocument(blocks: EditorSample.blocks))
}

#Preview("WriteV2 빈 문서") {
    EditorHarnessView(document: EditorDocument())
}
