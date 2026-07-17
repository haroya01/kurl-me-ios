//
//  ComposeView.swift
//  kurl
//

import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// 마크다운 컴포즈 — 제목·태그·소개글·시리즈·커버 메타 + 본문 캔버스.
/// 자동저장(2초 디바운스·dirty 시그니처)이 기본이고, ⋯ 메뉴에 미리보기/예약 발행/리비전.
/// 본문은 서버 md→blocks 변환, 메타는 PATCH 부분 수정(slug 는 안 보냄 — 발행 후 frozen).
struct ComposeView: View {
    let existing: MyPost?
    let onSaved: () -> Void
    /// 방금 발행한 글의 slug 를 들고 닫힌다 — 호스트(스튜디오)가 라이브 글로 이어 보낸다.
    var onOpenPublished: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    private enum Field: Hashable { case title }
    @FocusState private var focusedField: Field?

    /// 본문 캔버스(UIKit 직결)의 포커스·커서 제어 — TextEditor selection 바인딩의
    /// 한글 조합 깨짐을 피해 FocusState 대신 delegate 콜백으로 추적한다.
    @State private var editorController = MarkdownEditorController()
    @State private var editorFocused = false
    /// 캐럿이 표 안에 있는가 — 그때만 행·열 편집 바를 마크다운 바 위에 띄운다.
    @State private var caretInTable = false
    /// 캐럿이 이미지 줄에 있는가 — 그때만 폭·캡션·삭제 편집 바를 띄운다.
    @State private var caretOnImage = false
    /// 캐럿이 단독 URL(임베드) 줄에 있는가 — 그때만 교체·삭제 바를 띄운다.
    @State private var caretOnVideo = false
    /// 캐럿이 목록 줄에 있는가 — 그때만 들여쓰기/내어쓰기 바를 띄운다(목록 밖에선 감춰 소음을 줄인다).
    @State private var caretInList = false
    /// 내어쓰기 가능 여부(선행 공백이 있을 때만) — 목록 바의 '내어쓰기' 비활성 상태에 반영.
    @State private var caretCanOutdent = false
    /// 실행취소/다시실행 가능 여부 — 스니펫 바의 버튼 비활성 상태에 라이브로 반영.
    @State private var canUndo = false
    @State private var canRedo = false
    /// 이미 넣은 이미지의 캡션을 고치는 시트.
    @State private var showEditImageCaption = false
    @State private var editImageCaptionText = ""

    @State private var title = ""
    @State private var tags: [String] = []
    @State private var tagDraft = ""
    @State private var excerpt = ""
    @State private var markdown = ""
    /// WYSIWYG(WriteV2) 옵트인일 때만 사는 블록 문서. `markdown` 문자열이 여전히 저장 계약의
    /// 진실이고(자동저장·DraftFlusher·발행 전부 이걸 본다), 이 문서는 그 위에 얹힌 편집 표면이다.
    /// blocks 변화 → `markdown = document.markdown` 으로 동기화해 기존 저장 파이프를 그대로 태운다.
    /// nil = 현행 마크다운 에디터(MarkdownTextView) default 경로.
    /// nil = 옛 마크다운 에디터(MarkdownTextView) 복귀 경로(설정 토글/`--editor legacy`). 기본은 non-nil.
    @State private var editorDocument: EditorDocument?
    /// WriteV2 캔버스에 이미지를 넣는 사진 선택 — 실제 업로드 후 `insertNonText(.image)` 로 삽입한다.
    @State private var showV2ImagePicker = false
    @State private var v2ImageItem: PhotosPickerItem?
    /// WriteV2 통합 링크 삽입 — 주소(+선택 라벨)를 받아 동영상이면 임베드, 아니면 링크로 문서에 넣는다.
    @State private var showV2LinkDialog = false
    @State private var v2LinkURL = ""
    @State private var v2LinkLabel = ""
    /// 링크 알럿을 열기 직전에 잡아둔 캔버스 포커스(블록·선택) — 알럿이 first responder 를 뺏어 선택이
    /// 접히므로, 확인 시 이 포커스로 원래 선택을 감싼다. nil 이면 포커스 없이 눌린 것(문단 삽입 폴백).
    @State private var v2LinkTargetFocus: EditorFocus?
    @State private var postId: Int64?
    @State private var status = "DRAFT"
    @State private var busy = false
    /// 발행 성공 모먼트(전체화면 블룸) 표시.
    @State private var celebrating = false
    /// 예약 발행 모먼트 = 같은 마크 환호지만 "예약되었습니다" + 발행 예정 시각, "글 보기"는 없음(아직 비공개).
    @State private var celebrationIsSchedule = false
    @State private var celebrationSubtitle: String?
    @State private var errorMessage: String?
    @State private var loaded = false
    /// 기존 글 본문을 서버에서 성공적으로 읽었는가 — 읽기 전엔 저장(전체 교체)을 절대 보내지 않는다.
    /// 새 글은 읽을 본문이 없으므로 곧장 true. 로드 실패 시 false 로 남아 빈 본문 덮어쓰기를 막는다.
    @State private var bodyLoaded = false
    /// 기존 글 본문 로드가 실패했는가 — 에디터를 잠그고 다시 시도 안내를 띄운다.
    @State private var loadFailed = false
    @State private var lastSavedSignature: String?
    @State private var lastSavedAt: Date?
    /// 마지막 자동저장이 실패했는가 — 정직한 '저장 실패' 표시(조용히 재시도 중).
    @State private var autosaveFailed = false
    /// 실패 원인이 인증(401·세션 만료)인가 — "실패했어요"만 반복하면 사용자는 원인을 영영 모른다.
    /// 편집 중 세션이 죽으면(리프레시 토큰 만료 → 로컬 세션 폐기) 이후 모든 저장이 같은 이유로
    /// 실패하므로, 배지·토스트가 "다시 로그인" 을 말해야 한다.
    @State private var autosaveNeedsLogin = false
    /// 연속 자동저장 실패 횟수 — 재시도 간격 백오프 계산용(성공하면 리셋).
    @State private var autosaveRetryStreak = 0
    /// 발행 폼 안에서의 발행/저장 실패 — fullScreenCover 라 루트 알럿이 가려져 폼에 따로 띄운다.
    @State private var publishSheetError: String?
    @State private var showSaveStatus = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var createTask: Task<Int64, Error>?
    /// 기기 로컬 초안 금고 스태시 디바운스 — 서버 자동저장과 별개로, 못 실린 변경을 기기에 남긴다.
    @State private var recoveryStashTask: Task<Void, Never>?
    /// 열었을 때 금고에서 발견한 "서버에 못 실린 변경" — 복구/버리기 제안의 재료.
    @State private var pendingRecovery: ComposeRecoveryStore.Draft?
    /// 세션이 풀렸을 때 컴포즈를 떠나지 않고 다시 로그인하는 시트.
    @State private var showLoginSheet = false

    // 마지막으로 서버에 반영된 메타 — 바뀐 필드만 PATCH 해 다른 기기(웹)의 동시 편집을 덮지 않는다.
    @State private var savedTitle = ""
    @State private var savedExcerpt = ""
    @State private var savedTags: [String] = []

    // 시리즈
    @State private var seriesList: [MySeries] = []
    @State private var seriesId: Int64?
    @State private var savedSeriesId: Int64?
    @State private var showNewSeries = false
    @State private var newSeriesTitle = ""
    @State private var creatingSeries = false

    // 커버
    @State private var coverUrl: String?
    @State private var coverItem: PhotosPickerItem?
    @State private var uploadingCover = false

    // 본문 이미지 — 스니펫 바의 사진 버튼이 연다. 업로드되면 곧장 커서 자리에 삽입(막는 캡션 다이얼로그 없이).
    @State private var showBodyImagePicker = false
    @State private var bodyImageItem: PhotosPickerItem?
    @State private var uploadingBodyImage = false

    // 시트
    @State private var showPublish = false
    @State private var previewItem: PreviewItem?

    struct PreviewItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    /// 발행 폼(fullScreenCover) 안에서 여는 미리보기 — 루트 ⋯ 미리보기(previewItem)와 분리.
    @State private var formPreviewItem: PreviewItem?
    /// 이미 발행된 글의 미리보기 — 웹 시트가 아니라 인앱 리더(PostDetailView)로 네이티브 항해한다.
    /// 발행 전(초안·예약·비공개)은 공개 엔드포인트가 안 줘서 여전히 미리보기 토큰 URL(previewItem)로 연다.
    @State private var previewPublished: PublishedRef?
    /// 초안(미발행) 네이티브 미리보기 — 지금 문서를 발행 후 읽기면으로 보여준다(웹 사파리 대신).
    /// 발행된 글은 이 경로를 안 탄다(위 previewPublished 가 PostDetailView 로 항해). 루트(⋯)와 발행 폼에서
    /// 각각 뜨므로 presenter 를 둘로 나눈다(웹 preview 의 previewItem/formPreviewItem 과 같은 이유 —
    /// 폼은 fullScreenCover 라 루트 시트가 그 아래 깔려 안 보인다).
    @State private var showDraftPreview = false
    @State private var showFormDraftPreview = false
    @State private var showSchedule = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var scheduleError: String?
    @State private var showRevisions = false

    // 링크 추가 다이얼로그 — 본문에 `(url)` 리터럴을 떨구지 않고 주소를 받아서 넣는다.
    @State private var showLinkDialog = false
    @State private var linkURL = ""
    @State private var linkLabel = ""
    @State private var showVideoDialog = false
    @State private var videoURL = ""

    /// 방금 발행한 글의 slug — 셀레브레이션의 "글 보기" 한 틱이 이걸 들고 라이브로 보낸다.
    @State private var publishedSlug: String?

    init(post: MyPost?, onSaved: @escaping () -> Void, onOpenPublished: ((String) -> Void)? = nil) {
        self.existing = post
        self.onSaved = onSaved
        self.onOpenPublished = onOpenPublished
    }

