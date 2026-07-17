//
//  SiteSessionStore.swift
//  持久化站内 Web 会话，并在同一 WebKit 会话内执行 Discourse JSON 请求。
//

import Foundation
import Security
@preconcurrency import WebKit

struct SiteUser: Equatable, Sendable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return username
    }
}

enum SiteRequestError: LocalizedError {
    case hostNotReady
    case invalidResponse
    case loginRequired
    case challengeRequired
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .hostNotReady:
            return "站内请求环境尚未就绪，请稍后重试。"
        case .invalidResponse:
            return "LINUX DO 返回了无法识别的响应。"
        case .loginRequired:
            return "需要先登录 LINUX DO 才能访问此内容。"
        case .challengeRequired:
            return "需要在“登录与验证”中完成 Cloudflare 验证。"
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return "LINUX DO 返回 HTTP \(status)：\(message)"
            }
            return "LINUX DO 返回 HTTP \(status)。"
        }
    }
}

@MainActor
final class SiteSessionStore: NSObject, ObservableObject {
    @Published private(set) var title = "LINUX DO"
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isClearingData = false
    @Published private(set) var currentUser: SiteUser?
    @Published private(set) var isSessionChecking = false
    @Published private(set) var requestHostReady = false

    let webView: WKWebView
    let requestWebView: WKWebView

    private var didStartRequestHost = false
    private var didRestorePersistedCookies = false
    private var sessionTask: Task<Void, Never>?
    private var loginPollTask: Task<Void, Never>?

    override init() {
        let websiteDataStore = WKWebsiteDataStore.default()

        func configuration() -> WKWebViewConfiguration {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = websiteDataStore
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            configuration.preferences.isElementFullscreenEnabled = true
            return configuration
        }

        self.webView = WKWebView(frame: .zero, configuration: configuration())
        self.requestWebView = WKWebView(frame: .zero, configuration: configuration())
        super.init()

        for view in [webView, requestWebView] {
            view.navigationDelegate = self
            view.customUserAgent = Self.safariUserAgent
        }
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
    }

    deinit {
        sessionTask?.cancel()
        loginPollTask?.cancel()
    }

    var isLoggedIn: Bool { currentUser != nil }

    func prepareRequestHost() {
        guard !didStartRequestHost else { return }
        didStartRequestHost = true
        Task { [weak self] in
            guard let self else { return }
            await self.restorePersistedCookiesIfNeeded()
            self.requestHostReady = false
            self.requestWebView.load(URLRequest(url: Endpoints.sessionCSRF()))
        }
    }

    func loadHomeIfNeeded() {
        prepareRequestHost()
        guard webView.url == nil else { return }
        load(Endpoints.baseURL)
    }

    func load(_ url: URL) {
        errorMessage = nil
        webView.load(URLRequest(url: url))
        if url.host == Endpoints.baseURL.host, url.path.hasPrefix("/login") {
            startLoginPolling()
        }
    }

    func loadLogin() {
        load(Endpoints.login())
    }

    func loadTopic(id: Int, slug: String? = nil) {
        load(Endpoints.topicPage(id: id, slug: slug))
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    func reload() {
        errorMessage = nil
        webView.reload()
    }

    func goHome() {
        load(Endpoints.baseURL)
    }

    func refreshSession() {
        prepareRequestHost()
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            guard let self else { return }
            self.isSessionChecking = true
            defer { self.isSessionChecking = false }
            do {
                let user = try await self.fetchCurrentUser()
                self.currentUser = user
                if user != nil {
                    await self.persistSessionCookies()
                } else {
                    await SessionCookieVault.deleteAsync()
                }
            } catch is CancellationError {
                return
            } catch {
                // 网络或 Cloudflare 暂时失败时保留上一次已确认的登录态。
            }
        }
    }

