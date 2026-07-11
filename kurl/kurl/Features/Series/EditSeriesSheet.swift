//
//  EditSeriesSheet.swift
//  kurl
//
//  시리즈 수정 — 이름과 주소(slug). 수정 시트(EditCollectionSheet)와 같은 입력 문법(밑줄 · 유리 캡슐).
//  시리즈엔 소개·공개범위 필드가 없다(웹도 동일) — 두 가지만 다룬다. PATCH 라 바뀐 것만 보낸다.
//

import SwiftUI

struct EditSeriesSheet: View {
    let seriesId: Int64
    let initialTitle: String
    let initialSlug: String
    /// 저장 성공 시 갱신된 (제목, slug) 을 돌려준다 — 상세가 재로드 없이 마스트헤드를 즉시 고친다.
    let onSaved: (String, String) -> Void

    @State private var title: String
    @State private var slug: String
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    init(
        seriesId: Int64, initialTitle: String, initialSlug: String,
        onSaved: @escaping (String, String) -> Void
    ) {
        self.seriesId = seriesId
        self.initialTitle = initialTitle
        self.initialSlug = initialSlug
        self.onSaved = onSaved
        _title = State(initialValue: initialTitle)
        _slug = State(initialValue: initialSlug)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var trimmedSlug: String { slug.trimmingCharacters(in: .whitespaces) }

    /// 주소 규칙 — 소문자·숫자·하이픈(연속·양끝 하이픈 금지), 2~200자. 서버 규칙과 같게 눌러 저장 전에 막는다.
    private var slugValid: Bool {
        let s = trimmedSlug
        guard (2...200).contains(s.count) else { return false }
        return s.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil
    }

    private var canSave: Bool { !trimmedTitle.isEmpty && slugValid && !saving }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("시리즈 수정")
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .padding(.top, 26)

            // 회색 채움 박스 대신 밑줄 — 수정 시트(EditCollectionSheet)와 같은 입력 문법(§10).
            VStack(alignment: .leading, spacing: 9) {
                TextField("시리즈 이름", text: $title)
                    .font(.system(size: 17 * unit))
                    .foregroundStyle(Palette.ink)
                Hairline()
            }
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 6) {
                Text("주소")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.faint)
                HStack(spacing: 8) {
                    Text(verbatim: "kurl.me/…/")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                    TextField("series-slug", text: $slug)
                        .font(.system(size: 15 * unit).monospaced())
                        .foregroundStyle(Palette.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Hairline()
            }
            .padding(.top, 22)

            Spacer(minLength: 0)

            Button {
                Task { await save() }
            } label: {
                Group {
                    if saving { ProgressView().tint(.white) } else { Text("저장") }
                }
                .font(.system(size: 16 * unit, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassCapsule(prominent: true)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, Metrics.gutter)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .background(Palette.readingBg)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        // PATCH — 바뀐 것만 보낸다(null 은 서버가 무시). 둘 다 그대로면 호출 없이 닫는다.
        let newTitle = trimmedTitle != initialTitle ? trimmedTitle : nil
        let newSlug = trimmedSlug != initialSlug ? trimmedSlug : nil
        guard newTitle != nil || newSlug != nil else {
            dismiss()
            return
        }
        do {
            let savedTitle = try await WriteAPI.updateSeries(
                id: seriesId, title: newTitle, slug: newSlug)
            onSaved(savedTitle, trimmedSlug)
            dismiss()
        } catch let error as APIError {
            // 주소 충돌은 흔한 실패라 따로 안내 — 나머지는 일반 메시지.
            if case .http(let status) = error, status == 409 {
                ToastCenter.shared.show(String(localized: "이미 쓰고 있는 주소예요"))
            } else {
                ToastCenter.shared.show(String(localized: "수정하지 못했습니다"))
            }
        } catch {
            ToastCenter.shared.show(String(localized: "수정하지 못했습니다"))
        }
    }
}
