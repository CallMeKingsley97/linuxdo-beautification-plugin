//
//  CookedHTMLView.swift
//  使用 WKWebView 沙箱渲染 Discourse cooked HTML
//

import SwiftUI
import AppKit
import WebKit

enum PostMenuAction: String {
    case like
    case reactions
    case copyLink
    case share
    case boost
    case more
    case bookmark
    case report
    case edit
    case delete
    case recover
    case wiki
    case solution
    case sharedIssue
    case reply
}

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
            --surface: rgba(255,255,255,0.62);
            --surface-border: rgba(0,0,0,0.12);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --text: #f5f5f7;
              --muted: #a1a1a6;
              --link: #6cb6ff;
              --code-bg: rgba(255,255,255,0.08);
              --quote-border: rgba(255,255,255,0.25);
              --subtle-bg: rgba(255,255,255,0.055);
              --surface: rgba(255,255,255,0.045);
              --surface-border: rgba(255,255,255,0.085);
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
            border-radius: 8px;
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
    private static let postActionMessageName = "postAction"
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
    let runningPostActions: [Int: Set<PostActionKind>]
    let isLoggedIn: Bool
    let targetPostNumber: Int?
    var onOpenTopic: ((Int) -> Void)?
    var onOpenUser: ((PostItem) -> Void)?
    var onReply: ((PostItem) -> Void)?
    var onPostAction: ((PostItem, PostMenuAction) -> Void)?
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
            name: Self.postActionMessageName
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
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let signature = documentSignature
        guard context.coordinator.lastSignature != signature else {
            context.coordinator.syncReadState(in: webView)
            context.coordinator.syncInteractionState(in: webView)
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
        context.coordinator.lastInteractionStateSignature = nil
        let page = Self.documentHTML(
            detail: detail,
            followedUsernames: followedUsernames,
            followedHighlightEnabled: followedHighlightEnabled,
            followedColorHex: followedColorHex,
            readPostNumbers: readPostNumbers,
            reportingPostNumbers: reportingPostNumbers,
            runningPostActions: runningPostActions,
            isLoggedIn: isLoggedIn
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
            forName: Self.postActionMessageName
        )
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.userProfileMessageName
        )
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.readingVisibilityMessageName
        )
        nsView.navigationDelegate = nil
        nsView.stopLoading()
        coordinator.webView = nil
    }

    private var documentSignature: String {
        let posts = detail.posts.map {
            "\($0.id):\($0.cookedHTML.hashValue):\($0.acceptedAnswer):\($0.hidden):\($0.deletedAt?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "|")
        let followed = followedHighlightEnabled
            ? followedUsernames.sorted().joined(separator: ",")
            : "disabled"
        return "\(detail.id)|\(posts)|\(followed)|\(followedColorHex)|\(detail.sharedIssueVisible)|\(detail.canCreatePost)|\(isLoggedIn)"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TopicDocumentWebView
        var lastSignature: String?
        var lastTopicID: Int?
        var pendingScrollY: Double?
        var documentReady = false
        var lastReadStateSignature: String?
        var lastInteractionStateSignature: String?
        var lastScrolledTarget: String?
        weak var webView: WKWebView?
        private var sharingPicker: NSSharingServicePicker?
        private var lastMenuAnchor = NSPoint.zero

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
            syncInteractionState(in: webView, force: true)
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
            case TopicDocumentWebView.postActionMessageName:
                handlePostActionMessage(message.body)
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

        func syncInteractionState(in webView: WKWebView, force: Bool = false) {
            guard documentReady else { return }
            let payload = TopicDocumentWebView.interactionStateJSON(
                detail: parent.detail,
                runningPostActions: parent.runningPostActions,
                isLoggedIn: parent.isLoggedIn
            )
            guard force || payload != lastInteractionStateSignature else { return }
            lastInteractionStateSignature = payload
            webView.evaluateJavaScript("window.LDOActions?.setState(\(payload));")
        }

        private func handlePostActionMessage(_ body: Any) {
            guard let payload = body as? [String: Any],
                  let postNumber = TopicDocumentWebView.integer(from: payload["postNumber"]),
                  let rawAction = payload["action"] as? String,
                  let action = PostMenuAction(rawValue: rawAction),
                  let post = parent.detail.posts.first(where: {
                      $0.postNumber == postNumber
                  }) else { return }

            if action == .more, let webView {
                if let rect = payload["rect"] as? [String: Any] {
                    let x = TopicDocumentWebView.number(from: rect["x"]) ?? 0
                    let y = TopicDocumentWebView.number(from: rect["y"]) ?? 0
                    let height = TopicDocumentWebView.number(from: rect["height"]) ?? 0
                    lastMenuAnchor = webView.isFlipped
                        ? NSPoint(x: x, y: y + height)
                        : NSPoint(x: x, y: max(0, webView.bounds.height - y - height))
                }
                showMoreMenu(for: post, in: webView)
                return
            }

            if action == .copyLink {
                copyLink(for: post)
                return
            }

            dispatch(post: post, action: action)
        }

        private func showMoreMenu(for post: PostItem, in webView: WKWebView) {
            let menu = NSMenu(title: "楼层操作")
            addMenuItem(
                to: menu,
                title: "分享…",
                symbol: "square.and.arrow.up",
                action: .share,
                post: post
            )

            if post.canBookmark || post.bookmarked || !parent.isLoggedIn {
                addMenuItem(
                    to: menu,
                    title: post.bookmarked ? "编辑收藏…" : "收藏…",
                    symbol: post.bookmarked ? "bookmark.fill" : "bookmark",
                    action: .bookmark,
                    post: post
                )
            }
            if post.canFlag || !parent.isLoggedIn {
                addMenuItem(
                    to: menu,
                    title: "举报…",
                    symbol: "flag",
                    action: .report,
                    post: post
                )
            }

            let hasEditingActions = post.canEdit || post.canDelete || post.canRecover
                || post.canWiki || post.canAcceptAnswer
            if hasEditingActions {
                menu.addItem(.separator())
            }
            if post.canEdit {
                addMenuItem(
                    to: menu,
                    title: "编辑…",
                    symbol: "pencil",
                    action: .edit,
                    post: post
                )
            }
            if post.canAcceptAnswer {
                addMenuItem(
                    to: menu,
                    title: post.acceptedAnswer ? "取消采纳" : "采纳为解决方案",
                    symbol: post.acceptedAnswer ? "checkmark.square.fill" : "checkmark.square",
                    action: .solution,
                    post: post
                )
            }
            if post.canWiki {
                addMenuItem(
                    to: menu,
                    title: post.wiki ? "取消 Wiki" : "设为 Wiki",
                    symbol: "person.2.wave.2",
                    action: .wiki,
                    post: post
                )
            }
            if post.canRecover {
                addMenuItem(
                    to: menu,
                    title: "恢复帖子",
                    symbol: "arrow.uturn.backward",
                    action: .recover,
                    post: post
                )
            } else if post.canDelete {
                let item = addMenuItem(
                    to: menu,
                    title: "删除帖子…",
                    symbol: "trash",
                    action: .delete,
                    post: post
                )
                item.attributedTitle = NSAttributedString(
                    string: item.title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }

            menu.popUp(positioning: nil, at: lastMenuAnchor, in: webView)
        }

        @discardableResult
        private func addMenuItem(
            to menu: NSMenu,
            title: String,
            symbol: String,
            action: PostMenuAction,
            post: PostItem
        ) -> NSMenuItem {
            let item = NSMenuItem(
                title: title,
                action: #selector(performMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = post.postNumber
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            menu.addItem(item)
            return item
        }

        @objc private func performMenuAction(_ sender: NSMenuItem) {
            guard let rawAction = sender.representedObject as? String,
                  let action = PostMenuAction(rawValue: rawAction),
                  let post = parent.detail.posts.first(where: {
                      $0.postNumber == sender.tag
                  }) else { return }
            switch action {
            case .share:
                showSharePicker(for: post)
            case .copyLink:
                copyLink(for: post)
            default:
                dispatch(post: post, action: action)
            }
        }

        private func dispatch(post: PostItem, action: PostMenuAction) {
            if action == .reply, let onReply = parent.onReply {
                DispatchQueue.main.async { onReply(post) }
                return
            }
            guard let onPostAction = parent.onPostAction else { return }
            DispatchQueue.main.async { onPostAction(post, action) }
        }

        private func copyLink(for post: PostItem) {
            let url = TopicDocumentWebView.postURL(
                detail: parent.detail,
                postNumber: post.postNumber
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            webView?.evaluateJavaScript(
                "window.LDOActions?.feedback(\(post.postNumber), '已复制链接');"
            )
        }

        private func showSharePicker(for post: PostItem) {
            guard let webView else { return }
            let url = TopicDocumentWebView.postURL(
                detail: parent.detail,
                postNumber: post.postNumber
            )
            let picker = NSSharingServicePicker(items: [url])
            sharingPicker = picker
            picker.show(
                relativeTo: NSRect(origin: lastMenuAnchor, size: NSSize(width: 1, height: 1)),
                of: webView,
                preferredEdge: .minY
            )
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
        reportingPostNumbers: Set<Int>,
        runningPostActions: [Int: Set<PostActionKind>],
        isLoggedIn: Bool
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
                ownerUserID: detail.ownerUserID,
                ownerUsername: detail.ownerUsername,
                followedUsernames: followedUsernames,
                followedHighlightEnabled: followedHighlightEnabled,
                readPostNumbers: readPostNumbers,
                reportingPostNumbers: reportingPostNumbers,
                runningActions: runningPostActions[post.id] ?? [],
                canLike: post.canToggleLike || !isLoggedIn,
                canReply: detail.canCreatePost || !isLoggedIn,
                sharedIssueVisible: post.postNumber == 1 && detail.sharedIssueVisible,
                sharedIssueCreated: detail.userCreatedSharedIssue,
                sharedIssueCount: detail.sharedIssueCount,
                canCreateSharedIssue: detail.canCreateSharedIssue || detail.userCreatedSharedIssue || !isLoggedIn
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
          .discourse-icon {
            display: block;
            width: 16px;
            height: 16px;
            fill: currentColor;
          }
          html, body { min-height: 100%; }
          body { overflow-y: auto; }
          .topic-document {
            width: 100%;
            max-width: \(Int(LDOTheme.readerMaxWidth))px;
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
          .status-owner {
            color: color-mix(in srgb, var(--link) 82%, var(--text));
            background: color-mix(in srgb, var(--link) 14%, transparent);
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
          .post-body { margin-top: 10px; }
          .post-body > :first-child { margin-top: 0; }
          .post-body > :last-child { margin-bottom: 0; }
          .shared-issue-button {
            position: relative;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            margin-top: 12px;
            padding: 6px 10px;
            border: 1px solid var(--quote-border);
            border-radius: 8px;
            color: var(--muted);
            background: transparent;
            font: 13px/1.2 -apple-system, BlinkMacSystemFont, sans-serif;
            cursor: pointer;
          }
          .shared-issue-button:hover { color: var(--text); background: var(--subtle-bg); }
          .shared-issue-button.active { color: var(--link); border-color: color-mix(in srgb, var(--link) 38%, transparent); }
          .post-actions-footer {
            display: flex;
            min-height: 26px;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            margin-top: 12px;
          }
          .reaction-summary {
            display: inline-flex;
            min-width: 0;
            align-items: center;
            gap: 3px;
            color: var(--muted);
            font-size: 12px;
          }
          .reaction-summary:empty { display: none; }
          .reaction-emoji { font-size: 15px; line-height: 1; }
          .reaction-count { margin-left: 2px; font-variant-numeric: tabular-nums; }
          .post-action-buttons {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            margin-left: auto;
            padding: 0;
            border: 0;
            border-radius: 0;
            background: transparent;
            box-shadow: none;
          }
          .post-action-button {
            appearance: none;
            position: relative;
            display: inline-flex;
            width: 32px;
            height: 30px;
            box-sizing: border-box;
            align-items: center;
            justify-content: center;
            border: 0;
            border-radius: 8px;
            padding: 0;
            color: color-mix(in srgb, var(--muted) 78%, var(--text));
            background: transparent;
            cursor: pointer;
            transition: color 150ms ease, background-color 150ms ease, opacity 150ms ease;
          }
          .post-action-button[hidden] { display: none !important; }
          .post-action-button:hover:not(:disabled) {
            color: var(--text);
            background: color-mix(in srgb, var(--text) 0.065, transparent);
          }
          .post-action-button:active:not(:disabled) {
            background: color-mix(in srgb, var(--text) 0.105, transparent);
          }
          .post-action-button:focus-visible,
          .shared-issue-button:focus-visible {
            outline: 2px solid var(--link);
            outline-offset: 2px;
          }
          .post-action-button:disabled,
          .shared-issue-button:disabled { opacity: 0.42; cursor: default; }
          .like-button.active {
            color: #d70015;
            background: transparent;
          }
          .like-button.active:hover:not(:disabled) {
            background: rgba(215, 0, 21, 0.065);
          }
          .like-button .discourse-icon + .discourse-icon { display: none; }
          .like-button.active .discourse-icon + .discourse-icon { display: block; }
          .like-button.active .discourse-icon:first-of-type { display: none; }
          @media (prefers-color-scheme: dark) {
            .like-button.active {
              color: #ff453a;
              background: transparent;
            }
            .like-button.active:hover:not(:disabled) {
              background: rgba(255, 69, 58, 0.105);
            }
          }
          @media (prefers-reduced-motion: reduce) {
            .post-action-button,
            .shared-issue-button {
              transition: none;
            }
          }
          .post-action-button.loading::after,
          .shared-issue-button.loading::after {
            content: '';
            position: absolute;
            width: 10px;
            height: 10px;
            margin: -5px 0 0 -5px;
            left: 50%;
            top: 50%;
            border: 1.25px solid currentColor;
            border-right-color: transparent;
            border-radius: 50%;
            animation: action-spin 0.8s linear infinite;
          }
          .post-action-button.loading > span,
          .shared-issue-button.loading > span { opacity: 0; }
          @keyframes action-spin { to { transform: rotate(360deg); } }
          .boost-row {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 6px;
            margin-top: 6px;
          }
          .boost-row:empty { display: none; }
          .boost-row-button {
            margin-left: 4px;
            border: 0;
            background: transparent;
          }
          .boost-row-button:hover:not(:disabled) {
            border-color: transparent;
          }
          .boost-pill {
            display: inline-flex;
            max-width: 72%;
            align-items: center;
            gap: 6px;
            box-sizing: border-box;
            padding: 3px 9px 3px 4px;
            border-radius: 999px;
            color: var(--muted);
            background: var(--subtle-bg);
            font-size: 12px;
          }
          .boost-avatar {
            width: 20px;
            height: 20px;
            flex: 0 0 20px;
            border-radius: 50%;
            object-fit: cover;
          }
          .boost-content {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .boost-content img { width: 16px; height: 16px; border-radius: 0; vertical-align: -3px; }
          .action-feedback {
            position: absolute;
            right: 24px;
            bottom: 8px;
            z-index: 3;
            padding: 5px 8px;
            border-radius: 7px;
            color: var(--text);
            background: color-mix(in srgb, var(--subtle-bg) 88%, var(--text) 12%);
            font-size: 11px;
            opacity: 0;
            transform: translateY(4px);
            pointer-events: none;
            transition: opacity 160ms ease, transform 160ms ease;
          }
          .action-feedback.visible { opacity: 1; transform: translateY(0); }
          @media (max-width: 620px) {
            .topic-header { padding: 16px; }
            .post { padding: 16px; grid-template-columns: 32px minmax(0, 1fr); }
            .avatar, .avatar-button { width: 32px; height: 32px; }
            .post-actions-footer { align-items: flex-end; }
          }
        </style>
        """

        let interactionScript = """
        <script>
          const sendPostAction = (button, actionOverride) => {
            const article = button.closest('.post[data-post-number]');
            const postNumber = Number(article?.dataset.postNumber || 0);
            const action = actionOverride || button.dataset.postAction || '';
            if (postNumber <= 0 || !action) return;
            const rect = button.getBoundingClientRect();
            window.webkit?.messageHandlers?.postAction?.postMessage({
              postNumber,
              action,
              rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
            });
          };

          let reactionHoldTimer = 0;
          let reactionHoldButton = null;
          let suppressLikeClick = false;

          document.addEventListener('click', (event) => {
            const actionButton = event.target.closest('[data-post-action]');
            if (actionButton) {
              if (suppressLikeClick && actionButton.classList.contains('like-button')) {
                suppressLikeClick = false;
                event.preventDefault();
                return;
              }
              sendPostAction(actionButton);
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

          document.addEventListener('pointerdown', (event) => {
            const button = event.target.closest('.like-button');
            if (!button || button.disabled) return;
            reactionHoldButton = button;
            reactionHoldTimer = window.setTimeout(() => {
              suppressLikeClick = true;
              sendPostAction(button, 'reactions');
              reactionHoldTimer = 0;
            }, 480);
          });

          const cancelReactionHold = () => {
            if (reactionHoldTimer) window.clearTimeout(reactionHoldTimer);
            reactionHoldTimer = 0;
            reactionHoldButton = null;
          };
          document.addEventListener('pointerup', cancelReactionHold);
          document.addEventListener('pointercancel', cancelReactionHold);
          document.addEventListener('pointermove', (event) => {
            if (reactionHoldButton && !reactionHoldButton.contains(event.target)) {
              cancelReactionHold();
            }
          });
          document.addEventListener('contextmenu', (event) => {
            const button = event.target.closest('.like-button');
            if (!button || button.disabled) return;
            event.preventDefault();
            cancelReactionHold();
            suppressLikeClick = false;
            sendPostAction(button, 'reactions');
          });

          (() => {
            const emojiFor = (id) => ({
              heart: '♥', '+1': '👍', laughing: '😆', open_mouth: '😮',
              clap: '👏', confetti_ball: '🎉', hugs: '🤗',
              distorted_face: '🫠', tieba_087: '😭', bili_057: '✨'
            })[id] || '●';
            const escapeHTML = (value) => String(value || '')
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;')
              .replaceAll('"', '&quot;')
              .replaceAll("'", '&#39;');
            const renderBoosts = (article, state) => {
              const row = article.querySelector('.boost-row');
              const inlineRocket = article.querySelector('.boost-inline-button');
              if (!row || !inlineRocket) return;
              const boosts = state.boosts || [];
              inlineRocket.hidden = boosts.length > 0 || !state.canBoost;
              const pills = boosts.map((boost) => {
                const avatar = boost.avatarURL
                  ? `<img class="boost-avatar" src="${escapeHTML(boost.avatarURL)}" alt="">`
                  : `<span class="boost-avatar avatar-fallback">${escapeHTML((boost.displayName || '?').slice(0, 1).toUpperCase())}</span>`;
                return `<span class="boost-pill" title="${escapeHTML(boost.displayName)}">${avatar}<span class="boost-content">${boost.cookedHTML || ''}</span></span>`;
              }).join('');
              const rocket = boosts.length > 0 && state.canBoost
                ? `<button class="post-action-button boost-row-button" data-post-action="boost" aria-label="Boost 此楼层" title="Boost 此楼层"><svg class="discourse-icon" viewBox="0 0 512 512" aria-hidden="true"><path d="M498.1 5.6c10.1 7 15.4 19.1 13.5 31.2l-64 416c-1.5 9.7-7.4 18.2-16 23s-18.9 5.4-28 1.6L284 427.7l-68.5 74.1c-8.9 9.7-22.9 12.9-35.2 8.1S160 493.2 160 480l0-83.6c0-4 1.5-7.8 4.2-10.8L331.8 202.8c5.8-6.3 5.6-16-.4-22s-15.7-6.4-22-.7L106 360.8 17.7 316.6C7.1 311.3 .3 300.7 0 288.9s5.9-22.8 16.1-28.7l448-256c10.7-6.1 23.9-5.5 34 1.4z"/></svg></button>`
                : '';
              row.innerHTML = pills + rocket;
            };

            window.LDOActions = {
              setState(payload) {
                for (const state of (payload?.posts || [])) {
                  const article = document.getElementById(`post-${state.postNumber}`);
                  if (!article) continue;
                  const running = new Set(state.running || []);
                  const like = article.querySelector('.like-button');
                  if (like) {
                    like.classList.toggle('active', Boolean(state.currentReaction || state.liked));
                    like.classList.toggle('loading', running.has('reaction'));
                    like.disabled = running.has('reaction') || !state.canLike;
                  }
                  const summary = article.querySelector('.reaction-summary');
                  if (summary) {
                    const reactions = (state.reactions || []).filter((item) => item.count > 0);
                    summary.innerHTML = reactions.map((item) => `<span class="reaction-emoji" title="${escapeHTML(item.id)}">${emojiFor(item.id)}</span>`).join('')
                      + (state.reactionUsersCount > 0 ? `<span class="reaction-count">${state.reactionUsersCount}</span>` : '');
                  }
                  renderBoosts(article, state);
                  const boostButtons = article.querySelectorAll('[data-post-action="boost"]');
                  boostButtons.forEach((button) => {
                    button.classList.toggle('loading', running.has('boost'));
                    button.disabled = running.has('boost');
                  });
                }

                const shared = payload?.sharedIssue;
                if (shared) {
                  const button = document.querySelector('.shared-issue-button');
                  if (button) {
                    button.classList.toggle('active', Boolean(shared.created));
                    button.classList.toggle('loading', Boolean(shared.loading));
                    button.disabled = Boolean(shared.loading) || !shared.enabled;
                    const label = button.querySelector('.shared-issue-label');
                    if (label) label.textContent = shared.created ? `俺也一样 (${shared.count})` : '俺也一样';
                  }
                }
              },
              feedback(postNumber, message) {
                const article = document.getElementById(`post-${postNumber}`);
                const feedback = article?.querySelector('.action-feedback');
                if (!feedback) return;
                feedback.textContent = message;
                feedback.classList.add('visible');
                window.setTimeout(() => feedback.classList.remove('visible'), 1400);
              }
            };
          })();

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
                    const isReporting = reporting.has(postNumber) && !isRead;
                    indicator.setAttribute('aria-hidden', isRead ? 'true' : 'false');
                    if (isRead) {
                      indicator.removeAttribute('title');
                    } else {
                      indicator.setAttribute('role', 'status');
                      indicator.setAttribute('aria-label', isReporting ? '阅读状态同步中' : '未读楼层');
                      indicator.setAttribute('title', isReporting ? '正在同步阅读状态…' : '停留后同步阅读状态');
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
        ownerUserID: Int?,
        ownerUsername: String?,
        followedUsernames: Set<String>,
        followedHighlightEnabled: Bool,
        readPostNumbers: Set<Int>,
        reportingPostNumbers: Set<Int>,
        runningActions: Set<PostActionKind>,
        canLike: Bool,
        canReply: Bool,
        sharedIssueVisible: Bool,
        sharedIssueCreated: Bool,
        sharedIssueCount: Int,
        canCreateSharedIssue: Bool
    ) -> String {
        let normalizedUsername = post.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        let normalizedOwnerUsername = ownerUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        let isOwner = post.postNumber == 1
            || (ownerUserID != nil && post.userID == ownerUserID)
            || (normalizedOwnerUsername != nil && normalizedUsername == normalizedOwnerUsername)
        let isFollowed = followedHighlightEnabled
            && followedUsernames.contains(normalizedUsername)
        let displayName = post.name?.isEmpty == false ? post.name! : post.username
        let username = post.name?.isEmpty == false && post.name != post.username
            ? "<span class=\"username\">@\(escapeHTML(post.username))</span>"
            : ""
        let acceptedBadge = post.acceptedAnswer
            ? badgeHTML("已采纳", className: "status-success")
            : ""
        let ownerBadge = isOwner
            ? badgeHTML("楼主", className: "status-owner", title: "主题作者")
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
        let isReporting = !isRead && reportingPostNumbers.contains(post.postNumber)
        let indicatorAccessibility = isRead
            ? "aria-hidden=\"true\""
            : isReporting
                ? "role=\"status\" aria-label=\"阅读状态同步中\" title=\"正在同步阅读状态…\""
                : "role=\"status\" aria-label=\"未读楼层\" title=\"停留后同步阅读状态\""
        let actionFooter = postActionsHTML(
            post,
            runningActions: runningActions,
            canLike: canLike,
            canReply: canReply
        )
        let sharedIssue = sharedIssueVisible
            ? sharedIssueHTML(
                created: sharedIssueCreated,
                count: sharedIssueCount,
                enabled: canCreateSharedIssue,
                loading: runningActions.contains(.sharedIssue)
            )
            : ""

        return """
        <article class="post\(followedClass)\(readClass)\(reportingClass)" id="post-\(post.postNumber)" data-post-number="\(post.postNumber)">
          \(avatar)
          <div class="post-main">
            <div class="post-heading">
              <div>
                <div class="author-line">
                  <button class="profile-button author-name" data-profile-post-number="\(post.postNumber)" aria-label="查看 \(escapeAttribute(displayName)) 的资料">\(escapeHTML(displayName))</button>
                  \(username)\(ownerBadge)\(acceptedBadge)\(followedBadge)
                </div>
                <div class="post-metadata">
                  <span>#\(post.postNumber)</span><span>\(createdAt)</span><span class="read-indicator" \(indicatorAccessibility)></span>\(replyMetadata)
                </div>
              </div>
            </div>
            <div class="post-body">\(post.cookedHTML)</div>
            \(sharedIssue)
            \(actionFooter)
            <span class="action-feedback" aria-live="polite"></span>
          </div>
        </article>
        """
    }

    private static func postActionsHTML(
        _ post: PostItem,
        runningActions: Set<PostActionKind>,
        canLike: Bool,
        canReply: Bool
    ) -> String {
        let reactionSummary = post.reactions
            .filter { $0.count > 0 }
            .map { "<span class=\"reaction-emoji\" title=\"\(escapeAttribute($0.id))\">\(reactionEmoji($0.id))</span>" }
            .joined()
        let reactionCount = post.reactionUsersCount > 0
            ? "<span class=\"reaction-count\">\(post.reactionUsersCount)</span>"
            : ""
        let likeLoading = runningActions.contains(.reaction)
        let likeClasses = [
            "post-action-button",
            "like-button",
            post.isLiked ? "active" : nil,
            likeLoading ? "loading" : nil,
        ].compactMap { $0 }.joined(separator: " ")
        let boostLoading = runningActions.contains(.boost)
        let boostClasses = [
            "post-action-button",
            "boost-inline-button",
            boostLoading ? "loading" : nil,
        ].compactMap { $0 }.joined(separator: " ")
        let boostButton = """
        <button class="\(boostClasses)" data-post-action="boost" aria-label="Boost 此楼层" title="Boost 此楼层" \(post.canBoost && post.boosts.isEmpty ? "" : "hidden") \(boostLoading ? "disabled" : "")>\(discourseIcon(named: "boost"))</button>
        """
        let replyButton = canReply
            ? "<button class=\"post-action-button\" data-post-action=\"reply\" aria-label=\"回复 #\(post.postNumber)\" title=\"回复 #\(post.postNumber)\">\(discourseIcon(named: "reply"))</button>"
            : ""

        return """
        <div class="post-actions-footer">
          <div class="reaction-summary">\(reactionSummary)\(reactionCount)</div>
          <div class="post-action-buttons">
            <button class="\(likeClasses)" data-post-action="like" aria-label="点赞；按住或右键选择其他回应" title="点赞；按住或右键选择其他回应" \(likeLoading || !canLike ? "disabled" : "")>\(discourseIcon(named: "heart"))\(discourseIcon(named: "heart", filled: true))</button>
            <button class="post-action-button" data-post-action="copyLink" aria-label="复制楼层链接" title="复制楼层链接">\(discourseIcon(named: "copyLink"))</button>
            \(boostButton)
            <button class="post-action-button" data-post-action="more" aria-label="更多操作" title="更多操作">\(discourseIcon(named: "more"))</button>
            \(replyButton)
          </div>
        </div>
        <div class="boost-row">\(boostRowHTML(post))</div>
        """
    }

    private static func sharedIssueHTML(
        created: Bool,
        count: Int,
        enabled: Bool,
        loading: Bool
    ) -> String {
        let classes = [
            "shared-issue-button",
            created ? "active" : nil,
            loading ? "loading" : nil,
        ].compactMap { $0 }.joined(separator: " ")
        let label = created ? "俺也一样 (\(count))" : "俺也一样"
        return "<button class=\"\(classes)\" data-post-action=\"sharedIssue\" \(!enabled || loading ? "disabled" : "")>\(discourseIcon(named: "agree"))<span class=\"shared-issue-label\">\(label)</span></button>"
    }

    private static func boostRowHTML(_ post: PostItem) -> String {
        guard !post.boosts.isEmpty else { return "" }
        let pills = post.boosts.map { boost in
            let displayName = boost.user.displayName
            let avatar: String
            if let template = boost.user.avatarTemplate,
               let url = Endpoints.avatarURL(template: template, size: 40) {
                avatar = "<img class=\"boost-avatar\" src=\"\(escapeAttribute(url.absoluteString))\" alt=\"\">"
            } else {
                avatar = "<span class=\"boost-avatar avatar-fallback\">\(escapeHTML(String(displayName.prefix(1)).uppercased()))</span>"
            }
            return "<span class=\"boost-pill\" title=\"\(escapeAttribute(displayName))\">\(avatar)<span class=\"boost-content\">\(boost.cookedHTML)</span></span>"
        }.joined()
        let rocket = post.canBoost
            ? "<button class=\"post-action-button boost-row-button\" data-post-action=\"boost\" aria-label=\"Boost 此楼层\" title=\"Boost 此楼层\">\(discourseIcon(named: "boost"))</button>"
            : ""
        return pills + rocket
    }

    private struct DiscourseIcon {
        let viewBox: String
        let path: String
    }

    private static let discourseIcons: [String: DiscourseIcon] = [
        "heart": DiscourseIcon(
            viewBox: "0 0 512 512",
            path: "M225.8 468.2l-2.5-2.3L48.1 303.2C17.4 274.7 0 234.7 0 192.8l0-3.3c0-70.4 50-130.8 119.2-144C158.6 37.9 198.9 47 231 69.6c9 6.4 17.4 13.8 25 22.3c4.2-4.8 8.7-9.2 13.5-13.3c3.7-3.2 7.5-6.2 11.5-9c0 0 0 0 0 0C313.1 47 353.4 37.9 392.8 45.4C462 58.6 512 119.1 512 189.5l0 3.3c0 41.9-17.4 81.9-48.1 110.4L288.7 465.9l-2.5 2.3c-8.2 7.6-19 11.9-30.2 11.9s-22-4.2-30.2-11.9zM239.1 145c-.4-.3-.7-.7-1-1.1l-17.8-20-.1-.1s0 0 0 0c-23.1-25.9-58-37.7-92-31.2C81.6 101.5 48 142.1 48 189.5l0 3.3c0 28.5 11.9 55.8 32.8 75.2L256 430.7 431.2 268c20.9-19.4 32.8-46.7 32.8-75.2l0-3.3c0-47.3-33.6-88-80.1-96.9c-34-6.5-69 5.4-92 31.2c0 0 0 0-.1 .1s0 0-.1 .1l-17.8 20c-.3 .4-.7 .7-1 1.1c-4.5 4.5-10.6 7-16.9 7s-12.4-2.5-16.9-7z"
        ),
        "heartFill": DiscourseIcon(
            viewBox: "0 0 512 512",
            path: "M47.6 300.4L228.3 469.1c7.5 7 17.4 10.9 27.7 10.9s20.2-3.9 27.7-10.9L464.4 300.4c30.4-28.3 47.6-68 47.6-109.5v-5.8c0-69.9-50.5-129.5-119.4-141C347 36.5 300.6 51.4 268 84L256 96 244 84c-32.6-32.6-79-47.5-124.6-39.9C50.5 55.6 0 115.2 0 185.1v5.8c0 41.5 17.2 81.2 47.6 109.5z"
        ),
        "copyLink": DiscourseIcon(
            viewBox: "0 0 640 512",
            path: "M579.8 267.7c56.5-56.5 56.5-148 0-204.5c-50-50-128.8-56.5-186.3-15.4l-1.6 1.1c-14.4 10.3-17.7 30.3-7.4 44.6s30.3 17.7 44.6 7.4l1.6-1.1c32.1-22.9 76-19.3 103.8 8.6c31.5 31.5 31.5 82.5 0 114L422.3 334.8c-31.5 31.5-82.5 31.5-114 0c-27.9-27.9-31.5-71.8-8.6-103.8l1.1-1.6c10.3-14.4 6.9-34.4-7.4-44.6s-34.4-6.9-44.6 7.4l-1.1 1.6C206.5 251.2 213 330 263 380c56.5 56.5 148 56.5 204.5 0L579.8 267.7zM60.2 244.3c-56.5 56.5-56.5 148 0 204.5c50 50 128.8 56.5 186.3 15.4l1.6-1.1c14.4-10.3 17.7-30.3 7.4-44.6s-30.3-17.7-44.6-7.4l-1.6 1.1c-32.1 22.9-76 19.3-103.8-8.6C74 372 74 321 105.5 289.5L217.7 177.2c31.5-31.5 82.5-31.5 114 0c27.9 27.9 31.5 71.8 8.6 103.9l-1.1 1.6c-10.3 14.4-6.9 34.4 7.4 44.6s34.4 6.9 44.6-7.4l1.1-1.6C433.5 260.8 427 182 377 132c-56.5-56.5-148-56.5-204.5 0L60.2 244.3z"
        ),
        "boost": DiscourseIcon(
            viewBox: "0 0 512 512",
            path: "M498.1 5.6c10.1 7 15.4 19.1 13.5 31.2l-64 416c-1.5 9.7-7.4 18.2-16 23s-18.9 5.4-28 1.6L284 427.7l-68.5 74.1c-8.9 9.7-22.9 12.9-35.2 8.1S160 493.2 160 480l0-83.6c0-4 1.5-7.8 4.2-10.8L331.8 202.8c5.8-6.3 5.6-16-.4-22s-15.7-6.4-22-.7L106 360.8 17.7 316.6C7.1 311.3 .3 300.7 0 288.9s5.9-22.8 16.1-28.7l448-256c10.7-6.1 23.9-5.5 34 1.4z"
        ),
        "more": DiscourseIcon(
            viewBox: "0 0 448 512",
            path: "M8 256a56 56 0 1 1 112 0A56 56 0 1 1 8 256zm160 0a56 56 0 1 1 112 0 56 56 0 1 1 -112 0zm216-56a56 56 0 1 1 0 112 56 56 0 1 1 0-112z"
        ),
        "reply": DiscourseIcon(
            viewBox: "0 0 512 512",
            path: "M205 34.8c11.5 5.1 19 16.6 19 29.2l0 64 112 0c97.2 0 176 78.8 176 176c0 113.3-81.5 163.9-100.2 174.1c-2.5 1.4-5.3 1.9-8.1 1.9c-10.9 0-19.7-8.9-19.7-19.7c0-7.5 4.3-14.4 9.8-19.5c9.4-8.8 22.2-26.4 22.2-56.7c0-53-43-96-96-96l-96 0 0 64c0 12.6-7.4 24.1-19 29.2s-25 3-34.4-5.4l-160-144C3.9 225.7 0 217.1 0 208s3.9-17.7 10.6-23.8l160-144c9.4-8.5 22.9-10.6 34.4-5.4z"
        ),
        "agree": DiscourseIcon(
            viewBox: "0 0 384 512",
            path: "M64 64l0 177.6c5.2-1 10.5-1.6 16-1.6l16 0 0-32L96 64c0-8.8-7.2-16-16-16s-16 7.2-16 16zM80 288c-17.7 0-32 14.3-32 32c0 0 0 0 0 0l0 24c0 66.3 53.7 120 120 120l48 0c52.5 0 97.1-33.7 113.4-80.7c-3.1 .5-6.2 .7-9.4 .7c-20 0-37.9-9.2-49.7-23.6c-9 4.9-19.4 7.6-30.3 7.6c-15.1 0-29-5.3-40-14c-11 8.8-24.9 14-40 14l-40 0c-13.3 0-24-10.7-24-24s10.7-24 24-24l40 0c8.8 0 16-7.2 16-16s-7.2-16-16-16l-40 0-40 0zM0 320s0 0 0 0c0-18 6-34.6 16-48L16 64C16 28.7 44.7 0 80 0s64 28.7 64 64l0 82c5.1-1.3 10.5-2 16-2c25.3 0 47.2 14.7 57.6 36c7-2.6 14.5-4 22.4-4c20 0 37.9 9.2 49.7 23.6c9-4.9 19.4-7.6 30.3-7.6c35.3 0 64 28.7 64 64l0 64 0 24c0 92.8-75.2 168-168 168l-48 0C75.2 512 0 436.8 0 344l0-24zm336-64c0-8.8-7.2-16-16-16s-16 7.2-16 16l0 48 0 16c0 8.8 7.2 16 16 16s16-7.2 16-16l0-64zM160 240c5.5 0 10.9 .7 16 2l0-2 0-32c0-8.8-7.2-16-16-16s-16 7.2-16 16l0 32 16 0zm64 24l0 40c0 8.8 7.2 16 16 16s16-7.2 16-16l0-48 0-16c0-8.8-7.2-16-16-16s-16 7.2-16 16l0 24z"
        ),
    ]

    private static func discourseIcon(named name: String, filled: Bool = false) -> String {
        guard let icon = discourseIcons[filled ? "\(name)Fill" : name] else { return "" }
        return """
        <svg class="discourse-icon" viewBox="\(icon.viewBox)" aria-hidden="true"><path d="\(icon.path)"/></svg>
        """
    }

    private static func reactionEmoji(_ id: String) -> String {
        switch id {
        case "heart": return "♥"
        case "+1": return "👍"
        case "laughing": return "😆"
        case "open_mouth": return "😮"
        case "clap": return "👏"
        case "confetti_ball": return "🎉"
        case "hugs": return "🤗"
        case "distorted_face": return "🫠"
        case "tieba_087": return "😭"
        case "bili_057": return "✨"
        default: return "●"
        }
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

    private static func badgeHTML(_ text: String, className: String, title: String? = nil) -> String {
        let titleAttribute = title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
        return "<span class=\"status-badge \(className)\"\(titleAttribute)>\(escapeHTML(text))</span>"
    }

    private static func safeColor(_ value: String) -> String {
        value.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
            ? value
            : "#40B883"
    }

    private static func interactionStateJSON(
        detail: TopicDetail,
        runningPostActions: [Int: Set<PostActionKind>],
        isLoggedIn: Bool
    ) -> String {
        let posts: [[String: Any]] = detail.posts.map { post in
            let boosts: [[String: Any]] = post.boosts.map { boost in
                let avatarURL = boost.user.avatarTemplate
                    .flatMap { Endpoints.avatarURL(template: $0, size: 40)?.absoluteString }
                return [
                    "id": boost.id,
                    "cookedHTML": boost.cookedHTML,
                    "displayName": boost.user.displayName,
                    "avatarURL": avatarURL ?? "",
                ]
            }
            return [
                "postNumber": post.postNumber,
                "liked": post.isLiked,
                "currentReaction": post.currentUserReaction ?? "",
                "reactionUsersCount": post.reactionUsersCount,
                "reactions": post.reactions.map { ["id": $0.id, "count": $0.count] },
                "boosts": boosts,
                "canBoost": post.canBoost,
                "canLike": post.canToggleLike || !isLoggedIn,
                "running": (runningPostActions[post.id] ?? []).map(\.rawValue).sorted(),
            ]
        }
        let firstPostID = detail.posts.first?.id
        let payload: [String: Any] = [
            "posts": posts,
            "sharedIssue": [
                "created": detail.userCreatedSharedIssue,
                "count": detail.sharedIssueCount,
                "enabled": detail.canCreateSharedIssue || detail.userCreatedSharedIssue || !isLoggedIn,
                "loading": firstPostID.map {
                    runningPostActions[$0]?.contains(.sharedIssue) == true
                } ?? false,
            ],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func postURL(detail: TopicDetail, postNumber: Int) -> URL {
        var url = Endpoints.topicPage(id: detail.id, slug: detail.slug)
        if postNumber > 0 {
            url.appendPathComponent(String(postNumber))
        }
        return url
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
