//
//  Route.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation

/// NavigationStack 값 기반 라우팅.
enum Route: Hashable {
    case post(username: String, slug: String)
    case author(username: String)
    case series(username: String, slug: String)
    case tag(String)
    /// 작가의 팔로워 / 팔로잉 목록 — 같은 화면을 미리 고른 탭으로 연다.
    case followers(username: String)
    case following(username: String)
}
