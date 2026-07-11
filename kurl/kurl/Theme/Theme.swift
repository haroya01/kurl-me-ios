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

    /// 명암 4종 — 시스템 "대비 증가"(Increase Contrast)를 켜면 더 또렷한 변형으로.
    /// 읽기·메타·구분선이 손가락 설정 하나로 단단해진다(접근성).
    init(light: UInt, dark: UInt, lightHC: UInt, darkHC: UInt) {
        self = Color(uiColor: UIColor { trait in
            let high = trait.accessibilityContrast == .high
            switch (trait.userInterfaceStyle, high) {
            case (.dark, true): return UIColor(Color(hex: darkHC))
            case (.dark, false): return UIColor(Color(hex: dark))
            case (_, true): return UIColor(Color(hex: lightHC))
            default: return UIColor(Color(hex: light))
            }
        })
    }
}

/// "조용한 웹로그" 표면 토큰. 프론트 §10 디자인 언어를 그대로 옮긴다.
/// 차별화는 타이포 위계로만 — Material elevation / 떠 있는 카드 금지.
enum Palette {
    // 잉크 (slate)
    static let ink = Color(light: 0x0F172A, dark: 0xF1F5F9)            // 제목/헤딩 slate-900/100
    static let heading = Color(light: 0x1E293B, dark: 0xE2E8F0)        // RailHeading slate-800/200
    // 본문·메타·구분선은 "대비 증가"를 켜면 한 단계 진하게(읽기 가독 우선).
    static let body = Color(light: 0x334155, dark: 0xCBD5E1, lightHC: 0x1E293B, darkHC: 0xE2E8F0)        // slate-700/300 → 800/200
    static let secondary = Color(light: 0x64748B, dark: 0x94A3B8, lightHC: 0x475569, darkHC: 0xCBD5E1)  // slate-500/400 → 600/300
    static let faint = Color(light: 0x94A3B8, dark: 0x64748B, lightHC: 0x64748B, darkHC: 0x94A3B8)      // slate-400/500 → 600/400
    static let hairline = Color(light: 0xF1F5F9, dark: 0x1E293B, lightHC: 0xCBD5E1, darkHC: 0x475569)   // slate-100/800 → 300/600
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

    // 리더 하이라이트 워시/밑줄/플래시 — 웹(globals.css)과 같은 색 언어. 다크에선 accent-600(#059669)이
    // 검은 읽기면에 묻혀 안 보이므로 중간톤 accent-500(#10B981)을 살짝 더 실어 칠하고, 본문 슬레이트-300
    // 글자가 그 위에서 대비를 유지하게(≥8:1). alpha 를 담아야 해서 동적 UIColor 로 직접 짠다.
    static let highlightWash = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(Color(hex: 0x10B981)).withAlphaComponent(0.28)   // accent-500 @ 0.28
            : UIColor(Color(hex: 0x059669)).withAlphaComponent(0.18)   // accent-600 @ 0.18
    })
    // 메모/답글 있는 하이라이트의 강조 밑줄 — 다크에선 accent-400(#34D399)로 또렷하게.
    static let highlightUnderline = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(Color(hex: 0x34D399)).withAlphaComponent(0.6)
            : UIColor(Color(hex: 0x059669)).withAlphaComponent(0.6)
    })
    // 딥링크 도착 시 잠깐 비추는 블록 플래시 — 워시보다 옅게, 다크는 accent-500 로.
    static let highlightFlash = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(Color(hex: 0x10B981)).withAlphaComponent(0.16)
            : UIColor(Color(hex: 0x059669)).withAlphaComponent(0.10)
    })

    // 오류·파괴·한도초과 텍스트 — 흩어진 raw `.red` 종식. 양 모드 본문 위 WCAG AA(≥4.5:1).
    static let danger = Color(light: 0xDC2626, dark: 0xF87171) // red-600/400

    // 페이지 배경. 다크 = slate-950(웹과 동일 휴). 라이트는 순백이 아니라 slate-50 —
    // 무보더 흰 카드가 "종이 위 종이"로 떠야 화이트가 비어 보이지 않는다(다크의
    // 950/900 톤 레이어링과 대칭). 순백은 글 상세 본문·에디터 캔버스만 쓴다.
    static let pageBg = Color(light: 0xF8FAFC, dark: 0x020617)

    // 읽기 면(글 상세 본문·에디터 캔버스·발견 덱) = 순백. 종이 세계의 본문은 흰 종이,
    // 카드(browse)는 slate-50 pageBg 위에서 뜬다(§1). 다크는 OLED 순흑.
    static let readingBg = Color(light: 0xFFFFFF, dark: 0x000000)

    // 카드 (browse 면 전용 — 읽기 면은 여전히 flat 행)
    static let cardBg = Color(light: 0xFFFFFF, dark: 0x0F172A)     // white / slate-900
    static let cardBorder = Color(light: 0xE2E8F0, dark: 0x1E293B) // slate-200 / slate-800
    static let coverVeil = Color(hex: 0x064E3B).opacity(0.10)      // accent-900/10 톤 베일

    // 코드
    static let codeBg = Color(hex: 0x0F172A)        // slate-900 (항상 어둡게)
    static let codeText = Color(hex: 0xF1F5F9)      // slate-100
    static let inlineCodeBg = Color(light: 0xF1F5F9, dark: 0x1E293B)
    static let inlineCodeText = Color(light: 0x065F46, dark: 0x6EE7B7) // accent-800/300

    // 구문 하이라이트 — §색 규율의 *유일한* 허용 다색 예외(어두운 codeBg 한정).
    // 문자열은 브랜드 그린 계열로 묶고 나머지는 IDE 관습색. 인라인 매직 헥스가 아니라
    // 여기서 한 곳으로 다스린다(흩어진 색 산포 금지).
    static let codeComment = Color(hex: 0x7C8BA3)   // muted slate
    static let codeKeyword = Color(hex: 0xF472B6)
    static let codeString = Color(hex: 0x6EE7B7)    // accent-300 계열
    static let codeNumber = Color(hex: 0xFCD34D)
    static let codeType = Color(hex: 0x7DD3FC)
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Palette.accent }
}

