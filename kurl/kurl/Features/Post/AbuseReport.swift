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
    /// 신고 사유 선택 다이얼로그 — 글/작가 어디서나 같은 문법. 접수되면 토스트로 알린다.
    /// 익명도 가능(서버 permitAll). subjectType = "POST" | "USER".
    func reportDialog(isPresented: Binding<Bool>, subjectType: String, subjectId: Int64) -> some View {
        let noun: String
        switch subjectType {
        case "USER": noun = String(localized: "이 작가를")
        case "COMMENT": noun = String(localized: "이 댓글을")
        default: noun = String(localized: "이 글을")
        }
        return confirmationDialog(
            "신고 사유를 선택하세요", isPresented: isPresented, titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(LocalizedStringKey(reason.text)) {
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
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(noun) 신고합니다. 검토 후 조치됩니다.")
        }
    }
}
