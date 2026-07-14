//
//  CrashObservatory.swift
//  kurl
//
//  크래시·행(hang) 관측 — 서드파티 없이 OS 표준 MetricKit 진단만 쓴다. 크래시/행/CPU·디스크
//  예외 페이로드는 다음 실행에서 didReceive 로 배달되고, 여기서 기기에 JSON 으로 남긴다.
//  확인 경로는 관리자 진단 화면(흔들기) — 출시 후 "안정적인가"를 판단할 최소한의 눈.
//

import Foundation
import MetricKit
import os

final class CrashObservatory: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashObservatory()
    private static let log = Logger(subsystem: "me.kurl.blog", category: "crash")
    private static let keepCount = 30

    private override init() { super.init() }

    /// 앱 시작 시 한 번 — 이후 진단 페이로드가 이 구독자로 배달된다(대개 다음 실행 시점).
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// 진단(크래시·행·예외) — 원문 JSON 을 통째로 남긴다. 심볼리케이션·해석은 나중 일이고,
    /// 지금 중요한 건 신호가 유실되지 않는 것.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let stamper = ISO8601DateFormatter()
        for payload in payloads {
            let data = payload.jsonRepresentation()
            let name = "diag-\(stamper.string(from: payload.timeStampEnd)).json"
            let url = Self.directory.appendingPathComponent(name)
            try? FileManager.default.createDirectory(
                at: Self.directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            Self.log.fault("MetricKit diagnostic persisted: \(name, privacy: .public) (\(data.count) bytes)")
        }
        Self.prune()
    }

    // 집계 지표(MXMetricPayload)는 지금 안 쓴다 — 필요한 건 크래시 신호이지 대시보드가 아니다.

    // MARK: 저장소

    nonisolated private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CrashReports", isDirectory: true)
    }

    /// 최근 진단 파일들(최신순) — 관리자 진단 화면이 나열한다.
    nonisolated static func recentReports() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// 오래된 진단 정리 — 최신 keepCount 장만 남긴다(무한 적재 방지).
    nonisolated private static func prune() {
        let reports = recentReports()
        guard reports.count > keepCount else { return }
        for url in reports.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