    var body: some View {
        VStack(spacing: 0) {
            // 가로(compact 높이)에서 에디터에 포커스가 가면 메타를 접는다 —
            // 안 그러면 키보드+메타가 에디터 가시 영역을 0 으로 만든다.
            if !(verticalSizeClass == .compact && editorFocused) {
                meta
                Hairline()
                    .padding(.horizontal, Metrics.gutter)
            }
            editor
        }
        .background(Palette.readingBg.ignoresSafeArea())
        // 키보드 위에 뜨는 유리 마크다운 바 — 캔버스는 종이, 크롬은 유리(AGENTS.md §1).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let editorDocument {
                // WriteV2 서식 툴바 — 선택 서식(볼드·이탤릭·코드·링크)·블록 서식(제목·인용·코드·리스트)·
                // 삽입(구분선·사진·표)을 한 유리 바로. 캔버스는 종이, 이 크롬만 유리(AGENTS §1).
                V2FormatToolbar(
                    focusedKind: editorDocument.focus.flatMap { f in
                        editorDocument.blocks.first(where: { $0.id == f.blockID })?.kind
                    },
                    wrapInline: { marker in editorDocument.wrapFocusedSelection(with: marker); syncFromDocument() },
                    insertLink: { presentV2LinkSheet() },
                    toggleBlock: { kind in editorDocument.toggleFocusedBlockKind(kind); syncFromDocument() },
                    cycleHeading: { editorDocument.cycleFocusedHeading(); syncFromDocument() },
                    insertDivider: { editorDocument.insertNonText(.divider); syncFromDocument() },
                    insertImage: { showV2ImagePicker = true },
                    insertTable: { editorDocument.insertNonText(.table(.blank)); syncFromDocument() },
                    indentList: {
                        if let id = editorDocument.focus?.blockID {
                            editorDocument.indentListItem(id)
                            syncFromDocument()
                        }
                    },
                    outdentList: {
                        if let id = editorDocument.focus?.blockID {
                            editorDocument.outdentListItem(id)
                            syncFromDocument()
                        }
                    },
                    dismissKeyboard: {
                        // 포커스 블록의 UITextView 는 responder 체인에 있으니 전역 resign 으로 키보드를 접고,
                        // 문서 focus 도 비워 서식 툴바가 함께 내려가게 한다(editorFocused=false).
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        editorDocument.focus = nil
                    }
                )
            } else if editorFocused {
                VStack(spacing: 8) {
                    // 캐럿이 표 안일 때만 — 마크다운을 몰라도 행·열을 늘리고 줄인다.
                    if caretInTable {
                        TableActionBar(perform: applyTableAction)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // 캐럿이 이미지 줄일 때만 — 폭·캡션을 바꾸고 지운다(마크다운을 건드리지 않고).
                    if caretOnImage {
                        ImageActionBar(
                            selectedWidth: editorController.currentImageWidth(),
                            perform: applyImageAction
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // 캐럿이 단독 URL(임베드) 줄일 때만 — 교체·삭제.
                    if caretOnVideo {
                        VideoActionBar(perform: applyVideoAction)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // 캐럿이 목록 줄일 때만 — 들여쓰기/내어쓰기(목록 밖에선 스니펫 바에서 감춰 소음을 줄였다).
                    if caretInList {
                        ListActionBar(canOutdent: caretCanOutdent, perform: applyListAction)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    MarkdownSnippetBar(
                        canUndo: canUndo, canRedo: canRedo,
                        undo: performUndo, redo: performRedo,
                        perform: applySnippet
                    ) { editorController.dismissKeyboard() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: editorFocused)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: caretInTable)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: caretOnImage)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: caretOnVideo)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: caretInList)
        .navigationTitle(existing == nil ? "새 글" : "편집")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        // 쓰는 동안 탭 5개가 떠 있을 이유가 없다 — 에디터는 풀스크린 몰입.
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .task {
            await loadExisting()
            // `--focus editor` / `--sheet publish` — 검증 진입로(simctl 터치 불가 우회).
            if Config.consumeLaunchValue(after: "--focus") == "editor" {
                // representable 의 makeUIView 가 붙은 뒤에 포커스를 줘야 한다.
                try? await Task.sleep(for: .milliseconds(200))
                editorController.focus()
            }
            if Config.consumeLaunchValue(after: "--sheet") == "publish" {
                showPublish = true
            }
        }
        .onChange(of: signature) { scheduleAutosave() }
        .onChange(of: coverItem) { uploadPickedCover() }
        .photosPicker(isPresented: $showBodyImagePicker, selection: $bodyImageItem, matching: .images)
        .onChange(of: bodyImageItem) { uploadBodyImage() }
        .photosPicker(isPresented: $showV2ImagePicker, selection: $v2ImageItem, matching: .images)
        .onChange(of: v2ImageItem) { uploadV2BodyImage() }
        .onDisappear {
            // 디바운스 창에 걸린 마지막 변경을 버리지 않는다 — 마지막 1회 저장.
            // 단, 이 뷰(값 타입)는 곧 사라지므로 여기서 Task 로 save(silent:) 를 돌리면
            // 죽어가는 @State 위에서 실패해도 배지·토스트를 못 띄워 조용히 유실됐다.
            // 저장을 뷰 수명과 분리된 루트 싱글턴(DraftFlusher)에 넘겨, 사라진 뒤에도
            // 끝까지 밀고 실패 시 루트 토스트로 반드시 알린다(초안 미생성=전량 유실 방지).
            autosaveTask?.cancel()
            // 디바운스를 기다리지 않고 즉시 금고에 눕힌다 — 이탈 플러시가 실패해도 기기에 남는다.
            recoveryStashTask?.cancel()
            if signature != lastSavedSignature {
                ComposeRecoveryStore.stash(postId: postId, title: title, markdown: markdown)
            }
            if canSave, signature != lastSavedSignature {
                DraftFlusher.shared.flush(
                    .init(
                        postId: postId,
                        title: title,
                        markdown: markdown,
                        savedTitle: savedTitle,
                        savedExcerpt: savedExcerpt,
                        savedTags: savedTags,
                        excerpt: excerpt,
                        tags: tags,
                        savedSeriesId: savedSeriesId,
                        seriesId: seriesId))
            }
        }
        // 발행 준비 = 살아있는 카드 미리보기 폼(전체 화면). 미리보기·예약은 이 폼 위에
        // 바로 떠서 폼을 잃지 않는다(닫았다 다시 여는 왕복을 없앴다).
        .fullScreenCover(isPresented: $showPublish) { publishSheet }
        // ⋯ 메뉴의 미리보기(폼 밖) 경로 — 발행 전 글은 인앱 사파리(미리보기 토큰 URL).
        .sheet(item: $previewItem) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        // 이미 발행된 글의 미리보기 = 인앱 리더로 네이티브 항해(웹으로 안 내보낸다). 뒤로 = 에디터.
        .navigationDestination(item: $previewPublished) { ref in
            PostDetailView(username: ref.username, slug: ref.slug)
        }
        // 초안(미발행) 네이티브 미리보기 — 폼 밖(⋯ 메뉴) 경로. 지금 문서를 발행 후 읽기면으로.
        .sheet(isPresented: $showDraftPreview) {
            DraftPreviewView(title: title, markdown: markdown)
        }
        .sheet(isPresented: $showRevisions) {
            RevisionsSheet(postId: postId) { restored in
                markdown = restored
                // WriteV2 라면 복원 본문으로 문서를 다시 짓는다(제자리 교체 API 가 없어 재생성이 계약).
                rebuildEditorDocumentIfNeeded()
                // 복원 본문을 곧장 '저장됨'으로 맞춰(동기) 2초 디바운스가 복원본문+옛메타로
                // 저장하는 창을 닫는다. 메타는 syncAfterRestore 가 마저 맞춘다.
                lastSavedSignature = signature
                Task { await syncAfterRestore() }
            }
        }
        // 지난 세션이 저장 실패/강제 종료로 끝났다 — 기기 금고의 변경을 이어 쓸지 묻는다.
        .alert(
            "저장되지 못한 본문이 있어요",
            isPresented: .init(get: { pendingRecovery != nil }, set: { if !$0 { pendingRecovery = nil } })
        ) {
            Button("이어서 쓰기") {
                guard let draft = pendingRecovery else { return }
                title = draft.title
                markdown = draft.markdown
                rebuildEditorDocumentIfNeeded()
                scheduleAutosave()
                pendingRecovery = nil
            }
            Button("버리기", role: .destructive) {
                ComposeRecoveryStore.clear(postId: postId)
                pendingRecovery = nil
            }
        } message: {
            Text("지난 편집이 서버에 저장되지 못한 채 끝났어요. 기기에 남아 있는 내용을 이어서 쓸까요?")
        }
        // 세션이 풀렸을 때 — 컴포즈를 떠나지 않고 여기서 다시 로그인해 이어서 저장한다.
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet(message: "로그인이 풀렸어요 — 다시 로그인하면 쓰던 글이 이어서 저장돼요.") {
                autosaveNeedsLogin = false
                scheduleAutosave(after: .zero)
            }
        }
        // 저장·발행·예약·미리보기 모두 이 알럿을 쓰므로 제목은 중립으로 — 본문에 서버가 준 사유를 보인다.
        .alert(
            "문제가 생겼어요",
            isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        // 링크 추가 — 주소만 받아 본문에 `[라벨](주소)` 로. 본문에 `(url)` 가 보이지 않는다.
        .alert("링크 추가", isPresented: $showLinkDialog) {
            TextField("https://…", text: $linkURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Button("추가") { confirmLink() }
            Button("취소", role: .cancel) {}
        } message: {
            Text(linkLabel.isEmpty
                ? "주소를 붙여넣거나 입력하세요."
                : "‘\(linkLabel)’에 연결할 주소를 입력하세요.")
        }
        // 동영상 추가 — YouTube/Vimeo 주소를 한 줄로 넣으면 발행 시 플레이어로(EMBED).
        .alert("동영상 추가", isPresented: $showVideoDialog) {
            TextField("https://youtu.be/…", text: $videoURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Button("추가") { confirmVideo() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("YouTube·Vimeo 주소를 붙여넣거나 입력하세요.")
        }
        // WriteV2 통합 링크 — 하나의 입력으로 링크·동영상을 다 받는다. 주소가 동영상이면 발행 시
        // 플레이어(임베드), 아니면 링크. 라벨은 링크일 때만 쓰이고, 동영상이면 주소 자체가 문단이 된다.
        .alert("링크", isPresented: $showV2LinkDialog) {
            TextField("표시할 텍스트 (선택)", text: $v2LinkLabel)
            TextField("https://…", text: $v2LinkURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Button("추가") { confirmV2Link() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("주소를 붙여넣으세요. YouTube·Vimeo 주소는 발행할 때 동영상으로 재생돼요.")
        }
        // 이미 넣은 이미지의 캡션 고치기 — 이미지 편집 바의 ‘캡션’ 버튼이 연다(막는 알럿 대신 종이 시트).
        .sheet(isPresented: $showEditImageCaption) {
            ImageCaptionSheet(initial: editImageCaptionText) { text in
                confirmEditImageCaption(text)
            }
        }
    }

    // MARK: 메타 영역 — 캔버스엔 제목뿐. 태그·소개글·시리즈·커버는 발행 시트의 일.

    private var meta: some View {
        TextField("제목", text: $title)
            .typeScale(.masthead)
            .focused($focusedField, equals: .title)
            .submitLabel(.next)
            .onSubmit { editorController.focus() }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 16)
            .padding(.bottom, 12)
    }

    /// 본문 캔버스 — 옵트인이면 WriteV2 블록 에디터, 아니면 현행 마크다운 에디터(default).
    @ViewBuilder
    private var editorCanvas: some View {
        if let editorDocument {
            WysiwygComposeCanvas(document: editorDocument, pasteHandlers: v2PasteHandlers)
                // 블록 편집을 저장 계약(마크다운 문자열)으로 흘려보낸다 — 기존 자동저장·서명·발행 파이프
                // 는 이 `markdown` 하나만 본다. 여기가 WriteV2 배선의 유일한 접합점이다.
                .onChange(of: editorDocument.blocks) {
                    markdown = editorDocument.markdown
                }
        } else {
            MarkdownTextView(
                text: $markdown, controller: editorController,
                onFocusChange: { focused in
                    editorFocused = focused
                    if !focused {
                        caretInTable = false
                        caretOnImage = false
                        caretOnVideo = false
                        caretInList = false
                    }
                },
                onContextChange: { ctx in
                    caretInTable = ctx == .table
                    caretOnImage = ctx == .image
                    caretOnVideo = ctx == .video
                    caretInList = ctx == .list
                    caretCanOutdent = editorController.currentLineIndentSpaces() > 0
                    canUndo = editorController.canUndo
                    canRedo = editorController.canRedo
                },
                onPasteImageURL: { url in importPastedImage(url) },
                onPasteImages: { images in uploadPastedImages(images) })
        }
    }

    private var editor: some View {
        editorCanvas
        .padding(.horizontal, Metrics.gutter - 4)
        .overlay(alignment: .topLeading) {
            // 본문 로드 중엔 입력을 권하지 않는다 — '탭해 시작' 대신 로딩을 보인다.
            if bodyLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("본문을 불러오는 중이에요…")
                        .typeScale(.body)
                        .foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 12)
                .allowsHitTesting(false)
            } else if markdown.isEmpty, !loadFailed, editorDocument == nil {
                // 현행 에디터에서만 — WriteV2 캔버스는 빈 블록·삽입 툴바가 스스로 시작을 안내한다(이 힌트 억제).
                // 마크다운 지식을 요구하지 않는다 — 탭하면 도구 막대가 떠서 제목·목록·이미지·표를 넣는다.
                Text("여기를 탭해 시작하세요 — 아래 도구 막대로 제목·사진·목록·표를 넣어요.")
                    .typeScale(.body)
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
        // 잠금은 캔버스(텍스트뷰)에만 — 아래 다시-시도 오버레이는 disabled 서브트리 밖이라 탭이 살아 있다.
        // 본문 로드 중에도 잠근다 — 로드 창에서 친 입력이 서버 본문으로 덮여 유실되는 것 방지.
        .disabled(loadFailed || bodyLoading)
        // 본문 로드 실패 시 — 에디터를 잠그고 다시 시도를 권한다(빈 본문 덮어쓰기 방지).
        .overlay {
            if loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 30 * unit))
                        .foregroundStyle(Palette.secondary)
                    Text("본문을 불러오지 못했어요")
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                    Button("다시 시도") {
                        guard let id = postId else { return }
                        Task { await reloadBody(postId: id) }
                    }
                    .buttonStyle(.bordered)
                    .tint(GlassTokens.prominentTint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.readingBg)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // 저장 상태를 정직하게 — 저장됨(체크)·미저장(점선)·저장 실패(구름!) 를 구분한다.
            // 커버만 올린 걸 "저장됨"으로 속이지 않게(본문 dirty 면 점선).
            if busy {
                ProgressView().controlSize(.small)
            } else if lastSavedAt != nil || saveStatusVisible {
                let dirty = signature != lastSavedSignature
                Button {
                    showSaveStatus = true
                } label: {
                    // 아이콘 + 짧은 텍스트("저장 중…/저장됨") — 점선 스피너 홀로가 아니라 상태를 말로(B5).
                    // "저장 상태 보기" 진입(팝오버)은 그대로. 실패 상태는 라벨 없이 아이콘만(saveStatusLabel=nil).
                    HStack(spacing: 5) {
                        Image(systemName: saveStatusIcon)
                            .font(.system(size: 13 * metaUnit))
                        if let label = saveStatusLabel {
                            Text(label).font(.system(size: 13 * metaUnit, weight: .medium))
                        }
                    }
                    .foregroundStyle(Palette.secondary)
                    // 유리칩이 없으니 라벨이 좁은 슬롯에 갇혀 "저\n…"로 접히지 않게 한 줄로 편다.
                    .lineLimit(1)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("저장 상태 보기"))
                .popover(isPresented: $showSaveStatus) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(saveStatusText(dirty: dirty))
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                        // 세션이 풀린 실패는 재시도가 아니라 로그인이 처방 — 그 자리에서 잇는다.
                        if autosaveNeedsLogin {
                            Button("다시 로그인") {
                                showSaveStatus = false
                                showLoginSheet = true
                            }
                            .font(.system(size: 13 * metaUnit, weight: .semibold))
                            .foregroundStyle(Palette.link)
                        } else if autosavePersistentFailure {
                            // 서버·네트워크 실패는 백오프를 기다리지 않고 지금 한 번 밀어볼 손잡이를 준다.
                            Button("지금 다시 저장") {
                                showSaveStatus = false
                                scheduleAutosave(after: .zero)
                            }
                            .font(.system(size: 13 * metaUnit, weight: .semibold))
                            .foregroundStyle(Palette.link)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        // 상태 배지는 back(<)·⋯ 과 같은 원형 유리칩이 아니라 평문 상태 라벨이어야 한다 —
        // 유리 크롬이 붙으면 "동작 버튼"으로 과약속하고 라벨이 원형에 갇혀 "저…"로 잘린다.
        // 시스템 유리 배경만 걷어내(iOS 26+) 텍스트 버튼 수준으로: 탭→팝오버는 그대로,
        // 프레스 시 .plain 의 옅은 디밍만 남는다. §10.
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .primaryAction) {
            if isPrePublish {
                // 초안은 자동저장이 곧 저장이다(2초 디바운스·이탈 플러시) — 손 저장 버튼을 따로 두면
                // '임시저장'과 '자동저장'이 겹쳐 두 개념처럼 보인다. 손 버튼을 걷고, 좌측 상태 배지
                // (저장됨·미저장·실패)를 초안의 단일 저장 표시로 둔다(웹 /write 와 같은 모델).
                // 발행 = 즉시 쏘지 않는다 — 발행 시트에서 메타데이터를 갖추는 마지막 한 박자.
                Button("발행") { showPublish = true }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(GlassTokens.prominentTint)
                    .disabled(!canSave || busy)
            } else {
                // 발행·비공개 글은 라이브 상태라 명시 저장을 남긴다 — 편집이 독자 앞 글을
                // 자동으로 바꾸지 않게(수정 저장 의미 유지). '글 정보'는 ⋯ 메뉴로.
                Button("저장") { Task { await save(publish: false) } }
                    .disabled(!canSave || busy)
            }
        }
        // ⋯ 는 별도 유리 핀으로 — 저장·발행 묶음과 부가 동작을 물리적으로 분리.
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    openPreview()
                } label: {
                    Label("미리보기", systemImage: "safari")
                }
                .disabled(postId == nil)
                if !isPrePublish {
                    // 발행·비공개 글의 태그·소개글·시리즈·커버 편집(+비공개는 다시 게시) — 같은 시트.
                    Button {
                        showPublish = true
                    } label: {
                        Label(status == "UNPUBLISHED" ? "다시 게시…" : "글 정보…", systemImage: "info.circle")
                    }
                }
                Button {
                    showRevisions = true
                } label: {
                    Label("리비전…", systemImage: "clock.arrow.circlepath")
                }
                .disabled(postId == nil)
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("더 보기")
        }
    }

    /// 발행 준비 — 캔버스에서 걷어낸 메타데이터(태그·소개글·시리즈·커버)가 모이는 자리.
    /// 미발행 글은 [지금 발행]이 주행동, 발행된 글은 같은 시트가 "글 정보" 저장 모드로 선다.
    // 글자 수(공백 제외) + 읽는 시간 ≈ 한글 500자/분. 마크다운 기호가 약간 섞이지만 분량 가늠용.
    private var readStats: String {
        let chars = markdown.filter { !$0.isWhitespace }.count
        let minutes = max(1, Int((Double(chars) / 500.0).rounded()))
        return String(localized: "\(chars)자 · 약 \(minutes)분 읽기")
    }

    private var publishSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // 살아있는 미리보기 — 발행하면 이 카드로 보인다. 커버는 카드 위를 탭해 넣고,
                    // 아래 필드(태그·소개글)를 다듬으면 카드가 그 자리에서 따라 바뀐다.
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("이렇게 보여요")
                        publishPreview
                        // 분량 감각 — 독자가 보는 읽는 시간·글자 수(작성 도구의 기본 피드백).
                        Text(readStats)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    .modifier(QuietAppear(index: 0))

                    sheetField("태그") {
                        TagsField(tags: $tags, draft: $tagDraft)
                    }
                    .modifier(QuietAppear(index: 1))

                    sheetField("소개글") {
                        TextField(
                            "소개글 — 카드와 검색에 보이는 한 단락", text: $excerpt, axis: .vertical
                        )
                        .typeScale(.lede)
                        .lineLimit(2...4)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(
                            Palette.chipBg,
                            in: RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
                    }
                    .modifier(QuietAppear(index: 2))

                    sheetField("시리즈") {
                        Menu {
                            Button("시리즈 없음") { seriesId = nil }
                            ForEach(seriesList) { series in
                                Button(series.title) { seriesId = series.id }
                            }
                            Divider()
                            Button {
                                newSeriesTitle = ""
                                showNewSeries = true
                            } label: {
                                Label("새 시리즈 만들기…", systemImage: "plus")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 12 * metaUnit))
                                Text(
                                    seriesList.first(where: { $0.id == seriesId })?.title
                                        ?? String(localized: "시리즈 없음")
                                )
                                .typeScale(.lede)
                                .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10 * metaUnit))
                            }
                            .foregroundStyle(
                                seriesId == nil
                                    ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.link))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Capsule())
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .modifier(QuietAppear(index: 3))

                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            // 주행동은 detent 높이와 무관하게 항상 보이게 — 시트 하단 고정.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        let willPublish = status != "PUBLISHED"
                        // 발행이면 폼을 유지한다 — 그 위로 성공 모먼트가 뜨고, 끝나면 onDone 이 닫는다.
                        // 글 정보 저장(발행됨)은 모먼트 없이 폼만 닫는다.
                        if !willPublish { showPublish = false }
                        Task { await save(publish: willPublish) }
                    } label: {
                        Text(primaryPublishLabel)
                            .typeScale(.titleSmall)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            // 높이 고정(48)이 큰 글자에서 라벨을 잘랐다 — 패딩 + 최소높이로 캡슐이 따라 자란다.
                            .padding(.vertical, 14)
                            .frame(minHeight: 48)
                            .background(GlassTokens.prominentTint, in: Capsule())
                            // 캡슐 버튼 전수 규칙(#185): 라벨에 contentShape 명시 — 여백부 탭 보장.
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled((status != "PUBLISHED" ? !canPublish : !canSave) || busy)

                    // 비활성엔 이유를 — 흐린 버튼만 보여주고 침묵하지 않는다.
                    if let reason = publishBlockReason {
                        Text(reason)
                            .typeScale(.footnote)
                            .foregroundStyle(Palette.secondary)
                    }

                    HStack(spacing: 18) {
                        // 폼을 닫지 않고 그 위로 — 보고 닫으면 폼으로 돌아온다.
                        Button { openPreview() } label: {
                            Label("전체 미리보기", systemImage: "doc.text.magnifyingglass")
                                .typeScale(.footnote)
                        }
                        .foregroundStyle(Palette.link)
                        .disabled(postId == nil)

                        if isPrePublish {
                            Button("예약 발행…") {
                                // 컴포즈를 오래 열어둬 기본 예약 시각이 지났으면 다시 한 시간 뒤로 클램프.
                                if scheduleDate <= Date() {
                                    scheduleDate = Date().addingTimeInterval(3600)
                                }
                                showSchedule = true
                            }
                                .typeScale(.footnote)
                                .foregroundStyle(Palette.link)
                                .disabled(postId == nil)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // 첫 저장 전(postId 없음)엔 미리보기·예약이 흐리다 — 이유를 한 줄로(침묵하지 않는다).
                    if postId == nil, canSave {
                        Text("저장되면 미리보기·예약할 수 있어요.")
                            .typeScale(.footnote)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .navigationTitle(publishSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { showPublish = false }
                }
            }
            .alert("새 시리즈", isPresented: $showNewSeries) {
                TextField("시리즈 제목", text: $newSeriesTitle)
                    .textInputAutocapitalization(.never)
                Button("만들기") { createNewSeries() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 글이 들어갈 새 시리즈를 만듭니다. 제목은 나중에 시리즈에서 바꿀 수 있어요.")
            }
            // 발행/저장 실패는 폼 자체에 — 루트 알럿은 fullScreenCover 뒤에 가린다.
            .alert(
                "발행하지 못했어요",
                isPresented: .init(
                    get: { publishSheetError != nil }, set: { if !$0 { publishSheetError = nil } })
            ) {
                // 초안은 그대로다 — 폼을 닫아 에디터로 돌려보내 초안이 안전함을 분명히 한다.
                Button("에디터로 돌아가기") {
                    publishSheetError = nil
                    showPublish = false
                }
                Button("확인", role: .cancel) {}
            } message: {
                Text(publishSheetError ?? "")
            }
            // 미리보기·예약은 폼 위에 직접 — 폼을 잃지 않는다. 폼 전용 상태(formPreviewItem)로,
            // 루트의 ⋯ 미리보기와 같은 바인딩을 공유해 두 presenter 가 동시에 뜨던 것을 막는다.
            .sheet(item: $formPreviewItem) { item in
                SafariView(url: item.url).ignoresSafeArea()
            }
            // 초안 네이티브 미리보기 — 발행 폼 위 경로(폼 전용 상태). 발행 폼은 미발행 글에서 열리니
            // 여기 프리뷰는 항상 초안 갈래다.
            .sheet(isPresented: $showFormDraftPreview) {
                DraftPreviewView(title: title, markdown: markdown)
            }
            .sheet(isPresented: $showSchedule) { scheduleSheet }
            // 발행 성공 모먼트 — 폼 위 전체화면 블룸. 끝나면 토스트 남기고 에디터를 닫는다.
            .overlay {
                if celebrating {
                    PublishCelebrationView(
                        title: celebrationIsSchedule ? "예약되었습니다" : "발행되었습니다",
                        announcement: String(
                            localized: celebrationIsSchedule ? "예약되었습니다" : "발행되었습니다"),
                        subtitle: celebrationSubtitle,
                        onView: celebrationIsSchedule ? nil : publishedSlug.map { slug in
                            { showPublish = false; dismiss(); onOpenPublished?(slug) }
                        }
                    ) {
                        // 예약은 모먼트가 사라진 뒤에도 발행 예정 시각을 토스트에 남긴다.
                        let toast =
                            celebrationIsSchedule
                            ? (celebrationSubtitle.map { String(localized: "예약됨 · \($0)") }
                                ?? String(localized: "예약되었습니다"))
                            : String(localized: "발행되었습니다")
                        ToastCenter.shared.show(toast)
                        showPublish = false
                        dismiss()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: celebrating)
        }
    }

    /// 섹션 라벨 — RailHeading 의 작은 인라인 형(그린 마커 + bold).
    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.accentMarker)
                .frame(width: 3, height: 12 * metaUnit)
            Text(text)
                .typeScale(.eyebrow)
                .foregroundStyle(Palette.heading)
        }
    }

    /// 살아있는 카드 미리보기 — 발행 결과를 그대로. 커버 영역 탭 = 사진 선택.
    private var publishPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotosPicker(selection: $coverItem, matching: .images) {
                coverArea
            }
            .buttonStyle(.plain)
            // 업로드가 도는 동안엔 재선택을 막는다 — 안 그러면 두 번째 선택이 조용히 버려진다(스피너로 진행을 보인다).
            .disabled(uploadingCover)
            // 커버가 비었는데 본문에 이미지가 있으면 한 탭 제안 — 웹 발행 다이얼로그의 커버 제안 미러.
            // 안 그러면 "글엔 이미지가 있는데 대표 이미지 자리가 빈 타일"이라는 기대 불일치가 남는다.
            .overlay(alignment: .bottomLeading) {
                if !uploadingCover, coverUrl == nil, let suggestion = suggestedCoverURL {
                    Button {
                        applySuggestedCover(suggestion)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 11 * metaUnit, weight: .semibold))
                            Text("본문 첫 이미지를 커버로")
                                .typeScale(.meta)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let tag = tags.first {
                    HStack(spacing: 5) {
                        Circle().fill(Palette.accentMarker).frame(width: 5, height: 5)
                        Text(tag)
                            .font(.system(size: 12.5 * metaUnit, weight: .semibold))
                            .tracking(0.4)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Palette.link)
                }
                Text(title.trimmingCharacters(in: .whitespaces).isEmpty
                    ? String(localized: "제목을 적어 주세요") : title)
                    .font(.system(size: 20 * unit, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(title.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Palette.faint : Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !excerpt.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let me = AuthStore.shared.me, let username = me.username {
                    HStack(spacing: 7) {
                        AvatarView(
                            author: Author(id: me.id ?? 0, username: username, bio: nil, avatarUrl: me.avatarUrl),
                            size: 20)
                        Text(username)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.ink)
                        Text("· 지금")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
        }
        .cardShadow()
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: coverUrl)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: tags)
        // 커버가 자리잡는 순간 가벼운 햅틱 — 손에 닿는 확인.
        .sensoryFeedback(.impact(weight: .light), trigger: coverUrl)
    }

    /// 본문 첫 이미지 URL — 커버가 빈 발행 카드의 한 탭 제안 재료(웹 coverSuggestion 미러).
    private var suggestedCoverURL: String? {
        Self.firstImageURL(in: markdown)
    }

    /// 마크다운 본문의 첫 `![alt](url)` 의 url. 인라인·단독 무관(카드 커버 후보로는 첫 이미지면 충분).
    private static func firstImageURL(in markdown: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\(([^)\\s]+)"),
              let m = regex.firstMatch(
                in: markdown, range: NSRange(location: 0, length: (markdown as NSString).length))
        else { return nil }
        return (markdown as NSString).substring(with: m.range(at: 1))
    }

    /// 제안 커버 적용 — 카드는 즉시 바뀌고, 서버 반영은 뒤에서(초안이 없으면 만든다).
    private func applySuggestedCover(_ url: String) {
        coverUrl = url
        Task {
            guard let id = try? await ensurePost() else { return }
            try? await WriteAPI.updateCover(postId: id, url: url, key: nil)
            onSaved()
        }
    }

    /// 미리보기 카드의 커버 — 채워졌으면 16:9 이미지(+변경), 없으면 추가 타일. 업로드 중엔 스피너.
    @ViewBuilder
    private var coverArea: some View {
        Group {
            if uploadingCover {
                ZStack {
                    Palette.chipBg
                    ProgressView().controlSize(.small)
                }
            } else if let coverUrl, let url = URL(string: coverUrl) {
                RemoteImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Palette.hairline)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 11 * metaUnit, weight: .semibold))
                        Text("변경")
                            .typeScale(.meta)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(10)
                }
                // 커버가 들어오면 카드가 펼쳐지며 이미지가 살짝 부풀어 자리잡는다.
                .transition(.scale(scale: 1.04).combined(with: .opacity))
            } else {
                ZStack {
                    Palette.chipBg
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 22 * unit, weight: .regular))
                        Text("커버 이미지 추가")
                            .typeScale(.meta)
                    }
                    .foregroundStyle(Palette.secondary)
                }
            }
        }
        // 빈 상태는 컴팩트, 커버가 들어오면 176 으로 펼쳐진다(높이 변화가 곧 언폴드).
        .frame(height: (coverUrl == nil && !uploadingCover) ? 96 : 176)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
    }

    /// 시트 필드 한 단 — 작은 라벨 + 컨트롤.
    private func sheetField(
        _ label: LocalizedStringKey, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .typeScale(.eyebrow)
                .foregroundStyle(Palette.heading)
            content()
        }
    }

    private var scheduleSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // 빠른 선택 — 자주 쓰는 발행 시각을 한 번에. 지난 시각은 숨긴다.
                let presets = schedulePresets
                if !presets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.label) { preset in
                                let active = abs(scheduleDate.timeIntervalSince(preset.date)) < 60
                                Button {
                                    scheduleDate = preset.date
                                } label: {
                                    Text(preset.label)
                                        .typeScale(.meta)
                                        .foregroundStyle(active ? .white : Palette.chipText)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            active ? AnyShapeStyle(Palette.accentFill) : AnyShapeStyle(Palette.chipBg),
                                            in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: scheduleDate)
                }

                DatePicker("발행 시각", selection: $scheduleDate, in: Date().addingTimeInterval(300)...)
                    .datePickerStyle(.graphical)

                // 무엇이 정해졌는지 한 줄로 — 그래프 픽커만으론 결정이 흐릿했다.
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 13 * unit, weight: .semibold))
                    Text(scheduleSummary)
                        .typeScale(.meta)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Palette.link)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))

                Spacer()
            }
            .padding(Metrics.gutter)
            .alert(
                "예약하지 못했습니다",
                isPresented: .init(get: { scheduleError != nil }, set: { if !$0 { scheduleError = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(scheduleError ?? "")
            }
            .navigationTitle("예약 발행")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showSchedule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 예약은 저장→예약 두 왕복이라 잠시 걸린다 — 본 에디터 툴바처럼 스피너로 진행을 보인다.
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("예약") { Task { await scheduleNow() } }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// 자주 쓰는 발행 시각 — 지난 시각은 빼고. 그래프 픽커 전에 한 번에 고르게.
    private var schedulePresets: [(label: String, date: Date)] {
        let cal = Calendar.current
        let now = Date()
        // picker 하한(지금+5분)과 같은 바닥 — 프리셋이 picker 가 거부할 시각을 고르지 못하게.
        let floor = now.addingTimeInterval(300)
        func at(_ base: Date, _ hour: Int) -> Date? {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: base)
        }
        var out: [(String, Date)] = []
        if let d = at(now, 19), d > floor { out.append((String(localized: "오늘 저녁 7시"), d)) }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), let d = at(tomorrow, 9) {
            out.append((String(localized: "내일 아침 9시"), d))
        }
        var sat = DateComponents()
        sat.weekday = 7 // 토요일
        if let next = cal.nextDate(after: now, matching: sat, matchingPolicy: .nextTime),
           let d = at(next, 10) {
            out.append((String(localized: "주말 오전 10시"), d))
        }
        return out
    }

    private var scheduleSummary: String {
        scheduleDate.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute())
    }

    // MARK: 상태

    private var canSave: Bool {
        bodyLoaded
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 기존 글 본문을 아직 읽는 중 — 이 동안 캔버스를 잠근다(이때 친 입력은 서버 본문 도착에 덮인다).
    private var bodyLoading: Bool { existing != nil && !bodyLoaded && !loadFailed }

    /// 발행은 대표 태그(첫 태그) 1개가 필수 — 초안 저장(canSave)과는 분리한다.
    private var canPublish: Bool { canSave && !tags.isEmpty }

    /// 한 번도 공개된 적 없는 글(초안·예약) — '발행 준비/지금 발행/예약' 표면을 띄운다.
    /// PUBLISHED 는 '글 정보' 저장, UNPUBLISHED(웹에서 내린 글)는 '다시 게시'로 다룬다.
    private var isPrePublish: Bool { status == "DRAFT" || status == "SCHEDULED" }

    private var primaryPublishLabel: String {
        isPrePublish
            ? String(localized: "지금 발행")
            : status == "UNPUBLISHED" ? String(localized: "다시 게시") : String(localized: "저장")
    }

    private var publishSheetTitle: String {
        isPrePublish
            ? String(localized: "발행 준비")
            : status == "UNPUBLISHED" ? String(localized: "다시 게시") : String(localized: "글 정보")
    }

    /// 발행 버튼이 흐릴 때의 이유 한 줄 — 침묵하지 않는다.
    private var publishBlockReason: String? {
        if !canSave { return String(localized: "제목과 본문을 채우면 발행할 수 있어요.") }
        if status != "PUBLISHED", tags.isEmpty {
            return String(localized: "대표 태그를 1개 이상 정하면 발행할 수 있어요.")
        }
        return nil
    }

    private var signature: String {
        [title, tags.joined(separator: ","), excerpt, markdown, seriesId.map(String.init) ?? ""]
            .joined(separator: "\u{1F}")
    }

    /// 저장 상태 표시를 띄울 조건 — 저장 이력이 있거나, 실패했거나, 저장할 미저장 변경이 있을 때.
    private var saveStatusVisible: Bool {
        lastSavedAt != nil || autosaveFailed || (canSave && signature != lastSavedSignature)
    }

    /// 인증이 아닌 저장 실패가 거듭되는가(서버 5xx·네트워크 단절) — 자동 재시도만 조용히 도는 대신
    /// 지금 다시 시도할 손잡이를 줄 근거. 첫 실패는 일시적일 수 있어 두 번째부터 격상한다.
    private var autosavePersistentFailure: Bool {
        autosaveFailed && !autosaveNeedsLogin && autosaveRetryStreak >= 2
    }

    private var saveStatusIcon: String {
        if autosavePersistentFailure { return "exclamationmark.triangle" }
        if autosaveFailed { return "exclamationmark.icloud" }
        if signature != lastSavedSignature { return "circle.dotted" }
        return "checkmark.circle"
    }

    /// 내비바 배지의 짧은 라벨(B5) — 점선 스피너 홀로가 아니라 "저장 중…/저장됨" 텍스트로 신뢰를 준다.
    /// 실패류는 아이콘만으로도 눈에 띄니 라벨은 저장/저장중에만(§10 조용함 — 정상 상태를 조용히 말한다).
    private var saveStatusLabel: String? {
        if autosaveFailed { return nil }  // 실패는 아이콘(구름!·삼각)이 말한다 — 라벨로 소란 떨지 않는다.
        if signature != lastSavedSignature { return String(localized: "저장 중…") }
        if lastSavedAt != nil { return String(localized: "저장됨") }
        return nil
    }

    /// 저장 실패가 인증(401·세션 만료) 때문인가 — 배지·토스트가 "다시 로그인"을 말할 근거(플러셔와 공용 판정).
    private static func isAuthFailure(_ error: Error) -> Bool {
        DraftFlusher.isAuthFailure(error)
    }

    /// 태스크 취소로 끝난 저장인가 — URLSession 은 취소를 URLError(.cancelled)로,
    /// APIClient 는 그걸 transport 로 감싼다. 셋 다 "실패"가 아니라 "물러남"이다.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if case APIError.transport(let inner) = error { return isCancellation(inner) }
        return false
    }

    private func saveStatusText(dirty: Bool) -> String {
        if autosaveNeedsLogin { return String(localized: "로그인이 풀렸어요 — 다시 로그인해야 저장돼요") }
        if autosavePersistentFailure { return String(localized: "계속 저장하지 못하고 있어요 — 지금 다시 시도해 보세요") }
        if autosaveFailed { return String(localized: "저장하지 못했어요 — 자동으로 다시 시도해요") }
        if dirty { return String(localized: "미저장 — 곧 저장돼요") }
        if let at = lastSavedAt {
            return String(localized: "저장됨 \(at.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "저장 전")
    }

    private func loadExisting() async {
        guard !loaded else { return }
        loaded = true
        // 시리즈 목록은 발행 시트에서나 쓴다 — 본문 GET 과 독립이라 병렬로(본문 첫 페인트를 안 막게).
        async let series = WriteAPI.mySeries()
        if let post = existing {
            title = post.title
            tags = post.tags ?? []
            excerpt = post.excerpt ?? ""
            savedTitle = title
            savedTags = tags
            savedExcerpt = excerpt
            coverUrl = post.ogImageUrl
            seriesId = post.seriesId
            savedSeriesId = post.seriesId
            postId = post.id
            status = post.status
            await reloadBody(postId: post.id)
        } else {
            // 새 글은 읽을 본문이 없다 — 곧장 편집·저장 가능.
            bodyLoaded = true
            rebuildEditorDocumentIfNeeded()
            offerRecoveryIfAny()
        }
        seriesList = (try? await series) ?? []
    }

    /// 금고에 "서버에 못 실린 변경"이 남아 있으면 복구를 제안한다 — 지난 세션이 저장 실패/강제
    /// 종료로 끝났다는 뜻. 서버 본문과 같으면(이미 실렸으면) 조용히 슬롯만 비운다.
    private func offerRecoveryIfAny() {
        guard let draft = ComposeRecoveryStore.peek(postId: postId) else { return }
        if draft.markdown == markdown, draft.title == title {
            ComposeRecoveryStore.clear(postId: postId)
            return
        }
        pendingRecovery = draft
    }

    /// 리비전 복원 후 — 서버가 본문(과 메타)을 바꿨으므로 화면 상태 전체를 다시 읽어 맞춘다.
    /// 안 그러면 복원 본문 + 복원 전 메타가 섞여 다음 저장에서 덮인다.
    private func syncAfterRestore() async {
        // 메타를 읽어오는 동안 디바운스가 끼어들지 못하게 먼저 취소한다.
        autosaveTask?.cancel()
        // 네트워크 왕복 사이에 사용자가 본문을 더 칠 수 있다 — 진입 시점 본문을 떠 둔다.
        let bodyAtRestore = markdown
        if let postId,
            let post = (try? await WriteAPI.myPosts())?.first(where: { $0.id == postId }) {
            title = post.title
            tags = post.tags ?? []
            excerpt = post.excerpt ?? ""
            savedTitle = title
            savedTags = tags
            savedExcerpt = excerpt
            coverUrl = post.ogImageUrl
            seriesId = post.seriesId
            savedSeriesId = post.seriesId
            status = post.status
        }
        if markdown == bodyAtRestore {
            // 복원 후 본문에 손대지 않았으면 깨끗한 상태로.
            lastSavedSignature = signature
            autosaveFailed = false
        } else {
            // await 사이에 본문을 더 쳤다 — 깨끗하다고 표시하지 않고 그 입력을 저장하도록 디바운스를 무장(유실 방지).
            scheduleAutosave()
        }
        onSaved()
    }

    /// 기존 글 본문을 읽어 에디터에 채운다. 실패하면 loadFailed 로 표시해 에디터를 잠그고
    /// 다시 시도 경로를 연다 — 빈 본문이 첫 저장으로 원본을 덮어쓰지 못하게(데이터 손실 방지).
    private func reloadBody(postId: Int64) async {
        loadFailed = false
        errorMessage = nil
        // 로드 중 캔버스는 잠그지만(bodyLoading) 리비전 복원 등 다른 경로가 본문을 바꿀 수 있다 —
        // 진입 시점 본문을 떠 두고, 왕복 사이 바뀌었으면 서버 본문으로 덮지 않는다(입력 유실 방지).
        let bodyAtEntry = markdown
        do {
            let body = try await WriteAPI.markdown(postId: postId)
            if markdown == bodyAtEntry {
                markdown = body
                lastSavedSignature = signature
                // 서버 본문이 확정된 순간에만 WriteV2 문서를 짓는다 — 로드 중 친 입력으로 덮지 않는다.
                rebuildEditorDocumentIfNeeded()
                offerRecoveryIfAny()
            }
            bodyLoaded = true
        } catch {
            // 전용 잠금·다시시도 오버레이가 사유를 설명하므로 모달 알럿은 띄우지 않는다(이중 알림 방지).
            loadFailed = true
        }
    }

    // MARK: 저장

    /// 기본 2초 = 입력 디바운스. 실패 재시도는 백오프한 간격을 넘겨 온다.
    private func scheduleAutosave(after delay: Duration = .seconds(2)) {
        autosaveTask?.cancel()
        // 서버 자동저장과 별개로 기기 금고에도 눕힌다(0.8초 디바운스) — 서버가 실패하든 앱이
        // 죽든, 마지막 몇 초의 변경까지 기기에 남는다. 제목만 있어도 스태시(canSave 와 무관).
        recoveryStashTask?.cancel()
        let stash = (postId: postId, title: title, markdown: markdown)
        recoveryStashTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            ComposeRecoveryStore.stash(postId: stash.postId, title: stash.title, markdown: stash.markdown)
        }
        guard canSave, signature != lastSavedSignature else { return }
        autosaveTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await save(publish: false, silent: true)
        }
    }

    /// silent = 자동저장(디바운스·이탈) — 실패해도 타이핑 위로 모달을 띄우지 않고 첫 실패에만
    /// 토스트로 알린 뒤 백오프 간격으로 재무장한다. 명시 저장(버튼·발행·예약)은 silent=false 로 모달을 띄운다.
    private func save(publish: Bool, silent: Bool = false) async {
        guard !busy, canSave else { return }
        // 명시 저장·발행이면 아직 +/Enter 안 누른 입력 중 태그도 포함한다(유실 방지).
        if !silent {
            let pending = normalizedTag(tagDraft)
            // 대소문자 무시 중복 검사 — TagsField.commit 과 같은 규칙(중복 태그 방지).
            if !pending.isEmpty,
                !tags.contains(where: { $0.caseInsensitiveCompare(pending) == .orderedSame }) {
                tags.append(pending)
                tagDraft = ""
            }
        }
        guard publish || signature != lastSavedSignature else { return }
        busy = true
        defer { busy = false }
        // 비행 중 타이핑이 "저장된 셈" 되지 않게 — 전송 시점 스냅샷을 기록한다.
        let snapshot = signature
        do {
            let id = try await ensurePost()
            let canonical = try await WriteAPI.replaceMarkdown(postId: id, markdown: markdown)
            // 사용자가 그 사이 더 입력했으면 정규화 본문으로 덮지 않는다(타이핑 손실 방지).
            if markdown == canonical || signature == lastSavedSignature {
                markdown = canonical
            }
            // 바뀐 메타 필드만 PATCH — 본문만 고쳤는데 제목·태그·소개글을 매번 덮어써
            // 다른 기기(웹)의 동시 편집을 지우던 것을 막는다(null=무변경 계약 이용).
            let newTitle = title.trimmingCharacters(in: .whitespaces)
            if newTitle != savedTitle || excerpt != savedExcerpt || tags != savedTags {
                try await WriteAPI.updateMetadata(
                    postId: id,
                    title: newTitle != savedTitle ? newTitle : nil,
                    excerpt: excerpt != savedExcerpt ? excerpt : nil,
                    tags: tags != savedTags ? tags : nil
                )
                savedTitle = newTitle
                savedExcerpt = excerpt
                savedTags = tags
            }
            if seriesId != savedSeriesId {
                try await WriteAPI.assign(postId: id, from: savedSeriesId, to: seriesId)
                savedSeriesId = seriesId
            }
            if publish {
                let published = try await WriteAPI.publish(postId: id)
                status = published.status
                publishedSlug = published.slug
            }
            lastSavedSignature = snapshot
            lastSavedAt = Date()
            autosaveFailed = false
            autosaveNeedsLogin = false
            autosaveRetryStreak = 0
            // 서버에 실렸다 — 금고 슬롯을 비운다(스냅샷 이후 입력은 다음 스태시가 다시 눕힌다).
            recoveryStashTask?.cancel()
            ComposeRecoveryStore.clear(postId: postId)
            onSaved()
            // 스냅샷 이후 입력이 있었으면 디바운스를 다시 무장한다.
            if signature != snapshot { scheduleAutosave() }
            if publish {
                // 이 앱 최대의 순간 — 전체화면 모먼트(그린 블룸 + 햅틱 시퀀스)로 받는다.
                // 토스트·dismiss 는 모먼트가 끝난 뒤 onDone 에서.
                // 키보드가 떠 있으면 축하를 반쯤 가린다(B3) — 접어 전체 화면을 축하가 소유하게 한다.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                editorController.dismissKeyboard()
                editorDocument?.focus = nil
                celebrationIsSchedule = false
                celebrationSubtitle = nil
                celebrating = true
            }
        } catch {
            // 새 입력이 이전 비행을 취소한 것은 실패가 아니다 — scheduleAutosave 가 매 입력마다
            // 이전 태스크를 cancel 하는데, 그 태스크가 이미 네트워크 비행 중이면 여기로 취소가
            // 떨어진다. 더 새 저장이 이미 디바운스에 무장돼 있으므로 조용히 물러난다
            // (타이핑이 빠를수록 "실패했다고 뜨는데 실제론 저장됨"이 잦던 허위 실패의 뿌리).
            if silent, Self.isCancellation(error) { return }
            if silent {
                // 자동저장 실패는 조용히 — 토스트(+VoiceOver 낭독)는 첫 실패에만 한 번.
                // 지속 상태는 saveStatusIcon 배지가 보여주므로 재시도마다 다시 알리지 않는다.
                // 단, 원인은 말한다 — "실패했어요"만 반복하면 로그인 만료도 서버 오류도 구분이 안 돼
                // 사용자가 손쓸 길이 없다(진단 불가의 뿌리). 인증이면 처방(다시 로그인)까지.
                let needsLogin = Self.isAuthFailure(error)
                if !autosaveFailed {
                    ToastCenter.shared.show(needsLogin
                        ? String(localized: "로그인이 풀려 저장하지 못했어요 — 다시 로그인해 주세요")
                        : String(localized: "자동저장에 실패했어요 — \(error.localizedDescription)"))
                }
                autosaveNeedsLogin = needsLogin
                autosaveFailed = true
                // 재시도는 지수 백오프(4초→8초→…→60초 상한) — 오프라인에서 2초 간격 무한 폭주 방지.
                // 새 입력이 오면 onChange 가 기본 2초 디바운스로 다시 앞당긴다.
                autosaveRetryStreak += 1
                let backoff = min(60, 2 << min(autosaveRetryStreak, 5))
                scheduleAutosave(after: .seconds(backoff))
            } else if showPublish, !showSchedule {
                // 발행 폼은 fullScreenCover 라 루트의 에러 알럿이 가려진다 — 폼 자체에 띄운다.
                publishSheetError = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 단일 비행 — 자동저장과 커버 업로드가 동시에 들어와도 초안은 하나만 만든다.
    private func ensurePost() async throws -> Int64 {
        if let postId { return postId }
        if let running = createTask {
            return try await running.value
        }
        let task = Task<Int64, Error> {
            let created = try await WriteAPI.createDraft(
                title: title.trimmingCharacters(in: .whitespaces))
            return created.id
        }
        createTask = task
        defer { createTask = nil }
        let id = try await task.value
        postId = id
        // 새 글이 초안 id 를 얻었다 — 금고의 new 슬롯을 이 id 로 승격(중간에 죽어도 이어지게).
        ComposeRecoveryStore.promote(to: id)
        return id
    }

    // MARK: 부가 동작

    private func openPreview() {
        guard let postId else { return }
        // 초안(미발행)은 네이티브 읽기 미리보기 — 지금 문서(markdown)를 발행 후 모습으로 바로 띄운다.
        // 웹 프리뷰 URL 왕복이 없어 slug·서버 대기 없이 즉시 열린다. 발행된 글만 웹 경로(아래).
        if isPrePublish {
            if showPublish { showFormDraftPreview = true } else { showDraftPreview = true }
            return
        }
        let slug = existing?.slug
        Task {
            // 새 글이면 목록에서 slug 를 다시 찾는다(생성 응답을 보관 안 했을 때 대비).
            let resolved: String
            if let slug {
                resolved = slug
            } else {
                resolved = (try? await WriteAPI.myPosts())?
                    .first(where: { $0.id == postId })?.slug ?? ""
            }
            // slug 미해결이면 깨진 URL(.../p/username/?preview=…)을 열지 않는다 — 잠시 후 재시도.
            guard !resolved.isEmpty else {
                ToastCenter.shared.show(String(localized: "미리보기를 여는 중이에요. 잠시 후 다시 시도해 주세요."))
                return
            }
            // 이미 발행된 글은 공개 블록이 있으니 인앱 리더(PostDetailView)로 네이티브 렌더 —
            // 웹 미리보기 시트로 내보내지 않는다(항목 17). 발행 폼이 떠 있으면 먼저 닫고 항해한다.
            if status == "PUBLISHED", let username = await AuthStore.shared.me?.username,
               !username.isEmpty {
                if showPublish { showPublish = false }
                previewPublished = PublishedRef(username: username, slug: resolved)
                return
            }
            // 발행 전(초안·예약·비공개)은 공개 엔드포인트가 안 줘서 미리보기 토큰 URL 을 인앱 사파리로 연다
            // (외부 사파리로 내쫓지 않는다). 발행 폼이 떠 있으면 폼 전용 presenter 로(바인딩 충돌 방지).
            if let url = try? await WriteAPI.previewURL(slug: resolved, postId: postId) {
                if showPublish {
                    formPreviewItem = PreviewItem(url: url)
                } else {
                    previewItem = PreviewItem(url: url)
                }
            } else {
                // username 미해결 등으로 URL 을 못 만들면 깨진 페이지 대신 안내한다.
                ToastCenter.shared.show(String(localized: "미리보기를 여는 중이에요. 잠시 후 다시 시도해 주세요."))
            }
        }
    }

    private func scheduleNow() async {
        guard let postId, !busy else { return }
        // 예약도 발행이다 — 즉시 발행과 같은 대표 태그 규칙을 강제(둘이 어긋나지 않게).
        guard !tags.isEmpty else {
            scheduleError = String(localized: "대표 태그를 1개 이상 정하면 예약할 수 있어요.")
            return
        }
        // 제출 시점에 다시 검증 — 시트를 오래 열어두면 고른 시각이 이미 지났을 수 있다(picker 의
        // `in: Date()...` 는 렌더 시점만 제약). 저장→예약 2왕복 지연까지 감안해 1분 여유를 둔다.
        guard scheduleDate > Date().addingTimeInterval(60) else {
            scheduleError = String(localized: "발행 시각은 지금부터 조금 뒤여야 해요. 다시 골라 주세요.")
            return
        }
        // 저장이 자체 busy 를 관리하므로 먼저 끝낸다 — busy 선점은 저장 스킵을 만든다.
        await save(publish: false)
        guard signature == lastSavedSignature else {
            scheduleError = errorMessage ?? String(localized: "저장하지 못했습니다")
            // save 실패가 루트 errorMessage 에 남긴 알럿을 소비한다 —
            // 안 그러면 발행 폼을 닫을 때 같은 에러가 루트 알럿으로 한 번 더 뜬다.
            errorMessage = nil
            return
        }
        busy = true
        defer { busy = false }
        do {
            let scheduled = try await WriteAPI.schedule(postId: postId, at: scheduleDate)
            status = scheduled.status
            onSaved()
            // 예약도 발행과 같은 마크 환호로 — 보조줄에 발행 예정 시각, "글 보기"는 없음.
            // 성공 햅틱은 모먼트의 playHaptics() 한 곳에서만 운다(이중 박자 방지).
            celebrationIsSchedule = true
            celebrationSubtitle = String(localized: "\(scheduleSummary) 발행 예정")
            showSchedule = false
            celebrating = true
        } catch {
            // 시트가 떠 있는 동안 본체 알럿은 가려진다 — 시트 안에서 보여준다.
            scheduleError = error.localizedDescription
        }
    }

    private func uploadPickedCover() {
        guard let item = coverItem, !uploadingCover else { return }
        uploadingCover = true
        Task {
            // 같은 사진을 다시 골라 재시도할 수 있게 선택을 비운다(onChange 재발화).
            defer { uploadingCover = false; coverItem = nil }
            do {
                let id = try await ensurePost()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = await Self.encodeUploadJPEG(from: data)
                else { return }
                let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                try await WriteAPI.updateCover(postId: id, url: uploaded.url, key: uploaded.key)
                coverUrl = uploaded.url
                // 커버만 올린 것 — 본문 저장 표시(lastSavedAt)는 건드리지 않는다(거짓 "저장됨" 방지).
                onSaved()
            } catch {
                // 커버 업로드는 타이핑 곁에서 도는 자동 동작 — 실패해도 모달 대신 토스트로.
                ToastCenter.shared.show(String(localized: "커버 이미지를 올리지 못했습니다"))
            }
        }
    }

    // MARK: 새 시리즈

    /// 발행 폼에서 새 시리즈를 만들고 곧장 이 글에 지정한다. slug 는 제목에서 파생.
    private func createNewSeries() {
        let title = newSeriesTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !creatingSeries else { return }
        creatingSeries = true
        Task {
            defer { creatingSeries = false }
            do {
                let slug = makeSeriesSlug(from: title)
                let list = try await WriteAPI.createSeries(slug: slug, title: title)
                seriesList = list
                seriesId = (list.first { $0.slug == slug } ?? list.first { $0.title == title })?.id
                newSeriesTitle = ""
            } catch {
                ToastCenter.shared.show(String(localized: "시리즈를 만들지 못했습니다"))
            }
        }
    }

    /// 제목 → 유저별 유니크 slug. ASCII 영숫자만 남기고(한글은 떨궈) 짧은 토큰을 붙여 충돌 회피.
    private func makeSeriesSlug(from title: String) -> String {
        let mapped = title.lowercased().unicodeScalars.map {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) ? Character($0) : "-"
        }
        var base = String(mapped)
        while base.contains("--") { base = base.replacingOccurrences(of: "--", with: "-") }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.count < 2 { base = "series" }
        let token = String(Int.random(in: 1_000_000...9_999_999), radix: 36)
        return "\(base.prefix(40))-\(token)"
    }

    // MARK: 마크다운 스니펫 삽입 — 커서/선택 기준

    private func applySnippet(_ action: MarkdownSnippetBar.Action) {
        switch action {
        case .heading: editorController.cycleHeading()
        case .quote: editorController.toggleLinePrefix("> ")
        case .list: editorController.toggleLinePrefix("- ")
        case .orderedList: editorController.toggleLinePrefix("1. ")
        case .bold: editorController.wrapSelection("**")
        case .italic: editorController.wrapSelection("*")
        case .strikethrough: editorController.wrapSelection("~~")
        case .inlineCode: editorController.wrapSelection("`")
        case .codeBlock: editorController.toggleCodeBlock()
        case .table: editorController.insertTable()
        case .link: presentLinkDialog()
        case .video: presentVideoDialog()
        case .image: showBodyImagePicker = true  // 폭은 넣은 뒤 이미지 편집 바에서.
        case .divider: editorController.insertDivider()
        }
        // 프로그램 삽입은 delegate 를 거치지 않는다 — 바인딩(자동저장 시그니처) 수동 동기화.
        // 이미지·.link·.video 는 비동기(피커·다이얼로그)라 각자 끝낼 때 동기화한다.
        if action != .image, action != .link, action != .video {
            syncMarkdownFromEditor()
        }
        // 표·이미지를 막 넣었으면 곧장 컨텍스트 바가 뜨도록(델리게이트 콜백을 안 거치므로 수동).
        refreshCaretContext()
    }

    /// 프로그램 삽입·치환 결과를 바인딩으로 동기화 — 단, 한글 조합(IME) 중이면 보류한다
    /// (조합 중간 글자가 바인딩에 새어 자동저장 시그니처가 출렁이지 않게).
    private func syncMarkdownFromEditor() {
        guard !editorController.isComposing else { return }
        markdown = editorController.currentText
    }

    /// 프로그램 삽입/치환 뒤 캐럿 위치의 성격을 다시 읽어 컨텍스트 바를 켜고 끈다.
    private func refreshCaretContext() {
        let ctx = editorController.caretContext()
        caretInTable = ctx == .table
        caretOnImage = ctx == .image
        caretOnVideo = ctx == .video
        caretInList = ctx == .list
        caretCanOutdent = editorController.currentLineIndentSpaces() > 0
        canUndo = editorController.canUndo
        canRedo = editorController.canRedo
    }

    /// 표 편집 바 → 컨트롤러. 행·열을 늘리고 줄인 뒤 바인딩·컨텍스트를 동기화한다.
    private func applyTableAction(_ action: TableActionBar.Action) {
        switch action {
        case .addRow: editorController.addTableRow()
        case .addColumn: editorController.addTableColumn()
        case .deleteRow:
            if editorController.deleteTableRow() { showUndoToast(String(localized: "행을 지웠어요")) }
        case .deleteColumn:
            if editorController.deleteTableColumn() { showUndoToast(String(localized: "열을 지웠어요")) }
        case .alignLeft: editorController.setTableColumnAlign(.left)
        case .alignCenter: editorController.setTableColumnAlign(.center)
        case .alignRight: editorController.setTableColumnAlign(.right)
        }
        syncMarkdownFromEditor()
        refreshCaretContext()
        editorController.focus()
    }

    /// 목록 바 → 컨트롤러. 들여쓰기/내어쓰기(현재 줄 또는 선택)를 한 뒤 바인딩·컨텍스트를 동기화한다.
    private func applyListAction(_ action: ListActionBar.Action) {
        switch action {
        case .indent: editorController.indentLine()
        case .outdent: editorController.outdentLine()
        }
        syncMarkdownFromEditor()
        refreshCaretContext()
        editorController.focus()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()  // 깊이가 바뀐 걸 촉감으로.
    }

    /// 실행취소 — 시스템 undo 스택을 되돌리고 바인딩·컨텍스트·버튼 상태를 동기화한다.
    private func performUndo() {
        if editorController.undoLastEdit() {
            syncMarkdownFromEditor()
            refreshCaretContext()
        }
        editorController.focus()
    }

    /// 다시실행 — 방금 되돌린 편집을 다시 적용한다.
    private func performRedo() {
        if editorController.redoLastEdit() {
            syncMarkdownFromEditor()
            refreshCaretContext()
        }
        editorController.focus()
    }

    /// 삭제처럼 비가역적으로 보이는 동작 뒤 '실행취소' 토스트 — 시스템 undo 로 되돌린다.
    private func showUndoToast(_ message: String) {
        ToastCenter.shared.show(message, actionLabel: String(localized: "실행취소")) {
            if editorController.undoLastEdit() {
                syncMarkdownFromEditor()
                refreshCaretContext()
            }
        }
    }

    /// 이미지 편집 바 → 컨트롤러. 폭·캡션을 바꾸거나 지운다. 캡션은 알럿을 거친다.
    private func applyImageAction(_ action: ImageActionBar.Action) {
        switch action {
        case .standard: editorController.setImageWidth(nil)
        case .wide: editorController.setImageWidth("wide")
        case .half: editorController.setImageWidth("half")
        case .caption:
            editImageCaptionText = editorController.currentImageCaption()
            showEditImageCaption = true
            return  // 알럿 확인에서 동기화한다.
        case .delete:
            if editorController.removeImage() { showUndoToast(String(localized: "이미지를 지웠어요")) }
        }
        syncMarkdownFromEditor()
        refreshCaretContext()
        editorController.focus()
    }

    private func confirmEditImageCaption(_ text: String) {
        editorController.setImageCaption(text)
        syncMarkdownFromEditor()
        refreshCaretContext()
        editorController.focus()
    }

    /// 임베드(동영상) 편집 바 → 컨트롤러. 줄을 지우거나(삭제) 새 주소로 바꾼다(교체).
    private func applyVideoAction(_ action: VideoActionBar.Action) {
        switch action {
        case .replace:
            // 현재 임베드 줄을 지우고 그 자리에 새 주소를 받는다.
            editorController.removeEmbedLine()
            syncMarkdownFromEditor()
            refreshCaretContext()
            presentVideoDialog()
            return
        case .delete:
            if editorController.removeEmbedLine() {
                showUndoToast(String(localized: "동영상을 지웠어요"))
            }
        }
        syncMarkdownFromEditor()
        refreshCaretContext()
        editorController.focus()
    }

    /// 링크 버튼 — 선택을 라벨 후보로 들고, 클립보드에 URL 이 있으면 미리 채워 다이얼로그를 연다.
    /// 어르신도 "주소 붙여넣고 추가"만 하면 되게 — 본문에 `(url)` 가 보이지 않는다.
    private func presentLinkDialog() {
        linkLabel = editorController.beginLinkInsertion()
        if let clip = UIPasteboard.general.string, Self.looksLikeURL(clip) {
            linkURL = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            linkURL = ""
        }
        showLinkDialog = true
    }

    private func confirmLink() {
        editorController.commitLink(label: linkLabel, url: Self.normalizedURL(linkURL))
        syncMarkdownFromEditor()
        editorController.focus() // 키보드·스니펫 바를 다시 불러 흐름이 끊기지 않게.
    }

    /// 동영상 버튼 — 클립보드에 URL 이 있으면 미리 채워 다이얼로그를 연다.
    private func presentVideoDialog() {
        if let clip = UIPasteboard.general.string, Self.looksLikeURL(clip) {
            videoURL = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            videoURL = ""
        }
        showVideoDialog = true
    }

    private func confirmVideo() {
        let url = Self.normalizedURL(videoURL)
        guard !url.isEmpty else { return }
        editorController.insertVideoEmbed(url: url)
        syncMarkdownFromEditor()
        editorController.focus()
    }

    /// 커버가 비어 있으면 방금 본문에 넣은 이미지를 기본 커버로 — 이미지 글이 커버 없이 발행되지
    /// 않게(작성자는 발행 시트에서 언제든 바꾼다). 본문 저장 표시는 건드리지 않는다.
    private func maybeSetCoverFromBodyImage(url: String, key: String?) {
        guard coverUrl == nil, let postId, let key else { return }
        coverUrl = url
        Task {
            do {
                try await WriteAPI.updateCover(postId: postId, url: url, key: key)
                onSaved()
                ToastCenter.shared.show(
                    String(localized: "첫 이미지를 커버로 설정했어요 — 발행 시트에서 바꿀 수 있어요"))
            } catch {
                ToastCenter.shared.show(
                    String(localized: "커버를 저장하지 못했어요 — 발행 시트에서 다시 지정해 주세요"))
            }
        }
    }

    private static func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" "), !t.contains("\n"), t.count <= 2000 else { return false }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return true }
        return t.contains(".")
    }

    /// 스킴이 없으면 https 를 붙인다 — "example.com" 만 적어도 살아있는 링크가 되게.
    private static func normalizedURL(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("mailto:") { return t }
        return "https://\(t)"
    }

    /// 붙여넣은 외부 이미지 URL — 우리 버킷으로 재호스팅(원본 만료·핫링크 차단에도 안 깨지게)한 뒤 본문에
    /// `![](url)` 한 줄로 넣는다. 재호스팅 실패 시 원본 URL 그대로 넣어도 백엔드가 IMAGE 블록으로 렌더한다.
    private func importPastedImage(_ original: String) {
        ToastCenter.shared.show(String(localized: "이미지 가져오는 중…"))
        Task {
            var finalURL = original
            if let id = try? await ensurePost(),
                let hosted = try? await WriteAPI.importImage(postId: id, url: original) {
                finalURL = hosted
            }
            editorController.insertImageMarkdown(url: finalURL)
            syncMarkdownFromEditor()
            editorController.focus()
        }
    }

    /// 클립보드 이미지 붙여넣기 — 스크린샷·노션 등에서 복사한 이미지 바이트를 순서대로 업로드해 커서
    /// 자리에 넣는다. 사진 선택과 달리 여러 장이 한 번에 올 수 있어 캡션 다이얼로그는 생략한다
    /// (캡션은 이미지 컨텍스트 바로 나중에 붙일 수 있다).
    private func uploadPastedImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        guard !uploadingBodyImage else {
            // 앞 이미지가 올라가는 중엔 조용히 버리지 않고 알린다 — 스피너가 사라진 뒤 다시.
            ToastCenter.shared.show(String(localized: "이미지를 올리는 중이에요 — 잠시 후 다시 시도해 주세요"))
            return
        }
        uploadingBodyImage = true
        ToastCenter.shared.show(String(localized: "이미지 올리는 중…"))
        Task {
            defer { uploadingBodyImage = false }
            var failed = 0
            for image in images {
                guard let jpeg = await Self.encodeUploadJPEG(from: image) else {
                    failed += 1
                    continue
                }
                do {
                    let id = try await ensurePost()
                    let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                    editorController.insertImageMarkdown(url: uploaded.url)
                    maybeSetCoverFromBodyImage(url: uploaded.url, key: uploaded.key)
                } catch {
                    failed += 1
                }
            }
            syncMarkdownFromEditor()
            editorController.focus()
            if failed > 0 {
                ToastCenter.shared.show(String(localized: "이미지 \(failed)장을 올리지 못했습니다"))
            }
        }
    }

    /// 본문 이미지 — 골라서 업로드되면 곧장 커서 자리에 `![](url)` 한 줄로 들어간다(막는 캡션 다이얼로그 없이,
    /// 클립보드 붙여넣기 경로와 동일). 캡션은 넣은 뒤 이미지 편집 바의 ‘캡션’으로 붙인다.
    private func uploadBodyImage() {
        guard let item = bodyImageItem else { return }
        guard !uploadingBodyImage else {
            // 앞 이미지가 올라가는 중 — 조용히 버리지 않고 알린 뒤, 같은 사진을 다시 고를 수 있게 선택을 비운다.
            bodyImageItem = nil
            ToastCenter.shared.show(String(localized: "이미지를 올리는 중이에요 — 잠시 후 다시 시도해 주세요"))
            return
        }
        uploadingBodyImage = true
        bodyImageItem = nil
        ToastCenter.shared.show(String(localized: "이미지 올리는 중…"))
        Task {
            defer { uploadingBodyImage = false }
            do {
                let id = try await ensurePost()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = await Self.encodeUploadJPEG(from: data)
                else { return }
                let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                editorController.insertImageMarkdown(url: uploaded.url)
                syncMarkdownFromEditor()
                // 커버가 비어 있으면 이 첫 이미지를 기본 커버로(발행 시트에서 언제든 바꾼다).
                maybeSetCoverFromBodyImage(url: uploaded.url, key: uploaded.key)
                refreshCaretContext()
                editorController.focus()
            } catch {
                ToastCenter.shared.show(String(localized: "이미지를 올리지 못했습니다"))
            }
        }
    }

    // MARK: WriteV2 붙여넣기 훅 — 현행(V1) 캔버스와 같은 계약을 블록 문서에 잇는다

    /// 이미지 바이트 → 업로드 후 IMAGE 블록 / 이미지 URL → 재호스팅 후 IMAGE 블록 /
    /// 일반 URL → 캔버스가 원문을 넣고, 이 훅의 단축 결과로 그 자리를 치환한다.
    private var v2PasteHandlers: EditorPasteHandlers {
        EditorPasteHandlers(
            images: { images in uploadV2PastedImages(images) },
            imageURL: { url in importV2PastedImage(url) },
            shorten: { url in try? await WriteAPI.shorten(url) }
        )
    }

    /// 붙여넣은 외부 이미지 URL — 서버 재호스팅 후 IMAGE 블록으로. 재호스팅이 안 되면(비로그인 등)
    /// 원문 URL 그대로 넣는다 — 조용히 사라지는 것보다 핫링크가 낫다(현행 경로와 같은 판단).
    private func importV2PastedImage(_ original: String) {
        ToastCenter.shared.show(String(localized: "이미지 가져오는 중…"))
        Task {
            var finalURL = original
            if let id = try? await ensurePost(),
               let hosted = try? await WriteAPI.importImage(postId: id, url: original) {
                finalURL = hosted
            }
            editorDocument?.insertNonText(.image(url: finalURL, alt: ""))
            syncFromDocument()
        }
    }

    /// 클립보드 이미지 붙여넣기(V2) — 스크린샷·노션 등에서 복사한 이미지 바이트를 순서대로 업로드해
    /// IMAGE 블록으로 넣는다. 캡션(alt)은 블록의 대체 텍스트 필드에서 나중에 붙인다.
    private func uploadV2PastedImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        guard !uploadingBodyImage else {
            ToastCenter.shared.show(String(localized: "이미지를 올리는 중이에요 — 잠시 후 다시 시도해 주세요"))
            return
        }
        uploadingBodyImage = true
        ToastCenter.shared.show(String(localized: "이미지 올리는 중…"))
        Task {
            defer { uploadingBodyImage = false }
            var failed = 0
            for image in images {
                guard let jpeg = await Self.encodeUploadJPEG(from: image) else {
                    failed += 1
                    continue
                }
                do {
                    let id = try await ensurePost()
                    let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                    editorDocument?.insertNonText(.image(url: uploaded.url, alt: ""))
                    maybeSetCoverFromBodyImage(url: uploaded.url, key: uploaded.key)
                } catch {
                    failed += 1
                }
            }
            syncFromDocument()
            if failed > 0 {
                ToastCenter.shared.show(String(localized: "이미지를 올리지 못했습니다"))
            }
        }
    }

    // MARK: WriteV2 배선 — 블록 문서 ↔ 마크다운 계약

    /// 옵트인일 때, 현재 `markdown` 으로 WriteV2 블록 문서를 (재)생성한다. 문서엔 제자리 교체 API 가
    /// 없어 로드·복원마다 새 인스턴스를 짓는 게 계약(포커스·캐럿은 초기화 — 사용자가 탭해 다시 잡는다).
    /// 플래그 OFF 면 nil 로 두어 현행 MarkdownTextView default 경로를 탄다.
    private func rebuildEditorDocumentIfNeeded() {
        guard Config.wysiwygEditorEnabled else { editorDocument = nil; return }
        editorDocument = EditorDocument(markdown: markdown)
    }

    /// 문서를 직접 변형(삽입 등)한 직후 저장 계약(마크다운 문자열)을 즉시 맞춘다 —
    /// blocks 관찰(onChange)이 다음 런루프에나 돌아 삽입 직후 서명이 뒤처지는 창을 없앤다.
    private func syncFromDocument() {
        guard let editorDocument else { return }
        markdown = editorDocument.markdown
    }

    /// WriteV2 통합 링크 삽입 — 클립보드에 URL 이 있으면 미리 채워 다이얼로그를 연다.
    /// 다이얼로그(알럿)가 뜨면 캔버스 선택이 접히므로, 지금의 포커스(블록·선택)를 잡아둔다.
    private func presentV2LinkSheet() {
        v2LinkTargetFocus = editorDocument?.focus
        v2LinkLabel = ""
        if let clip = UIPasteboard.general.string, Self.looksLikeURL(clip) {
            v2LinkURL = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            v2LinkURL = ""
        }
        showV2LinkDialog = true
    }

    /// 다이얼로그 확인 — 링크/임베드를 넣고 저장 계약을 즉시 맞춘다. 동영상 URL 은 단독 문단(임베드),
    /// 아니면 알럿 열기 전 잡아둔 포커스의 선택을 `[선택](url)` 로 감싼다. 포커스가 없거나(캔버스 미포커스)
    /// 비텍스트 블록이면 문단으로 삽입(폴백) — 링크가 조용히 사라지지 않게.
    private func confirmV2Link() {
        let url = Self.normalizedURL(v2LinkURL)
        guard !url.isEmpty, let editorDocument else { return }
        if WriteV2VideoDetect.isVideoURL(url) {
            editorDocument.insertLink(url: url, label: v2LinkLabel)  // 임베드 문단
        } else if let target = v2LinkTargetFocus,
                  editorDocument.linkSelection(at: target, url: url, label: v2LinkLabel) {
            // 잡아둔 선택을 감쌌다.
        } else {
            editorDocument.insertLink(url: url, label: v2LinkLabel)  // 포커스 없음·비텍스트 → 문단 폴백
        }
        syncFromDocument()
        v2LinkURL = ""
        v2LinkLabel = ""
        v2LinkTargetFocus = nil
    }

    /// WriteV2 캔버스의 사진 삽입 — 실제 업로드 후 IMAGE 블록으로 넣는다(현행 경로와 같은 업로드 계약).
    private func uploadV2BodyImage() {
        guard let item = v2ImageItem else { return }
        guard !uploadingBodyImage else {
            v2ImageItem = nil
            ToastCenter.shared.show(String(localized: "이미지를 올리는 중이에요 — 잠시 후 다시 시도해 주세요"))
            return
        }
        uploadingBodyImage = true
        v2ImageItem = nil
        ToastCenter.shared.show(String(localized: "이미지 올리는 중…"))
        Task {
            defer { uploadingBodyImage = false }
            do {
                let id = try await ensurePost()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = await Self.encodeUploadJPEG(from: data)
                else { return }
                let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                editorDocument?.insertNonText(.image(url: uploaded.url, alt: ""))
                syncFromDocument()
                // 커버가 비어 있으면 이 첫 이미지를 기본 커버로(현행 경로와 동일).
                maybeSetCoverFromBodyImage(url: uploaded.url, key: uploaded.key)
            } catch {
                ToastCenter.shared.show(String(localized: "이미지를 올리지 못했습니다"))
            }
        }
    }

    // MARK: 업로드 JPEG 인코딩 — 메인 액터 밖

    /// 업로드 이미지 최대 변(px) — 원본 화소(12~48MP) 그대로 인코딩·전송하지 않는다.
    private static let uploadImageMaxSide: CGFloat = 2048

    /// 피커 바이트 → 업로드 JPEG. 풀사이즈 디코드·재인코딩은 수백 ms 라 메인 밖에서 돌린다
    /// (타이핑·캐럿 프리즈 방지). ImageIO 썸네일이라 원본 비트맵을 통째로 메모리에 펴지 않는다.
    private static func encodeUploadJPEG(from data: Data) async -> Data? {
        let maxSide = uploadImageMaxSide
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            let sourceOptions = [kCGImageSourceShouldCache: false] as [CFString: Any] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                // EXIF 회전을 픽셀에 구워 넣는다 — 회전 메타를 잃어도 사진이 눕지 않게.
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
            ] as [CFString: Any] as CFDictionary
            guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
            else { return nil }
            return UIImage(cgImage: scaled).jpegData(compressionQuality: 0.88)
        }.value
    }

    /// 클립보드 이미지 → 업로드 JPEG(같은 규칙) — 붙여넣기는 바이트가 아니라 UIImage 로 온다.
    private static func encodeUploadJPEG(from image: UIImage) async -> Data? {
        let maxSide = uploadImageMaxSide
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            let width = image.size.width * image.scale
            let height = image.size.height * image.scale
            let longest = max(width, height)
            guard longest > maxSide else { return image.jpegData(compressionQuality: 0.88) }
            let size = CGSize(
                width: (width * maxSide / longest).rounded(.down),
                height: (height * maxSide / longest).rounded(.down))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return scaled.jpegData(compressionQuality: 0.88)
        }.value
    }
}

