//
//  WidgetType.swift
//  kurlWidget
//

import SwiftUI

/// 위젯 전용 타입 사다리 — 앱 `TypeRole`(kurl/Theme/Theme.swift)를 위젯에서 import 할 수 없어
/// 위젯 관례에 맞춘 미니 사다리를 따로 둔다. 흩어진 `.font(.system(size:))` 매직 사이즈를 한 곳으로
/// 모으고, `@ScaledMetric` 으로 사용자 글자 크기를 따르게 한다(위젯은 시스템이 스케일 범위를 자체로
/// 좁게 잡는다). 색은 호출측이 `.foregroundStyle` 로 따로 입힌다 — 토큰은 글자꼴만.
enum WidgetType {
    /// 잠금화면 원형 라벨·스니펫 미니 라벨(9~9.5)
    case micro
    /// 헤더 눈썹·stat 라벨·안내 라벨(11)
    case caption
    /// 안내 본문·작가명(12~12.5)
    case footnote
    /// 중간 위젯 stat 값(13)
    case metricSmall
    /// 선반 행 제목(15)
    case rowTitle
    /// 잠금 사각 숫자·작은 위젯 한 장 제목(16~17)
    case headline
    /// 큰 조회수 숫자(30)
    case figure

    var size: CGFloat {
        switch self {
        case .micro: return 9.5
        case .caption: return 11
        case .footnote: return 12.5
        case .metricSmall: return 13
        case .rowTitle: return 15
        case .headline: return 17
        case .figure: return 30
        }
    }

    /// Dynamic Type 기준 — @ScaledMetric 이 이 비율로 키운다(위젯은 시스템이 상한을 좁게 잡는다).
    var relativeTo: Font.TextStyle {
        switch self {
        case .micro, .caption, .footnote: return .caption
        case .metricSmall, .rowTitle: return .footnote
        case .headline: return .headline
        case .figure: return .largeTitle
        }
    }
}

/// 위젯 타입 토큰을 Dynamic Type 와 함께 적용한다 — `Text(...).widgetType(.caption, weight: .bold)`.
/// 색은 따로 `.foregroundStyle`. 숫자 열이 흔들리지 않게 필요한 곳만 `monospacedDigit: true`.
private struct WidgetTypeModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let monospacedDigit: Bool

    init(_ role: WidgetType, weight: Font.Weight, monospacedDigit: Bool) {
        self.weight = weight
        self.monospacedDigit = monospacedDigit
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.relativeTo)
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

extension View {
    /// 위젯 타입 토큰 — 색은 따로 `.foregroundStyle`.
    func widgetType(
        _ role: WidgetType, weight: Font.Weight = .regular, monospacedDigit: Bool = false
    ) -> some View {
        modifier(WidgetTypeModifier(role, weight: weight, monospacedDigit: monospacedDigit))
    }
}
