//
//  AddNoteToSeriesSheet.swift
//  kurl
//
//  내 노트를 시리즈에 넣는다 — 노트 메뉴에서. 내 시리즈를 고르면 그 끝에 붙고, 다른 시리즈에 있던
//  노트면 옮겨 간다(노트는 한 시리즈에만 든다). 노트만으로 엮는 연재를 위해 여기서 새 시리즈도 만든다.
//

import SwiftUI

struct AddNoteToSeriesSheet: View {
    let noteId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var series: [MySeries] = []
    @State private var loading = true
    @State private var working = false
    @State private var naming = false
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            List {
                if !loading {
                    Button {
                        naming = true
                    } label: {
                        Label("새 시리즈 만들기", systemImage: "plus")
                            .foregroundStyle(Palette.link)
                    }
                    .disabled(working)
                }
                ForEach(series) { item in
                    Button {
                        Task { await add(to: item) }
                    } label: {
                        HStack {
                            Text(item.title)
                                .typeScale(.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text("\(item.episodeCount)편")
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                    .accessibilityIdentifier("series.pick.\(item.id)")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.readingBg)
            .overlay {
                if loading { KurlLoadingMark() }
            }
            .navigationTitle("시리즈에 넣기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
            .alert("새 시리즈", isPresented: $naming) {
                TextField("시리즈 이름", text: $newTitle)
                Button("만들고 넣기") { Task { await createAndAdd() } }
                Button("취소", role: .cancel) { newTitle = "" }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            series = try await WriteAPI.mySeries()
        } catch {
            ToastCenter.shared.show(String(localized: "시리즈를 불러오지 못했습니다"))
        }
        loading = false
    }

    private func add(to item: MySeries) async {
        working = true
        defer { working = false }
        do {
            try await WriteAPI.addNote(noteId, toSeries: item.id)
            ToastCenter.shared.show(String(localized: "‘\(item.title)’에 넣었어요"))
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "시리즈에 넣지 못했습니다"))
        }
    }

    private func createAndAdd() async {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        newTitle = ""
        guard !title.isEmpty else { return }
        working = true
        defer { working = false }
        do {
            let slug = WriteAPI.seriesSlug(from: title)
            let list = try await WriteAPI.createSeries(slug: slug, title: title)
            series = list
            guard let created = list.first(where: { $0.slug == slug }) else { return }
            try await WriteAPI.addNote(noteId, toSeries: created.id)
            ToastCenter.shared.show(String(localized: "‘\(created.title)’에 넣었어요"))
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "시리즈에 넣지 못했습니다"))
        }
    }
}