/// 키보드 위에 뜨는 유리 마크다운 바 — 에디터의 유일한 유리 크롬.
/// 표준 md 만 — 비표준 문법 버튼은 두지 않는다(웹 에디터와 같은 경계).
/// 좁은 화면에선 스니펫 캡슐이 가로 스크롤되고 터치 타깃 44pt 는 줄이지 않는다.
private struct MarkdownSnippetBar: View {
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void
    let perform: (Action) -> Void
    let dismiss: () -> Void

    /// 아이콘만 키운다 — 44pt 터치 타깃 프레임은 작은 글자 설정에서도 줄이지 않는다.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    // 순서 = 일반 사용자가 자주 쓰는 것 먼저(좁은 화면 가로 스크롤에서 앞쪽이 보임). 표준 md 만(형광펜·콜아웃
    // 같은 비표준은 제외). 이미지는 한 버튼 — 폭(와이드·하프)은 넣은 뒤 이미지 편집 바에서 고른다.
    // 들여쓰기/내어쓰기는 여기서 뺐다 — 목록 줄일 때만 뜨는 전용 바(ListActionBar)로 옮겨 소음을 줄였다.
    enum Action: CaseIterable {
        case heading, bold, italic, list, orderedList, link, image, table, quote,
            video, strikethrough, inlineCode, codeBlock, divider

