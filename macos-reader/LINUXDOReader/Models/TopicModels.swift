//
//  TopicModels.swift
//  领域模型 + Discourse JSON DTO
//

import Foundation

// MARK: - Domain

struct TopicSummary: Identifiable, Hashable {
    let id: Int
    let title: String
    let slug: String
    let postsCount: Int
    let replyCount: Int
    let views: Int
    let likeCount: Int
    let categoryID: Int?
    let tags: [String]
    let createdAt: Date?
    let lastPostedAt: Date?
    let bumpedAt: Date?
    let pinned: Bool
    let closed: Bool
    let archived: Bool
    let visible: Bool
    let excerpt: String?
    let lastPosterUsername: String?
    let originalPosterUsername: String?
    let posterUsernames: [String]
}

struct TopicListPage {
    let topics: [TopicSummary]
    let usersByID: [Int: UserSummary]
    let canCreateTopic: Bool
    /// 是否可能还有下一页
    let hasMore: Bool

    static func from(latest dto: LatestJSON) -> TopicListPage {
        let users = Dictionary(uniqueKeysWithValues: (dto.users ?? []).map { ($0.id, UserSummary.from($0)) })
        let topics = (dto.topicList?.topics ?? []).map { TopicSummary.from(dto: $0, users: users) }
        let hasMore = dto.topicList?.moreTopicsUrl?.isEmpty == false
        return TopicListPage(
            topics: topics,
            usersByID: users,
            canCreateTopic: dto.topicList?.canCreateTopic ?? false,
            hasMore: hasMore
        )
    }

    static func from(rss feed: RSSFeed) -> TopicListPage {
        let topics = feed.items.compactMap(TopicSummary.from)
        return TopicListPage(
            topics: topics,
            usersByID: [:],
            canCreateTopic: false,
            hasMore: false
        )
    }
}

struct UserSummary: Identifiable, Hashable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return username
    }

    static func from(_ dto: UserJSON) -> UserSummary {
        UserSummary(
            id: dto.id,
            username: dto.username ?? "user-\(dto.id)",
            name: dto.name,
            avatarTemplate: dto.avatarTemplate
        )
    }
}

struct PostItem: Identifiable, Hashable {
    let id: Int
    let topicID: Int
    let postNumber: Int
    let username: String
    let name: String?
    let userID: Int?
    let avatarTemplate: String?
    let createdAt: Date?
    let cookedHTML: String
    let replyToPostNumber: Int?
    let postType: Int?
    let acceptedAnswer: Bool
    let read: Bool?
}

struct TopicDetail: Identifiable, Hashable {
    let id: Int
    let title: String
    let slug: String
    let postsCount: Int
    let categoryID: Int?
    let tags: [String]
    let closed: Bool
    let archived: Bool
    let pinned: Bool
    let posts: [PostItem]
    let postStreamIDs: [Int]
    let chunkSize: Int?
    let deletedBy: String?
    let lastReadPostNumber: Int?
    let highestPostNumber: Int?

    static func from(dto: TopicDetailJSON, posts postDTOs: [PostJSON]? = nil) -> TopicDetail {
        let posts = (postDTOs ?? dto.postStream?.posts ?? [])
            .map { PostItem.from(dto: $0, topicID: dto.id) }
            .sorted { $0.postNumber < $1.postNumber }
        return TopicDetail(
            id: dto.id,
            title: dto.title ?? "无标题",
            slug: dto.slug ?? "",
            postsCount: dto.postsCount ?? posts.count,
            categoryID: dto.categoryId,
            tags: dto.tags?.map(\.name).filter { !$0.isEmpty } ?? [],
            closed: dto.closed ?? false,
            archived: dto.archived ?? false,
            pinned: dto.pinned ?? false,
            posts: posts,
            postStreamIDs: dto.postStream?.stream ?? posts.map(\.id),
            chunkSize: dto.chunkSize,
            deletedBy: dto.details?.deletedBy?.username,
            lastReadPostNumber: dto.lastReadPostNumber,
            highestPostNumber: dto.highestPostNumber
        )
    }

