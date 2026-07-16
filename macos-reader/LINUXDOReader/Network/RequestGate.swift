//
//  RequestGate.swift
//  请求去重 + 成功缓存 TTL（P1 简化版）
//

import Foundation

actor RequestGate {
    struct CacheEntry {
        let data: Data
        let expiresAt: Date
    }

    private var inflight: [String: Task<Data, Error>] = [:]
    private var cache: [String: CacheEntry] = [:]

    /// - Parameters:
    ///   - key: 通常为完整 URL 字符串
    ///   - ttl: 成功缓存时长；nil 表示不缓存
    ///   - force: 忽略缓存强制刷新
    func data(
        forKey key: String,
        ttl: TimeInterval?,
        force: Bool,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if !force, let ttl, let entry = cache[key], entry.expiresAt > Date() {
            return entry.data
        }

        if let existing = inflight[key] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            try await operation()
        }
        inflight[key] = task

        do {
            let data = try await task.value
            if let ttl {
                cache[key] = CacheEntry(data: data, expiresAt: Date().addingTimeInterval(ttl))
            }
            inflight[key] = nil
            return data
        } catch {
            inflight[key] = nil
            throw error
        }
    }

    func invalidate(key: String) {
        cache[key] = nil
    }

    func invalidateAll() {
        cache.removeAll()
    }
}