        var icon: String {
            switch self {
            case .heading: "number"
            case .bold: "bold"
            case .italic: "italic"
            case .list: "list.bullet"
            case .orderedList: "list.number"
            case .link: "link"
            case .image: "photo"
            case .table: "tablecells"
            case .quote: "text.quote"
            case .video: "play.rectangle"
            case .strikethrough: "strikethrough"
            case .inlineCode: "chevron.left.forwardslash.chevron.right"
            case .codeBlock: "curlybraces"
            case .divider: "minus"
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .heading: "제목"
            case .bold: "굵게"
            case .italic: "기울임"
            case .list: "목록"
            case .orderedList: "번호"
            case .link: "링크"
            case .image: "사진"
            case .table: "표"
            case .quote: "인용"
            case .video: "동영상"
            case .strikethrough: "취소선"
            case .inlineCode: "코드"
            case .codeBlock: "코드 블록"
            case .divider: "구분선"
            }
        }
    }

    var body: some View {
        // 도구 캡슐과 키보드 내리기 버튼은 성격이 다른 컨트롤 — clusterSpacing(18) 안에서
        // 액체처럼 녹아 붙어(metaball) 한 덩어리로 보였다. 이 묶음의 융합 거리만 0 으로
        // (닿을 때만 융합) 두고 간격을 벌려 또렷한 두 컨트롤로 분리한다.
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 14) {
                // 실행취소·다시실행 — 고정 리딩(스크롤 안 됨). 가능 여부를 라이브로 비활성 반영한다.
                HStack(spacing: 0) {
                    undoRedoButton("실행취소", icon: "arrow.uturn.backward", enabled: canUndo, action: undo)
                    undoRedoButton("다시실행", icon: "arrow.uturn.forward", enabled: canRedo, action: redo)
                }
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Action.allCases, id: \.self) { action in
                            Button {
                                perform(action)
                            } label: {
                                // 아이콘 + 작은 라벨 — 마크다운을 몰라도 무슨 버튼인지 읽히게(자매 바와 동일 패턴).
                                VStack(spacing: 2) {
                                    Image(systemName: action.icon)
                                        .font(.system(size: 15 * unit, weight: .medium))
                                    Text(action.label)
                                        .font(.system(size: 9.5 * unit, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(.horizontal, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(action.label))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button(action: dismiss) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14 * unit, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("키보드 내리기"))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// 실행취소/다시실행 버튼 — 44pt 터치 타깃. 비활성이면 눌리지 않고 흐려진다(disabled 가 딤 처리).
    private func undoRedoButton(
        _ label: LocalizedStringKey, icon: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15 * unit, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }
}

/// 표 편집 바 — 캐럿이 표 안에 있을 때만 마크다운 바 위에 뜬다. 행·열을 한 번 탭으로 늘리고
/// 줄여, 손으로 `|` 를 칠 일이 없게 한다.
private struct TableActionBar: View {
    let perform: (Action) -> Void

    /// 아이콘·라벨을 함께 키운다(Dynamic Type) — 44pt 터치 타깃 프레임만 그대로 둔다.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    // 추가(행→열) 먼저, 삭제(행→열) 뒤. 라벨의 행/열로 구분하므로 +/− 아이콘만으로 충분하다.
    enum Action: CaseIterable, Identifiable {
        case addRow, addColumn, deleteRow, deleteColumn, alignLeft, alignCenter, alignRight
        var id: Self { self }

        var symbol: String {
            switch self {
            case .addRow, .addColumn: "plus"
            case .deleteRow, .deleteColumn: "minus"
            case .alignLeft: "text.alignleft"
            case .alignCenter: "text.aligncenter"
            case .alignRight: "text.alignright"
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .addRow: "행 추가"
            case .addColumn: "열 추가"
            case .deleteRow: "행 삭제"
            case .deleteColumn: "열 삭제"
            case .alignLeft: "왼쪽 정렬"
            case .alignCenter: "가운데 정렬"
            case .alignRight: "오른쪽 정렬"
            }
        }

        var isDestructive: Bool { self == .deleteRow || self == .deleteColumn }

        // 삭제는 즉시·비가역이라 VoiceOver 가 결과를 알리도록 힌트를 단다(색은 §10 대로 조용히).
        var hint: LocalizedStringKey {
            switch self {
            case .deleteRow: "이 행을 지웁니다"
            case .deleteColumn: "이 열을 지웁니다"
            default: ""
            }
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Action.allCases) { action in
                        Button {
                            perform(action)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: action.symbol)
                                    .font(.system(size: 12 * unit, weight: .bold))
                                Text(action.label)
                                    .typeScale(.meta)
                            }
                            // 유리 위 글자 = 시맨틱 vibrancy(§1.2) — slate 고정색은 유리에서 안 쓴다.
                            .foregroundStyle(action.isDestructive ? .secondary : .primary)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(action.label))
                        .accessibilityHint(Text(action.hint))
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, Metrics.gutter)
    }
}

/// 이미지 편집 바 — 캐럿이 이미지 줄에 있을 때만 뜬다. 폭(기본/와이드/하프)을 한 탭으로 바꾸고,
/// 캡션을 고치고, 지운다. 마크다운(`![…](…)`)은 보이지 않으므로 손댈 일이 없다.
private struct ImageActionBar: View {
    let selectedWidth: String?
    let perform: (Action) -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    enum Action: Identifiable, Hashable {
        case standard, wide, half, caption, delete
        var id: Self { self }
    }

    private var widths: [(action: Action, label: LocalizedStringKey, icon: String, value: String?)] {
        [
            (.standard, "기본", "rectangle.center.inset.filled", nil),
            (.wide, "와이드", "rectangle", "wide"),
            (.half, "하프", "rectangle.split.2x1", "half"),
        ]
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(widths, id: \.action) { item in
                        // full 은 iOS 리더에서 wide 와 같게 그려지므로 와이드 칸으로 활성 표시한다
                        // (웹·리비전에서 들어온 «full» 이미지도 선택 상태가 비지 않게).
                        let active =
                            item.value == selectedWidth
                            || (item.action == .wide && selectedWidth == "full")
                        Button {
                            perform(item.action)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 12 * unit, weight: .semibold))
                                Text(item.label)
                                    .font(.system(size: 13 * unit, weight: active ? .semibold : .medium))
                            }
                            // active = 그린 위계 유리 번역(§1.2 규칙3 = Palette.link), 그 외는 시맨틱.
                            .foregroundStyle(active ? AnyShapeStyle(Palette.link) : AnyShapeStyle(.secondary))
                            .padding(.horizontal, 13)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.label))
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }

                    Divider().frame(height: 22).padding(.horizontal, 4)

                    barButton("캡션", icon: "text.bubble", tint: .primary) { perform(.caption) }
                    barButton(
                        "삭제", icon: "trash", tint: .secondary, hint: "이 이미지를 지웁니다"
                    ) { perform(.delete) }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func barButton(
        _ label: LocalizedStringKey, icon: String, tint: Color, hint: LocalizedStringKey = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12 * unit, weight: .semibold))
                Text(label)
                    .typeScale(.meta)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(hint))
    }
}