    static func from(rss feed: RSSFeed, topicID: Int) throws -> TopicDetail {
        let posts = feed.items.compactMap { PostItem.from(rss: $0, topicID: topicID) }
            .sorted { $0.postNumber < $1.postNumber }
        guard !posts.isEmpty else {
            throw LDOError.decoding("主题 RSS 中没有可显示的楼层")
        }

        return TopicDetail(
            id: topicID,
            title: feed.title.isEmpty ? posts[0].cookedHTML : feed.title,
            slug: "topic",
            postsCount: posts.count,
            categoryID: CategorySummary.rssCatalog.first { $0.name == feed.category }?.id,
            tags: feed.category.map { [$0] } ?? [],
            closed: false,
            archived: false,
            pinned: false,
            posts: posts,
            postStreamIDs: posts.map(\.id),
            chunkSize: posts.count,
            deletedBy: nil,
            lastReadPostNumber: nil,
            highestPostNumber: posts.map(\.postNumber).max()
        )
    }

    var remainingPostIDs: [Int] {
        let loaded = Set(posts.map(\.id))
        return postStreamIDs.filter { !loaded.contains($0) }
    }

    func merging(posts newPosts: [PostItem]) -> TopicDetail {
        var byID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        for post in newPosts {
            byID[post.id] = post
        }
        let merged = byID.values.sorted { $0.postNumber < $1.postNumber }
        let loadedHighestPostNumber = merged.map(\.postNumber).max() ?? 0
        return TopicDetail(
            id: id,
            title: title,
            slug: slug,
            postsCount: max(postsCount, loadedHighestPostNumber),
            categoryID: categoryID,
            tags: tags,
            closed: closed,
            archived: archived,
            pinned: pinned,
            posts: merged,
            postStreamIDs: postStreamIDs,
            chunkSize: chunkSize,
            deletedBy: deletedBy,
            lastReadPostNumber: lastReadPostNumber,
            highestPostNumber: max(highestPostNumber ?? 0, loadedHighestPostNumber)
        )
    }

    var hasServerReadState: Bool {
        lastReadPostNumber != nil || posts.contains { $0.read != nil }
    }

    var initiallyReadPostNumbers: Set<Int> {
        let watermark = lastReadPostNumber
        return Set(posts.compactMap { post in
            if post.read == true {
                return post.postNumber
            }
            if post.read == false {
                return nil
            }
            if let watermark, post.postNumber <= watermark {
                return post.postNumber
            }
            return nil
        })
    }
}

struct ReplyOutcome {
    let post: PostItem?
    let pending: Bool
}

extension TopicSummary {
    static func from(dto: TopicJSON, users: [Int: UserSummary]) -> TopicSummary {
        let posters = dto.posters ?? []
        let posterNames = posters.compactMap { username(for: $0, users: users) }
        let originalPoster = posters
            .first(where: isOriginalPoster)
            .flatMap { username(for: $0, users: users) }
            ?? posterNames.first

        let lastPoster: String? = {
            if let username = dto.lastPosterUsername, !username.isEmpty {
                return username
            }
            return posterNames.last
        }()

        return TopicSummary(
            id: dto.id,
            title: dto.title ?? "无标题",
            slug: dto.slug ?? "",
            postsCount: dto.postsCount ?? 0,
            replyCount: dto.replyCount ?? max((dto.postsCount ?? 1) - 1, 0),
            views: dto.views ?? 0,
            likeCount: dto.likeCount ?? 0,
            categoryID: dto.categoryId,
            tags: dto.tags?.map(\.name).filter { !$0.isEmpty } ?? [],
            createdAt: dto.createdAt,
            lastPostedAt: dto.lastPostedAt,
            bumpedAt: dto.bumpedAt,
            pinned: dto.pinned ?? false,
            closed: dto.closed ?? false,
            archived: dto.archived ?? false,
            visible: dto.visible ?? true,
            excerpt: dto.excerpt,
            lastPosterUsername: lastPoster,
            originalPosterUsername: originalPoster,
            posterUsernames: posterNames
        )
    }

