import SwiftUI

/// 비활성화된 버튼에 도착한 누름은 손을 떼도 isPressed 가 풀리지 않는다(넘기는 중인 SwipePager 가 페이지를 끈다).
/// 눌림을 그리는 버튼 스타일은 이 값으로 그린다. 그 누름은 그리지 않고, 다음 누름이 끝나면 풀린다.
struct PressLatch<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.isEnabled) private var isEnabled
    @State private var cutOff = false

    var body: some View {
        content(isPressed && !cutOff)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, isPressed { cutOff = true }
            }
            .onChange(of: isPressed) { _, now in
                cutOff = now && !isEnabled
            }
    }
}