/// 임베드(동영상) 편집 바 — 캐럿이 단독 URL 줄에 있을 때만 뜬다. 주소를 바꾸거나 지운다.
private struct VideoActionBar: View {
    let perform: (Action) -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    enum Action: CaseIterable, Identifiable {
        case replace, delete
        var id: Self { self }
        var symbol: String { self == .replace ? "arrow.triangle.2.circlepath" : "trash" }
        var label: LocalizedStringKey { self == .replace ? "주소 바꾸기" : "삭제" }
        var hint: LocalizedStringKey { self == .delete ? "이 동영상을 지웁니다" : "" }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Action.allCases) { action in
                        Button {
                            perform(action)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: action.symbol)
                                    .font(.system(size: 12 * unit, weight: .semibold))
                                Text(action.label)
                                    .typeScale(.meta)
                            }
                            // 유리 위 글자 = 시맨틱 vibrancy(§1.2).
                            .foregroundStyle(action == .delete ? .secondary : .primary)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(action.label))
                        .accessibilityHint(Text(action.hint))
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, Metrics.gutter)
    }
}

/// 목록 들여쓰기 바 — 캐럿이 목록 줄에 있을 때만 마크다운 바 위에 뜬다. 현재 줄(또는 선택)을 2칸씩
/// 들이거나 내어, 손으로 공백을 세지 않게 한다. 내어쓰기는 선행 공백이 있을 때만 활성.
private struct ListActionBar: View {
    let canOutdent: Bool
    let perform: (Action) -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    enum Action: CaseIterable, Identifiable {
        case outdent, indent
        var id: Self { self }
        var symbol: String { self == .indent ? "increase.indent" : "decrease.indent" }
        var label: LocalizedStringKey { self == .indent ? "들여쓰기" : "내어쓰기" }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                barButton(.outdent, enabled: canOutdent)
                barButton(.indent, enabled: true)
            }
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func barButton(_ action: Action, enabled: Bool) -> some View {
        Button {
            perform(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.symbol)
                    .font(.system(size: 12 * unit, weight: .semibold))
                Text(action.label)
                    .typeScale(.meta)
            }
            // 유리 위 글자 = 시맨틱 vibrancy(§1.2) — 비활성은 .tertiary 로 가라앉힌다.
            .foregroundStyle(enabled ? .primary : .tertiary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(action.label))
    }
}

