//
//  UserProfileModels.swift
//  Discourse 用户资料、摘要、徽章与动态模型。
//

import AppKit
import Foundation

struct UserProfileRoute: Hashable, Identifiable {
    let username: String
    var displayName: String?
    var avatarTemplate: String?

    var id: String { username.lowercased() }
}

struct UserProfileDetail: Identifiable, Hashable {
    let id: Int
    let username: String
    let displayName: String?
    let title: String?
    let trustLevel: Int?
    let createdAt: Date?
    let lastPostedAt: Date?
    let badgeCount: Int
    let profileViewCount: Int
    let avatarTemplate: String?
    let bio: String?
    let canFollow: Bool
    let isFollowed: Bool
    let followerCount: Int
    let followingCount: Int
    let endorsementAvailable: Bool
    let endorsedCategoryIDs: [Int]
    let statusEmoji: String?

    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username
    }

    var trustLevelName: String? {
        guard let trustLevel, (0...4).contains(trustLevel) else { return nil }
        return ["新用户", "基本用户", "成员", "活跃用户", "领导者"][trustLevel]
    }

    static func from(_ dto: UserProfileDetailJSON) throws -> UserProfileDetail {
        guard let id = dto.id, let username = dto.username, !username.isEmpty else {
            throw LDOError.decoding("用户资料响应缺少用户标识")
        }
        return UserProfileDetail(
            id: id,
            username: username,
            displayName: dto.name?.nilIfEmpty,
            title: dto.title?.nilIfEmpty,
            trustLevel: dto.trustLevel,
            createdAt: dto.createdAt,
            lastPostedAt: dto.lastPostedAt,
            badgeCount: dto.badgeCount ?? 0,
            profileViewCount: dto.profileViewCount ?? 0,
            avatarTemplate: dto.avatarTemplate?.nilIfEmpty,
            bio: LDOHTMLText.plainText(dto.bioExcerpt ?? dto.bioCooked),
            canFollow: dto.canFollow ?? false,
            isFollowed: dto.isFollowed ?? false,
            followerCount: dto.totalFollowers ?? 0,
            followingCount: dto.totalFollowing ?? 0,
            endorsementAvailable: dto.categoryExpertEndorsements != nil,
            endorsedCategoryIDs: (dto.categoryExpertEndorsements ?? []).compactMap(\.categoryId),
            statusEmoji: dto.status?.emoji?.nilIfEmpty
        )
    }

    func withFollowed(_ followed: Bool) -> UserProfileDetail {
        UserProfileDetail(
            id: id,
            username: username,
            displayName: displayName,
            title: title,
            trustLevel: trustLevel,
            createdAt: createdAt,
            lastPostedAt: lastPostedAt,
            badgeCount: badgeCount,
            profileViewCount: profileViewCount,
            avatarTemplate: avatarTemplate,
            bio: bio,
            canFollow: canFollow,
            isFollowed: followed,
            followerCount: max(0, followerCount + (followed == isFollowed ? 0 : (followed ? 1 : -1))),
            followingCount: followingCount,
            endorsementAvailable: endorsementAvailable,
            endorsedCategoryIDs: endorsedCategoryIDs,
            statusEmoji: statusEmoji
        )
    }

    func withEndorsedCategoryIDs(_ categoryIDs: Set<Int>) -> UserProfileDetail {
        UserProfileDetail(
            id: id,
            username: username,
            displayName: displayName,
            title: title,
            trustLevel: trustLevel,
            createdAt: createdAt,
            lastPostedAt: lastPostedAt,
            badgeCount: badgeCount,
            profileViewCount: profileViewCount,
            avatarTemplate: avatarTemplate,
            bio: bio,
            canFollow: canFollow,
            isFollowed: isFollowed,
            followerCount: followerCount,
            followingCount: followingCount,
            endorsementAvailable: endorsementAvailable,
            endorsedCategoryIDs: categoryIDs.sorted(),
            statusEmoji: statusEmoji
        )
    }
}