    static func from(rss item: RSSFeedItem) -> TopicSummary? {
        guard let id = RSSIdentifier.topicID(guid: item.guid, link: item.link) else {
            return nil
        }
        let postsCount = RSSIdentifier.postsCount(in: item.html) ?? 1
        return TopicSummary(
            id: id,
            title: item.title.isEmpty ? "无标题" : item.title,
            slug: "topic",
            postsCount: postsCount,
            replyCount: max(postsCount - 1, 0),
            views: 0,
            likeCount: 0,
            categoryID: CategorySummary.rssCatalog.first { $0.name == item.category }?.id,
            tags: item.category.map { [$0] } ?? [],
            createdAt: item.publishedAt,
            lastPostedAt: item.publishedAt,
            bumpedAt: item.publishedAt,
            pinned: item.pinned,
            closed: item.closed,
            archived: item.archived,
            visible: true,
            excerpt: nil,
            lastPosterUsername: item.creator.isEmpty ? nil : item.creator,
            originalPosterUsername: item.creator.isEmpty ? nil : item.creator,
            posterUsernames: item.creator.isEmpty ? [] : [item.creator]
        )
    }

    private static func username(
        for poster: PosterJSON,
        users: [Int: UserSummary]
    ) -> String? {
        if let username = poster.user?.username, !username.isEmpty {
            return username
        }
        if let userID = poster.userId, let user = users[userID] {
            return user.username
        }
        return nil
    }

    private static func isOriginalPoster(_ poster: PosterJSON) -> Bool {
        let description = [poster.description, poster.extras]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return description.contains("original poster")
            || description.contains("topic owner")
            || description.contains("主题作者")
            || description.contains("楼主")
            || description.contains("原始发帖人")
    }
}

extension PostItem {
    static func from(dto: PostJSON, topicID: Int) -> PostItem {
        PostItem(
            id: dto.id,
            topicID: topicID,
            postNumber: dto.postNumber ?? 0,
            username: dto.username ?? "unknown",
            name: dto.name,
            userID: dto.userId,
            avatarTemplate: dto.avatarTemplate,
            createdAt: dto.createdAt,
            cookedHTML: dto.cooked ?? "",
            replyToPostNumber: dto.replyToPostNumber,
            postType: dto.postType,
            acceptedAnswer: dto.acceptedAnswer ?? false,
            read: dto.read
        )
    }

    static func from(rss item: RSSFeedItem, topicID: Int) -> PostItem? {
        guard let postNumber = RSSIdentifier.postNumber(guid: item.guid, link: item.link) else {
            return nil
        }
        return PostItem(
            id: RSSIdentifier.syntheticPostID(topicID: topicID, postNumber: postNumber),
            topicID: topicID,
            postNumber: postNumber,
            username: item.creator.isEmpty ? "unknown" : item.creator,
            name: nil,
            userID: nil,
            avatarTemplate: nil,
            createdAt: item.publishedAt,
            cookedHTML: RSSHTML.cleanedPostBody(item.html),
            replyToPostNumber: nil,
            postType: 1,
            acceptedAnswer: false,
            read: nil
        )
    }
}

private enum RSSHTML {
    static func cleanedPostBody(_ html: String) -> String {
        let pattern = #"\s*<p><a href="https://linux\.do/t/[^"]+">(?:阅读完整话题|Read full topic)</a></p>\s*$"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return html
        }
        let range = NSRange(html.startIndex..., in: html)
        return expression.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }
}

private enum RSSIdentifier {
    static func topicID(guid: String, link: String) -> Int? {
        if guid.hasPrefix("linux.do-topic-"),
           let value = Int(guid.dropFirst("linux.do-topic-".count)) {
            return value
        }
        return numericPathComponents(link).first
    }

    static func postNumber(guid: String, link: String) -> Int? {
        if guid.hasPrefix("linux.do-post-"),
           let value = guid.split(separator: "-").last.flatMap({ Int($0) }) {
            return value
        }
        return numericPathComponents(link).dropFirst().first
    }

    static func postsCount(in html: String) -> Int? {
        let pattern = #"(\d+)\s*(?:个帖子|posts?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
              ),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return Int(html[range])
    }

    static func syntheticPostID(topicID: Int, postNumber: Int) -> Int {
        topicID &* 100_000 &+ postNumber
    }

    private static func numericPathComponents(_ rawURL: String) -> [Int] {
        guard let url = URL(string: rawURL) else { return [] }
        return url.pathComponents.compactMap(Int.init)
    }
}