/// 이미지 캡션 편집 — 이미지 편집 바의 ‘캡션’이 여는 종이 시트(막는 알럿 대신). 짧은 높이로 떠서
/// 본문을 잃지 않고, 저장하면 캡션만 바뀐다. 비우면 캡션이 사라진다.
private struct ImageCaptionSheet: View {
    let initial: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var draft = ""
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("이미지 아래에 보일 설명 — 비우면 캡션이 사라져요.")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                TextField("이미지 설명", text: $draft, axis: .vertical)
                    .typeScale(.body)
                    .lineLimit(1...3)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        Palette.chipBg,
                        in: RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
                Spacer(minLength: 0)
            }
            .padding(Metrics.gutter)
            .navigationTitle("캡션")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(draft)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
        .onAppear {
            draft = initial
            focused = true
        }
    }
}

/// 리비전 목록 + 복원 — 복원하면 서버 상태가 바뀌므로 본문을 다시 읽어 에디터에 반영한다.
private struct RevisionsSheet: View {
    let postId: Int64?
    let onRestored: (String) -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    @State private var revisions: [PostRevision] = []
    @State private var loading = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if revisions.isEmpty {
                    ContentUnavailableView("리비전이 없습니다", systemImage: "clock.arrow.circlepath")
                } else {
                    List(revisions) { revision in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("v\(revision.versionNumber) — \(revision.titleSnapshot)")
                                    .typeScale(.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                if let date = revision.createdAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .typeScale(.meta)
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                            Spacer()
                            Button("복원") {
                                restore(revision)
                            }
                            .typeScale(.meta)
                            .foregroundStyle(Palette.link)
                            .disabled(busy)
                        }
                        .listRowSeparatorTint(Palette.hairline)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("리비전")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if let postId {
                revisions = (try? await WriteAPI.revisions(postId: postId)) ?? []
            }
            loading = false
        }
    }

