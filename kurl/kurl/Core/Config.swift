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

    /// WYSIWYG 블록 에디터(WriteV2) 옵트인 — 아직 현행 마크다운 에디터가 default 다.
    /// 두 경로로 켠다: 설정의 '실험' 토글(@AppStorage "wysiwygEditorEnabled", 실기기용) 또는
    /// 런치 플래그 `--editor v2`(simctl/XCUITest 검증용, 터치 없이 강제 진입). 검증이 끝나면
    /// default 를 넘긴다 — 그때까지 현행 에디터를 하드 교체하지 않는다.
    static var wysiwygEditorEnabled: Bool {
        if ProcessInfo.processInfo.arguments.firstIndex(of: "--editor")
            .map({ $0 + 1 < ProcessInfo.processInfo.arguments.count
                && ProcessInfo.processInfo.arguments[$0 + 1] == "v2" }) == true {
            return true
        }
        return UserDefaults.standard.bool(forKey: "wysiwygEditorEnabled")
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
