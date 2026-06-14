//
//  LoginPrompt.swift
//  kurl
//

import SwiftUI

extension View {
    /// 인게이지 버튼(팔로우·구독·태그 구독·좋아요/북마크 독·댓글) 공용 로그인 유도 —
    /// 비로그인일 때 그 자리에서 정식 로그인 시트(LoginSheet)를 띄운다. 알럿(텍스트 버튼)이
    /// 네 곳에 복제돼 있던 것을 한 자리로. 면마다 다른 건 안내 문구뿐이고, 로그인되면
    /// `onSignedIn`(보통 `model.hydrate()`)을 부르고 시트가 닫힌다. 2FA 는 시트 안에서 끝까지 간다.
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
