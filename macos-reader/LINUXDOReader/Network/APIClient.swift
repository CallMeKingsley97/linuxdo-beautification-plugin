//
//  APIClient.swift
//  登录后通过同源 WKWebView fetch 访问 Discourse JSON；匿名或桥不可用时回退 RSS。
//

import Foundation

@MainActor
final class APIClient {
    nonisolated static let appUserAgent = "LINUXDOReader/0.7.0 (macOS; WebKit session; third-party; not-affiliated)"

    private let siteSession: SiteSessionStore
    private let rssSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let gate = RequestGate()

    var listTTL: TimeInterval = 60
    var detailTTL: TimeInterval = 45
    var categoryTTL: TimeInterval = 300

    init(siteSession: SiteSessionStore, session: URLSession? = nil) {
        self.siteSession = siteSession

        if let session {
            self.rssSession = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.httpAdditionalHeaders = [
                "User-Agent": Self.appUserAgent,
                "Accept": "application/rss+xml, application/xml;q=0.9",
                "Accept-Encoding": "identity",
            ]
            self.rssSession = URLSession(configuration: configuration)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.ldoFractional.date(from: raw)
                ?? ISO8601DateFormatter.ldo.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析日期：\(raw)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func fetchLatest(page: Int = 0, force: Bool = false) async throws -> TopicListPage {
        do {
            let dto: LatestJSON = try await getJSON(
                url: Endpoints.latest(page: page),
                ttl: listTTL,
                force: force
            )
            return TopicListPage.from(latest: dto)
        } catch {
            try requireFallbackAllowed(error)
            let feed = try await fetchFeed(url: Endpoints.latestRSS(), ttl: listTTL, force: force)
            return TopicListPage.from(rss: feed)
        }
    }

    func fetchHot(page: Int = 0, force: Bool = false) async throws -> TopicListPage {
        do {
            let dto: LatestJSON = try await getJSON(
                url: Endpoints.hot(page: page),
                ttl: listTTL,
                force: force
            )
            return TopicListPage.from(latest: dto)
        } catch {
            try requireFallbackAllowed(error)
            let feed = try await fetchFeed(url: Endpoints.hotRSS(), ttl: listTTL, force: force)
            return TopicListPage.from(rss: feed)
        }
    }

    func fetchCategoryTopics(
        slug: String,
        id: Int,
        page: Int = 0,
        force: Bool = false
    ) async throws -> TopicListPage {
        do {
            let dto: LatestJSON = try await getJSON(
                url: Endpoints.category(slug: slug, id: id, page: page),
                ttl: listTTL,
                force: force
            )
            return TopicListPage.from(latest: dto)
        } catch {
            try requireFallbackAllowed(error)
            let feed = try await fetchFeed(
                url: Endpoints.categoryRSS(slug: slug, id: id),
                ttl: listTTL,
                force: force
            )
            return TopicListPage.from(rss: feed)
        }
    }

    func fetchCategories(force: Bool = false) async throws -> [CategorySummary] {
        CategorySummary.rssCatalog
    }

    func fetchTopic(id: Int, force: Bool = false) async throws -> TopicDetail {
        do {
            let dto: TopicDetailJSON = try await getJSON(
                url: Endpoints.topic(id: id),
                ttl: detailTTL,
                force: force
            )
            return TopicDetail.from(dto: dto)
        } catch {
            try requireFallbackAllowed(error)
            let feed = try await fetchFeed(
                url: Endpoints.topicRSS(id: id),
                ttl: detailTTL,
                force: force
            )
            return try TopicDetail.from(rss: feed, topicID: id)
        }
    }

    func fetchPosts(topicID: Int, postIDs: [Int]) async throws -> [PostItem] {
        guard !postIDs.isEmpty else { return [] }
        let dto: TopicDetailJSON = try await getJSON(
            url: Endpoints.topicPosts(id: topicID, postIDs: postIDs),
            ttl: nil,
            force: true
        )
        return (dto.postStream?.posts ?? [])
            .map { PostItem.from(dto: $0, topicID: topicID) }
            .sorted { $0.postNumber < $1.postNumber }
    }

    func reportTopicTimings(
        topicID: Int,
        timings: [Int: Int],
        topicTime: Int
    ) async throws {
        guard !timings.isEmpty else { return }

        var parts = timings.keys.sorted().map { postNumber in
            let milliseconds = max(1, timings[postNumber] ?? 0)
            return "timings%5B\(postNumber)%5D=\(milliseconds)"
        }
        parts.append("topic_time=\(max(0, topicTime))")
        parts.append("topic_id=\(topicID)")

        _ = try await siteSession.requestForm(
            path: "/topics/timings",
            body: parts.joined(separator: "&"),
            referrer: Endpoints.topicPage(id: topicID).absoluteString,
            isBackground: true
        )
    }

    func fetchFollowedUsernames(username: String) async throws -> [String] {
        let url = Endpoints.following(username: username)
        let data = try await siteSession.requestJSON(path: url.path)
        return try Self.decodeFollowedUsernames(data)
    }

    func fetchUserProfile(username: String, force: Bool = false) async throws -> UserProfileDetail {
        let response: UserProfileResponseJSON = try await getJSON(
            url: Endpoints.userProfile(username: username),
            ttl: 60,
            force: force
        )
        guard let user = response.user else {
            throw LDOError.decoding("用户资料响应为空")
        }
        return try UserProfileDetail.from(user)
    }

    func fetchUserProfileSummary(
        username: String,
        force: Bool = false
    ) async throws -> UserProfileSummary {
        let response: UserProfileSummaryResponseJSON = try await getJSON(
            url: Endpoints.userSummary(username: username),
            ttl: 60,
            force: force
        )
        return try UserProfileSummary.from(response)
    }

    func fetchUserActivity(
        username: String,
        filter: UserActivityFilter,
        offset: Int,
        force: Bool = false
    ) async throws -> UserActivityPage {
        let response: UserActionsResponseJSON = try await getJSON(
            url: Endpoints.userActions(username: username, filter: filter.rawValue, offset: offset),
            ttl: 30,
            force: force
        )
        let source = response.userActions ?? []
        let items = source.compactMap { action -> UserActivityItem? in
            guard let actionType = action.actionType,
                  let topicID = action.topicId,
                  let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            let author: UserSummary? = {
                guard let username = action.username?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !username.isEmpty else { return nil }
                return UserSummary(
                    id: action.userId ?? 0,
                    username: username,
                    name: action.name,
                    avatarTemplate: action.avatarTemplate
                )
            }()
            return UserActivityItem(
                actionType: actionType,
                topicID: topicID,
                postNumber: action.postNumber,
                title: title,
                excerpt: LDOHTMLText.plainText(action.excerpt) ?? "",
                categoryID: action.categoryId,
                createdAt: action.createdAt,
                author: author
            )
        }
        return UserActivityPage(items: items, hasMore: source.count >= 30)
    }

    func fetchUserBadges(username: String, force: Bool = false) async throws -> [UserBadgeGroup] {
        let response: UserBadgesResponseJSON = try await getJSON(
            url: Endpoints.userBadges(username: username),
            ttl: 300,
            force: force
        )
        let definitions = Dictionary(
            uniqueKeysWithValues: (response.badges ?? []).compactMap { badge -> (Int, UserBadgeDefinitionJSON)? in
                guard let id = badge.id else { return nil }
                return (id, badge)
            }
        )
        let typeNames = Dictionary(
            uniqueKeysWithValues: (response.badgeTypes ?? []).compactMap { type -> (Int, String)? in
                guard let id = type.id, let name = type.name, !name.isEmpty else { return nil }
                return (id, name)
            }
        )
        let badges = (response.userBadges ?? []).compactMap { record -> UserBadgeItem? in
            guard let badgeID = record.badgeId, let definition = definitions[badgeID] else { return nil }
            return UserBadgeItem.from(
                definition: definition,
                count: record.count,
                grantedAt: record.grantedAt
            )
        }
        let grouped = Dictionary(grouping: badges, by: \.badgeTypeID)
        let orderedTypeIDs = [1, 2, 3] + grouped.keys.filter { ![1, 2, 3].contains($0) }.sorted()
        return orderedTypeIDs.compactMap { typeID in
            guard let badges = grouped[typeID], !badges.isEmpty else { return nil }
            let fallbackName: String
            switch typeID {
            case 1: fallbackName = "金牌徽章"
            case 2: fallbackName = "银牌徽章"
            default: fallbackName = "铜牌徽章"
            }
            return UserBadgeGroup(
                id: typeID,
                name: typeNames[typeID] ?? fallbackName,
                badges: badges
            )
        }
    }

    func fetchSolvedPosts(username: String, offset: Int) async throws -> SolvedPostPage {
        let response: SolvedPostsResponseJSON = try await getJSON(
            url: Endpoints.solvedPosts(username: username, offset: offset),
            ttl: 60,
            force: false
        )
        let source = response.userSolvedPosts ?? []
        let items = source.compactMap { post -> SolvedPostItem? in
            guard let postID = post.postId,
                  let topicID = post.topicId,
                  let postNumber = post.postNumber,
                  let title = post.topicTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            return SolvedPostItem(
                postID: postID,
                topicID: topicID,
                postNumber: postNumber,
                topicTitle: title,
                slug: post.slug,
                excerpt: LDOHTMLText.plainText(post.excerpt) ?? "",
                categoryID: post.categoryId,
                createdAt: post.createdAt
            )
        }
        return SolvedPostPage(items: items, hasMore: source.count >= 20)
    }

    func fetchEndorsableCategories(username: String) async throws -> EndorsableCategoriesResult {
        let response: EndorsableCategoriesResponseJSON = try await getJSON(
            url: Endpoints.endorsableCategories(username: username),
            ttl: nil,
            force: true
        )
        let categories = (response.categories ?? []).compactMap { category -> EndorsableCategory? in
            guard let id = category.id,
                  let name = category.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            return EndorsableCategory(id: id, name: name, color: category.color)
        }
        return EndorsableCategoriesResult(
            categories: categories,
            remainingEndorsements: response.extras?.remainingEndorsements ?? 0
        )
    }

    func setFollowing(_ following: Bool, username: String) async throws {
        let path = "/follow/\(Self.encodedPathComponent(username)).json"
        _ = try await siteSession.requestEmpty(
            path: path,
            method: following ? "PUT" : "DELETE",
            referrer: Endpoints.userPage(username: username).absoluteString
        )
    }

    func endorse(username: String, categoryIDs: Set<Int>) async throws {
        guard !categoryIDs.isEmpty else {
            throw LDOError.decoding("请至少选择一个认可类别")
        }
        let body = categoryIDs.sorted()
            .map { "categoryIds%5B%5D=\($0)" }
            .joined(separator: "&")
        _ = try await siteSession.requestForm(
            path: "/category-experts/endorse/\(Self.encodedPathComponent(username)).json",
            method: "PUT",
            body: body,
            referrer: Endpoints.userPage(username: username).absoluteString
        )
    }

    func fetchNotifications(offset: Int = 0, limit: Int = 60) async throws -> NotificationPage {
        let response: NotificationsResponseJSON = try await getJSON(
            url: Endpoints.notifications(offset: offset, limit: limit),
            ttl: nil,
            force: true
        )
        let items = (response.notifications ?? []).compactMap(LDOUserNotification.from)
        let totalCount = response.totalRowsNotifications ?? (offset + items.count)
        let hasMore = response.totalRowsNotifications.map {
            offset + items.count < $0
        } ?? (items.count >= limit)
        return NotificationPage(
            items: items,
            totalCount: totalCount,
            hasMore: hasMore
        )
    }

    func fetchNotificationTotals() async throws -> NotificationTotals {
        let response: NotificationTotalsJSON = try await getJSON(
            url: Endpoints.notificationTotals(),
            ttl: nil,
            force: true
        )
        return NotificationTotals.from(response)
    }

    func markNotificationRead(id: Int) async throws {
        _ = try await siteSession.requestForm(
            path: "/notifications/mark-read.json",
            method: "PUT",
            body: "id=\(id)",
            referrer: Endpoints.baseURL.absoluteString
        )
    }

    func markAllNotificationsRead() async throws {
        _ = try await siteSession.requestEmpty(
            path: "/notifications/mark-read.json",
            method: "PUT",
            referrer: Endpoints.baseURL.absoluteString
        )
    }

    func createReply(
        topicID: Int,
        categoryID: Int?,
        raw: String,
        replyToPostNumber: Int?
    ) async throws -> ReplyOutcome {
        let payload = CreateReplyPayload(
            raw: raw,
            unlistTopic: false,
            topicID: topicID,
            category: categoryID,
            replyToPostNumber: replyToPostNumber,
            isWarning: false,
            whisper: false,
            archetype: "regular",
            typingDurationMsecs: 0,
            composerOpenDurationMsecs: 0,
            composerVersion: 1,
            tags: [],
            featuredLink: nil,
            sharedDraft: false,
            draftKey: "topic_\(topicID)",
            locale: "",
            imageSizes: [:],
            nestedPost: true
        )
        let body = try encoder.encode(payload)
        let data = try await siteSession.requestJSON(
            path: "/posts",
            method: "POST",
            body: body,
            referrer: Endpoints.topicPage(id: topicID).absoluteString
        )

        do {
            let response = try decoder.decode(CreatePostResponseJSON.self, from: data)
            if let post = response.post {
                return ReplyOutcome(
                    post: PostItem.from(dto: post, topicID: topicID),
                    pending: false
                )
            }
            if response.action == "enqueued" || response.pendingPost != nil {
                return ReplyOutcome(post: nil, pending: true)
            }
            throw LDOError.decoding("回复响应中缺少楼层数据")
        } catch let error as LDOError {
            throw error
        } catch {
            throw LDOError.decoding(error.localizedDescription)
        }
    }

    func invalidateCaches() {
        Task { await gate.invalidateAll() }
    }

    private func getJSON<T: Decodable>(
        url: URL,
        ttl: TimeInterval?,
        force: Bool
    ) async throws -> T {
        let key = "webkit:\(url.absoluteString)"
        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let session = siteSession
        let data = try await gate.data(forKey: key, ttl: ttl, force: force) {
            try await session.requestJSON(path: path)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[LINUXDOReader][JSON] decode failed url=\(url.absoluteString) error=\(String(reflecting: error))")
            #endif
            throw LDOError.decoding(error.localizedDescription)
        }
    }

    private func fetchFeed(url: URL, ttl: TimeInterval?, force: Bool) async throws -> RSSFeed {
        let key = "rss:\(url.absoluteString)"
        do {
            let data = try await gate.data(forKey: key, ttl: ttl, force: force) { [rssSession] in
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue(Self.appUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(
                    "application/rss+xml, application/xml;q=0.9",
                    forHTTPHeaderField: "Accept"
                )
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

                let (data, response) = try await rssSession.data(for: request)
                try Self.validateRSS(response: response, data: data)
                return data
            }
            return try RSSFeedParser.parse(data)
        } catch let error as LDOError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw LDOError.cancelled
        } catch let error as URLError {
            throw LDOError.network(error.localizedDescription)
        } catch {
            throw LDOError.network(error.localizedDescription)
        }
    }

    private func requireFallbackAllowed(_ error: Error) throws {
        if siteSession.isLoggedIn {
            throw error
        }
    }

    nonisolated private static func validateRSS(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LDOError.network("无效的 HTTP 响应")
        }

        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw LDOError.unauthorized
        case 403:
            throw LDOError.forbidden
        case 404:
            throw LDOError.notFound
        case 429:
            throw LDOError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(200)) }
            throw LDOError.server(status: http.statusCode, message: message)
        }
    }

    nonisolated private static func decodeFollowedUsernames(_ data: Data) throws -> [String] {
        let root = try JSONSerialization.jsonObject(with: data)
        let rawUsers: [Any]?

        if let users = root as? [Any] {
            rawUsers = users
        } else if let payload = root as? [String: Any] {
            if let users = payload["users"] as? [Any] {
                rawUsers = users
            } else if let users = payload["following"] as? [Any] {
                rawUsers = users
            } else if let userList = payload["user_list"] as? [String: Any],
                      let users = userList["users"] as? [Any] {
                rawUsers = users
            } else {
                rawUsers = nil
            }
        } else {
            rawUsers = nil
        }

        guard let rawUsers else {
            throw LDOError.decoding("关注用户响应格式无法识别")
        }

        let usernames = rawUsers.compactMap { item -> String? in
            if let username = item as? String { return username }
            guard let user = item as? [String: Any] else { return nil }
            return (user["username"] as? String)
                ?? (user["user_name"] as? String)
                ?? (user["userName"] as? String)
        }
        return Array(Set(usernames)).sorted()
    }

    nonisolated private static func encodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private struct CreateReplyPayload: Encodable {
    let raw: String
    let unlistTopic: Bool
    let topicID: Int
    let category: Int?
    let replyToPostNumber: Int?
    let isWarning: Bool
    let whisper: Bool
    let archetype: String
    let typingDurationMsecs: Int
    let composerOpenDurationMsecs: Int
    let composerVersion: Int
    let tags: [String]
    let featuredLink: String?
    let sharedDraft: Bool
    let draftKey: String
    let locale: String
    let imageSizes: [String: Int]
    let nestedPost: Bool
}

private extension ISO8601DateFormatter {
    static let ldo: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let ldoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