    private func restore(_ revision: PostRevision) {
        guard let postId, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await WriteAPI.restoreRevision(postId: postId, version: revision.versionNumber)
                let restored = try await WriteAPI.markdown(postId: postId)
                onRestored(restored)
                dismiss()
            } catch {
                // 복원 실패 — 시트는 열어두고 버튼만 다시 살리되, 침묵하지 않고 알린다.
                ToastCenter.shared.show(String(localized: "복원하지 못했어요"))
            }
        }
    }
}

/// 태그 정규화 — '#' 제거(태그는 해시태그가 아니라 주제어) + 공백 트림 + 최대 길이 캡
/// (백엔드 PostEntity.MAX_TAG_LENGTH = 40 과 정합). 빈 입력이면 빈 문자열을 돌려준다.
private func normalizedTag(_ raw: String) -> String {
    String(
        raw.replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
            .prefix(40)
    )
}

/// 대표 태그 칩 에디터 — 입력해서 칩으로 쌓고, 첫 칩이 "대표"(카드·글 위 카테고리).
/// 비대표 칩을 탭하면 대표로 끌어올리고, ✕ 로 지운다. 발행은 대표 1개가 필수.
private struct TagsField: View {
    @Binding var tags: [String]
    @Binding var draft: String
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("태그 입력 후 추가 (쉼표로 여러 개)", text: $draft)
                    .typeScale(.lede)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .onChange(of: draft) { _, value in
                        // '#'는 태그에서 못 쓰게 — 입력 즉시 제거(태그는 해시태그가 아니라 주제어).
                        if value.contains("#") { draft = value.replacingOccurrences(of: "#", with: "") }
                        if value.contains(",") { commit() } // 쉼표 입력 즉시 칩으로.
                    }
                Button { commit() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20 * unit))
                        .foregroundStyle(isDraftEmpty ? Palette.faint : Palette.accent)
                }
                .buttonStyle(.plain)
                .disabled(isDraftEmpty)
                .accessibilityLabel(Text("태그 추가"))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))

            if tags.isEmpty {
                Text("첫 번째 태그가 대표 — 카드·글 위에 카테고리로 보입니다. (발행 시 1개 필수)")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                        chip(tag, isPrimary: index == 0)
                    }
                }
                Text("탭하면 대표로 · ✕ 로 삭제")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    private func chip(_ tag: String, isPrimary: Bool) -> some View {
        HStack(spacing: 5) {
            if isPrimary {
                Text("대표")
                    .font(.system(size: 10 * metaUnit, weight: .bold))
                    .opacity(0.9)
            }
            Button {
                promote(tag)
            } label: {
                Text(tag).typeScale(.meta)
            }
            .buttonStyle(.plain)
            .disabled(isPrimary)
            .accessibilityLabel(Text(isPrimary ? "대표 태그 \(tag)" : "\(tag) — 대표로 지정"))

            Button {
                tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9 * metaUnit, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(tag) 삭제"))
        }
        .foregroundStyle(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.chipText))
        .padding(.leading, isPrimary ? 9 : 11)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            isPrimary ? AnyShapeStyle(Palette.accentFill) : AnyShapeStyle(Palette.chipBg),
            in: Capsule())
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commit() {
        let parts = draft
            .split(whereSeparator: { $0 == "," })
            .map { normalizedTag(String($0)) }
            .filter { !$0.isEmpty }
        for part in parts where !tags.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
            tags.append(part)
        }
        draft = ""
    }

    private func promote(_ tag: String) {
        guard let index = tags.firstIndex(of: tag), index != 0 else { return }
        tags.remove(at: index)
        tags.insert(tag, at: 0)
    }
}

