import SwiftUI

extension View {
    /// 비로그인일 때 그 자리에서 로그인 시트(LoginSheet)를 띄운다. 면마다 다른 건 안내 문구뿐이고,
    /// 로그인되면 `onSignedIn`을 부르고 시트가 닫힌다. 2FA 는 시트 안에서 끝까지 간다.
    func loginPrompt(
        isPresented: Binding<Bool>,
        message: LocalizedStringKey,
        onSignedIn: @escaping () async -> Void = {}
    ) -> some View {
        sheet(isPresented: isPresented) {
            LoginSheet(message: message, onSignedIn: onSignedIn)
        }
    }
}

/// 로그인해야 채워지는 탭 루트의 비로그인 상태 — "로그인"을 누르면 같은 로그인 시트가 뜬다.
struct SignedOutState: View {
    let description: LocalizedStringKey
    let message: LocalizedStringKey

    @State private var showLogin = false

    var body: some View {
        FeedPlaceholder(title: description, actionTitle: "로그인", action: { showLogin = true })
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.pageBg)
        .loginPrompt(isPresented: $showLogin, message: message)
    }
}
