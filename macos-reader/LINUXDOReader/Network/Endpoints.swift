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