    func requestJSON(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        referrer: String? = nil
    ) async throws -> Data {
        prepareRequestHost()
        try await waitForRequestHost()

        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let functionBody = """
        const requestURL = new URL(path, window.location.origin);
        const headers = {
          'Accept': method === 'GET' ? 'application/json' : '*/*',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache'
        };
        const options = {
          method: method,
          credentials: 'include',
          cache: 'no-store',
          headers: headers
        };
        if (method !== 'GET' && method !== 'HEAD') {
          let csrf = '';
          try {
            const csrfResponse = await fetch(new URL('/session/csrf.json', window.location.origin), {
              credentials: 'include',
              cache: 'no-store',
              headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
            });
            const csrfPayload = await csrfResponse.json();
            csrf = csrfPayload && csrfPayload.csrf ? csrfPayload.csrf : '';
          } catch (_) {}
          headers['Content-Type'] = 'application/json';
          headers['X-CSRF-Token'] = csrf;
          headers['X-Requested-With'] = 'XMLHttpRequest';
          headers['Discourse-Present'] = 'true';
          headers['Discourse-Logged-In'] = 'true';
          options.body = body;
          if (referrer.length > 0) {
            options.referrer = referrer;
            options.referrerPolicy = 'strict-origin-when-cross-origin';
          }
        }
        try {
          const response = await fetch(requestURL.toString(), options);
          const responseBody = await response.text();
          return {
            status: response.status,
            contentType: response.headers.get('content-type') || '',
            body: responseBody
          };
        } catch (error) {
          return { status: 0, contentType: '', body: '', error: String(error) };
        }
        """

        let value = try await requestWebView.callAsyncJavaScript(
            functionBody,
            arguments: [
                "path": path,
                "method": method.uppercased(),
                "body": bodyString,
                "referrer": referrer ?? "",
            ],
            in: nil,
            contentWorld: .page
        )

        guard let envelope = value as? [String: Any],
              let status = (envelope["status"] as? NSNumber)?.intValue,
              let responseBody = envelope["body"] as? String else {
            throw SiteRequestError.invalidResponse
        }

        if status == 0 {
            throw SiteRequestError.hostNotReady
        }

        let contentType = (envelope["contentType"] as? String ?? "").lowercased()
        let trimmedBody = responseBody.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if contentType.contains("text/html") || trimmedBody.hasPrefix("<!doctype html") || trimmedBody.hasPrefix("<html") {
            throw SiteRequestError.challengeRequired
        }

        switch status {
        case 200..<300:
            return Data(responseBody.utf8)
        case 401:
            throw SiteRequestError.loginRequired
        case 403 where currentUser == nil:
            throw SiteRequestError.loginRequired
        default:
            throw SiteRequestError.http(status: status, message: Self.responseMessage(from: responseBody))
        }
    }

    func clearWebsiteData() {
        guard !isClearingData else { return }
        isClearingData = true
        sessionTask?.cancel()
        loginPollTask?.cancel()
        let store = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { [weak self] records in
            let linuxDORecords = records.filter {
                $0.displayName.localizedCaseInsensitiveContains("linux.do")
                    || $0.displayName.localizedCaseInsensitiveContains("ldstatic.com")
            }
            store.removeData(ofTypes: dataTypes, for: linuxDORecords) {
                Task { @MainActor in
                    guard let self else { return }
                    self.currentUser = nil
                    await SessionCookieVault.deleteAsync()
                    self.isClearingData = false
                    self.didStartRequestHost = false
                    self.didRestorePersistedCookies = false
                    self.requestHostReady = false
                    self.prepareRequestHost()
                    self.goHome()
                }
            }
        }
    }

    private func fetchCurrentUser() async throws -> SiteUser? {
        let data = try await requestJSON(path: "/session/current.json")
        let payload = try JSONDecoder().decode(CurrentSessionResponse.self, from: data)
        guard let user = payload.currentUser else { return nil }
        return SiteUser(
            id: user.id,
            username: user.username,
            name: user.name,
            avatarTemplate: user.avatarTemplate
        )
    }

