//
//  CollectionsListView.swift
//  kurl
//
//  내 컬렉션 목록 — 라이브러리 위의 주제별 채널. 백엔드 `GET /users/me/collections`.
//

import SwiftUI

struct CollectionsListView: View {
    @State private var collections: [CollectionSummary] = []
    @State private var loading = true
    @State private var failed = false
    @State private var showCreate = false
    /// 첫 로드는 .task 한 곳에서만 — .task 와 .onAppear 의 첫 등장 순서는 보장되지 않아
    /// 둘 다 걸면 첫 진입에서 GET 이 두 번 나갈 수 있다. .onAppear 는 재진입 갱신만 맡는다.
    @State private var didLoad = false
    /// 상세로 실제로 벗어났다 돌아온 경우에만 갱신 — 첫 등장의 .onAppear 를 재진입과 구분한다.
    @State private var wentAway = false
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            Text("읽고 생각한 것을 주제로 잇는 곳.")
                .typeScale(.lede)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 4)
                .padding(.bottom, 18)

            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed {
                failedState
            } else if collections.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(collections.enumerated()), id: \.element.id) { index, c in
                        NavigationLink(value: CollectionRef(id: c.id)) {
                            row(c)
                        }
                        .buttonStyle(RowButtonStyle())
                        .modifier(QuietAppear(index: index))
                        if index < collections.count - 1 { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("컬렉션")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
                .tint(.brand)
                .accessibilityLabel(Text("새 컬렉션"))
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateCollectionSheet { created in
                collections.insert(created, at: 0)
            }
        }
        .navigationDestination(for: CollectionRef.self) { CollectionDetailView(collectionId: $0.id) }
        .navigationDestination(for: Route.self) { RouteView(route: $0) }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
        // 상세로 벗어난 걸 표시 — 돌아왔을 때만 조용히 갱신하기 위한 신호.
        .onDisappear { wentAway = true }
        // 상세에서 삭제·수정 후 돌아오면 새로 읽는다(스피너 없이 제자리 갱신).
        // 첫 등장(.task 로드)과 겹치지 않게, 실제로 벗어났다 돌아온 경우에만.
        .onAppear {
            guard wentAway else { return }
            wentAway = false
            Task { await load() }
        }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do {
            collections = try await CollectionsAPI.mine()
            loading = false
        } catch {
            loading = false
            if collections.isEmpty { failed = true }
        }
    }

    private func row(_ c: CollectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.title)
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)

            if let blurb = c.blurb {
                Text(blurb)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !c.preview.isEmpty {
                // 소개가 없으면 안에 든 것으로 — 어디든 "뭐가 들었는지"가 보이게.
                Text(c.preview.joined(separator: " · "))
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 6) {
                Image(systemName: c.visibility.icon)
                    .font(.system(size: 11 * metaUnit, weight: .medium))
                Text(c.visibility.label)
                Text("·").foregroundStyle(Palette.faint)
                Text("\(c.count)개")
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.faint)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("아직 컬렉션이 없어요", systemImage: "square.grid.2x2")
        } description: {
            Text("글을 읽다 마음에 닿는 것을 주제로 이어 보세요.")
        } actions: {
            Button("새 컬렉션 만들기") { showCreate = true }
                .foregroundStyle(Palette.link)
        }
        .padding(.top, 60)
    }

    private var failedState: some View {
        ErrorState(retry: { Task { loading = true; await load() } })
            .padding(.top, 60)
    }
}

/// 새 컬렉션 만들기 — 제목 + 공개 범위. 만들면 목록에 즉시 끼운다.
struct CreateCollectionSheet: View {
    let onCreated: (CollectionSummary) -> Void

    @State private var title = ""
    @State private var visibility: CollectionVisibility = .private
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("새 컬렉션")
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .padding(.top, 26)

            // 회색 채움 박스 대신 밑줄 — 수정 시트(EditCollectionSheet)와 같은 입력 문법(§10).
            VStack(alignment: .leading, spacing: 9) {
                TextField("컬렉션 이름", text: $title)
                    .font(.system(size: 17 * unit))
                    .foregroundStyle(Palette.ink)
                Hairline()
            }
            .padding(.top, 18)

            Picker("공개 범위", selection: $visibility) {
                ForEach([CollectionVisibility.private, .unlisted, .public], id: \.self) { v in
                    Text(v.label).tag(v)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 12)

            Spacer(minLength: 0)

            Button {
                Task { await create() }
            } label: {
                Group {
                    if saving { ProgressView().tint(.white) } else { Text("만들기") }
                }
                .typeScale(.titleSmall)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: true)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, Metrics.gutter)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .background(Palette.readingBg)
    }

    private func create() async {
        saving = true
        defer { saving = false }
        do {
            let created = try await CollectionsAPI.create(
                title: title.trimmingCharacters(in: .whitespaces),
                description: nil, visibility: visibility)
            onCreated(created)
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "컬렉션을 만들지 못했습니다"))
        }
    }
}

/// 컬렉션 수정 — 이름 + 공개 범위. 소개(blurb)는 보존해 함께 보낸다.
/// 길(PATH)이면 제목·플레이스홀더를 "길"로 — 삭제 라벨과 어휘를 맞춘다.
struct EditCollectionSheet: View {
    let id: Int64
    let kind: CollectionKind
    let initialBlurb: String?
    let onSaved: () -> Void

    @State private var title: String
    @State private var visibility: CollectionVisibility
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    init(
        id: Int64, kind: CollectionKind, initialTitle: String, initialBlurb: String?,
        initialVisibility: CollectionVisibility, onSaved: @escaping () -> Void
    ) {
        self.id = id
        self.kind = kind
        self.initialBlurb = initialBlurb
        self.onSaved = onSaved
        _title = State(initialValue: initialTitle)
        _visibility = State(initialValue: initialVisibility)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kind == .path ? "길 수정" : "컬렉션 수정")
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .padding(.top, 26)

            // 회색 채움 박스 대신 밑줄 — 입력이되 박스 없이(§10).
            VStack(alignment: .leading, spacing: 9) {
                TextField(kind == .path ? "길 이름" : "컬렉션 이름", text: $title)
                    .font(.system(size: 17 * unit))
                    .foregroundStyle(Palette.ink)
                Hairline()
            }
            .padding(.top, 18)

            Picker("공개 범위", selection: $visibility) {
                ForEach([CollectionVisibility.private, .unlisted, .public], id: \.self) { v in
                    Text(v.label).tag(v)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 16)

            Spacer(minLength: 0)

            Button {
                Task { await save() }
            } label: {
                Group {
                    if saving { ProgressView().tint(.white) } else { Text("저장") }
                }
                .typeScale(.titleSmall)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: true)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, Metrics.gutter)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .background(Palette.readingBg)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await CollectionsAPI.edit(
                id: id, title: title.trimmingCharacters(in: .whitespaces),
                description: initialBlurb, visibility: visibility)
            onSaved()
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "수정하지 못했습니다"))
        }
    }
}
