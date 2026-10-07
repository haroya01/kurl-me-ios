//
//  NoteListsView.swift
//  kurl
//

import SwiftUI

struct NoteListsSheet: View {
    private var store = NoteListsStore.shared
    @State private var newTitle = ""
    @State private var renaming: NoteListSummary?
    @State private var renameTitle = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.lists.isEmpty {
                        Text("아직 리스트가 없어요. 아래에서 만들어 보세요.")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                    ForEach(store.lists) { list in
                        NavigationLink(value: list) {
                            HStack {
                                Text(list.title)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(list.memberCount)명")
                                    .foregroundStyle(Palette.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { try? await store.delete(list) }
                            } label: {
                                Label("지우기", systemImage: "trash")
                            }
                            Button {
                                renameTitle = list.title
                                renaming = list
                            } label: {
                                Label("이름 바꾸기", systemImage: "pencil")
                            }
                        }
                        .accessibilityIdentifier("noteList.row.\(list.id)")
                    }
                } footer: {
                    Text("리스트는 나만 봐요. 담은 사람의 노트만 모아 노트 탭 메뉴에서 볼 수 있어요.")
                }
                Section("새 리스트") {
                    HStack {
                        TextField("리스트 이름", text: $newTitle)
                            .submitLabel(.done)
                            .onSubmit { Task { await create() } }
                            .accessibilityIdentifier("noteList.newTitle")
                        Button("만들기") { Task { await create() } }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("noteList.create")
                    }
                }
            }
            .navigationTitle("리스트")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: NoteListSummary.self) { list in
                NoteListMembersView(list: list)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .alert("리스트 이름 바꾸기", isPresented: Binding(
                get: { renaming != nil }, set: { if !$0 { renaming = nil } }
            )) {
                TextField("리스트 이름", text: $renameTitle)
                Button("바꾸기") {
                    if let list = renaming {
                        Task { try? await store.rename(list, to: renameTitle) }
                    }
                }
                Button("취소", role: .cancel) {}
            }
            .task { await store.reload() }
        }
    }

    private func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            try await store.create(title)
            newTitle = ""
        } catch {
            ToastCenter.shared.show(String(localized: "리스트를 만들지 못했어요"))
        }
    }
}

struct NoteListMembersView: View {
    let list: NoteListSummary
    @State private var members: [Author]?

    var body: some View {
        List {
            if let members {
                if members.isEmpty {
                    Text("담은 사람이 없어요. 프로필의 … 메뉴에서 \"리스트에 추가\"를 눌러 보세요.")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        AvatarView(author: member, size: 32)
                        Text(member.username)
                            .foregroundStyle(Palette.ink)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await remove(member) }
                        } label: {
                            Label("빼기", systemImage: "person.badge.minus")
                        }
                    }
                }
            } else {
                KurlLoadingMark().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { members = (try? await NoteAPI.listMembers(id: list.id)) ?? [] }
    }

    private func remove(_ member: Author) async {
        do {
            try await NoteAPI.setListMember(id: list.id, username: member.username, on: false)
            members?.removeAll { $0.id == member.id }
            NoteListsStore.shared.memberCountChanged(list.id, by: -1)
        } catch {
            ToastCenter.shared.show(String(localized: "리스트에서 빼지 못했어요"))
        }
    }
}

struct NoteListMembershipSheet: View {
    let username: String
    private var store = NoteListsStore.shared
    @State private var inLists: Set<Int64>?
    @State private var newTitle = ""
    @Environment(\.dismiss) private var dismiss

    init(username: String) {
        self.username = username
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.lists) { list in
                        Button {
                            Task { await toggle(list) }
                        } label: {
                            HStack {
                                Text(list.title)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if inLists?.contains(list.id) == true {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .disabled(inLists == nil)
                        .accessibilityAddTraits(inLists?.contains(list.id) == true ? .isSelected : [])
                        .accessibilityIdentifier("noteList.membership.\(list.id)")
                    }
                } footer: {
                    Text("리스트는 나만 봐요. \(username)님에게 알리지 않아요.")
                }
                Section("새 리스트") {
                    HStack {
                        TextField("리스트 이름", text: $newTitle)
                            .submitLabel(.done)
                            .onSubmit { Task { await createAndAdd() } }
                            .accessibilityIdentifier("noteList.membership.newTitle")
                        Button("만들고 담기") { Task { await createAndAdd() } }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("noteList.membership.create")
                    }
                }
            }
            .navigationTitle("리스트에 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .task {
                await store.reload()
                inLists = Set((try? await NoteAPI.listMemberships(username: username))?.listIds ?? [])
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ list: NoteListSummary) async {
        let on = inLists?.contains(list.id) != true
        do {
            try await NoteAPI.setListMember(id: list.id, username: username, on: on)
            if on { inLists?.insert(list.id) } else { inLists?.remove(list.id) }
            store.memberCountChanged(list.id, by: on ? 1 : -1)
        } catch {
            ToastCenter.shared.show(String(localized: "리스트를 바꾸지 못했어요"))
        }
    }

    private func createAndAdd() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            let created = try await store.create(title)
            newTitle = ""
            await toggle(created)
        } catch {
            ToastCenter.shared.show(String(localized: "리스트를 만들지 못했어요"))
        }
    }
}
