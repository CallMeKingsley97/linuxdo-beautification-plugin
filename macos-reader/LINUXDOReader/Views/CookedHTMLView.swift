//
//  CookedHTMLView.swift
//  使用 WKWebView 沙箱渲染 Discourse cooked HTML
//

import SwiftUI
import AppKit
import WebKit

struct CookedHTMLView: NSViewRepresentable {
    private static let heightMessageName = "contentHeight"
    private static let contentDataStore = WKWebsiteDataStore.nonPersistent()
    private static let heightCache = NSCache<NSNumber, NSNumber>()

    let contentID: Int
    let html: String
    var onOpenTopic: ((Int) -> Void)?

    init(contentID: Int, html: String, onOpenTopic: ((Int) -> Void)? = nil) {
        self.contentID = contentID
        self.html = html
        self.onOpenTopic = onOpenTopic
    }

    func makeNSView(context: Context) -> HeightReportingWebView {
        let config = WKWebViewConfiguration()
        // cooked HTML 来自 linux.do；允许 JS 以便测量高度与部分媒体表现
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = false
        config.websiteDataStore = Self.contentDataStore
        config.userContentController.add(context.coordinator, name: Self.heightMessageName)

        let webView = HeightReportingWebView(frame: .zero, configuration: config)
        let cachedHeight = Self.cachedHeight(for: contentID)
        webView.contentHeight = cachedHeight
        context.coordinator.lastHeight = cachedHeight
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.configureForEmbeddedDocument()
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
            let cachedHeight = Self.cachedHeight(for: contentID)
            context.coordinator.lastHeight = cachedHeight
            webView.contentHeight = cachedHeight
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
        nsView.navigationDelegate = nil
        nsView.stopLoading()
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CookedHTMLView
        var lastHTML: String?
        var lastHeight: CGFloat = 80
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
            let contentHeight = max(48, min(height + 12, 5000))
            guard abs(lastHeight - contentHeight) > 0.5 else { return }
            lastHeight = contentHeight
            CookedHTMLView.heightCache.setObject(
                NSNumber(value: Double(contentHeight)),
                forKey: NSNumber(value: parent.contentID)
            )
            DispatchQueue.main.async { [weak self] in
                guard let reporting = self?.webView else { return }
                reporting.contentHeight = contentHeight
            }
        }
    }

    private static func cachedHeight(for contentID: Int) -> CGFloat {
        heightCache.object(forKey: NSNumber(value: contentID))
            .map { CGFloat(truncating: $0) }
            ?? 80
    }

    fileprivate static func wrapHTML(
        _ body: String,
        additionalHead: String = "",
        additionalScript: String = ""
    ) -> String {
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
        \(additionalHead)
        </head>
        <body>
        \(body)
        <script>
          (() => {
            let reportScheduled = false;
            let lastReportedHeight = { value: 0 };

            const reportHeight = () => {
              if (reportScheduled) return;
              reportScheduled = true;
              requestAnimationFrame(() => {
                reportScheduled = false;
                const height = Math.max(
                  document.body.scrollHeight,
                  document.documentElement.scrollHeight
                );
                if (Math.abs(lastReportedHeight.value - height) < 1) return;
                lastReportedHeight.value = height;
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
              reportHeight();
            };

            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', start, { once: true });
            } else {
              start();
            }
          })();
        </script>
        \(additionalScript)
        </body>
        </html>
        """
    }
}

/// 将一个主题的楼层合并到单个 WKWebView，避免多 WebView 嵌套滚动和合成开销。
struct TopicDocumentWebView: NSViewRepresentable {
    private static let replyMessageName = "replyPost"
    private static let userProfileMessageName = "openUserProfile"
    private static let readingVisibilityMessageName = "readingVisibility"
    // 与登录/请求 WebView 共用会话，确保等级受限帖子中的图片也能携带站内 Cookie。
    private static let contentDataStore = WKWebsiteDataStore.default()

    let detail: TopicDetail
    let followedUsernames: Set<String>
    let followedHighlightEnabled: Bool
    let followedColorHex: String
    let readPostNumbers: Set<Int>
    let reportingPostNumbers: Set<Int>
    let targetPostNumber: Int?
    var onOpenTopic: ((Int) -> Void)?
    var onOpenUser: ((PostItem) -> Void)?
    var onReply: ((PostItem) -> Void)?
    var onVisiblePostsChanged: ((Set<Int>) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.websiteDataStore = Self.contentDataStore
        configuration.userContentController.add(
            context.coordinator,
            name: Self.replyMessageName
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Self.userProfileMessageName
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Self.readingVisibilityMessageName
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        webView.customUserAgent = SiteSessionStore.compatibleSafariUserAgent
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let signature = documentSignature
        guard context.coordinator.lastSignature != signature else {
            context.coordinator.syncReadState(in: webView)
            context.coordinator.scrollToTargetIfNeeded(in: webView)
            return
        }

        let targetKey = targetPostNumber.map { "\(detail.id):\($0)" }
        let shouldRestoreScroll = context.coordinator.lastTopicID == detail.id
            && context.coordinator.lastSignature != nil
            && (targetPostNumber == nil || context.coordinator.lastScrolledTarget == targetKey)
        if context.coordinator.lastTopicID != detail.id {
            context.coordinator.lastScrolledTarget = nil
        }
        context.coordinator.lastSignature = signature
        context.coordinator.lastTopicID = detail.id
        context.coordinator.documentReady = false
        context.coordinator.lastReadStateSignature = nil
        let page = Self.documentHTML(
            detail: detail,
            followedUsernames: followedUsernames,
            followedHighlightEnabled: followedHighlightEnabled,
            followedColorHex: followedColorHex,
            readPostNumbers: readPostNumbers,
            reportingPostNumbers: reportingPostNumbers
        )

        if shouldRestoreScroll {
            webView.evaluateJavaScript("window.scrollY") { result, _ in
                context.coordinator.pendingScrollY = Self.number(from: result)
                webView.loadHTMLString(page, baseURL: Endpoints.baseURL)
            }
        } else {
            // WKWebView 在连续 loadHTMLString 时可能沿用上一主题的滚动偏移；
            // 新主题必须回到顶部，否则会把错误楼层误判为当前可见并上报已读。
            context.coordinator.pendingScrollY = 0
            webView.loadHTMLString(page, baseURL: Endpoints.baseURL)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.replyMessageName
        )
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.userProfileMessageName
        )
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.readingVisibilityMessageName
        )
        nsView.navigationDelegate = nil
        nsView.stopLoading()
    }

    private var documentSignature: String {
        let posts = detail.posts.map {
            "\($0.id):\($0.cookedHTML.hashValue):\($0.acceptedAnswer)"
        }.joined(separator: "|")
        let followed = followedHighlightEnabled
            ? followedUsernames.sorted().joined(separator: ",")
            : "disabled"
        return "\(detail.id)|\(posts)|\(followed)|\(followedColorHex)"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TopicDocumentWebView
        var lastSignature: String?
        var lastTopicID: Int?
        var pendingScrollY: Double?
        var documentReady = false
        var lastReadStateSignature: String?
        var lastScrolledTarget: String?

        init(_ parent: TopicDocumentWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            documentReady = true
            if let pendingScrollY {
                self.pendingScrollY = nil
                webView.evaluateJavaScript(
                    "window.scrollTo({ top: \(pendingScrollY), behavior: 'auto' });"
                )
            }
            scrollToTargetIfNeeded(in: webView)
            syncReadState(in: webView, force: true)
        }

        func scrollToTargetIfNeeded(in webView: WKWebView) {
            guard documentReady,
                  let postNumber = parent.targetPostNumber,
                  postNumber > 0 else { return }
            let key = "\(parent.detail.id):\(postNumber)"
            guard lastScrolledTarget != key else { return }
            let script = """
            (() => {
              const element = document.getElementById('post-\(postNumber)');
              if (!element) return false;
              element.scrollIntoView({ block: 'start', behavior: 'auto' });
              window.scrollBy(0, -12);
              return true;
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] value, _ in
                guard (value as? Bool) == true else { return }
                self?.lastScrolledTarget = key
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case TopicDocumentWebView.replyMessageName:
                guard let postNumber = TopicDocumentWebView.integer(from: message.body),
                      let post = parent.detail.posts.first(where: {
                          $0.postNumber == postNumber
                      }),
                      let onReply = parent.onReply else { return }
                DispatchQueue.main.async {
                    onReply(post)
                }
            case TopicDocumentWebView.userProfileMessageName:
                guard let postNumber = TopicDocumentWebView.integer(from: message.body),
                      let post = parent.detail.posts.first(where: {
                          $0.postNumber == postNumber
                      }),
                      let onOpenUser = parent.onOpenUser else { return }
                DispatchQueue.main.async {
                    onOpenUser(post)
                }
            case TopicDocumentWebView.readingVisibilityMessageName:
                guard let postNumbers = TopicDocumentWebView.postNumbers(from: message.body),
                      let onVisiblePostsChanged = parent.onVisiblePostsChanged else { return }
                DispatchQueue.main.async {
                    onVisiblePostsChanged(postNumbers)
                }
            default:
                break
            }
        }

        func syncReadState(in webView: WKWebView, force: Bool = false) {
            guard documentReady else { return }
            let read = parent.readPostNumbers.sorted()
            let reporting = parent.reportingPostNumbers.sorted()
            let signature = "\(read.map(String.init).joined(separator: ","))|\(reporting.map(String.init).joined(separator: ","))"
            guard force || signature != lastReadStateSignature else { return }
            lastReadStateSignature = signature

            let script = "window.LDOReading?.setState(\(TopicDocumentWebView.javaScriptArray(read)), \(TopicDocumentWebView.javaScriptArray(reporting)));"
            webView.evaluateJavaScript(script)
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
            decisionHandler(.allow)
        }

        private static func topicID(from url: URL) -> Int? {
            guard url.pathComponents.contains("t") else { return nil }
            return url.pathComponents.compactMap(Int.init).first
        }
    }

    private static func documentHTML(
        detail: TopicDetail,
        followedUsernames: Set<String>,
        followedHighlightEnabled: Bool,
        followedColorHex: String,
        readPostNumbers: Set<Int>,
        reportingPostNumbers: Set<Int>
    ) -> String {
        let stateBadges = [
            detail.pinned ? badgeHTML("置顶", className: "status-warning") : nil,
            detail.closed ? badgeHTML("已关闭", className: "status-muted") : nil,
            detail.archived ? badgeHTML("已归档", className: "status-muted") : nil,
        ].compactMap { $0 }.joined()
        let tags = detail.tags.prefix(4).map {
            badgeHTML($0, className: "status-muted")
        }.joined()
        let posts = detail.posts.map { post in
            postHTML(
                post,
                followedUsernames: followedUsernames,
                followedHighlightEnabled: followedHighlightEnabled,
                readPostNumbers: readPostNumbers,
                reportingPostNumbers: reportingPostNumbers
            )
        }.joined(separator: "")

        let body = """
        <main class="topic-document" style="--follow-color: \(safeColor(followedColorHex));">
          <header class="topic-header">
            <h1>\(escapeHTML(detail.title))</h1>
            <div class="topic-meta">
              \(stateBadges)
              <span class="post-count">\(detail.postsCount.formatted()) 层</span>
              \(tags)
            </div>
          </header>
          <section class="post-stream">\(posts)</section>
        </main>
        """

        let documentCSS = """
        <style>
          html, body { min-height: 100%; }
          body { overflow-y: auto; }
          .topic-document {
            width: 100%;
            max-width: 860px;
            margin: 0 auto;
          }
          .topic-header {
            padding: 20px 24px;
          }
          .topic-header h1 {
            margin: 0;
            font-size: 22px;
            line-height: 1.25;
            font-weight: 650;
            letter-spacing: -0.01em;
          }
          .topic-meta {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 6px;
            margin-top: 12px;
            color: var(--muted);
            font-size: 12px;
          }
          .status-badge {
            display: inline-flex;
            align-items: center;
            min-height: 20px;
            box-sizing: border-box;
            padding: 2px 7px;
            border-radius: 999px;
            font-size: 11px;
            font-weight: 600;
            line-height: 1.2;
          }
          .status-muted { color: var(--muted); background: var(--subtle-bg); }
          .status-warning { color: #b56b00; background: rgba(255, 159, 10, 0.12); }
          .status-success {
            color: color-mix(in srgb, var(--follow-color) 82%, var(--text));
            background: color-mix(in srgb, var(--follow-color) 13%, transparent);
          }
          .post-stream { border-top: 1px solid var(--quote-border); }
          .post {
            position: relative;
            display: grid;
            grid-template-columns: 36px minmax(0, 1fr);
            gap: 12px;
            padding: 18px 24px;
            border-bottom: 1px solid var(--quote-border);
          }
          .post.followed {
            background: color-mix(in srgb, var(--follow-color) 8%, transparent);
            box-shadow: inset 3px 0 0 var(--follow-color);
          }
          .avatar {
            width: 36px;
            height: 36px;
            border-radius: 50%;
            object-fit: cover;
            background: var(--subtle-bg);
          }
          .avatar-fallback {
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--muted);
            font-size: 14px;
            font-weight: 650;
          }
          .profile-button {
            appearance: none;
            border: 0;
            padding: 0;
            color: inherit;
            background: transparent;
            font: inherit;
            text-align: left;
            cursor: pointer;
          }
          .profile-button:focus-visible {
            outline: 2px solid var(--link);
            outline-offset: 2px;
          }
          .avatar-button {
            width: 36px;
            height: 36px;
            border-radius: 50%;
          }
          .avatar-button:hover .avatar { filter: brightness(0.94); }
          .post-main { min-width: 0; }
          .post-heading {
            display: flex;
            align-items: flex-start;
            gap: 8px;
            padding-right: 34px;
          }
          .author-line {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 6px;
            font-size: 13px;
          }
          .author-name { font-weight: 650; }
          .author-name:hover { color: var(--link); }
          .username { color: var(--muted); font-size: 12px; }
          .post-metadata {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 7px;
            margin-top: 3px;
            color: var(--muted);
            font-size: 11px;
          }
          .read-indicator {
            display: inline-block;
            width: 8px;
            height: 8px;
            flex: 0 0 8px;
            border-radius: 50%;
            background: #248a3d;
            box-shadow: 0 0 0 0.5px rgba(0, 0, 0, 0.08);
            opacity: 1;
            transform: scale(1);
            transition: opacity 1.2s ease-in-out, transform 1.2s ease-in-out;
          }
          .post.is-read .read-indicator {
            opacity: 0;
            transform: scale(0.72);
          }
          .post.is-reporting:not(.is-read) .read-indicator {
            animation: reading-pulse 1.4s ease-in-out infinite;
          }
          @keyframes reading-pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.35; }
          }
          @media (prefers-color-scheme: dark) {
            .read-indicator {
              background: #30d158;
              box-shadow: 0 0 0 0.5px rgba(255, 255, 255, 0.12);
            }
          }
          .reply-button {
            position: absolute;
            top: 17px;
            right: 22px;
            border: 0;
            border-radius: 6px;
            padding: 4px 6px;
            color: var(--muted);
            background: transparent;
            font: inherit;
            cursor: pointer;
          }
          .reply-button:hover { color: var(--text); background: var(--subtle-bg); }
          .post-body { margin-top: 10px; }
          .post-body > :first-child { margin-top: 0; }
          .post-body > :last-child { margin-bottom: 0; }
          @media (max-width: 620px) {
            .topic-header { padding: 16px; }
            .post { padding: 16px; grid-template-columns: 32px minmax(0, 1fr); }
            .avatar, .avatar-button { width: 32px; height: 32px; }
            .reply-button { right: 12px; }
          }
        </style>
        """

        let interactionScript = """
        <script>
          document.addEventListener('click', (event) => {
            const button = event.target.closest('.reply-button');
            if (button) {
              const postNumber = Number(button.dataset.postNumber || 0);
              if (postNumber > 0) {
                window.webkit?.messageHandlers?.replyPost?.postMessage(postNumber);
              }
              return;
            }

            const profileButton = event.target.closest('[data-profile-post-number]');
            if (profileButton) {
              const postNumber = Number(profileButton.dataset.profilePostNumber || 0);
              if (postNumber > 0) {
                window.webkit?.messageHandlers?.openUserProfile?.postMessage(postNumber);
              }
            }
          });

          (() => {
            const articles = Array.from(document.querySelectorAll('.post[data-post-number]'));
            let visibilityTimer = 0;

            const visiblePostNumbers = () => {
              const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
              return articles.reduce((numbers, article) => {
                const rect = article.getBoundingClientRect();
                const visiblePixels = Math.max(
                  0,
                  Math.min(rect.bottom, viewportHeight) - Math.max(rect.top, 0)
                );
                const requiredPixels = Math.min(120, Math.max(48, rect.height * 0.25));
                const postNumber = Number(article.dataset.postNumber || 0);
                if (postNumber > 0 && visiblePixels >= requiredPixels) {
                  numbers.push(postNumber);
                }
                return numbers;
              }, []);
            };

            const reportVisibility = () => {
              visibilityTimer = 0;
              window.webkit?.messageHandlers?.readingVisibility?.postMessage({
                postNumbers: visiblePostNumbers()
              });
            };

            const scheduleVisibilityReport = () => {
              if (visibilityTimer) return;
              visibilityTimer = window.setTimeout(() => {
                window.requestAnimationFrame(reportVisibility);
              }, 180);
            };

            window.LDOReading = {
              setState(readPostNumbers, reportingPostNumbers) {
                const read = new Set((readPostNumbers || []).map(Number));
                const reporting = new Set((reportingPostNumbers || []).map(Number));
                for (const article of articles) {
                  const postNumber = Number(article.dataset.postNumber || 0);
                  const isRead = read.has(postNumber);
                  article.classList.toggle('is-read', isRead);
                  article.classList.toggle(
                    'is-reporting',
                    reporting.has(postNumber) && !isRead
                  );
                  const indicator = article.querySelector('.read-indicator');
                  if (indicator) {
                    indicator.setAttribute('aria-hidden', isRead ? 'true' : 'false');
                    if (isRead) {
                      indicator.removeAttribute('title');
                    } else {
                      indicator.setAttribute('role', 'status');
                      indicator.setAttribute('aria-label', '未读楼层');
                      indicator.setAttribute('title', '停留后同步阅读状态');
                    }
                  }
                }
              },
              reportVisibility
            };

            window.addEventListener('scroll', scheduleVisibilityReport, { passive: true });
            window.addEventListener('resize', scheduleVisibilityReport, { passive: true });
            document.addEventListener('visibilitychange', scheduleVisibilityReport);
            window.requestAnimationFrame(reportVisibility);
          })();
        </script>
        """

        return CookedHTMLView.wrapHTML(
            body,
            additionalHead: documentCSS,
            additionalScript: interactionScript
        )
    }

    private static func postHTML(
        _ post: PostItem,
        followedUsernames: Set<String>,
        followedHighlightEnabled: Bool,
        readPostNumbers: Set<Int>,
        reportingPostNumbers: Set<Int>
    ) -> String {
        let normalizedUsername = post.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        let isFollowed = followedHighlightEnabled
            && followedUsernames.contains(normalizedUsername)
        let displayName = post.name?.isEmpty == false ? post.name! : post.username
        let username = post.name?.isEmpty == false && post.name != post.username
            ? "<span class=\"username\">@\(escapeHTML(post.username))</span>"
            : ""
        let acceptedBadge = post.acceptedAnswer
            ? badgeHTML("已采纳", className: "status-success")
            : ""
        let followedBadge = isFollowed
            ? badgeHTML("已关注", className: "status-success")
            : ""
        let replyMetadata = post.replyToPostNumber.map {
            "<span>回复 #\($0)</span>"
        } ?? ""
        let createdAt = post.createdAt.map {
            escapeHTML($0.formatted(date: .abbreviated, time: .shortened))
        } ?? ""
        let avatar = avatarHTML(post)
        let followedClass = isFollowed ? " followed" : ""
        let isRead = readPostNumbers.contains(post.postNumber)
        let readClass = isRead ? " is-read" : ""
        let reportingClass = reportingPostNumbers.contains(post.postNumber) ? " is-reporting" : ""
        let indicatorAccessibility = isRead
            ? "aria-hidden=\"true\""
            : "role=\"status\" aria-label=\"未读楼层\" title=\"停留后同步阅读状态\""

        return """
        <article class="post\(followedClass)\(readClass)\(reportingClass)" id="post-\(post.postNumber)" data-post-number="\(post.postNumber)">
          \(avatar)
          <div class="post-main">
            <div class="post-heading">
              <div>
                <div class="author-line">
                  <button class="profile-button author-name" data-profile-post-number="\(post.postNumber)" aria-label="查看 \(escapeAttribute(displayName)) 的资料">\(escapeHTML(displayName))</button>
                  \(username)\(acceptedBadge)\(followedBadge)
                </div>
                <div class="post-metadata">
                  <span>#\(post.postNumber)</span><span>\(createdAt)</span><span class="read-indicator" \(indicatorAccessibility)></span>\(replyMetadata)
                </div>
              </div>
            </div>
            <button class="reply-button" data-post-number="\(post.postNumber)" aria-label="回复 #\(post.postNumber)" title="回复 #\(post.postNumber)">↩︎</button>
            <div class="post-body">\(post.cookedHTML)</div>
          </div>
        </article>
        """
    }

    private static func avatarHTML(_ post: PostItem) -> String {
        let label = escapeAttribute("查看 \(post.name?.isEmpty == false ? post.name! : post.username) 的资料")
        if let template = post.avatarTemplate,
           let url = Endpoints.avatarURL(template: template, size: 72) {
            return "<button class=\"profile-button avatar-button\" data-profile-post-number=\"\(post.postNumber)\" aria-label=\"\(label)\"><img class=\"avatar\" src=\"\(escapeAttribute(url.absoluteString))\" alt=\"\"></button>"
        }
        let initial = escapeHTML(String((post.name ?? post.username).prefix(1)).uppercased())
        return "<button class=\"profile-button avatar-button\" data-profile-post-number=\"\(post.postNumber)\" aria-label=\"\(label)\"><span class=\"avatar avatar-fallback\" aria-hidden=\"true\">\(initial)</span></button>"
    }

    private static func badgeHTML(_ text: String, className: String) -> String {
        "<span class=\"status-badge \(className)\">\(escapeHTML(text))</span>"
    }

    private static func safeColor(_ value: String) -> String {
        value.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
            ? value
            : "#40B883"
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value)
    }

    private static func number(from value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func integer(from value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func postNumbers(from value: Any?) -> Set<Int>? {
        guard let payload = value as? [String: Any],
              let values = payload["postNumbers"] as? [Any] else { return nil }
        return Set(values.compactMap(integer(from:)))
    }

    private static func javaScriptArray(_ values: [Int]) -> String {
        "[\(values.map(String.init).joined(separator: ","))]"
    }
}

/// 根据内容高度报告 intrinsicContentSize，便于嵌在 ScrollView 中
final class HeightReportingWebView: WKWebView {
    private var isRegisteredForScrollRouting = false

    var contentHeight: CGFloat = 80 {
        didSet {
            guard abs(oldValue - contentHeight) > 0.5 else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureForEmbeddedDocument()
        if window == nil, isRegisteredForScrollRouting {
            EmbeddedWebViewScrollRouter.shared.unregister()
            isRegisteredForScrollRouting = false
        } else if window != nil, !isRegisteredForScrollRouting {
            EmbeddedWebViewScrollRouter.shared.register()
            isRegisteredForScrollRouting = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldForwardVertically(event), let outerScrollView {
            outerScrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    deinit {
        if isRegisteredForScrollRouting {
            EmbeddedWebViewScrollRouter.shared.unregister()
        }
    }

    fileprivate func shouldForwardVertically(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaY) > 0
            && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
    }

    fileprivate var outerScrollView: NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            ancestor = view.superview
        }
        return nil
    }

    func configureForEmbeddedDocument() {
        guard let internalScrollView = descendantScrollView(in: self) else { return }
        internalScrollView.hasVerticalScroller = false
        internalScrollView.hasHorizontalScroller = false
        internalScrollView.verticalScrollElasticity = .none
        internalScrollView.horizontalScrollElasticity = .none
    }

    private func descendantScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                return scrollView
            }
            if let nested = descendantScrollView(in: subview) {
                return nested
            }
        }
        return nil
    }
}

private final class EmbeddedWebViewScrollRouter {
    static let shared = EmbeddedWebViewScrollRouter()

    private var registrationCount = 0
    private var eventMonitor: Any?

    func register() {
        registrationCount += 1
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard abs(event.scrollingDeltaY) > 0,
                  abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
                  let contentView = event.window?.contentView,
                  var hitView = contentView.hitTest(event.locationInWindow) else {
                return event
            }

            while true {
                if let webView = hitView as? HeightReportingWebView,
                   webView.shouldForwardVertically(event),
                   let outerScrollView = webView.outerScrollView {
                    outerScrollView.scrollWheel(with: event)
                    return nil
                }
                guard let superview = hitView.superview else { return event }
                hitView = superview
            }
        }
    }

    func unregister() {
        registrationCount = max(0, registrationCount - 1)
        guard registrationCount == 0, let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}