/// 칩이 줄을 넘기면 다음 줄로 흐르는 단순 flow 레이아웃(iOS 16+ Layout).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 발행 성공 모먼트 — "조용한 웹로그"의 절제 안에서 허락하는 한 번의 환호.
/// 그린 블룸(컨페티) + 체크 + 햅틱 시퀀스. reduce-motion 이면 정적 체크만 띄운다.
private struct PublishCelebrationView: View {
    /// 발행=「발행되었습니다」, 예약=「예약되었습니다」. 보조줄(예약 시각 등)은 있을 때만.
    var title: LocalizedStringKey = "발행되었습니다"
    /// VoiceOver 로 읽어줄 성공 문구(title 의 해석본) — 오버레이가 타이머로 사라지기 전에 말해진다.
    var announcement: String = String(localized: "발행되었습니다")
    var subtitle: String? = nil
    /// "글 보기" 한 틱 — 있으면 버튼을 띄우고 자동 닫힘을 늦춘다(탭할 시간을 준다).
    var onView: (() -> Void)? = nil
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 19
    @State private var bloom = false
    @State private var marked = false
    /// 발행 순간의 서명 — 브랜드 마크가 스플래시처럼 줄별로 그려진다(체크 대신).
    @State private var barsDrawn = [false, false, false]
    @State private var actionsShown = false
    /// 사용자가 "글 보기"를 눌렀으면 자동 닫힘(onDone)이 뒤늦게 끼어들지 않게.
    @State private var handled = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                // 탭하면 바로 이어간다 — 읽고 있던 작성자를 벽시계가 먼저 닫지 않게(조기 종료도 허용).
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !handled else { return }
                    handled = true
                    onDone()
                }
            if !reduceMotion {
                ConfettiBurst(active: bloom)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Palette.accentFill)
                            .frame(width: 84, height: 84)
                            .shadow(color: Palette.accent.opacity(0.35), radius: 16, y: 6)
                        // 흰 3-bar 마크 — 그린 원판 위에서 줄별로 왼쪽부터 그어진다.
                        KurlMark(drawn: barsDrawn, tint: .white)
                            .frame(width: 40, height: 24)
                    }
                    .scaleEffect(marked ? 1 : 0.4)
                    .opacity(marked ? 1 : 0)
                    VStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: titleSize, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        if let subtitle {
                            Text(subtitle)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .opacity(marked ? 1 : 0)
                }
                // 마크+문구만 한 덩어리로 읽고, "글 보기"는 별도 동작 요소로 남긴다(VoiceOver).
                .accessibilityElement(children: .combine)
                if let onView {
                    Button {
                        guard !handled else { return }
                        handled = true
                        onView()
                    } label: {
                        Text("글 보기")
                            .typeScale(.titleSmall)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Palette.accentFill).interactive(), in: .capsule)
                    .opacity(actionsShown ? 1 : 0)
                    .offset(y: actionsShown ? 0 : 6)
                    .padding(.top, 4)
                    .accessibilityIdentifier("viewPublishedPost")
                }
            }
        }
        .onAppear {
            withAnimation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.6)
            ) { marked = true }
            if reduceMotion {
                barsDrawn = [true, true, true]
            } else {
                withAnimation(.easeOut(duration: 1.0)) { bloom = true }
                // 원판이 솟은 뒤 줄별 스태거 — 스플래시 warp 의 타이밍을 그대로.
                for i in 0..<3 {
                    withAnimation(
                        .timingCurve(0.22, 1, 0.36, 1, duration: 0.26).delay(0.22 + Double(i) * 0.1)
                    ) { barsDrawn[i] = true }
                }
            }
            // 마크가 다 그려진 뒤 "글 보기"가 떠오른다.
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3).delay(0.7)) {
                actionsShown = true
            }
            playHaptics()
            // 오버레이가 타이머로 사라지므로 성공을 음성으로 확실히 알린다(보조줄 있으면 함께).
            let voiceOver = UIAccessibility.isVoiceOverRunning
            let spoken = subtitle.map { "\(announcement). \($0)" } ?? announcement
            AccessibilityNotification.Announcement(spoken).post()
            Task {
                // "글 보기"가 있으면 탭할 시간을 주고(4s), 예약은 발행 예정 시각을 읽을 시간을
                // 줘야 하므로 더 길게(3s). VoiceOver 면 안내가 끝나도록 더 붙잡는다.
                var hold: Double = reduceMotion ? 2.0 : (onView != nil ? 4.0 : 3.0)
                if voiceOver { hold = max(hold, onView != nil ? 6.0 : 4.0) }
                try? await Task.sleep(for: .seconds(hold))
                guard !handled else { return }
                handled = true
                onDone()
            }
        }
    }

    private func playHaptics() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard !reduceMotion else { return }
        Task {
            let impact = UIImpactFeedbackGenerator(style: .light)
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(110))
                impact.impactOccurred(intensity: 0.65)
            }
        }
    }
}

/// 중심에서 터지는 그린 블룸 — active 토글에 맞춰 바깥으로 퍼지며 가라앉고 사라진다.
/// 브랜드 그린 계열 + slate 한 톤으로만(요란한 무지개 ❌).
private struct ConfettiBurst: View {
    let active: Bool
    private let pieces: [Piece]

    init(active: Bool) {
        self.active = active
        self.pieces = (0..<22).map { _ in Piece.random() }
    }

    struct Piece {
        var angle: Double
        var distance: CGFloat
        var fall: CGFloat
        var size: CGFloat
        var spin: Double
        var color: Color

        static func random() -> Piece {
            let palette: [Color] = [Palette.accent, Palette.accentSoft, Palette.accentMarker, Palette.faint]
            return Piece(
                angle: Double.random(in: 0..<(2 * .pi)),
                distance: CGFloat.random(in: 80...190),
                fall: CGFloat.random(in: 40...160),
                size: CGFloat.random(in: 7...13),
                spin: Double.random(in: -220...220),
                color: palette.randomElement() ?? Palette.accent)
        }
    }

    var body: some View {
        ZStack {
            ForEach(pieces.indices, id: \.self) { i in
                let p = pieces[i]
                RoundedRectangle(cornerRadius: 2)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size * 0.55)
                    .rotationEffect(.degrees(active ? p.spin : 0))
                    .offset(
                        x: active ? cos(p.angle) * p.distance : 0,
                        y: active ? sin(p.angle) * p.distance + p.fall : 0)
                    .opacity(active ? 0 : 1)
            }
        }
    }
}

// MARK: - WriteV2 캔버스 래퍼 (플래그 뒤 옵트인)

/// ComposeView 가 소유한 EditorDocument 를 WriteV2 캔버스에 태우는 얇은 어댑터.
/// WysiwygEditorView 는 `@State` 로 문서 인스턴스를 캡처하므로, ComposeView 가 문서를 새 인스턴스로
/// 갈아끼울 때(리비전 복원 등) 옛 인스턴스를 계속 잡지 않게 인스턴스 정체로 `.id` 를 걸어 재생성한다.
private struct WysiwygComposeCanvas: View {
    let document: EditorDocument
    let pasteHandlers: EditorPasteHandlers

    var body: some View {
        WysiwygEditorView(document: document, pasteHandlers: pasteHandlers)
            .id(ObjectIdentifier(document))
    }
}

/// WriteV2 서식 툴바 — 선택 서식(볼드·이탤릭·코드·링크)·블록 서식(제목·인용·코드·리스트)·삽입
/// (구분선·사진·표)을 한 유리 바로. 캔버스는 종이, 이 크롬만 유리(AGENTS §1). 아이콘은 SF Symbols
/// 표준. 블록 서식은 현재 블록 종류면 켜진(초록) 상태로 보여 토글임을 알린다. 좁은 화면을 위해
/// 가로 스크롤(그룹 구분선으로 세 묶음을 시각 분리). "링크" 하나로 동영상/링크 통합(신고 11 유지).
private struct V2FormatToolbar: View {
    /// 현재 포커스 블록의 종류(없으면 nil) — 블록 토글 버튼의 활성 상태를 그린다.
    let focusedKind: EditorBlockKind?
    /// 선택을 마커로 감싸기(볼드=`**`·이탤릭=`*`·인라인코드=`` ` ``).
    let wrapInline: (String) -> Void
    /// 링크 — 선택을 `[선택](url)` 로(다이얼로그로 URL 받음). 동영상 URL 은 임베드.
    let insertLink: () -> Void
    /// 블록 종류 토글(인용·코드·불릿·번호).
    let toggleBlock: (EditorBlockKind) -> Void
    /// 제목 — 버튼 하나가 `#`→`##`→`###`→문단 을 순환한다(누를수록 작아짐).
    let cycleHeading: () -> Void
    let insertDivider: () -> Void
    let insertImage: () -> Void
    let insertTable: () -> Void
    /// 리스트 들여쓰기/내어쓰기 — 캐럿이 리스트 항목일 때만 버튼이 나타난다.
    let indentList: () -> Void
    let outdentList: () -> Void
    /// 키보드 내리기 — 포커스를 놓고 키보드를 접는다(레거시 스니펫 바 대응).
    let dismissKeyboard: () -> Void

    /// 아이콘만 키우고 44pt 터치 타깃은 작은 글자 설정에서도 유지(AGENTS §1 에디터 규율).
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    /// 버튼 탭마다 증가 — 선택 햅틱(.selection) 트리거(B2).
    @State private var hapticTick = 0

    var body: some View {
        // 스크롤 도구 캡슐 + 고정 키보드 내리기 버튼 — 두 성격의 유리를 GlassEffectContainer 로 묶어
        // 겹침(유리 위 유리) 없이 나란히(§1.4). 키보드 버튼은 스크롤에 안 밀려 늘 오른쪽에 선다.
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        // 선택 서식 — 마커로 감싸기.
                        item("bold", "굵게") { wrapInline("**") }
                        item("italic", "기울임") { wrapInline("*") }
                        item("strikethrough", "취소선") { wrapInline("~~") }
                        item("chevron.left.forwardslash.chevron.right", "코드") { wrapInline("`") }
                        item("link", "링크", action: insertLink)

                        groupDivider

                        // 블록 서식 — 종류 토글(현재 종류면 활성).
                        // 제목은 버튼 하나로 # → ## → ### → 본문 순환(제목/소제목 두 버튼의 통합) —
                        // 아이콘 크기가 현재 레벨을 따라 줄어들어 "누르면 작아진다"가 버튼에서 읽힌다.
                        item(headingIcon, "제목", active: isHeadingFocused, action: cycleHeading)
                        item("text.quote", "인용", active: isKind(.quote)) { toggleBlock(.quote) }
                        item("curlybraces", "코드블록", active: isCode) { toggleBlock(.code(language: nil)) }
                        item("list.bullet", "글머리", active: isList(ordered: false)) {
                            toggleBlock(.listItem(ordered: false, indent: 0))
                        }
                        item("list.number", "번호", active: isList(ordered: true)) {
                            toggleBlock(.listItem(ordered: true, indent: 0))
                        }
                        // 캐럿이 리스트 항목일 때만 — 중첩을 여기서(마크다운 선행 공백을 몰라도 된다).
                        if isListFocused {
                            item("increase.indent", "들여쓰기", action: indentList)
                            item("decrease.indent", "내어쓰기", action: outdentList)
                        }

                        groupDivider

                        // 삽입 — 비텍스트 블록.
                        item("minus", "구분선", action: insertDivider)
                        item("photo", "사진", action: insertImage)
                        item("tablecells", "표", action: insertTable)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
                .glassEffect(.regular, in: .capsule)

                // 키보드 내리기 — 고정(스크롤 밖). 별도 유리 원으로(레거시 스니펫 바 대응).
                Button {
                    hapticTick &+= 1
                    dismissKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14 * unit, weight: .semibold))
                        .foregroundStyle(Palette.link)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(ToolbarPressStyle())
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("키보드 내리기"))
            }
        }
        // 선택 햅틱(B2) — 세그먼트·독 토글과 같은 앱 문법. 컨테이너 한 곳에서 모든 버튼 탭을 받는다.
        .sensoryFeedback(.selection, trigger: hapticTick)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 1, height: 26)
            .padding(.horizontal, 4)
    }

    private func item(
        _ icon: String, _ label: LocalizedStringKey, active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        // 탭마다 선택 햅틱(B2) — 세그먼트 전환·독 토글과 같은 앱 문법(.selection). 서식이 손에 닿는다.
        Button {
            hapticTick &+= 1
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17 * unit, weight: .medium))
                Text(label)
                    .font(.system(size: 10 * unit, weight: .medium))
            }
            // 활성(현재 블록 종류) = 초록 채움 배지로 켜짐을 알린다(§ 초록은 상태/데이터 전용).
            .foregroundStyle(active ? Color.white : Palette.link)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: Metrics.radiusMini)
                        .fill(Palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        // 터치다운 즉시 딤+살짝 눌림(B4) — 카드 press(0.975)와 같은 결의 툴바용 프레스 문법.
        .buttonStyle(ToolbarPressStyle())
    }

    // MARK: 활성 판정

    private func isKind(_ kind: EditorBlockKind) -> Bool { focusedKind == kind }
    private var isHeadingFocused: Bool {
        if case .heading = focusedKind { return true }
        return false
    }
    /// 현재 제목 레벨을 아이콘 크기로 비춘다 — 1=크게 · 2=중간 · 3=작게. 문단(비활성)은 다음 탭이
    /// 줄 제목 1 의 아이콘을 미리 보여준다.
    private var headingIcon: String {
        if case .heading(let level) = focusedKind {
            switch level {
            case 1: return "textformat.size.larger"
            case 2: return "textformat.size"
            default: return "textformat.size.smaller"
            }
        }
        return "textformat.size.larger"
    }
    private var isCode: Bool {
        if case .code = focusedKind { return true }
        return false
    }
    private func isList(ordered: Bool) -> Bool {
        if case .listItem(let o, _) = focusedKind { return o == ordered }
        return false
    }
    private var isListFocused: Bool {
        if case .listItem = focusedKind { return true }
        return false
    }
}

/// 툴바 버튼 프레스 상태(B4) — 터치다운 즉시 살짝 눌리고 흐려진다(카드 press 0.975 와 같은 결).
/// 상태 배지·햅틱과 별개로 "눌렀다"를 손보다 먼저 눈에 준다. reduce-motion 이면 스케일만 끈다.
private struct ToolbarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