struct UserProfileStats: Hashable {
    let daysVisited: Int
    let timeReadSeconds: Int
    let likesGiven: Int
    let likesReceived: Int
    let topicCount: Int
    let postCount: Int
    let topicsEntered: Int
    let solvedCount: Int?
}

struct UserBadgeItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let badgeTypeID: Int
    let icon: String?
    let imageURL: String?
    let grantCount: Int
    let description: String?
    let grantedAt: Date?
}

struct UserBadgeGroup: Identifiable, Hashable {
    let id: Int
    let name: String
    let badges: [UserBadgeItem]
}

struct UserTopTopic: Identifiable, Hashable {
    let topicID: Int
    let slug: String?
    let title: String
    let likeCount: Int
    let createdAt: Date?
    let categoryID: Int?

    var id: Int { topicID }
}

struct UserTopReply: Identifiable, Hashable {
    let topicID: Int
    let postNumber: Int
    let topicTitle: String
    let slug: String?
    let likeCount: Int
    let createdAt: Date?
    let categoryID: Int?

    var id: String { "\(topicID)-\(postNumber)" }
}

struct UserInteraction: Identifiable, Hashable {
    let user: UserSummary
    let count: Int

    var id: Int { user.id }
}

struct UserProfileSummary: Hashable {
    let stats: UserProfileStats
    let topBadges: [UserBadgeItem]
    let topTopics: [UserTopTopic]
    let topReplies: [UserTopReply]
    let mostRepliedToUsers: [UserInteraction]
    let mostLikedUsers: [UserInteraction]
    let mostLikedByUsers: [UserInteraction]

    static func from(_ dto: UserProfileSummaryResponseJSON) throws -> UserProfileSummary {
        guard let source = dto.userSummary else {
            throw LDOError.decoding("用户摘要响应缺少 user_summary")
        }
        let topicsByID = Dictionary(
            uniqueKeysWithValues: (dto.topics ?? []).compactMap { topic -> (Int, UserProfileTopicJSON)? in
                guard let id = topic.id else { return nil }
                return (id, topic)
            }
        )
        let badgesByID = Dictionary(
            uniqueKeysWithValues: (dto.badges ?? []).compactMap { badge -> (Int, UserBadgeDefinitionJSON)? in
                guard let id = badge.id else { return nil }
                return (id, badge)
            }
        )

        let topBadges = (source.badges ?? []).compactMap { grant -> UserBadgeItem? in
            guard let badgeID = grant.badgeId, let badge = badgesByID[badgeID] else { return nil }
            return UserBadgeItem.from(definition: badge, count: grant.count, grantedAt: nil)
        }.prefix(8)

        let topTopics = (source.topicIds ?? []).compactMap { topicID -> UserTopTopic? in
            guard let topic = topicsByID[topicID], let title = topic.title?.nilIfEmpty else { return nil }
            return UserTopTopic(
                topicID: topicID,
                slug: topic.slug?.nilIfEmpty,
                title: title,
                likeCount: topic.likeCount ?? 0,
                createdAt: topic.createdAt,
                categoryID: topic.categoryId
            )
        }.prefix(6)

        let topReplies = (source.replies ?? []).compactMap { reply -> UserTopReply? in
            guard let topicID = reply.topicId,
                  let postNumber = reply.postNumber,
                  let topic = topicsByID[topicID],
                  let title = topic.title?.nilIfEmpty else { return nil }
            return UserTopReply(
                topicID: topicID,
                postNumber: postNumber,
                topicTitle: title,
                slug: topic.slug?.nilIfEmpty,
                likeCount: reply.likeCount ?? 0,
                createdAt: reply.createdAt,
                categoryID: topic.categoryId
            )
        }.prefix(6)

        return UserProfileSummary(
            stats: UserProfileStats(
                daysVisited: source.daysVisited ?? 0,
                timeReadSeconds: source.timeRead ?? 0,
                likesGiven: source.likesGiven ?? 0,
                likesReceived: source.likesReceived ?? 0,
                topicCount: source.topicCount ?? 0,
                postCount: source.postCount ?? 0,
                topicsEntered: source.topicsEntered ?? 0,
                solvedCount: source.solvedCount
            ),
            topBadges: Array(topBadges),
            topTopics: Array(topTopics),
            topReplies: Array(topReplies),
            mostRepliedToUsers: interactions(from: source.mostRepliedToUsers),
            mostLikedUsers: interactions(from: source.mostLikedUsers),
            mostLikedByUsers: interactions(from: source.mostLikedByUsers)
        )
    }

