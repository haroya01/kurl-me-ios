//
//  Theme.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import UIKit

enum Brand {
    /// kurl 브랜드 그린 #059669
    static let green = Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255)
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Brand.green }
}

extension Color {
    /// 코드/임베드/테이블 등 카드 배경.
    static let surface = Color(uiColor: .secondarySystemBackground)
}

enum Metrics {
    /// 본문 읽기 최대 폭 (조용한 웹로그 컬럼 감성)
    static let readingMaxWidth: CGFloat = 680
}
