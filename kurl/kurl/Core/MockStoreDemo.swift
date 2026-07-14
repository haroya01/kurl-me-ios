//
//  MockStoreDemo.swift
//  kurl
//

import Foundation

/// 스토어 캡처 전용 목 콘텐츠(`--store-demo`) — 기본 목 픽스처("발행된 목 글"·"목 초안 …")는
/// UITest 20여 곳이 제목을 고정하고 있어 그대로 두고, 캡처를 뜰 때만 있을 법한 글(일상·문학·
/// 홍보·개발)로 갈아끼운다. 언어는 시스템 우선 언어를 따른다 — `-AppleLanguages (ja)` 런치
/// 인자와 함께 쓰면 크롬과 콘텐츠가 같은 언어로 찍힌다(스토어 5개 언어 캡처 파이프라인).
enum MockStoreDemo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("--store-demo") }

    /// ko·ja·vi·hi 아니면 en — 스토어 로케일 다섯과 같은 축.
    static var lang: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        for code in ["ko", "ja", "vi", "hi"] where preferred.hasPrefix(code) { return code }
        return "en"
    }

    struct Row {
        let slug: String
        let title: String
    }

    /// 분석 "글별 성과" 세 줄 — 장르를 섞는다: 일상 · 문학 · 홍보. 숫자는 라우트가 기존 값을 쓴다.
    static var analyticsRows: [Row] {
        switch lang {
        case "ko":
            return [
                Row(slug: "minimal-3-weeks", title: "비우고 시작한 미니멀 라이프 3주"),
                Row(slug: "winter-pace", title: "겨울의 속도 — 한강 산책 단상"),
                Row(slug: "no-ads-month", title: "광고 없이 작은 가게 알리기, 한 달의 기록"),
            ]
        case "ja":
            return [
                Row(slug: "minimal-3-weeks", title: "手放して始めたミニマルな3週間"),
                Row(slug: "winter-pace", title: "冬の速度 — 川沿いの散歩から"),
                Row(slug: "no-ads-month", title: "広告なしで小さな店を知らせた一か月"),
            ]
        case "vi":
            return [
                Row(slug: "minimal-3-weeks", title: "Ba tuần sống tối giản"),
                Row(slug: "winter-pace", title: "Nhịp mùa đông — ghi chép bên sông"),
                Row(slug: "no-ads-month", title: "Một tháng quảng bá tiệm nhỏ không cần quảng cáo"),
            ]
        case "hi":
            return [
                Row(slug: "minimal-3-weeks", title: "कम चीज़ों के साथ तीन हफ़्ते"),
                Row(slug: "winter-pace", title: "सर्दी की रफ़्तार — नदी किनारे की सैर"),
                Row(slug: "no-ads-month", title: "बिना विज्ञापन छोटी दुकान का प्रचार — एक महीना"),
            ]
        default:
            return [
                Row(slug: "minimal-3-weeks", title: "Three weeks of living with less"),
                Row(slug: "winter-pace", title: "The pace of winter — notes from a river walk"),
                Row(slug: "no-ads-month", title: "A month of promoting a tiny shop, no ads"),
            ]
        }
    }

    /// 분석 "시리즈" 두 줄 — 연재의 결(일상 기록 · 홍보 실무).
    static var seriesTitles: [String] {
        switch lang {
        case "ko": return ["주말 산책 일지", "작은 가게 마케팅"]
        case "ja": return ["週末さんぽ日誌", "小さな店のマーケティング"]
        case "vi": return ["Nhật ký dạo bộ cuối tuần", "Marketing cho tiệm nhỏ"]
        case "hi": return ["वीकेंड सैर डायरी", "छोटी दुकान की मार्केटिंग"]
        default: return ["Weekend walk journal", "Marketing a small shop"]
        }
    }
}