    private static func interactions(from source: [UserInteractionJSON]?) -> [UserInteraction] {
        (source ?? []).compactMap { item in
            guard let id = item.id, let username = item.username?.nilIfEmpty else { return nil }
            return UserInteraction(
                user: UserSummary(
                    id: id,
                    username: username,
                    name: item.name?.nilIfEmpty,
                    avatarTemplate: item.avatarTemplate?.nilIfEmpty
                ),
                count: item.count ?? 0
            )
        }.prefix(5).map { $0 }
    }
}

enum UserActivityFilter: String, CaseIterable, Identifiable {
    case posts = "4,5"
    case topics = "4"
    case replies = "5"
    case likes = "1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: return "全部动态"
        case .topics: return "话题"
        case .replies: return "回复"
        case .likes: return "点赞"
        }
    }
}

struct UserActivityItem: Identifiable, Hashable {
    let actionType: Int
    let topicID: Int
    let postNumber: Int?
    let title: String
    let excerpt: String
    let categoryID: Int?
    let createdAt: Date?
    let author: UserSummary?

    var id: String {
        "\(actionType)-\(topicID)-\(postNumber ?? 0)-\(createdAt?.timeIntervalSince1970 ?? 0)"
    }
}

struct UserActivityPage: Hashable {
    let items: [UserActivityItem]
    let hasMore: Bool
}

struct SolvedPostItem: Identifiable, Hashable {
    let postID: Int
    let topicID: Int
    let postNumber: Int
    let topicTitle: String
    let slug: String?
    let excerpt: String
    let categoryID: Int?
    let createdAt: Date?

    var id: Int { postID }
}

struct SolvedPostPage: Hashable {
    let items: [SolvedPostItem]
    let hasMore: Bool
}

struct EndorsableCategory: Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String?
}

struct EndorsableCategoriesResult: Hashable {
    let categories: [EndorsableCategory]
    let remainingEndorsements: Int
}

// MARK: - DTOs

struct UserProfileResponseJSON: Decodable {
    let user: UserProfileDetailJSON?
}

struct UserProfileDetailJSON: Decodable {
    let id: Int?
    let username: String?
    let name: String?
    let title: String?
    let trustLevel: Int?
    let createdAt: Date?
    let lastPostedAt: Date?
    let badgeCount: Int?
    let profileViewCount: Int?
    let avatarTemplate: String?
    let bioExcerpt: String?
    let bioCooked: String?
    let canFollow: Bool?
    let isFollowed: Bool?
    let totalFollowers: Int?
    let totalFollowing: Int?
    let categoryExpertEndorsements: [UserEndorsementRecordJSON]?
    let status: UserStatusJSON?
}

struct UserEndorsementRecordJSON: Decodable {
    let categoryId: Int?
}

struct UserStatusJSON: Decodable {
    let emoji: String?
}

struct UserProfileSummaryResponseJSON: Decodable {
    let userSummary: UserProfileSummaryJSON?
    let badges: [UserBadgeDefinitionJSON]?
    let topics: [UserProfileTopicJSON]?
}

