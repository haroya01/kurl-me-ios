//
//  BusinessCardView.swift
//  kurl
//

import SwiftUI
import WebKit

/// 명함(/u) — 링크 모음·소셜·이벤트가 담긴 링크인바이오 면. 종류가 다양해(링크·이벤트·이메일폼·
/// 상품 카드) 네이티브로 통째 옮기기보다, 웹 원문을 앱 안 화면으로 얹는다. 앱 밖 Safari 로
/// 내쫓지 않고 네비 스택에 얹혀 뒤로가 자연스럽고, 툴바에서 같은 정체의 다른 얼굴(블로그)로 건넌다.
struct BusinessCardView: View {
    let username: String

    @State private var isLoading = true
    @State private var failed = false
    /// 재시도 세대 — 다시 시도할 때마다 +1 해 웹뷰가 같은 URL 을 처음부터 다시 받게 한다.
    /// (url == nil 판정 재시도는 실패 뒤엔 url 이 남아 있어 헛돌았다.)
    @State private var attempt = 0

    private var url: URL? {
        URL(string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/u/\(username)")
    }

    var body: some View {
        Group {
            if let url {
                InlineWebView(url: url, attempt: attempt, isLoading: $isLoading, failed: $failed)
                    .opacity(failed ? 0 : 1)
                    .overlay {
                        if isLoading, !failed {
                            KurlLoadingMark()
                        }
                    }
                    .overlay {
                        if failed {
                            ContentUnavailableView {
                                Label("명함을 불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                            } description: {
                                Text("연결을 확인하고 다시 시도해 주세요.")
                            } actions: {
                                Button("다시 시도") {
                                    failed = false
                                    isLoading = true
                                    attempt += 1
                                }
                                .foregroundStyle(Palette.accent)
                            }
                        }
                    }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.pageBg)
        .navigationTitle("명함")
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 같은 정체의 다른 얼굴로 건너는 문 — 명함에서 곧장 블로그(/p)로. 스택에 얹혀 돌아오기 쉽다.
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.author(username: username)) {
                    HStack(spacing: 5) {
                        KurlMark(drawn: [true, true, true])
                            .frame(width: 15, height: 9)
                        Text("블로그")
                            .typeScale(.footnote)
                    }
                }
                .tint(.brand)
                .accessibilityLabel("블로그 보기")
            }
        }
    }
}

/// 네비 스택에 얹히는 인앱 웹뷰 — SFSafariViewController 는 모달 전용이라 스택 푸시가 안 된다.
/// 앱 안에 살면서 뒤로/툴바 크롬을 SwiftUI 가 소유하도록 WKWebView 를 직접 얹는다.
private struct InlineWebView: UIViewRepresentable {
    let url: URL
    /// 재시도 세대 — 값이 바뀌면 웹뷰를 처음부터 다시 로드한다(부모의 "다시 시도" 버튼이 올린다).
    let attempt: Int
    @Binding var isLoading: Bool
    @Binding var failed: Bool

    /// 로드 워치독 — didFinish·didFail 이 끝내 오지 않아도(예: 챌린지·행 응답) 이 시간 뒤엔
    /// 실패로 넘겨 무한 백지 대신 재시도 UI 를 띄운다.
    private static let loadTimeout: TimeInterval = 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Palette.pageBg)
        webView.scrollView.backgroundColor = UIColor(Palette.pageBg)
        context.coordinator.beginLoad(webView, url: url, timeout: Self.loadTimeout)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 재시도 — attempt 가 오르면(실패 후 "다시 시도") 같은 URL 을 처음부터 다시 받는다.
        if attempt != context.coordinator.loadedAttempt, isLoading, !failed {
            context.coordinator.loadedAttempt = attempt
            context.coordinator.beginLoad(webView, url: url, timeout: Self.loadTimeout)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelWatchdog()
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: InlineWebView
        /// 마지막으로 로드한 재시도 세대 — updateUIView 가 중복 로드를 걸지 않게 한다.
        var loadedAttempt = 0
        private var watchdog: Task<Void, Never>?

        init(_ parent: InlineWebView) {
            self.parent = parent
            self.loadedAttempt = parent.attempt
        }

        /// 로드 시작 + 워치독 무장 — didFinish/didFail 이 오면 워치독은 해제된다.
        func beginLoad(_ webView: WKWebView, url: URL, timeout: TimeInterval) {
            webView.stopLoading()
            watchdog?.cancel()
            watchdog = Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled, let self, self.parent.isLoading else { return }
                // 응답 신호가 끝내 없었다 — 무한 백지 대신 재시도 UI 로.
                webView?.stopLoading()
                self.fail()
            }
            webView.load(URLRequest(url: url))
        }

        func cancelWatchdog() {
            watchdog?.cancel()
            watchdog = nil
        }

        private func finishLoading() {
            cancelWatchdog()
            parent.isLoading = false
        }

        private func fail() {
            cancelWatchdog()
            parent.isLoading = false
            parent.failed = true
        }

        // 응답 헤더를 먼저 본다 — didFail 만 의존하면 Cloudflare 챌린지·5xx 처럼
        // "본문은 왔지만 명함이 아닌" 페이지가 백지로 안착한다. non-2xx 는 실패로 넘긴다.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.isForMainFrame,
               let http = navigationResponse.response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                decisionHandler(.cancel)
                fail()
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finishLoading()
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            fail()
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            fail()
        }
    }
}
