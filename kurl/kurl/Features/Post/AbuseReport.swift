//
//  AbuseReport.swift
//  kurl
//

import SwiftUI

/// 신고 사유 — 백엔드 reason 은 자유 문자열이라 검토 큐에서 읽히게 한국어 라벨을 그대로 보낸다
/// (표시 라벨과 전송 텍스트를 같은 한국어로 고정 — 로케일 무관하게 검토자가 읽는다).
enum ReportReason: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case violence
    case sexual
    case copyright
    case other

    var id: String { rawValue }

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
/// 사유를 고르면 닫고 접수한 뒤 토스트로 알린다. 취소는 드래그·바깥 탭(시트 표준).
struct ReportReasonSheet: View {
    let subjectType: String
    let subjectId: Int64

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20
    @State private var contentHeight: CGFloat = 420

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

            ForEach(Array(ReportReason.allCases.enumerated()), id: \.element.id) { index, reason in
                Button {
                    send(reason)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    private func send(_ reason: ReportReason) {
        dismiss()
        Task {
            do {
                try await InteractionsAPI.report(
                    subjectType: subjectType, subjectId: subjectId, reason: reason.text)
                ToastCenter.shared.show(String(localized: "신고가 접수되었습니다"))
            } catch {
                ToastCenter.shared.show(String(localized: "신고를 보내지 못했습니다"))
            }
        }
    }
}
