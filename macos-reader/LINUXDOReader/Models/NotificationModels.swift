//
//  NotificationModels.swift
//  Discourse 通知中心模型。覆盖核心 1...45、Follow 800...802 与 Circles 900。
//

import Foundation

enum NotificationGroup: String, CaseIterable, Identifiable {
    case all
    case replies
    case likes
    case messages
    case chat
    case bookmarks
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .replies: return "回复"
        case .likes: return "赞"
        case .messages: return "私信"
        case .chat: return "聊天"
        case .bookmarks: return "书签"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "bell"
        case .replies: return "arrowshape.turn.up.left"
        case .likes: return "heart"
        case .messages: return "envelope"
        case .chat: return "bubble.left.and.bubble.right"
        case .bookmarks: return "bookmark"
        case .other: return "ellipsis.circle"
        }
    }

    func contains(_ kind: NotificationKind) -> Bool {
        self == .all || kind.group == self
    }
}

/// 使用结构体而非 raw-value enum，确保服务端新增类型时仍可完整展示。
struct NotificationKind: Hashable {
    let rawValue: Int

    static let knownRawValues = Array(1...45) + [800, 801, 802, 900]

    var isKnown: Bool { Self.knownRawValues.contains(rawValue) }

    var group: NotificationGroup {
        switch rawValue {
        case 1, 2, 3, 9, 15:
            return .replies
        case 5, 19, 25:
            return .likes
        case 6, 7, 16:
            return .messages
        case 24:
            return .bookmarks
        case 29, 30, 31, 32, 33, 40:
            return .chat
        default:
            return .other
        }
    }

    var title: String {
        switch rawValue {
        case 1: return "提及了你"
        case 2: return "回复了你"
        case 3: return "引用了你的帖子"
        case 4: return "编辑了你的帖子"
        case 5: return "点赞了你的帖子"
        case 6: return "发来私人消息"
        case 7: return "邀请你加入私人消息"
        case 8: return "接受了你的邀请"
        case 9: return "发布了新帖子"
        case 10: return "移动了帖子"
        case 11: return "链接了你的帖子"
        case 12: return "获得新徽章"
        case 13: return "邀请你加入话题"
        case 14: return "站点通知"
        case 15: return "在群组中提及了你"
        case 16: return "收到群组消息"
        case 17: return "创建了新话题"
        case 18: return "话题提醒"
        case 19: return "多个帖子收到点赞"
        case 20: return "帖子审核通过"
        case 21: return "代码评审通过"
        case 22: return "成员资格申请已接受"
        case 23: return "新的成员资格申请"
        case 24: return "书签提醒"
        case 25: return "回应了你的帖子"
        case 26: return "投票额度已释放"
        case 27: return "活动提醒"
        case 28: return "活动邀请"
        case 29: return "在聊天中提及了你"
        case 30: return "收到聊天消息"
        case 31: return "邀请你加入聊天"
        case 32: return "聊天群组提及"
        case 33: return "聊天内容被引用"
        case 34: return "有新任务指派给你"
        case 35: return "问答收到新评论"
        case 36: return "关注的分类或标签有新帖"
        case 37: return "有新功能可用"
        case 38: return "站点信息中心有新建议"
        case 39: return "多个帖子收到新链接"
        case 40: return "关注的聊天线程有新消息"
        case 41: return "即将推出的更改可供预览"
        case 42: return "即将推出的更改已自动启用"
        case 43: return "Boost 动态"
        case 44: return "收到新的修改建议"
        case 45: return "修改建议已被接受"
        case 800: return "开始关注你"
        case 801: return "关注的用户创建了新话题"
        case 802: return "关注的用户发布了新回复"
        case 900: return "Circles 动态"
        default: return "新通知 · 类型 \(rawValue)"
        }
    }

    var systemImage: String {
        switch rawValue {
        case 1, 15, 29, 32: return "at"
        case 2, 802: return "arrowshape.turn.up.left"
        case 3, 33: return "quote.bubble"
        case 4: return "pencil"
        case 5, 19: return "heart"
        case 6, 7, 16: return "envelope"
        case 8, 20, 21, 22, 42, 45: return "checkmark.circle"
        case 9, 17, 36, 801: return "text.badge.plus"
        case 10: return "arrow.right.square"
        case 11, 39: return "link"
        case 12: return "medal"
        case 13, 28, 31: return "person.badge.plus"
        case 14: return "bell"
        case 18: return "clock.badge"
        case 23: return "person.3"
        case 24: return "bookmark"
        case 25: return "face.smiling"
        case 26: return "arrow.uturn.backward.circle"
        case 27: return "calendar.badge.clock"
        case 30, 35: return "message"
        case 34: return "person.crop.circle.badge.checkmark"
        case 37: return "gift"
        case 38: return "exclamationmark.triangle"
        case 40: return "bubble.left.and.bubble.right"
        case 41: return "flask"
        case 43: return "bolt.heart"
        case 44: return "pencil.and.list.clipboard"
        case 800: return "person.badge.plus"
        case 900: return "circle.grid.3x3"
        default: return "bell"
        }
    }