/// 제목 타이포 사다리 — 한 곳에서 크기·굵기·자간을 정의한다(흩어진 매직넘버 종식).
/// 규칙(§10 + PR#7 검증): **클수록 자간을 더 조인다**(디스플레이는 −0.6, 목록 제목은 −0.3),
/// 디스플레이/마스트헤드는 bold, 목록 제목은 semibold. 본문·메타는 읽기면(BlockRenderer)이
/// 소유하므로 여기 두지 않는다 — 이 사다리는 "제목의 목소리"만 책임진다.
/// 색은 호출측이 따로 입힌다(.foregroundStyle) — 토큰은 글자꼴·자간만.
enum TypeRole {
    // 제목 사다리
    case display      // 글 상세 제목 — 읽기면 마스트헤드
    case masthead     // 시리즈/스튜디오 섹션 제목, 에디터 제목
    case name         // 작가 프로필 이름
    case featured     // featured(오늘의 글) 카드 제목
    case title        // 피드·카드·목록 표준 제목
    case titleSmall   // 에피소드·소형 카드 제목
    case eyebrow      // 섹션 라벨(RailHeading)
    // 본문 사다리 — 발췌·본문·메타도 토큰으로(raw size 산발 방지가 "에디토리얼"의 핵심 레버).
    case lede         // 발췌·소개 한 단락(카드·행 제목 아래)
    case body         // 컴포넌트 본문(댓글·노트·답글 본문)
    case meta         // 작가·날짜·카운트 등 메타
    case footnote     // 가장 작은 힌트·캡션

    var size: CGFloat {
        switch self {
        case .display: return 31
        case .masthead: return 24.5
        case .name: return 24
        case .featured: return 22
        case .title: return 18
        case .titleSmall: return 16
        case .eyebrow: return 13
        case .body: return 15.5
        case .lede: return 14.5
        case .meta: return 12.5
        case .footnote: return 11.5
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .masthead, .name, .featured, .eyebrow: return .bold
        case .title, .titleSmall: return .semibold
        case .meta: return .medium
        case .lede, .body, .footnote: return .regular
        }
    }

    /// 클수록 더 조인다 — 큰 제목의 헐거운 기본 자간이 "에디토리얼"을 깬다. 본문은 거의 안 건드린다.
    var tracking: CGFloat {
        switch self {
        case .display: return -0.6
        case .masthead: return -0.5
        case .name, .featured: return -0.4
        case .title: return -0.3
        case .titleSmall: return -0.25
        case .lede, .body: return -0.1
        case .eyebrow, .meta, .footnote: return 0
        }
    }

    /// 본문 사다리만 행간을 갖는다 — 읽기 호흡(제목은 0).
    var lineSpacing: CGFloat {
        switch self {
        case .lede: return 3.5
        case .body: return 4.5
        default: return 0
        }
    }

    /// Dynamic Type 기준 텍스트 스타일 — @ScaledMetric 이 이 비율로 키운다.
    var relativeTo: Font.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .masthead, .name: return .title
        case .featured: return .title2
        case .title, .titleSmall: return .headline
        case .body: return .callout
        case .lede: return .subheadline
        case .eyebrow, .meta, .footnote: return .caption
        }
    }
}

/// 제목 사다리를 Dynamic Type 와 함께 적용한다(글자꼴·굵기·자간). 색은 안 건드린다.
private struct TypeScaleModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let role: TypeRole

    init(_ role: TypeRole) {
        self.role = role
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: role.weight))
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
    }
}

extension View {
    /// 제목 타이포 토큰 — `Text(...).typeScale(.title)`. 색은 따로 `.foregroundStyle`.
    func typeScale(_ role: TypeRole) -> some View { modifier(TypeScaleModifier(role)) }
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

    /// 전폭 종이 카드 내부 여백 — radiusCard 면이 본문을 들이는 정준 인셋.
    /// 텍스트 카드·발행 미리보기·자리표시가 같은 값을 물어 카드끼리 결이 안 어긋난다.
    static let cardPadding: CGFloat = 18
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
