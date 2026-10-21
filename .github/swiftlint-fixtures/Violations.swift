//  Violations.swift
//  kurl

import SwiftUI
import UIKit

struct RatchetViolations: View {
    @State private var on = false

    // 캡슐 탭 영역 규칙(#185)
    /// 예전엔 마커가 겹쳤다.
    // 시작부터 독이 안 뜨는 회귀가 있었다.
    // 편집기가 열리던 것 교정.
    var body: some View {
        VStack {
            Text("A").foregroundStyle(.red)
            RoundedRectangle(cornerRadius: 12)
            AsyncImage(url: URL(string: "https://kurl.me/a.png"))
        }
        .animation(.easeInOut(duration: 0.3), value: on)
        .animation(.snappy(duration: 0.25), value: on)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { on.toggle() }
        }
    }
}
