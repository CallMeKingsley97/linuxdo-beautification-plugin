//
//  CookedHTMLView.swift
//  使用 WKWebView 沙箱渲染 Discourse cooked HTML
//

import SwiftUI
import AppKit
import WebKit

struct CookedHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> HeightReportingWebView {
        let config = WKWebViewConfiguration()
        // cooked HTML 来自 linux.do；允许 JS 以便测量高度与部分媒体表现
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = false
        config.websiteDataStore = .nonPersistent()

        let webView = HeightReportingWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        webView.setContentHuggingPriority(.required, for: .vertical)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        webView.setContentCompressionResistancePriority(.required, for: .vertical)
        return webView
    }

    func updateNSView(_ webView: HeightReportingWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.contentHeight = 80
            let page = Self.wrapHTML(html)
            webView.loadHTMLString(page, baseURL: Endpoints.baseURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CookedHTMLView
        var lastHTML: String?
        weak var webView: HeightReportingWebView?

        init(_ parent: CookedHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                let height = (result as? CGFloat)
                    ?? (result as? Double).map { CGFloat($0) }
                    ?? (result as? NSNumber).map { CGFloat(truncating: $0) }
                    ?? 120
                DispatchQueue.main.async {
                    guard let reporting = self?.webView else { return }
                    reporting.contentHeight = max(48, min(height + 12, 5000))
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // 仅允许初始 loadHTMLString 与站内图片等资源
            decisionHandler(.allow)
        }
    }

    private static func wrapHTML(_ body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root {
            color-scheme: light dark;
            --text: #1d1d1f;
            --muted: #6e6e73;
            --link: #0071e3;
            --code-bg: rgba(127,127,127,0.12);
            --quote-border: rgba(127,127,127,0.35);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --text: #f5f5f7;
              --muted: #a1a1a6;
              --link: #6cb6ff;
              --code-bg: rgba(255,255,255,0.08);
              --quote-border: rgba(255,255,255,0.25);
            }
          }
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: var(--text);
            font: 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            word-wrap: break-word;
            overflow-wrap: anywhere;
          }
          a { color: var(--link); text-decoration: none; }
          a:hover { text-decoration: underline; }
          img, video {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
          }
          pre, code {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-size: 13px;
          }
          pre {
            background: var(--code-bg);
            padding: 12px;
            border-radius: 8px;
            overflow-x: auto;
          }
          code {
            background: var(--code-bg);
            padding: 1px 4px;
            border-radius: 4px;
          }
          pre code { background: transparent; padding: 0; }
          blockquote {
            margin: 0.6em 0;
            padding: 0.2em 0 0.2em 0.9em;
            border-left: 3px solid var(--quote-border);
            color: var(--muted);
          }
          p { margin: 0.55em 0; }
          ul, ol { padding-left: 1.4em; }
          .emoji, img.emoji { width: 1.15em; height: 1.15em; vertical-align: -0.15em; border-radius: 0; }
          aside.quote .title { font-size: 12px; color: var(--muted); margin-bottom: 4px; }
          .lightbox-wrapper { margin: 0.5em 0; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

/// 根据内容高度报告 intrinsicContentSize，便于嵌在 ScrollView 中
final class HeightReportingWebView: WKWebView {
    var contentHeight: CGFloat = 80 {
        didSet {
            guard abs(oldValue - contentHeight) > 0.5 else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }
}

