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
    /// 인증이 필요한 표면을 로그인 없이 돌려본다(공개 읽기는 실서버 그대로).
    static let useMocks = ProcessInfo.processInfo.arguments.contains("--mocks")

    /// 디버그 화면 진입 — `--tab write|discover|search|account`, `--open analytics|compose`,
    /// `--selftest`. simctl 로는 터치를 못 넣으니 스크린샷/검증용 진입로다.
    static func launchValue(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// UI 로케일 (ja/ko/en). 시스템 우선 언어를 따르되 미지원이면 ko 로 떨어진다.
    static var preferredLanguageTag: String {
        let supported = ["ja", "ko", "en"]
        for code in Locale.preferredLanguages {
            let base = String(code.prefix(2))
            if supported.contains(base) { return base }
        }
        return "ko"
    }
}