    var omitsActor: Bool {
        switch rawValue {
        case 12, 16, 18, 19, 20, 21, 22, 23, 24, 26, 37, 38, 39, 41, 42:
            return true
        default:
            return false
        }
    }
}

enum NotificationDestination {
    case topic(id: Int, slug: String?, postNumber: Int?)
    case user(username: String)
    case site(path: String)
}

struct LDOUserNotification: Identifiable {
    let id: Int
    let kind: NotificationKind
    let isRead: Bool
    let isHighPriority: Bool
    let createdAt: Date?
    let postNumber: Int?
    let topicID: Int?
    let fancyTitle: String?
    let slug: String?
    let payload: NotificationPayload
    let actingUserAvatarTemplate: String?
    let actingUserName: String?

    static func from(_ dto: NotificationJSON) -> LDOUserNotification? {
        guard let id = dto.id, let type = dto.notificationType else { return nil }
        return LDOUserNotification(
            id: id,
            kind: NotificationKind(rawValue: type),
            isRead: dto.read ?? false,
            isHighPriority: dto.highPriority ?? false,
            createdAt: dto.createdAt,
            postNumber: dto.postNumber,
            topicID: dto.topicId,
            fancyTitle: LDOHTMLText.plainText(dto.fancyTitle),
            slug: dto.slug?.nilIfEmpty,
            payload: NotificationPayload(values: dto.data ?? [:]),
            actingUserAvatarTemplate: dto.actingUserAvatarTemplate?.nilIfEmpty,
            actingUserName: dto.actingUserName?.nilIfEmpty
        )
    }

    var actorUsername: String? {
        payload.string(
            "display_username",
            "mentioned_by_username",
            "invited_by_username",
            "username"
        )?.nilIfEmpty
    }

    var actorLabel: String? {
        guard !kind.omitsActor else { return nil }
        if let actingUserName, !actingUserName.isEmpty { return actingUserName }
        if let name = payload.string("display_name", "name"), !name.isEmpty { return name }
        return actorUsername.map { "@\($0)" }
    }

    var headline: String {
        if let actorLabel {
            return "\(actorLabel) · \(kind.title)"
        }
        return kind.title
    }

    var contextText: String? {
        let candidates = [
            fancyTitle,
            payload.string("topic_title"),
            payload.string("title"),
            payload.string("event_name"),
            payload.string("badge_name"),
            payload.string("chat_channel_title"),
            payload.string("description"),
            translatedMessage,
        ]
        return candidates.compactMap { $0?.nilIfEmpty }.first
    }

    var destinationHint: String {
        if topicID != nil { return "打开原生主题" }
        switch kind.rawValue {
        case 8, 800: return "打开用户资料"
        case 12: return "查看徽章"
        case 29, 30, 31, 32, 40: return "打开站内聊天"
        default: return isRead ? "已读" : "标记为已读"
        }
    }

    func destination(currentUsername: String?) -> NotificationDestination? {
        if let topicID {
            return .topic(id: topicID, slug: slug, postNumber: postNumber)
        }

        switch kind.rawValue {
        case 8, 800:
            return actorUsername.map(NotificationDestination.user)
        case 12:
            guard let badgeID = payload.int("badge_id") else { return nil }
            let badgeSlug = payload.string("badge_slug") ?? "badge"
            var path = "/badges/\(badgeID)/\(Self.pathComponent(badgeSlug))"
            if let username = payload.string("username") {
                path += "?username=\(Self.queryComponent(username.lowercased()))"
            }
            return .site(path: path)
        case 16:
            guard let username = payload.string("username") ?? currentUsername,
                  let groupName = payload.string("group_name") else { return nil }
            return .site(
                path: "/u/\(Self.pathComponent(username))/messages/group/\(Self.pathComponent(groupName))"
            )
        case 19:
            guard let currentUsername else { return nil }
            var path = "/u/\(Self.pathComponent(currentUsername))/notifications/likes-received"
            if let username = payload.string("username") {
                path += "?acting_username=\(Self.queryComponent(username))"
            }
            return .site(path: path)
        case 22:
            return payload.string("group_name").map {
                .site(path: "/g/\(Self.pathComponent($0))")
            }
        case 23:
            return currentUsername.map {
                .site(path: "/u/\(Self.pathComponent($0))/messages")
            }
        case 24:
            return payload.string("bookmarkable_url").map(NotificationDestination.site)
        case 29, 30, 31, 32, 40:
            return chatDestination
        case 37:
            return .site(path: "/admin/whats-new")
        case 38:
            return .site(path: "/admin")
        case 39:
            guard let currentUsername else { return nil }
            var path = "/u/\(Self.pathComponent(currentUsername))/notifications/links"
            if let username = payload.string("username") {
                path += "?acting_username=\(Self.queryComponent(username))"
            }
            return .site(path: path)
        case 41, 42:
            return .site(path: "/admin/config/upcoming-changes")
        default:
            if let path = payload.string("url", "path") {
                return .site(path: path)
            }
            return nil
        }
    }

