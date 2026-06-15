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
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            Text("읽고 생각한 것을 주제로 잇는 곳.")
                .font(.system(size: 14 * metaUnit))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 4)
                .padding(.bottom, 18)

            if loading {
                ProgressView().tint(Palette.accent)
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
        .task { await load() }
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
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: c.visibility.icon)
                    .font(.system(size: 11 * metaUnit, weight: .medium))
                Text(c.visibility.label)
                Text("·").foregroundStyle(Palette.faint)
                Text("\(c.count)개")
            }
            .font(.system(size: 12 * metaUnit, weight: .medium))
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
                .foregroundStyle(Palette.accent)
        }
        .padding(.top, 60)
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } actions: {
            Button("다시 시도") { Task { loading = true; await load() } }
                .foregroundStyle(Palette.accent)
        }
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

            TextField("컬렉션 이름", text: $title)
                .font(.system(size: 16 * unit))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 16)

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
                .font(.system(size: 16 * unit, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassCapsule(prominent: true)
            }
            .buttonStyle(.plain)
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
