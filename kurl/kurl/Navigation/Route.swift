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
}
