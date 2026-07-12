//
//  AbuseReport.swift
//  kurl
//

import SwiftUI

/// 신고 사유 — 백엔드는 `reasonCode`(enum) + `detail`(자유서술) 두 필드로 받는다(#611).
/// 표시 라벨(`text`)은 로케일별로 번역해 사용자에게 보이고, 서버로는 `code`(enum)만 보낸다 —
/// 검토 큐는 코드로 분류하고 자유서술 detail 로 맥락을 읽는다.
enum ReportReason: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case violence
    case sexual
    case copyright
    case other

    var id: String { rawValue }

    /// 백엔드 enum 값 — SPAM·HARASSMENT·VIOLENCE·SEXUAL·COPYRIGHT·OTHER.
    var code: String { rawValue.uppercased() }

    /// 사용자에게 보이는 라벨 — xcstrings 로 번역된다(서버 전송값이 아니다).
    var text: String {
        switch self {
        case .spam: return "스팸·광고"
        case .harassment: return "혐오·괴롭힘"
        case .violence: return "폭력·위험"
        case .sexual: return "성적인 콘텐츠"
        case .copyright: return "저작권 침해"
        case .other: return "기타"
        }
    }
}

extension View {
    /// 차단 확인 — 작가 프로필·글·댓글 어디서나 같은 문법(차단 = 그 사용자 콘텐츠 숨김).
    /// 파괴적 동작이라 한 번 되묻는다. 알럿(중앙 모달)이라 세로·가로·iPad 어디서나 같은 자리에
    /// 뜬다 — confirmationDialog 가 부리 팝오버로 바뀌어 트리거와 무관한 화면 중앙에 붕 뜨던 자리.
    /// BlockStore 가 낙관적으로 숨긴 뒤 토스트로 알린다.
    func blockDialog(isPresented: Binding<Bool>, username: String, userId: Int64) -> some View {
        alert("\(username) 님을 차단할까요?", isPresented: isPresented) {
            Button("차단", role: .destructive) {
                Task {
                    do {
                        try await BlockStore.shared.block(id: userId, username: username)
                        ToastCenter.shared.show(
                            String(localized: "차단했어요 — 이 사용자의 글·댓글이 숨겨집니다"))
                    } catch {
                        ToastCenter.shared.show(String(localized: "차단하지 못했어요"))
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("차단하면 이 사용자의 글·댓글·노트가 더는 보이지 않습니다.")
        }
    }

    /// 신고 사유 선택 — 글/작가/댓글 어디서나 같은 문법. 사유가 여럿인 폼이라 정식 시트로 띄운다
    /// (confirmationDialog 은 화면 중앙 팝오버로 깨지고, 알럿엔 목록이 안 들어간다). 접수되면 토스트로 알린다.
    /// 익명도 가능(서버 permitAll). subjectType = "POST" | "USER" | "COMMENT".
    func reportDialog(isPresented: Binding<Bool>, subjectType: String, subjectId: Int64) -> some View {
        sheet(isPresented: isPresented) {
            ReportReasonSheet(subjectType: subjectType, subjectId: subjectId)
        }
    }
}

/// 신고 사유 시트 — 종이 문법의 사유 행 + 콘텐츠 높이 detent(LoginSheet 와 같은 결).
/// 하이브리드: 코드 사유(스팸·혐오 등)는 한 번 눌러 바로 접수하고, "기타"만 고르면 그 자리에서
/// 자유서술(detail) 입력이 펼쳐진다 — 검토자가 맥락을 읽게. 서버로는 `reasonCode`(enum) +
/// `detail` 로 보낸다(#611). 취소는 드래그·바깥 탭(시트 표준).
struct ReportReasonSheet: View {
    let subjectType: String
    let subjectId: Int64

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @State private var contentHeight: CGFloat = 420
    /// false 면 사유 목록, "기타"를 고르면 true 로 자유서술 입력이 펼쳐진다(하이브리드).
    @State private var expandedOther = false
    @State private var detail = ""
    @FocusState private var detailFocused: Bool

    private static let detailLimit = 500

    private var noun: String {
        switch subjectType {
        case "USER": return String(localized: "이 작가를")
        case "COMMENT": return String(localized: "이 댓글을")
        default: return String(localized: "이 글을")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("신고 사유를 선택하세요")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("\(noun) 신고합니다. 검토 후 조치됩니다.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 6)
                .padding(.bottom, 12)

            if expandedOther {
                otherDetailForm
            } else {
                reasonList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .animation(.snappy(duration: 0.25), value: expandedOther)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    // 사유 목록 — 코드 사유는 즉시 접수, "기타"는 자유서술 입력으로 펼친다.
    private var reasonList: some View {
        ForEach(Array(ReportReason.allCases.enumerated()), id: \.element.id) { index, reason in
            Button {
                if reason == .other {
                    expandedOther = true
                    detailFocused = true
                } else {
                    send(reasonCode: reason.code, detail: nil)
                }
            } label: {
                Text(LocalizedStringKey(reason.text))
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            if index < ReportReason.allCases.count - 1 { Hairline() }
        }
    }

    // "기타" 자유서술 — 종이 문법 입력 상자 + 그린 유리 캡슐 제출(§1.3). 뒤로 돌아가면 목록.
    private var otherDetailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                expandedOther = false
                detailFocused = false
            } label: {
                Label("사유 다시 고르기", systemImage: "chevron.left")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.link)
            }
            .buttonStyle(.plain)

            TextField(
                "어떤 점이 문제인지 알려주세요 (선택)", text: $detail, axis: .vertical
            )
            .font(.system(size: 16 * unit))
            .foregroundStyle(Palette.ink)
            .lineLimit(3...7)
            .focused($detailFocused)
            .padding(14)
            .background(
                Palette.chipBg,
                in: RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
            .onChange(of: detail) { _, new in
                if new.count > Self.detailLimit {
                    detail = String(new.prefix(Self.detailLimit))
                }
            }

            HStack(spacing: 0) {
                Text("\(detail.count)/\(Self.detailLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 12)
                Button {
                    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    send(reasonCode: ReportReason.other.code, detail: trimmed.isEmpty ? nil : trimmed)
                } label: {
                    Text("신고 보내기")
                        .typeScale(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                }
                .glassCapsule(prominent: true)
            }
        }
    }

    private func send(reasonCode: String, detail: String?) {
        dismiss()
        Task {
            do {
                try await InteractionsAPI.report(
                    subjectType: subjectType, subjectId: subjectId,
                    reasonCode: reasonCode, detail: detail)
                ToastCenter.shared.show(String(localized: "신고가 접수되었습니다"))
            } catch {
                ToastCenter.shared.show(String(localized: "신고를 보내지 못했습니다"))
            }
        }
    }
}
