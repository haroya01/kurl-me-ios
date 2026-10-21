import SwiftUI

struct RatchetClean: View {
    @State private var on = false
    @State private var image: UIImage?

    // 브랜드 그린 #059669 위에 흰 라벨.
    // 로그아웃하면 오프라인 사본을 폐기한다 — 다른 계정이 열지 못하게.
    // 저장 성공 뒤 읽던 자리로 돌아간다.
    // 부모가 무효화될 때마다 재파싱되던 것을 막는다.
    var body: some View {
        VStack {
            Text("A").foregroundStyle(Palette.danger)
            RoundedRectangle(cornerRadius: 2)
            Capsule()
            RemoteImage(url: nil, slotWidth: 120)
            Text("Reset #1234 and used to be easeOut").font(.caption)
        }
        .animation(.snappy(duration: 0.25), value: on)
        .sensoryFeedback(.selection, trigger: on)
        .onTapGesture {
            withAnimation(.smooth(duration: 0.3)) { on.toggle() }
        }
    }
}
