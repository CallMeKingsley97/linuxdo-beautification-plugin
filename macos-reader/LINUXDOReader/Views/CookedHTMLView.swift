//
//  CookedHTMLView.swift
//  使用 WKWebView 沙箱渲染 Discourse cooked HTML
//

import SwiftUI
import AppKit
import WebKit

struct CookedHTMLView: NSViewRepresentable {
    private static let heightMessageName = "contentHeight"

    let html: String
    var onOpenTopic: ((Int) -> Void)?

    init(html: String, onOpenTopic: ((Int) -> Void)? = nil) {
        self.html = html
        self.onOpenTopic = onOpenTopic
    }

    func makeNSView(context: Context) -> HeightReportingWebView {
        let config = WKWebViewConfiguration()
        // cooked HTML 来自 linux.do；允许 JS 以便测量高度与部分媒体表现
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = false
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: Self.heightMessageName)

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

    static func dismantleNSView(_ nsView: HeightReportingWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.heightMessageName
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CookedHTMLView
        var lastHTML: String?
        weak var webView: HeightReportingWebView?

        init(_ parent: CookedHTMLView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let js = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                self?.updateHeight(from: result)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == CookedHTMLView.heightMessageName else { return }
            updateHeight(from: message.body)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if url.host == Endpoints.baseURL.host,
                   let topicID = Self.topicID(from: url),
                   let onOpenTopic = parent.onOpenTopic {
                    DispatchQueue.main.async {
                        onOpenTopic(topicID)
                    }
                    decisionHandler(.cancel)
                    return
                }
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // 仅允许初始 loadHTMLString 与站内图片等资源
            decisionHandler(.allow)
        }

        private static func topicID(from url: URL) -> Int? {
            guard url.pathComponents.contains("t") else { return nil }
            return url.pathComponents.compactMap(Int.init).first
        }

        private func updateHeight(from value: Any?) {
            let height = (value as? CGFloat)
                ?? (value as? Double).map { CGFloat($0) }
                ?? (value as? NSNumber).map { CGFloat(truncating: $0) }
                ?? 120
            DispatchQueue.main.async { [weak self] in
                guard let reporting = self?.webView else { return }
                reporting.contentHeight = max(48, min(height + 12, 5000))
            }
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
            --subtle-bg: rgba(127,127,127,0.08);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --text: #f5f5f7;
              --muted: #a1a1a6;
              --link: #6cb6ff;
              --code-bg: rgba(255,255,255,0.08);
              --quote-border: rgba(255,255,255,0.25);
              --subtle-bg: rgba(255,255,255,0.055);
            }
          }
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: var(--text);
            font: 15px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            -webkit-font-smoothing: antialiased;
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
            margin: 0.8em 0;
            padding: 0.55em 0.8em 0.55em 0.9em;
            border-left: 3px solid var(--quote-border);
            border-radius: 0 8px 8px 0;
            background: var(--subtle-bg);
            color: var(--muted);
          }
          p { margin: 0.6em 0; }
          ul, ol { padding-left: 1.4em; }
          hr { border: 0; border-top: 1px solid var(--quote-border); margin: 1.2em 0; }
          table { width: 100%; border-collapse: collapse; margin: 0.8em 0; }
          th, td { border-bottom: 1px solid var(--quote-border); padding: 0.45em 0.6em; text-align: left; }
          aside.quote, .onebox {
            background: var(--subtle-bg);
            border-radius: 9px;
            padding: 10px 12px;
            margin: 0.8em 0;
          }
          .emoji, img.emoji { width: 1.15em; height: 1.15em; vertical-align: -0.15em; border-radius: 0; }
          aside.quote .title { font-size: 12px; color: var(--muted); margin-bottom: 4px; }
          .lightbox-wrapper {
            display: block;
            width: fit-content;
            max-width: 100%;
            margin: 0.8em 0;
            line-height: 0;
          }
          .lightbox-wrapper > a.lightbox,
          a.lightbox {
            display: block;
            width: fit-content;
            max-width: 100%;
            line-height: 0;
          }
          .lightbox-wrapper img,
          a.lightbox img {
            display: block;
            margin: 0;
          }
          .lightbox-wrapper .meta,
          a.lightbox .meta {
            display: none !important;
          }
          .image-unavailable {
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 72px;
            min-width: min(320px, 100%);
            box-sizing: border-box;
            padding: 16px;
            margin: 0.8em 0;
            border: 1px dashed var(--quote-border);
            border-radius: 8px;
            background: var(--subtle-bg);
            color: var(--muted);
            font-size: 13px;
            line-height: 1.4;
          }
        </style>
        </head>
        <body>
        \(body)
        <script>
          (() => {
            let reportScheduled = false;

            const reportHeight = () => {
              if (reportScheduled) return;
              reportScheduled = true;
              requestAnimationFrame(() => {
                reportScheduled = false;
                const height = Math.max(
                  document.body.scrollHeight,
                  document.documentElement.scrollHeight
                );
                window.webkit?.messageHandlers?.contentHeight?.postMessage(height);
              });
            };

            const normalizeImages = () => {
              document
                .querySelectorAll('.lightbox-wrapper .meta, a.lightbox .meta')
                .forEach((meta) => meta.remove());

              document.querySelectorAll('img:not(.emoji)').forEach((image) => {
                if (image.dataset.ldoObserved === '1') return;
                if (!image.currentSrc && !image.getAttribute('src')) return;
                image.dataset.ldoObserved = '1';

                image.addEventListener('load', reportHeight);
                image.addEventListener('error', () => {
                  const wrapper = image.closest('.lightbox-wrapper');
                  if (wrapper) {
                    const fallback = document.createElement('div');
                    fallback.className = 'image-unavailable';
                    fallback.textContent = '图片暂时无法加载';
                    wrapper.replaceWith(fallback);
                  } else {
                    image.remove();
                  }
                  reportHeight();
                }, { once: true });

                if (image.complete) {
                  if (image.naturalWidth > 0) {
                    reportHeight();
                  } else {
                    image.dispatchEvent(new Event('error'));
                  }
                }
              });
            };

            const start = () => {
              normalizeImages();
              new ResizeObserver(reportHeight).observe(document.body);
              new MutationObserver(() => {
                normalizeImages();
                reportHeight();
              }).observe(document.body, { childList: true, subtree: true });
              reportHeight();
            };

            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', start, { once: true });
            } else {
              start();
            }
          })();
        </script>
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