    private func startLoginPolling() {
        prepareRequestHost()
        loginPollTask?.cancel()
        loginPollTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<112 {
                if Task.isCancelled { return }
                do {
                    if let user = try await self.fetchCurrentUser() {
                        self.currentUser = user
                        await self.persistSessionCookies()
                        return
                    }
                } catch {
                    // 登录页或挑战仍在进行时继续轮询，不暴露 Cookie 内容。
                }
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    private func waitForRequestHost() async throws {
        let deadline = Date().addingTimeInterval(15)
        while !requestHostReady {
            try Task.checkCancellation()
            if Date() >= deadline {
                throw SiteRequestError.hostNotReady
            }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func restorePersistedCookiesIfNeeded() async {
        guard !didRestorePersistedCookies else { return }
        didRestorePersistedCookies = true
        guard let records = await SessionCookieVault.loadAsync(), !records.isEmpty else { return }

        let store = requestWebView.configuration.websiteDataStore.httpCookieStore
        for record in records {
            guard record.expiresAt.map({ $0 > Date() }) ?? true,
                  let cookie = record.cookie else { continue }
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func persistSessionCookies() async {
        let store = requestWebView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let records = cookies
            .filter { cookie in
                cookie.domain == "linux.do" || cookie.domain.hasSuffix(".linux.do")
            }
            .compactMap(SessionCookieRecord.init)
        await SessionCookieVault.saveAsync(records)
    }

    private func syncState(_ webView: WKWebView) {
        title = webView.title ?? "LINUX DO"
        currentURL = webView.url
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private static func responseMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let errors = object["errors"] as? [String], !errors.isEmpty {
            return errors.joined(separator: "；")
        }
        return object["error"] as? String
    }

    private static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
}

extension SiteSessionStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === requestWebView {
            requestHostReady = false
            return
        }
        isLoading = true
        errorMessage = nil
        syncState(webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        syncState(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === requestWebView {
            requestHostReady = webView.url?.host == Endpoints.baseURL.host
            if requestHostReady { refreshSession() }
            return
        }

        isLoading = false
        syncState(webView)
        if webView.url?.host == Endpoints.baseURL.host {
            refreshSession()
            if webView.url?.path.hasPrefix("/login") == true {
                startLoginPolling()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportFailure(error, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        reportFailure(error, webView: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === requestWebView {
            requestHostReady = false
            didStartRequestHost = false
            prepareRequestHost()
            return
        }
        errorMessage = "网页进程已退出，正在重新加载…"
        webView.reload()
    }

    private func reportFailure(_ error: Error, webView: WKWebView) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if webView === requestWebView {
            requestHostReady = false
            return
        }
        isLoading = false
        errorMessage = error.localizedDescription
        syncState(webView)
    }
}

extension SiteSessionStore: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            load(url)
        }
        return nil
    }
}

private struct CurrentSessionResponse: Decodable {
    let currentUser: CurrentSessionUser?

    enum CodingKeys: String, CodingKey {
        case currentUser = "current_user"
    }
}

private struct CurrentSessionUser: Decodable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarTemplate = "avatar_template"
    }
}

private struct SessionCookieRecord: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let expiresAt: Date?

    init?(_ cookie: HTTPCookie) {
        guard !cookie.name.isEmpty, !cookie.domain.isEmpty else { return nil }
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path.isEmpty ? "/" : cookie.path
        secure = cookie.isSecure
        expiresAt = cookie.expiresDate
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: secure ? "TRUE" : "FALSE",
        ]
        if let expiresAt {
            properties[.expires] = expiresAt
        }
        return HTTPCookie(properties: properties)
    }
}

private enum SessionCookieVault {
    private static let service = "com.linuxdo.reader.web-session"
    private static let account = "linux.do-cookies-v1"

    static func loadAsync() async -> [SessionCookieRecord]? {
        await Task.detached(priority: .utility) {
            load()
        }.value
    }

    static func saveAsync(_ records: [SessionCookieRecord]) async {
        await Task.detached(priority: .utility) {
            save(records)
        }.value
    }

    static func deleteAsync() async {
        await Task.detached(priority: .utility) {
            delete()
        }.value
    }

    static func load() -> [SessionCookieRecord]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode([SessionCookieRecord].self, from: data)
    }

    static func save(_ records: [SessionCookieRecord]) {
        guard !records.isEmpty,
              let data = try? JSONEncoder().encode(records) else { return }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updates: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(identity as CFDictionary, updates as CFDictionary) == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
