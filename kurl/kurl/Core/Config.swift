//
//  Config.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation

enum Config {
    /// 백엔드 apex. 운영은 kurl.me 로 직접 호출한다.
    static let apiBase = URL(string: "https://kurl.me")!
    static let apiPrefix = "/api/v1"

    /// 공개 블로그 호스트 — 글·작가·시리즈의 정규 주소(웹 postHref 와 동일: blog.kurl.me/@user/slug).
    /// apex 의 /{lang}/p/… 경로도 열리긴 하지만 정규 주소가 아니다 — 공유·표기는 전부 이쪽으로.
    /// 로케일 세그먼트는 붙이지 않는다(블로그 호스트는 진입 시 언어를 자동 감지).
    static let blogBase = URL(string: "https://blog.kurl.me")!

    /// 목 모드 — 런치 인자 `--mocks`. 웹의 NEXT_PUBLIC_USE_MOCKS 와 같은 역할:
    /// 인증이 필요한 표면을 로그인 없이 돌려본다(공개 읽기는 실서버 그대로). DEBUG 전용.
    static let useMocks: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--mocks")
        #else
        return false
        #endif
    }()

    /// `--offline` — 모든 네트워크를 즉시 실패시켜 오프라인 폴백을 검증한다(DEBUG 전용).
    static let simulateOffline: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--offline")
        #else
        return false
        #endif
    }()

    /// WYSIWYG 블록 에디터(WriteV2) — 이제 글쓰기의 default 다. 이탤릭·링크·표·구분선·코드가
    /// 마크다운 원문이 아니라 최종 모습으로 바로 보이는 캔버스가 기본이 됐다.
    /// 복귀 경로 둘: 설정의 '실험' 토글(@AppStorage "legacyEditorEnabled", 실기기·릴리스 포함) 또는
    /// 런치 플래그 `--editor v2`|`--editor legacy`(DEBUG 전용 — simctl/XCUITest 검증용, 토글보다 우선).
    /// 실기기 릴리스에선 플래그가 없으니 토글이 유일한 제어다.
    ///
    /// 키를 "wysiwygEditorEnabled"(옛 옵트인, 기본 false) → "legacyEditorEnabled"(복귀, 기본 false)로
    /// 바꾼 이유: 옛 키를 그대로 두고 default 만 true 로 하면 옛 키가 `false`(대다수)인 기기가
    /// 레거시로 떨어진다. 새 키는 아무도 켜지 않았으니 전원이 곧장 v2 로 온다.
    static var wysiwygEditorEnabled: Bool {
        if let editor = launchEditorOverride {
            return editor == "v2"
        }
        return !UserDefaults.standard.bool(forKey: "legacyEditorEnabled")
    }

    /// `--editor v2` / `--editor legacy` 오버라이드 — 있으면 토글보다 우선. DEBUG 밖에선 무시.
    private static var launchEditorOverride: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--editor"), i + 1 < args.count else { return nil }
        let value = args[i + 1]
        return (value == "v2" || value == "legacy") ? value : nil
        #else
        return nil
        #endif
    }

    /// 디버그 화면 진입 — `--tab write|discover|search|account`, `--open analytics|compose`,
    /// `--selftest`. simctl 로는 터치를 못 넣으니 스크린샷/검증용 진입로다. DEBUG 전용.
    static func launchValue(after flag: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }

    /// `--open` 류 1회성 소비 — pop 으로 루트 복귀할 때마다 재푸시되는 루프 방지.
    @MainActor private static var consumedFlags: Set<String> = []
    @MainActor
    static func consumeLaunchValue(after flag: String) -> String? {
        guard !consumedFlags.contains(flag), let value = launchValue(after: flag) else { return nil }
        consumedFlags.insert(flag)
        return value
    }

    /// 특정 화면으로 바로 진입하는 검증용 딥링크 인자가 붙었는가 — `--post`·`--author`·
    /// `--series`·`--tag`·`--screen`. 이런 진입은 목적지가 명확하므로 첫 실행 웰컴 막을 띄우지
    /// 않는다(웰컴이 목적 화면을 덮어 터치를 삼키던 문제). DEBUG 전용.
    static var hasDeepLinkEntry: Bool {
        #if DEBUG
        let flags = ["--post", "--author", "--series", "--tag"]
        if flags.contains(where: { launchValue(after: $0) != nil }) { return true }
        // `--screen welcome` 은 웰컴 자체를 강제하는 진입이라 제외한다.
        if let screen = launchValue(after: "--screen"), screen != "welcome" { return true }
        return false
        #else
        return false
        #endif
    }

    /// UI 로케일 (ja/ko/en/vi/hi). 시스템 우선 언어를 따르되 미지원이면 ko 로 떨어진다.
    static var preferredLanguageTag: String {
        let supported = ["ja", "ko", "en", "vi", "hi"]
        for code in Locale.preferredLanguages {
            let base = String(code.prefix(2))
            if supported.contains(base) { return base }
        }
        return "ko"
    }

    /// 글 본문(POST /posts·PATCH)에 실어 보내는 언어 태그 — 백엔드 글 생성/수정은 ko·ja·en
    /// 만 허용(그 밖은 400 → 초안 생성 실패로 자동저장이 통째로 죽는다). UI 로케일이 vi·hi 여도
    /// 글 콘텐츠 언어는 서버가 받는 값으로 좁혀 보낸다(en 로 폴백 — UI 표시용 preferredLanguageTag 는
    /// 그대로 두고, 미리보기 URL·화면 문구엔 영향 없음).
    static var postContentLanguageTag: String {
        let backendSupported: Set<String> = ["ko", "ja", "en"]
        let tag = preferredLanguageTag
        return backendSupported.contains(tag) ? tag : "en"
    }
}
