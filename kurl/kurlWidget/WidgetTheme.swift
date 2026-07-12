//
//  WidgetTheme.swift
//  kurlWidget
//

import SwiftUI

/// 위젯 타깃의 표면 토큰 — 앱 `Palette`(kurl/Theme/Theme.swift)를 위젯에서 import 할 수 없어
/// 브랜드 그린 한 곳만 미러링한다. 두 위젯이 각자 들고 있던 raw RGB 를 여기 하나로 모아,
/// 그린이 흩어지지 않게 한다(§색 규율 — 단일 소스). 값은 앱 `Palette.accent`(#059669,
/// accent-600 §10.3 비텍스트)와 짝 — 한쪽 바꾸면 같이. `Color(hex:)` 는 앱 타깃 전용이라
/// 위젯에선 RGB 성분으로 같은 색을 짠다.
enum WidgetPalette {
    /// 브랜드 그린 #059669 (accent-600) — 마커·막대 등 비텍스트에만.
    static let accent = Color(red: 0x05 / 255.0, green: 0x96 / 255.0, blue: 0x69 / 255.0)
    /// 종이 세계 잉크 — 위젯 배경 위 vibrancy 로 대비를 만든다(고정 slate 대신 시맨틱).
    static let ink = Color.primary
    static let secondary = Color.secondary
    /// 종이 세계의 hairline 을 위젯 위에서 흉내 — 양 모드에서 옅게.
    static let hairline = Color.primary.opacity(0.06)
}