struct UserProfileSummaryJSON: Decodable {
    let daysVisited: Int?
    let timeRead: Int?
    let likesGiven: Int?
    let likesReceived: Int?
    let topicCount: Int?
    let postCount: Int?
    let topicsEntered: Int?
    let solvedCount: Int?
    let badges: [UserBadgeGrantJSON]?
    let topicIds: [Int]?
    let replies: [UserTopReplyJSON]?
    let mostRepliedToUsers: [UserInteractionJSON]?
    let mostLikedUsers: [UserInteractionJSON]?
    let mostLikedByUsers: [UserInteractionJSON]?
}

struct UserProfileTopicJSON: Decodable {
    let id: Int?
    let title: String?
    let slug: String?
    let likeCount: Int?
    let createdAt: Date?
    let categoryId: Int?
}

struct UserTopReplyJSON: Decodable {
    let topicId: Int?
    let postNumber: Int?
    let likeCount: Int?
    let createdAt: Date?
}

struct UserInteractionJSON: Decodable {
    let id: Int?
    let username: String?
    let name: String?
    let avatarTemplate: String?
    let count: Int?
}

struct UserBadgeDefinitionJSON: Decodable {
    let id: Int?
    let name: String?
    let badgeTypeId: Int?
    let icon: String?
    let imageUrl: String?
    let description: String?
}

struct UserBadgeGrantJSON: Decodable {
    let badgeId: Int?
    let count: Int?
}

struct UserBadgesResponseJSON: Decodable {
    let badges: [UserBadgeDefinitionJSON]?
    let badgeTypes: [UserBadgeTypeJSON]?
    let userBadges: [UserBadgeRecordJSON]?
}

struct UserBadgeTypeJSON: Decodable {
    let id: Int?
    let name: String?
}

struct UserBadgeRecordJSON: Decodable {
    let badgeId: Int?
    let grantedAt: Date?
    let count: Int?
}

struct UserActionsResponseJSON: Decodable {
    let userActions: [UserActionJSON]?
}

struct UserActionJSON: Decodable {
    let actionType: Int?
    let createdAt: Date?
    let topicId: Int?
    let postNumber: Int?
    let title: String?
    let excerpt: String?
    let categoryId: Int?
    let userId: Int?
    let username: String?
    let name: String?
    let avatarTemplate: String?
}

struct SolvedPostsResponseJSON: Decodable {
    let userSolvedPosts: [SolvedPostJSON]?
}

struct SolvedPostJSON: Decodable {
    let postId: Int?
    let topicId: Int?
    let postNumber: Int?
    let topicTitle: String?
    let slug: String?
    let excerpt: String?
    let categoryId: Int?
    let createdAt: Date?
}

struct EndorsableCategoriesResponseJSON: Decodable {
    let categories: [EndorsableCategoryJSON]?
    let extras: EndorsableExtrasJSON?
}

struct EndorsableCategoryJSON: Decodable {
    let id: Int?
    let name: String?
    let color: String?
}

struct EndorsableExtrasJSON: Decodable {
    let remainingEndorsements: Int?
}

extension UserBadgeItem {
    static func from(
        definition: UserBadgeDefinitionJSON,
        count: Int?,
        grantedAt: Date?
    ) -> UserBadgeItem? {
        guard let id = definition.id, let name = definition.name?.nilIfEmpty else { return nil }
        return UserBadgeItem(
            id: id,
            name: name,
            badgeTypeID: definition.badgeTypeId ?? 3,
            icon: definition.icon?.nilIfEmpty,
            imageURL: definition.imageUrl?.nilIfEmpty,
            grantCount: max(1, count ?? 1),
            description: definition.description.flatMap { LDOHTMLText.plainText($0) },
            grantedAt: grantedAt
        )
    }
}

enum LDOHTMLText {
    static func plainText(_ html: String?) -> String? {
        guard let html = html?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty else {
            return nil
        }
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else { return html.nilIfEmpty }
        let value = attributed.string
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
