//
//  Theme.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

/// "조용한 웹로그" 표면 토큰. 프론트 §10 디자인 언어를 그대로 옮긴다.
/// 차별화는 타이포 위계로만 — Material elevation / 떠 있는 카드 금지.
enum Palette {
    // 잉크 (slate)
    static let ink = Color(light: 0x0F172A, dark: 0xF1F5F9)            // 제목/헤딩 slate-900/100
    static let heading = Color(light: 0x1E293B, dark: 0xE2E8F0)        // RailHeading slate-800/200
    static let body = Color(light: 0x334155, dark: 0xCBD5E1)           // 본문 slate-700/300
    static let secondary = Color(light: 0x64748B, dark: 0x94A3B8)      // excerpt/메타 slate-500/400
    static let faint = Color(light: 0x94A3B8, dark: 0x64748B)          // 대표 태그 slate-400/500
    static let hairline = Color(light: 0xF1F5F9, dark: 0x1E293B)       // 구분선 slate-100/800
    static let hairlineStrong = Color(light: 0xE2E8F0, dark: 0x334155) // 테이블 헤더 slate-200/700
    static let rowHighlight = Color(light: 0xF8FAFC, dark: 0x111827)   // 행 hover slate-50
    static let chipBg = Color(light: 0xF1F5F9, dark: 0x1E293B)         // slate-100/800
    static let chipText = Color(light: 0x475569, dark: 0xCBD5E1)       // slate-600/300

    // 그린 한 가닥 (마커 / active 밑줄 / 링크) — 절제해서만
    static let accent = Color(hex: 0x059669)        // 브랜드
    static let accentMarker = Color(hex: 0x10B981)  // accent-500
    static let accentSoft = Color(hex: 0x34D399)    // accent-400 인용 보더
    static let link = Color(light: 0x047857, dark: 0x34D399) // accent-700/400
    static let accentFill = Color(hex: 0x047857)    // 흰 라벨 채움 = accent-700 (WCAG 4.5:1)

    // 코드
    static let codeBg = Color(hex: 0x0F172A)        // slate-900 (항상 어둡게)
    static let codeText = Color(hex: 0xF1F5F9)      // slate-100
    static let inlineCodeBg = Color(light: 0xF1F5F9, dark: 0x1E293B)
    static let inlineCodeText = Color(light: 0x065F46, dark: 0x6EE7B7) // accent-800/300
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Palette.accent }
}

enum Metrics {
    /// 읽기 컬럼 불변식 — 본문 정중앙 max-w-2xl(672 ≈ 한 줄 66자)
    static let readingColumn: CGFloat = 672
    static let gutter: CGFloat = 20
}
