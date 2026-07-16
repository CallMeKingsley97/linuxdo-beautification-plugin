//
//  LDOError.swift
//

import Foundation

enum LDOError: LocalizedError, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case network(String)
    case decoding(String)
    case server(status: Int, message: String?)
    case cancelled
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "需要登录后才能访问（P1 匿名模式不支持此内容）。"
        case .forbidden:
            return "没有权限访问该内容。"
        case .notFound:
            return "内容不存在或已删除。"
        case .rateLimited:
            return "请求过于频繁，请稍后再试。"
        case .network(let message):
            return "网络错误：\(message)"
        case .decoding(let message):
            return "数据解析失败：\(message)"
        case .server(let status, let message):
            if let message, !message.isEmpty {
                return "服务器错误（\(status)）：\(message)"
            }
            return "服务器错误（HTTP \(status)）。"
        case .cancelled:
            return "请求已取消。"
        case .invalidURL:
            return "无效的请求地址。"
        }
    }

    static func == (lhs: LDOError, rhs: LDOError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.notFound, .notFound),
             (.rateLimited, .rateLimited),
             (.cancelled, .cancelled),
             (.invalidURL, .invalidURL):
            return true
        case (.network(let a), .network(let b)),
             (.decoding(let a), .decoding(let b)):
            return a == b
        case (.server(let s1, let m1), .server(let s2, let m2)):
            return s1 == s2 && m1 == m2
        default:
            return false
        }
    }
}
