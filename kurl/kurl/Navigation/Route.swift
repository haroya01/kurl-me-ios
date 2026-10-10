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
    /// 글의 특정 구절로 딥링크 — 발견 피드의 하이라이트 카드가 "그 문장"으로 데려간다(스크롤+깜빡).
    case postFocusQuote(username: String, slug: String, quote: String)
    case postSpot(username: String, slug: String, spot: PostSpot)
    case author(username: String)
    case authorNotes(username: String)
    /// 명함(/u) — 링크인바이오 면. 블로그(/p)와 같은 정체의 다른 얼굴, 앱 안 화면으로 얹는다.
    case businessCard(username: String)
    case series(username: String, slug: String)
    case tag(String)
    /// 노트 해시태그 — 같은 태그 화면을 노트 탭으로 연다(뜨는 해시태그에서).
    case noteTag(String)
    /// 작가의 팔로워 / 팔로잉 목록 — 같은 화면을 미리 고른 탭으로 연다.
    case followers(username: String)
    case following(username: String)
    /// 공개 컬렉션 상세 — 작가 프로필의 컬렉션 레일에서 엮은 컬렉션으로 들어간다.
    case collection(id: Int64)
    /// 알림 인박스 — 계정 헤더의 벨에서 연다. 값 기반으로 밀어 인박스 안의 딥링크(글·컬렉션)가
    /// 같은 스택에서 이어 밀린다(isPresented 목적지와 값 목적지가 한 스택에서 충돌하던 문제 회피).
    case notifications
    /// 노트 하나와 그 답글 — 노트 행·답글 수를 누르면 열린다.
    case note(id: Int64)
    case noteQuotes(id: Int64)
    /// 다른 서버 계정 — 검색에서 @아이디@서버로 찾는다.
    case remoteAccount(id: Int64)
    /// 잠긴 계정에 온 팔로우 요청 — 알림 맨 위 줄과 요청 알림 푸시에서 연다.
    case followRequests
    /// 알림 거르기가 따로 둔 알림 — 알림 맨 위 줄에서 연다.
    case filteredNotifications
    case blogFeed(FeedSource)
    case subscribedTags
    case myCollections
    case noteFeed(NoteFeedKind)
    case noteList(id: Int64, title: String)
    case noteLink(url: String, title: String?)
}

enum PostSpot: Hashable {
    case comment(Int64)
    case highlight(Int64)
}
