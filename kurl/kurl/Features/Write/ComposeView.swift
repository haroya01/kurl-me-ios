//
//  ComposeView.swift
//  kurl
//

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
    /// 이미 넣은 이미지의 캡션을 고치는 알럿.
    @State private var showEditImageCaption = false
    @State private var editImageCaptionText = ""

    @State private var title = ""
    @State private var tags: [String] = []
    @State private var tagDraft = ""
    @State private var excerpt = ""
    @State private var markdown = ""
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
    @State private var lastSavedSignature: String?
    @State private var lastSavedAt: Date?
    @State private var showSaveStatus = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var createTask: Task<Int64, Error>?

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

    // 본문 이미지 — 스니펫 바의 사진 버튼이 연다. 업로드 후 커서 자리에 마크다운 삽입.
    @State private var showBodyImagePicker = false
    @State private var bodyImageItem: PhotosPickerItem?
    @State private var uploadingBodyImage = false
    @State private var pendingImageWidth: String?
    @State private var pendingImageURL: String?
    @State private var showImageCaption = false
    @State private var imageCaptionText = ""

    // 시트
    @State private var showPublish = false
    @State private var previewItem: PreviewItem?

    struct PreviewItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
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
            if editorFocused {
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
                    MarkdownSnippetBar(perform: applySnippet) { editorController.dismissKeyboard() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: editorFocused)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: caretInTable)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: caretOnImage)
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
        .onDisappear {
            // 디바운스 창에 걸린 마지막 변경을 버리지 않는다 — 즉시 1회 저장(자동저장이므로 조용히).
            autosaveTask?.cancel()
            if canSave, signature != lastSavedSignature {
                Task { await save(publish: false, silent: true) }
            }
        }
        // 발행 준비 = 살아있는 카드 미리보기 폼(전체 화면). 미리보기·예약은 이 폼 위에
        // 바로 떠서 폼을 잃지 않는다(닫았다 다시 여는 왕복을 없앴다).
        .fullScreenCover(isPresented: $showPublish) { publishSheet }
        // ⋯ 메뉴의 미리보기(폼 밖) 경로.
        .sheet(item: $previewItem) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showRevisions) {
            RevisionsSheet(postId: postId) { restored in
                markdown = restored
                lastSavedSignature = signature
            }
        }
        .alert(
            "저장하지 못했습니다",
            isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        // 링크 추가 — 주소만 받아 본문에 `[라벨](주소)` 로. 본문에 `(url)` 가 보이지 않는다.
        .alert("링크 추가", isPresented: $showLinkDialog) {
            TextField("https://example.com", text: $linkURL)
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
        // 이미지 캡션(선택) — 업로드 직후. 비워두면 캡션 없이 삽입.
        .alert("캡션 (선택)", isPresented: $showImageCaption) {
            TextField("이미지 설명", text: $imageCaptionText)
            Button("추가") { confirmImageInsert() }
            Button("건너뛰기", role: .cancel) { confirmImageInsert() }
        } message: {
            Text("이미지 아래에 보일 설명 — 비워도 됩니다.")
        }
        // 이미 넣은 이미지의 캡션 고치기 — 이미지 편집 바의 ‘캡션’ 버튼이 연다.
        .alert("캡션", isPresented: $showEditImageCaption) {
            TextField("이미지 설명", text: $editImageCaptionText)
            Button("저장") { confirmEditImageCaption() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이미지 아래에 보일 설명 — 비우면 캡션이 사라집니다.")
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

    private var editor: some View {
        MarkdownTextView(
            text: $markdown, controller: editorController,
            onFocusChange: { focused in
                editorFocused = focused
                if !focused {
                    caretInTable = false
                    caretOnImage = false
                }
            },
            onContextChange: { ctx in
                caretInTable = ctx == .table
                caretOnImage = ctx == .image
            })
        .padding(.horizontal, Metrics.gutter - 4)
        .overlay(alignment: .topLeading) {
            if markdown.isEmpty {
                Text("마크다운으로 쓰세요 — #, >, -, ```, 이미지·URL 한 줄이면 카드가 됩니다.")
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // 저장 상태는 평소엔 조용한 체크 아이콘 하나 — 탭하면 마지막 저장 시각을 팝오버로.
            // (항상 떠 있던 "저장됨 오후 X:XX" 텍스트가 중요도에 비해 과했다.)
            if busy {
                ProgressView().controlSize(.small)
            } else if let at = lastSavedAt {
                Button {
                    showSaveStatus = true
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15 * metaUnit))
                        .foregroundStyle(Palette.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("저장 상태 보기"))
                .popover(isPresented: $showSaveStatus) {
                    Text("저장됨 \(at.formatted(date: .omitted, time: .shortened))")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("저장") { Task { await save(publish: false) } }
                .disabled(!canSave || busy)
            if status != "PUBLISHED" {
                // 발행 = 즉시 쏘지 않는다 — 발행 시트에서 메타데이터를 갖추는 마지막 한 박자.
                Button("발행") { showPublish = true }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.glassProminent)
                    .tint(GlassTokens.prominentTint)
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
                if status == "PUBLISHED" {
                    // 발행된 글의 태그·소개글·시리즈·커버 편집 — 같은 시트, 저장 모드.
                    Button {
                        showPublish = true
                    } label: {
                        Label("글 정보…", systemImage: "info.circle")
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
        return "\(chars)자 · 약 \(minutes)분 읽기"
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
                            .font(.system(size: 12.5 * metaUnit))
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
                        .font(.system(size: 14 * unit))
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
                                .font(.system(size: 14 * unit, weight: .medium))
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
                        Text(status != "PUBLISHED" ? "지금 발행" : "저장")
                            .font(.system(size: 15 * unit, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(GlassTokens.prominentTint, in: Capsule())
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
                                .font(.system(size: 13 * unit))
                        }
                        .foregroundStyle(Palette.link)
                        .disabled(postId == nil)

                        if status != "PUBLISHED" {
                            Button("예약 발행…") { showSchedule = true }
                                .font(.system(size: 13 * unit))
                                .foregroundStyle(Palette.link)
                                .disabled(postId == nil)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .navigationTitle(status != "PUBLISHED" ? "발행 준비" : "글 정보")
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
            // 미리보기·예약은 폼 위에 직접 — 폼을 잃지 않는다.
            .sheet(item: $previewItem) { item in
                SafariView(url: item.url).ignoresSafeArea()
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
                        ToastCenter.shared.show(
                            String(localized: celebrationIsSchedule ? "예약되었습니다" : "발행되었습니다"))
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
            .padding(16)
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
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Palette.hairline)
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 11 * metaUnit, weight: .semibold))
                        Text("변경")
                            .font(.system(size: 12 * metaUnit, weight: .medium))
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
                                        .font(.system(size: 13 * unit, weight: .medium))
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

                DatePicker("발행 시각", selection: $scheduleDate, in: Date()...)
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
        func at(_ base: Date, _ hour: Int) -> Date? {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: base)
        }
        var out: [(String, Date)] = []
        if let d = at(now, 19), d > now { out.append(("오늘 저녁 7시", d)) }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), let d = at(tomorrow, 9) {
            out.append(("내일 아침 9시", d))
        }
        var sat = DateComponents()
        sat.weekday = 7 // 토요일
        if let next = cal.nextDate(after: now, matching: sat, matchingPolicy: .nextTime),
           let d = at(next, 10) {
            out.append(("주말 오전 10시", d))
        }
        return out
    }

    private var scheduleSummary: String {
        scheduleDate.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute())
    }

    // MARK: 상태

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 발행은 대표 태그(첫 태그) 1개가 필수 — 초안 저장(canSave)과는 분리한다.
    private var canPublish: Bool { canSave && !tags.isEmpty }

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

    private func loadExisting() async {
        guard !loaded else { return }
        loaded = true
        seriesList = (try? await WriteAPI.mySeries()) ?? []
        guard let post = existing else { return }
        title = post.title
        tags = post.tags ?? []
        excerpt = post.excerpt ?? ""
        coverUrl = post.ogImageUrl
        seriesId = post.seriesId
        savedSeriesId = post.seriesId
        postId = post.id
        status = post.status
        do {
            markdown = try await WriteAPI.markdown(postId: post.id)
            lastSavedSignature = signature
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 저장

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard canSave, signature != lastSavedSignature else { return }
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await save(publish: false, silent: true)
        }
    }

    /// silent = 자동저장(디바운스·이탈) — 실패해도 타이핑 위로 모달을 띄우지 않고 토스트로만
    /// 알리고 디바운스를 재무장한다. 명시 저장(버튼·발행·예약)은 silent=false 로 모달을 띄운다.
    private func save(publish: Bool, silent: Bool = false) async {
        guard !busy, canSave else { return }
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
            try await WriteAPI.updateMetadata(
                postId: id,
                title: title.trimmingCharacters(in: .whitespaces),
                excerpt: excerpt,
                tags: tags
            )
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
            onSaved()
            // 스냅샷 이후 입력이 있었으면 디바운스를 다시 무장한다.
            if signature != snapshot { scheduleAutosave() }
            if publish {
                // 이 앱 최대의 순간 — 전체화면 모먼트(그린 블룸 + 햅틱 시퀀스)로 받는다.
                // 토스트·dismiss 는 모먼트가 끝난 뒤 onDone 에서.
                celebrationIsSchedule = false
                celebrationSubtitle = nil
                celebrating = true
            }
        } catch {
            if silent {
                // 자동저장 실패는 조용히 — 토스트만 남기고 다음 변경 때 다시 무장한다.
                ToastCenter.shared.show(String(localized: "자동저장에 실패했어요"))
                scheduleAutosave()
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
        return id
    }

    // MARK: 부가 동작

    private func openPreview() {
        guard let postId else { return }
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
                ToastCenter.shared.show(String(localized: "미리보기를 준비 중이에요. 잠시 후 다시 시도해 주세요."))
                return
            }
            if let url = try? await WriteAPI.previewURL(slug: resolved, postId: postId) {
                // 외부 사파리로 내쫓지 않는다 — 발행 전 확인은 인앱 시트로.
                previewItem = PreviewItem(url: url)
            }
        }
    }

    private func scheduleNow() async {
        guard let postId, !busy else { return }
        // 저장이 자체 busy 를 관리하므로 먼저 끝낸다 — busy 선점은 저장 스킵을 만든다.
        await save(publish: false)
        guard signature == lastSavedSignature else {
            scheduleError = errorMessage ?? String(localized: "저장하지 못했습니다")
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
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.88)
                else { return }
                let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                try await WriteAPI.updateCover(postId: id, url: uploaded.url, key: uploaded.key)
                coverUrl = uploaded.url
                lastSavedAt = Date()
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
        case .heading: editorController.applyLinePrefix("# ")
        case .quote: editorController.applyLinePrefix("> ")
        case .list: editorController.applyLinePrefix("- ")
        case .orderedList: editorController.applyLinePrefix("1. ")
        case .bold: editorController.wrapSelection("**")
        case .italic: editorController.wrapSelection("*")
        case .strikethrough: editorController.wrapSelection("~~")
        case .inlineCode: editorController.wrapSelection("`")
        case .codeBlock: editorController.toggleCodeBlock()
        case .table: editorController.insertTable()
        case .indent: editorController.indentLine()
        case .outdent: editorController.outdentLine()
        case .link: presentLinkDialog()
        case .video: presentVideoDialog()
        case .image: pendingImageWidth = nil; showBodyImagePicker = true
        case .imageWide: pendingImageWidth = "wide"; showBodyImagePicker = true
        case .imageHalf: pendingImageWidth = "half"; showBodyImagePicker = true
        }
        // 프로그램 삽입은 delegate 를 거치지 않는다 — 바인딩(자동저장 시그니처) 수동 동기화.
        // 이미지·.link·.video 는 비동기(피커·다이얼로그)라 각자 끝낼 때 동기화한다.
        if action != .image, action != .imageWide, action != .imageHalf, action != .link,
            action != .video {
            markdown = editorController.currentText
        }
        // 표·이미지를 막 넣었으면 곧장 컨텍스트 바가 뜨도록(델리게이트 콜백을 안 거치므로 수동).
        refreshCaretContext()
    }

    /// 프로그램 삽입/치환 뒤 캐럿 위치의 성격을 다시 읽어 컨텍스트 바를 켜고 끈다.
    private func refreshCaretContext() {
        let ctx = editorController.caretContext()
        caretInTable = ctx == .table
        caretOnImage = ctx == .image
    }

    /// 표 편집 바 → 컨트롤러. 행·열을 늘리고 줄인 뒤 바인딩·컨텍스트를 동기화한다.
    private func applyTableAction(_ action: TableActionBar.Action) {
        switch action {
        case .addRow: editorController.addTableRow()
        case .addColumn: editorController.addTableColumn()
        case .deleteRow: editorController.deleteTableRow()
        case .deleteColumn: editorController.deleteTableColumn()
        }
        markdown = editorController.currentText
        refreshCaretContext()
        editorController.focus()
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
        case .delete: editorController.removeImage()
        }
        markdown = editorController.currentText
        refreshCaretContext()
        editorController.focus()
    }

    private func confirmEditImageCaption() {
        editorController.setImageCaption(editImageCaptionText)
        markdown = editorController.currentText
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
        markdown = editorController.currentText
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
        markdown = editorController.currentText
        editorController.focus()
    }

    /// 업로드된 이미지를 폭(pendingImageWidth)·캡션(선택)과 함께 삽입. 캡션 비우면 캡션 없이.
    private func confirmImageInsert() {
        guard let url = pendingImageURL else { return }
        let caption = imageCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        editorController.insertImage(
            url: url, width: pendingImageWidth, caption: caption.isEmpty ? nil : caption)
        markdown = editorController.currentText
        pendingImageURL = nil
        pendingImageWidth = nil
        editorController.focus()
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

    /// 본문 이미지 — 골라서 업로드되면 커서 자리에 `![](url)` 한 줄로 들어간다.
    private func uploadBodyImage() {
        guard let item = bodyImageItem, !uploadingBodyImage else { return }
        uploadingBodyImage = true
        bodyImageItem = nil
        ToastCenter.shared.show(String(localized: "이미지 올리는 중…"))
        Task {
            defer { uploadingBodyImage = false }
            do {
                let id = try await ensurePost()
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.88)
                else { return }
                let uploaded = try await WriteAPI.uploadImage(postId: id, jpegData: jpeg)
                // 업로드 완료 → 캡션(선택) 다이얼로그를 띄우고, 확인 시 폭·캡션과 함께 삽입.
                pendingImageURL = uploaded.url
                imageCaptionText = ""
                showImageCaption = true
                // 커버가 비어 있으면 본문 첫 이미지를 기본 커버로 — 이미지 있는 글이
                // 커버 없이 발행되지 않게(작성자는 발행 폼에서 언제든 바꿀 수 있다).
                if coverUrl == nil {
                    coverUrl = uploaded.url
                    try? await WriteAPI.updateCover(postId: id, url: uploaded.url, key: uploaded.key)
                    lastSavedAt = Date()
                    onSaved()
                }
            } catch {
                ToastCenter.shared.show(String(localized: "이미지를 올리지 못했습니다"))
            }
        }
    }
}

/// 키보드 위에 뜨는 유리 마크다운 바 — 에디터의 유일한 유리 크롬.
/// 표준 md 만 — 비표준 문법 버튼은 두지 않는다(웹 에디터와 같은 경계).
/// 좁은 화면에선 스니펫 캡슐이 가로 스크롤되고 터치 타깃 44pt 는 줄이지 않는다.
private struct MarkdownSnippetBar: View {
    let perform: (Action) -> Void
    let dismiss: () -> Void

    /// 아이콘만 키운다 — 44pt 터치 타깃 프레임은 작은 글자 설정에서도 줄이지 않는다.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    // 순서 = 자주 쓰는 것 먼저(좁은 화면 가로 스크롤에서 앞쪽이 보임) — 이미지가 맨 끝이라 화면 밖으로
    // 잘려 안 보이던 발견성 문제를 고친다. 표준 md 만(형광펜·콜아웃 같은 비표준은 여전히 제외).
    enum Action: CaseIterable {
        case heading, bold, italic, list, orderedList, indent, outdent, link, image, imageWide,
            imageHalf, video, table, quote, inlineCode, codeBlock, strikethrough

        var icon: String {
            switch self {
            case .heading: "number"
            case .bold: "bold"
            case .italic: "italic"
            case .list: "list.bullet"
            case .orderedList: "list.number"
            case .indent: "increase.indent"
            case .outdent: "decrease.indent"
            case .link: "link"
            case .image: "photo"
            case .imageWide: "rectangle"
            case .imageHalf: "rectangle.split.2x1"
            case .video: "play.rectangle"
            case .table: "tablecells"
            case .quote: "text.quote"
            case .inlineCode: "chevron.left.forwardslash.chevron.right"
            case .codeBlock: "curlybraces"
            case .strikethrough: "strikethrough"
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .heading: "제목"
            case .bold: "굵게"
            case .italic: "기울임"
            case .list: "글머리 목록"
            case .orderedList: "번호 목록"
            case .indent: "들여쓰기"
            case .outdent: "내어쓰기"
            case .link: "링크"
            case .image: "이미지"
            case .imageWide: "와이드 이미지"
            case .imageHalf: "이미지(하프)"
            case .video: "동영상"
            case .table: "표"
            case .quote: "인용"
            case .inlineCode: "인라인 코드"
            case .codeBlock: "코드 블록"
            case .strikethrough: "취소선"
            }
        }
    }

    var body: some View {
        // 도구 캡슐과 키보드 내리기 버튼은 성격이 다른 컨트롤 — clusterSpacing(18) 안에서
        // 액체처럼 녹아 붙어(metaball) 한 덩어리로 보였다. 이 묶음의 융합 거리만 0 으로
        // (닿을 때만 융합) 두고 간격을 벌려 또렷한 두 컨트롤로 분리한다.
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Action.allCases, id: \.self) { action in
                            Button {
                                perform(action)
                            } label: {
                                Image(systemName: action.icon)
                                    .font(.system(size: 15 * unit, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, height: 44)
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
}

/// 표 편집 바 — 캐럿이 표 안에 있을 때만 마크다운 바 위에 뜬다. 행·열을 한 번 탭으로 늘리고
/// 줄여, 손으로 `|` 를 칠 일이 없게 한다.
private struct TableActionBar: View {
    let perform: (Action) -> Void

    /// 아이콘만 키운다 — 44pt 터치 타깃은 작은 글자 설정에서도 줄이지 않는다.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    // 추가(행→열) 먼저, 삭제(행→열) 뒤. 라벨의 행/열로 구분하므로 +/− 아이콘만으로 충분하다.
    enum Action: CaseIterable, Identifiable {
        case addRow, addColumn, deleteRow, deleteColumn
        var id: Self { self }

        var symbol: String {
            switch self {
            case .addRow, .addColumn: "plus"
            case .deleteRow, .deleteColumn: "minus"
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .addRow: "행 추가"
            case .addColumn: "열 추가"
            case .deleteRow: "행 삭제"
            case .deleteColumn: "열 삭제"
            }
        }

        var isDestructive: Bool { self == .deleteRow || self == .deleteColumn }
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
                                    .font(.system(size: 13 * unit, weight: .medium))
                            }
                            .foregroundStyle(action.isDestructive ? Palette.secondary : Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
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
                        let active = item.value == selectedWidth
                        Button {
                            perform(item.action)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 12 * unit, weight: .semibold))
                                Text(item.label)
                                    .font(.system(size: 13 * unit, weight: active ? .semibold : .medium))
                            }
                            .foregroundStyle(active ? Palette.link : Palette.secondary)
                            .padding(.horizontal, 13)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.label))
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }

                    Divider().frame(height: 22).padding(.horizontal, 4)

                    barButton("캡션", icon: "text.bubble", tint: Palette.ink) { perform(.caption) }
                    barButton("삭제", icon: "trash", tint: Palette.secondary) { perform(.delete) }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func barButton(
        _ label: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12 * unit, weight: .semibold))
                Text(label)
                    .font(.system(size: 13 * unit, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
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
                                    .font(.system(size: 15 * unit, weight: .medium))
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
                            .font(.system(size: 13 * unit, weight: .medium))
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
                // 복원 실패 — 시트는 열어두고 버튼만 다시 살린다.
            }
        }
    }
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
                    .font(.system(size: 14 * unit))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .onChange(of: draft) { _, value in
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
                Text(tag).font(.system(size: 13 * unit, weight: .medium))
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
            .map { $0.trimmingCharacters(in: .whitespaces) }
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
                            .font(.system(size: 19, weight: .bold))
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
                            .font(.system(size: 15, weight: .semibold))
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
                // "글 보기"가 있으면 탭할 시간을 주고(4s), 없으면 짧게 닫는다.
                // VoiceOver 면 안내가 끝나도록 더 붙잡는다 — 사라지기 전에 다 읽히게.
                var hold: Double = reduceMotion ? 1.2 : (onView != nil ? 4.0 : 1.7)
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