    func withRead(_ read: Bool) -> LDOUserNotification {
        LDOUserNotification(
            id: id,
            kind: kind,
            isRead: read,
            isHighPriority: isHighPriority,
            createdAt: createdAt,
            postNumber: postNumber,
            topicID: topicID,
            fancyTitle: fancyTitle,
            slug: slug,
            payload: payload,
            actingUserAvatarTemplate: actingUserAvatarTemplate,
            actingUserName: actingUserName
        )
    }

    private var chatDestination: NotificationDestination? {
        guard let channelID = payload.int("chat_channel_id") else { return nil }
        let slug = payload.string("chat_channel_slug")?.nilIfEmpty ?? "-"
        var path = "/chat/c/\(Self.pathComponent(slug))/\(channelID)"
        if let threadID = payload.int("chat_thread_id") {
            path += "/t/\(threadID)"
            if let messageID = payload.int("chat_message_id") {
                path += "/\(messageID)"
            }
        } else if let messageID = payload.int("chat_message_id") {
            path += "/\(messageID)"
        }
        return .site(path: path)
    }

    private var translatedMessage: String? {
        guard let message = payload.string("message") else { return nil }
        switch message {
        case "discourse_assign.assign_notification":
            return "有任务指派给你"
        case "discourse_post_event.notifications.before_event_reminder":
            return "活动即将开始"
        case "discourse_post_event.notifications.ongoing_event_reminder":
            return "活动正在进行"
        case "discourse_post_event.notifications.after_event_reminder":
            return "活动已经结束"
        case "discourse_post_event.notifications.invite_user_notification",
             "discourse_post_event.notifications.invite_user_auto_notification",
             "discourse_calendar.invite_user_notification",
             "discourse_post_event.notifications.invite_user_predefined_attendance_notification":
            return "邀请你参加活动"
        default:
            return message.contains(".") ? nil : message
        }
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func queryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

struct NotificationPage {
    let items: [LDOUserNotification]
    let totalCount: Int
    let hasMore: Bool
}

struct NotificationTotals {
    let unreadNotifications: Int
    let unreadPersonalMessages: Int
    let unseenReviewables: Int
    let chatNotifications: Int

    var totalUnread: Int {
        unreadNotifications + unreadPersonalMessages + chatNotifications
    }

    static let empty = NotificationTotals(
        unreadNotifications: 0,
        unreadPersonalMessages: 0,
        unseenReviewables: 0,
        chatNotifications: 0
    )

    static func from(_ dto: NotificationTotalsJSON) -> NotificationTotals {
        NotificationTotals(
            unreadNotifications: dto.unreadNotifications ?? 0,
            unreadPersonalMessages: dto.unreadPersonalMessages ?? 0,
            unseenReviewables: dto.unseenReviewables ?? 0,
            chatNotifications: dto.chatNotifications ?? 0
        )
    }
}

struct NotificationPayload {
    let values: [String: JSONValue]

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = values[key]?.stringValue { return value }
        }
        return nil
    }

    func int(_ key: String) -> Int? {
        values[key]?.intValue
    }
}

enum JSONValue: Decodable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析通知数据字段"
            )
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .boolean(let value): return String(value)
        case .array, .object, .null: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .integer(let value): return value
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .boolean, .array, .object, .null: return nil
        }
    }
}

struct NotificationsResponseJSON: Decodable {
    let notifications: [NotificationJSON]?
    let totalRowsNotifications: Int?
    let seenNotificationId: Int?
    let loadMoreNotifications: String?
}

struct NotificationJSON: Decodable {
    let id: Int?
    let notificationType: Int?
    let read: Bool?
    let highPriority: Bool?
    let createdAt: Date?
    let postNumber: Int?
    let topicId: Int?
    let fancyTitle: String?
    let slug: String?
    let data: [String: JSONValue]?
    let actingUserAvatarTemplate: String?
    let actingUserName: String?
}

struct NotificationTotalsJSON: Decodable {
    let unreadNotifications: Int?
    let unreadPersonalMessages: Int?
    let unseenReviewables: Int?
    let chatNotifications: Int?
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
