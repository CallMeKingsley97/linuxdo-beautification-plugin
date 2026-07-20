//
//  Endpoints.swift
//

import Foundation

enum Endpoints {
    static let baseURL = URL(string: "https://linux.do")!

    static func latest(page: Int = 0) -> URL {
        paged(path: "latest.json", page: page)
    }

    static func hot(page: Int = 0) -> URL {
        paged(path: "hot.json", page: page)
    }

    static func categories() -> URL {
        baseURL.appendingPathComponent("categories.json")
    }

    static func category(slug: String, id: Int, page: Int = 0) -> URL {
        paged(path: "c/\(slug)/\(id).json", page: page)
    }

    static func topic(id: Int) -> URL {
        baseURL.appendingPathComponent("t/\(id).json")
    }

    static func topicPosts(id: Int, postIDs: [Int]) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("t/\(id)/posts.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = postIDs.map {
            URLQueryItem(name: "post_ids[]", value: String($0))
        } + [URLQueryItem(name: "include_suggested", value: "false")]
        return components.url!
    }

    static func topicPage(id: Int, slug: String? = nil) -> URL {
        if let slug, !slug.isEmpty, slug != "topic" {
            return baseURL.appendingPathComponent("t/\(slug)/\(id)")
        }
        return baseURL.appendingPathComponent("t/\(id)")
    }

    static func login() -> URL {
        baseURL.appendingPathComponent("login")
    }

    static func sessionCSRF() -> URL {
        baseURL.appendingPathComponent("session/csrf.json")
    }

    static func following(username: String) -> URL {
        baseURL
            .appendingPathComponent("u")
            .appendingPathComponent(username)
            .appendingPathComponent("follow")
            .appendingPathComponent("following.json")
    }

    static func userProfile(username: String) -> URL {
        baseURL
            .appendingPathComponent("u")
            .appendingPathComponent(username)
            .appendingPathExtension("json")
    }

    static func userSummary(username: String) -> URL {
        baseURL
            .appendingPathComponent("u")
            .appendingPathComponent(username)
            .appendingPathComponent("summary.json")
    }

    static func userPage(username: String) -> URL {
        baseURL
            .appendingPathComponent("u")
            .appendingPathComponent(username)
            .appendingPathComponent("summary")
    }

    static func userActions(username: String, filter: String, offset: Int) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("user_actions.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(max(0, offset))),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "filter", value: filter),
        ]
        return components.url!
    }

    static func userBadges(username: String) -> URL {
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("user-badges")
                .appendingPathComponent(username)
                .appendingPathExtension("json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grouped", value: "true")]
        return components.url!
    }

    static func solvedPosts(username: String, offset: Int, limit: Int = 20) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("solution/by_user.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "offset", value: String(max(0, offset))),
            URLQueryItem(name: "limit", value: String(max(1, limit))),
        ]
        return components.url!
    }

    static func endorsableCategories(username: String) -> URL {
        baseURL
            .appendingPathComponent("category-experts/endorsable-categories")
            .appendingPathComponent(username)
            .appendingPathExtension("json")
    }

    static func notifications(offset: Int = 0, limit: Int = 60) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("notifications.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(max(0, offset))),
            URLQueryItem(name: "limit", value: String(min(max(1, limit), 60))),
        ]
        return components.url!
    }

    static func notificationTotals() -> URL {
        baseURL.appendingPathComponent("notifications/totals.json")
    }

    static func latestRSS() -> URL {
        baseURL.appendingPathComponent("latest.rss")
    }

    static func hotRSS() -> URL {
        baseURL.appendingPathComponent("hot.rss")
    }

    static func categoryRSS(slug: String, id: Int) -> URL {
        baseURL.appendingPathComponent("c/\(slug)/\(id).rss")
    }

    static func topicRSS(id: Int) -> URL {
        baseURL.appendingPathComponent("t/topic/\(id).rss")
    }

    static func avatarURL(template: String, size: Int = 64) -> URL? {
        let path = template.replacingOccurrences(of: "{size}", with: String(size))
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if path.hasPrefix("//") {
            return URL(string: "https:\(path)")
        }
        if path.hasPrefix("/") {
            return URL(string: path, relativeTo: baseURL)?.absoluteURL
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private static func paged(path: String, page: Int) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if page > 0 {
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        return components.url!
    }
}
