//
//  ScheduledNotesView.swift
//  kurl
//

import SwiftUI

@MainActor
@Observable
final class ScheduledNotesStore {
    static let shared = ScheduledNotesStore()

    private(set) var items: [ScheduledNote] = []
    private(set) var loaded = false
    private(set) var failed = false

    private init() {}

    func reload() async {
        failed = false
        do {
            items = try await NoteAPI.scheduled()
        } catch {
            failed = true
        }
        loaded = true
    }

    func added(_ note: ScheduledNote) {
        items = (items + [note]).sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func cancel(_ note: ScheduledNote) async {
        do {
            try await NoteAPI.cancelScheduled(id: note.id)
            items.removeAll { $0.id == note.id }
            ToastCenter.shared.show(String(localized: "예약을 취소했어요"))
        } catch {
            ToastCenter.shared.show(String(localized: "예약을 바꾸지 못했어요"))
        }
    }

    func move(_ note: ScheduledNote, to date: Date) async {
        do {
            let moved = try await NoteAPI.reschedule(id: note.id, at: date)
            var next = items.filter { $0.id != moved.id }
            next.append(moved)
            next.sort { $0.scheduledAt < $1.scheduledAt }
            items = next
            ToastCenter.shared.show(String(localized: "올릴 시각을 바꿨어요"))
        } catch {
            ToastCenter.shared.show(NoteScheduleText.failure(error))
        }
    }
}

enum NoteScheduleText {
    /// 마스토돈처럼 최소 5분 뒤 — 고르는 동안 시간이 흘러도 서버 검사에 걸리지 않게 30초 여유를 둔다.
    static var earliest: Date { Date().addingTimeInterval(5 * 60 + 30) }

    static func failure(_ error: Error) -> String {
        if case let APIError.server(_, code, _) = error {
            switch code {
            case "NOTE_SCHEDULE_TOO_SOON": return String(localized: "5분 뒤부터 예약할 수 있어요")
            case "NOTE_SCHEDULE_LIMIT": return String(localized: "예약할 수 있는 노트 수를 넘었어요")
            default: break
            }
        }
        return String(localized: "예약을 바꾸지 못했어요")
    }

    static func reason(_ code: String) -> LocalizedStringKey {
        switch code {
        case "NOTE_NOT_FOUND": return "답글을 달 노트가 지워졌어요"
        case "NOTE_QUOTED_NOTE_NOT_FOUND", "NOTE_QUOTE_NOT_FOUND": return "인용할 글이 지워졌어요"
        case "NOTE_REPLY_BLOCKED": return "답글을 달 수 없는 노트예요"
        case "NOTE_IMAGE_INVALID": return "사진을 찾지 못했어요"
        default: return "올리지 못했어요"
        }
    }
}

/// 올릴 시각 고르기 — 작성기와 예약 목록이 같이 쓴다.
struct NoteScheduleSheet: View {
    let initial: Date?
    let onPick: (Date?) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(initial: Date?, onPick: @escaping (Date?) -> Void) {
        self.initial = initial
        self.onPick = onPick
        let start = initial ?? Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        _date = State(initialValue: max(start, NoteScheduleText.earliest))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "올릴 때",
                    selection: $date,
                    in: NoteScheduleText.earliest...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .accessibilityIdentifier("noteSchedule.picker")
                if initial != nil {
                    Section {
                        Button("예약 해제", role: .destructive) {
                            onPick(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("예약")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        onPick(max(date, NoteScheduleText.earliest))
                        dismiss()
                    }
                    .accessibilityIdentifier("noteSchedule.done")
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// 설정 > 노트의 "예약한 노트" — 올릴 차례를 기다리는 노트와 올리지 못한 노트.
struct ScheduledNotesView: View {
    @State private var store = ScheduledNotesStore.shared
    @State private var moving: ScheduledNote?

    var body: some View {
        Group {
            if !store.loaded {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.failed && store.items.isEmpty {
                ErrorState(
                    message: String(localized: "연결을 확인하고 다시 시도해 주세요."),
                    retry: { Task { await store.reload() } })
            } else {
                List {
                    ForEach(store.items) { note in
                        Button {
                            moving = note
                        } label: {
                            row(note)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scheduled.row.\(note.id)")
                        .swipeActions(edge: .trailing) {
                            Button("취소", role: .destructive) {
                                Task { await store.cancel(note) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if store.items.isEmpty {
                        ContentUnavailableView {
                            Label("예약한 노트가 없어요", systemImage: "clock")
                        } description: {
                            Text("노트를 쓸 때 아래의 \"예약\"으로 올릴 시각을 정할 수 있어요.")
                        }
                    }
                }
            }
        }
        .navigationTitle("예약한 노트")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $moving) { note in
            NoteScheduleSheet(initial: note.scheduledAt) { picked in
                if let picked {
                    Task { await store.move(note, to: picked) }
                } else {
                    Task { await store.cancel(note) }
                }
            }
        }
        .task { await store.reload() }
    }

    private func row(_ note: ScheduledNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: note.failure == nil ? "clock" : "exclamationmark.circle")
                    .foregroundStyle(note.failure == nil ? Palette.secondary : Palette.danger)
                Text(note.scheduledAt, format: .dateTime.month().day().weekday().hour().minute())
                    .typeScale(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(note.failure == nil ? Palette.ink : Palette.danger)
            }
            if let warning = note.contentWarning, !warning.isEmpty {
                Text(verbatim: warning)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
            }
            if let body = note.body, !body.isEmpty {
                Text(verbatim: body)
                    .typeScale(.note)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
            }
            HStack(spacing: 10) {
                if note.imageCount > 0 {
                    Label("사진 \(note.imageCount)장", systemImage: "photo")
                }
                if note.poll {
                    Label("투표", systemImage: "chart.bar.xaxis")
                }
                if note.inReplyToId != nil {
                    Label("답글", systemImage: "arrowshape.turn.up.left")
                }
                if note.quotedNoteId != nil || note.quotedPostId != nil {
                    Label("인용", systemImage: "quote.bubble")
                }
            }
            .labelStyle(.titleAndIcon)
            .typeScale(.footnote)
            .foregroundStyle(Palette.secondary)
            if let failure = note.failure {
                Text(NoteScheduleText.reason(failure))
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
