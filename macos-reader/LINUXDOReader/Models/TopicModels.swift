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
        let hasMore: Bool = {
            if let more = dto.topicList?.moreTopicsURL, !more.isEmpty {
                return true
            }
            return !topics.isEmpty
        }()
        return TopicListPage(
            topics: topics,
            usersByID: users,
            canCreateTopic: dto.topicList?.canCreateTopic ?? false,
            hasMore: hasMore
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
    let chunkSize: Int?
    let deletedBy: String?

    static func from(dto: TopicDetailJSON) -> TopicDetail {
        let posts = (dto.postStream?.posts ?? []).map { PostItem.from(dto: $0, topicID: dto.id) }
        return TopicDetail(
            id: dto.id,
            title: dto.title ?? "无标题",
            slug: dto.slug ?? "",
            postsCount: dto.postsCount ?? posts.count,
            categoryID: dto.categoryID,
            tags: dto.tags ?? [],
            closed: dto.closed ?? false,
            archived: dto.archived ?? false,
            pinned: dto.pinned ?? false,
            posts: posts,
            chunkSize: dto.chunkSize,
            deletedBy: dto.details?.deletedBy?.username
        )
    }
}

extension TopicSummary {
    static func from(dto: TopicJSON, users: [Int: UserSummary]) -> TopicSummary {
        let posterNames: [String] = (dto.posters ?? []).compactMap { poster in
            if let name = poster.user?.username { return name }
            if let uid = poster.userID, let user = users[uid] { return user.username }
            return nil
        }

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
            categoryID: dto.categoryID,
            tags: dto.tags ?? [],
            createdAt: dto.createdAt,
            lastPostedAt: dto.lastPostedAt,
            bumpedAt: dto.bumpedAt,
            pinned: dto.pinned ?? false,
            closed: dto.closed ?? false,
            archived: dto.archived ?? false,
            visible: dto.visible ?? true,
            excerpt: dto.excerpt,
            lastPosterUsername: lastPoster,
            posterUsernames: posterNames
        )
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
            userID: dto.userID,
            avatarTemplate: dto.avatarTemplate,
            createdAt: dto.createdAt,
            cookedHTML: dto.cooked ?? "",
            replyToPostNumber: dto.replyToPostNumber,
            postType: dto.postType,
            acceptedAnswer: dto.acceptedAnswer ?? false
        )
    }
}

// MARK: - DTO

struct LatestJSON: Decodable {
    let users: [UserJSON]?
    let topicList: TopicListJSON?
}

struct TopicListJSON: Decodable {
    let canCreateTopic: Bool?
    let moreTopicsURL: String?
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
    let imageURL: String?
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
    let tags: [String]?
    let views: Int?
    let likeCount: Int?
    let categoryID: Int?
    let excerpt: String?
    let lastPosterUsername: String?
    let posters: [PosterJSON]?
}

struct PosterJSON: Decodable {
    let extras: String?
    let description: String?
    let userID: Int?
    let primaryGroupID: Int?
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
    let categoryID: Int?
    let wordCount: Int?
    let deletedAt: Date?
    let userID: Int?
    let pinned: Bool?
    let tags: [String]?
    let chunkSize: Int?
    let postStream: PostStreamJSON?
    let details: TopicDetailsJSON?
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
    let topicID: Int?
    let topicSlug: String?
    let displayUsername: String?
    let primaryGroupName: String?
    let flairName: String?
    let version: Int?
    let canEdit: Bool?
    let canDelete: Bool?
    let canRecover: Bool?
    let canWiki: Bool?
    let userID: Int?
    let acceptedAnswer: Bool?
}

struct TopicDetailsJSON: Decodable {
    let createdBy: UserJSON?
    let lastPoster: UserJSON?
    let deletedBy: UserJSON?
}
