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

    private var url: URL? {
        URL(string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/u/\(username)")
    }

    var body: some View {
        Group {
            if let url {
                InlineWebView(url: url, isLoading: $isLoading, failed: $failed)
                    .opacity(failed ? 0 : 1)
                    .overlay {
                        if isLoading, !failed {
                            KurlLoadingMark()
                        }
                    }
                    .overlay {
                        if failed {
                            ContentUnavailableView {
                                Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                            } actions: {
                                Button("다시 시도") {
                                    failed = false
                                    isLoading = true
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
    @Binding var isLoading: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Palette.pageBg)
        webView.scrollView.backgroundColor = UIColor(Palette.pageBg)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 재시도 — 실패 상태에서 로딩으로 되돌리면 같은 URL 을 다시 받는다.
        if isLoading, !failed, webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: InlineWebView
        init(_ parent: InlineWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            parent.isLoading = false
            parent.failed = true
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.isLoading = false
            parent.failed = true
        }
    }
}