// MARK: - DTO

// APIClient 使用 convertFromSnakeCase，`user_id` 会被标准化为 `userId`。
// DTO 的缩写字段因此使用 Id / Url；领域模型仍使用 Swift 常见的 ID / URL 命名。

struct LatestJSON: Decodable {
    let users: [UserJSON]?
    let topicList: TopicListJSON?
}

struct TopicListJSON: Decodable {
    let canCreateTopic: Bool?
    let moreTopicsUrl: String?
    let topics: [TopicJSON]?
}

struct TopicJSON: Decodable {
    let id: Int
    let title: String?
    let fancyTitle: String?
    let slug: String?
    let postsCount: Int?
    let replyCount: Int?
    let highestPostNumber: Int?
    let imageUrl: String?
    let createdAt: Date?
    let lastPostedAt: Date?
    let bumped: Bool?
    let bumpedAt: Date?
    let archetype: String?
    let unseen: Bool?
    let pinned: Bool?
    let unpinned: Bool?
    let visible: Bool?
    let closed: Bool?
    let archived: Bool?
    let bookmarked: Bool?
    let liked: Bool?
    let tags: [TopicTagJSON]?
    let views: Int?
    let likeCount: Int?
    let categoryId: Int?
    let excerpt: String?
    let lastPosterUsername: String?
    let posters: [PosterJSON]?
}

struct PosterJSON: Decodable {
    let extras: String?
    let description: String?
    let userId: Int?
    let primaryGroupId: Int?
    let user: UserJSON?
}

struct UserJSON: Decodable {
    let id: Int
    let username: String?
    let name: String?
    let avatarTemplate: String?
    let trustLevel: Int?
}

struct TopicDetailJSON: Decodable {
    let id: Int
    let title: String?
    let fancyTitle: String?
    let postsCount: Int?
    let createdAt: Date?
    let views: Int?
    let replyCount: Int?
    let likeCount: Int?
    let lastPostedAt: Date?
    let visible: Bool?
    let closed: Bool?
    let archived: Bool?
    let hasSummary: Bool?
    let archetype: String?
    let slug: String?
    let categoryId: Int?
    let wordCount: Int?
    let deletedAt: Date?
    let userId: Int?
    let pinned: Bool?
    let tags: [TopicTagJSON]?
    let chunkSize: Int?
    let postStream: PostStreamJSON?
    let details: TopicDetailsJSON?
    let lastReadPostNumber: Int?
    let highestPostNumber: Int?
}

struct PostStreamJSON: Decodable {
    let posts: [PostJSON]?
    let stream: [Int]?
}

struct PostJSON: Decodable {
    let id: Int
    let name: String?
    let username: String?
    let avatarTemplate: String?
    let createdAt: Date?
    let cooked: String?
    let postNumber: Int?
    let postType: Int?
    let updatedAt: Date?
    let replyCount: Int?
    let replyToPostNumber: Int?
    let quoteCount: Int?
    let incomingLinkCount: Int?
    let reads: Int?
    let readersCount: Int?
    let score: Double?
    let yours: Bool?
    let topicId: Int?
    let topicSlug: String?
    let displayUsername: String?
    let primaryGroupName: String?
    let flairName: String?
    let version: Int?
    let canEdit: Bool?
    let canDelete: Bool?
    let canRecover: Bool?
    let canWiki: Bool?
    let userId: Int?
    let acceptedAnswer: Bool?
    let read: Bool?
}

struct TopicDetailsJSON: Decodable {
    let createdBy: UserJSON?
    let lastPoster: UserJSON?
    let deletedBy: UserJSON?
}

struct TopicTagJSON: Decodable {
    let name: String

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            name = value
            return
        }
        if let value = try? single.decode(Int.self) {
            name = String(value)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .name), !value.isEmpty {
            name = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .slug), !value.isEmpty {
            name = value
        } else {
            name = ""
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, slug
    }
}

struct CreatePostResponseJSON: Decodable {
    let action: String?
    let success: Bool?
    let post: PostJSON?
    let pendingPost: PostJSON?
}
