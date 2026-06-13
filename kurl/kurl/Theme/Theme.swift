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
    static let rowHighlight = Color(light: 0xF8FAFC, dark: 0x1E293B)   // 행 press slate-50/800
    static let chipBg = Color(light: 0xF1F5F9, dark: 0x1E293B)         // slate-100/800
    static let chipText = Color(light: 0x475569, dark: 0xCBD5E1)       // slate-600/300

    // 그린 한 가닥 (마커 / active 밑줄 / 링크) — 절제해서만
    static let accent = Color(hex: 0x059669)        // 브랜드
    static let accentMarker = Color(hex: 0x059669)  // accent-600 (§10.3 비텍스트=600)
    static let accentSoft = Color(hex: 0x34D399)    // accent-400 인용 보더
    static let link = Color(light: 0x047857, dark: 0x34D399) // accent-700/400
    static let accentFill = Color(hex: 0x047857)    // 흰 라벨 채움 = accent-700 (WCAG 4.5:1)

    // 페이지 배경. 다크 = slate-950(웹과 동일 휴). 라이트는 순백이 아니라 slate-50 —
    // 무보더 흰 카드가 "종이 위 종이"로 떠야 화이트가 비어 보이지 않는다(다크의
    // 950/900 톤 레이어링과 대칭). 순백은 글 상세 본문·에디터 캔버스만 쓴다.
    static let pageBg = Color(light: 0xF8FAFC, dark: 0x020617)

    // 카드 (browse 면 전용 — 읽기 면은 여전히 flat 행)
    static let cardBg = Color(light: 0xFFFFFF, dark: 0x0F172A)     // white / slate-900
    static let cardBorder = Color(light: 0xE2E8F0, dark: 0x1E293B) // slate-200 / slate-800
    static let coverVeil = Color(hex: 0x064E3B).opacity(0.10)      // accent-900/10 톤 베일

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

    // 코너 반경 4단 — 같은 급의 면은 같은 반경(매직넘버 산포 방지).
    /// 전폭 카드(피드·커버) — 하단 유리 띠와 동일값 강제(AGENTS §1.5).
    static let radiusCard: CGFloat = 20
    /// 미니 카드(레일·다음 편·힌트 캡슐류)
    static let radiusMini: CGFloat = 16
    /// 컨트롤 면(코드 블록·입력 프롬프트·임베드)
    static let radiusControl: CGFloat = 12
    /// 썸네일(행 안의 56×42 등)
    static let radiusThumb: CGFloat = 8
}

/// Liquid Glass 토큰 — "종이 본문, 액체 크롬"(AGENTS.md §1).
/// 유리는 떠 있는 크롬에만 산다. 종이 세계 토큰은 위 Palette 그대로.
enum GlassTokens {
    /// 흰 라벨을 받는 유리 틴트 = accent-700 — §10.3 600/700 규칙의 유리판.
    static let prominentTint = Palette.accentFill
    /// 커버 사진 위 맑은 유리의 가독 틴트 — 밝은 사진(흰 책상류)에서도 흰 타이포가 서야
    /// 해서 0.32 로는 모자랐다.
    static let mediaScrim = Color.black.opacity(0.40)
    /// 큰 유리 면(독·패널) 모서리. 컨트롤은 캡슐이 기본.
    static let panelRadius: CGFloat = 24
    /// 유리 클러스터 간격 — GlassEffectContainer 가 이 거리부터 서로 녹여 붙인다.
    static let clusterSpacing: CGFloat = 18
}
