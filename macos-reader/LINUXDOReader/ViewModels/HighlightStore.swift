//
//  HighlightStore.swift
//  关注作者与关键词高亮偏好、缓存和同步。
//

import Foundation
import SwiftUI

struct KeywordHighlightRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var keyword: String
    var colorHex: String
    var enabled: Bool

    init(
        id: UUID = UUID(),
        keyword: String = "",
        colorHex: String = "#FFD166",
        enabled: Bool = true
    ) {
        self.id = id
        self.keyword = keyword
        self.colorHex = colorHex
        self.enabled = enabled
    }
}

struct TopicHighlight: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case keyword
        case followed
    }

    let reason: Reason
    let colorHex: String
    let keyword: String?
    let keywordColorHex: String?

    init(
        reason: Reason,
        colorHex: String,
        keyword: String? = nil,
        keywordColorHex: String? = nil
    ) {
        self.reason = reason
        self.colorHex = colorHex
        self.keyword = keyword
        self.keywordColorHex = keywordColorHex
    }

    var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }

    var keywordColor: Color {
        Color(hex: keywordColorHex ?? colorHex) ?? .accentColor
    }
}

@MainActor
final class HighlightStore: ObservableObject {
    @Published var followedHighlightEnabled: Bool {
        didSet { savePreferences() }
    }
    @Published var followedColorHex: String {
        didSet { savePreferences() }
    }
    @Published var keywordsEnabled: Bool {
        didSet { savePreferences() }
    }
    @Published var keywordRules: [KeywordHighlightRule] {
        didSet { savePreferences() }
    }

    @Published private(set) var followedUsernames: Set<String> = []
    @Published private(set) var followedUsersOwner: String?
    @Published private(set) var isSyncingFollowedUsers = false
    @Published private(set) var lastFollowedUsersSyncAt: Date?
    @Published private(set) var followedUsersSyncError: String?

    private let api: APIClient
    private let defaults: UserDefaults
    private var syncTask: Task<Void, Never>?

    private static let preferencesKey = "com.linuxdo.reader.highlight-preferences-v1"
    private static let followedCacheKey = "com.linuxdo.reader.followed-users-v1"
    private static let defaultFollowedColor = "#40B883"
    private static let defaultKeywordColor = "#FFD166"

    init(api: APIClient, defaults: UserDefaults = .standard) {
        let preferences = Self.loadPreferences(from: defaults)
        self.api = api
        self.defaults = defaults
        self.followedHighlightEnabled = preferences.followedHighlightEnabled
        self.followedColorHex = Self.normalizedColor(
            preferences.followedColorHex,
            fallback: Self.defaultFollowedColor
        )
        self.keywordsEnabled = preferences.keywordsEnabled
        self.keywordRules = preferences.keywordRules.map(Self.normalizedRule)
    }

    deinit {
        syncTask?.cancel()
    }

    var followedColor: Color {
        Color(hex: followedColorHex) ?? Color(hex: Self.defaultFollowedColor) ?? .green
    }

    func setFollowedColor(_ color: Color) {
        guard let hex = color.ldoHexRGB else { return }
        followedColorHex = hex
    }

    @discardableResult
    func addKeywordRule() -> UUID {
        let rule = KeywordHighlightRule(colorHex: Self.defaultKeywordColor)
        keywordRules.append(rule)
        return rule.id
    }

    func removeKeywordRule(id: UUID) {
        keywordRules.removeAll { $0.id == id }
    }

    func setKeyword(_ keyword: String, ruleID: UUID) {
        updateKeywordRule(id: ruleID) { rule in
            rule.keyword = keyword
        }
    }

    func setKeywordEnabled(_ enabled: Bool, ruleID: UUID) {
        updateKeywordRule(id: ruleID) { rule in
            rule.enabled = enabled
        }
    }

    func setKeywordColor(_ color: Color, ruleID: UUID) {
        guard let hex = color.ldoHexRGB else { return }
        updateKeywordRule(id: ruleID) { rule in
            rule.colorHex = hex
        }
    }

    func keywordColor(ruleID: UUID) -> Color {
        guard let rule = keywordRules.first(where: { $0.id == ruleID }) else {
            return Color(hex: Self.defaultKeywordColor) ?? .yellow
        }
        return Color(hex: rule.colorHex) ?? Color(hex: Self.defaultKeywordColor) ?? .yellow
    }

    func topicHighlight(for topic: TopicSummary) -> TopicHighlight? {
        let keywordRule = matchingKeywordRule(for: topic)
        let keyword = keywordRule?.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywordColorHex = keywordRule.map {
            Self.normalizedColor($0.colorHex, fallback: Self.defaultKeywordColor)
        }

        if followedHighlightEnabled, followedUsername(in: topic) != nil {
            return TopicHighlight(
                reason: .followed,
                colorHex: followedColorHex,
                keyword: keyword,
                keywordColorHex: keywordColorHex
            )
        }

        guard let keywordRule, let keyword, !keyword.isEmpty else { return nil }
        return TopicHighlight(
            reason: .keyword,
            colorHex: Self.normalizedColor(
                keywordRule.colorHex,
                fallback: Self.defaultKeywordColor
            ),
            keyword: keyword,
            keywordColorHex: keywordColorHex
        )
    }

    func followedUsername(in topic: TopicSummary) -> String? {
        let usernames = [topic.originalPosterUsername].compactMap { $0 }
            + topic.posterUsernames
        return usernames.first(where: isFollowing)
    }

    func isFollowing(_ username: String) -> Bool {
        followedUsernames.contains(Self.normalizedUsername(username))
    }

    func setFollowing(_ username: String, isFollowing: Bool) {
        guard let owner = followedUsersOwner else { return }
        let normalized = Self.normalizedUsername(username)
        guard !normalized.isEmpty, normalized != owner else { return }

        if isFollowing {
            followedUsernames.insert(normalized)
        } else {
            followedUsernames.remove(normalized)
        }

        var cache = loadFollowedCache()
        let key = Self.accountKey(owner)
        var record = cache.accounts[key] ?? FollowedUsersRecord()
        record.users = followedUsernames.sorted()
        record.lastSuccessAt = Date()
        cache.accounts[key] = record
        saveFollowedCache(cache)
        lastFollowedUsersSyncAt = record.lastSuccessAt
    }

    private func matchingKeywordRule(for topic: TopicSummary) -> KeywordHighlightRule? {
        guard keywordsEnabled else { return nil }
        return keywordRules.first(where: { rule in
            let keyword = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            return rule.enabled
                && !keyword.isEmpty
                && topic.title.localizedCaseInsensitiveContains(keyword)
        })
    }

    func sessionDidChange(_ user: SiteUser?) {
        syncTask?.cancel()
        syncTask = nil
        followedUsersSyncError = nil

        guard let owner = user.map({ Self.normalizedUsername($0.username) }), !owner.isEmpty else {
            followedUsersOwner = nil
            followedUsernames = []
            lastFollowedUsersSyncAt = nil
            isSyncingFollowedUsers = false
            return
        }

        followedUsersOwner = owner
        hydrateFollowedUsers(owner: owner)
        syncFollowedUsers(force: false)
    }

    func syncFollowedUsers(force: Bool) {
        guard let owner = followedUsersOwner, !owner.isEmpty, syncTask == nil else { return }

        let cache = loadFollowedCache()
        let currentRecord = cache.accounts[Self.accountKey(owner)] ?? FollowedUsersRecord()
        if !force, currentRecord.lastAttemptDay == Self.localDayKey() {
            return
        }

        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.performFollowedUsersSync(owner: owner)
        }
    }

    private func performFollowedUsersSync(owner: String) async {
        isSyncingFollowedUsers = true
        followedUsersSyncError = nil

        var cache = loadFollowedCache()
        let accountKey = Self.accountKey(owner)
        var record = cache.accounts[accountKey] ?? FollowedUsersRecord()
        record.lastAttemptDay = Self.localDayKey()
        cache.accounts[accountKey] = record
        saveFollowedCache(cache)

        defer {
            isSyncingFollowedUsers = false
            syncTask = nil
        }

        do {
            let usernames = try await api.fetchFollowedUsernames(username: owner)
            guard followedUsersOwner == owner else { return }

            let normalizedUsers = Array(
                Set(usernames.map(Self.normalizedUsername).filter { !$0.isEmpty && $0 != owner })
            ).sorted()
            let syncedAt = Date()
            record.users = normalizedUsers
            record.lastSuccessAt = syncedAt
            cache.accounts[accountKey] = record
            saveFollowedCache(cache)

            followedUsernames = Set(normalizedUsers)
            lastFollowedUsersSyncAt = syncedAt
        } catch is CancellationError {
            return
        } catch {
            guard followedUsersOwner == owner else { return }
            followedUsersSyncError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            hydrateFollowedUsers(owner: owner)
        }
    }

    private func hydrateFollowedUsers(owner: String) {
        let record = loadFollowedCache().accounts[Self.accountKey(owner)]
            ?? FollowedUsersRecord()
        followedUsernames = Set(record.users.map(Self.normalizedUsername).filter { !$0.isEmpty })
        lastFollowedUsersSyncAt = record.lastSuccessAt
    }

    private func savePreferences() {
        let preferences = HighlightPreferences(
            followedHighlightEnabled: followedHighlightEnabled,
            followedColorHex: Self.normalizedColor(
                followedColorHex,
                fallback: Self.defaultFollowedColor
            ),
            keywordsEnabled: keywordsEnabled,
            keywordRules: keywordRules.map(Self.normalizedRule)
        )
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.preferencesKey)
    }

    private func updateKeywordRule(
        id: UUID,
        update: (inout KeywordHighlightRule) -> Void
    ) {
        guard let index = keywordRules.firstIndex(where: { $0.id == id }) else { return }
        var rules = keywordRules
        update(&rules[index])
        keywordRules = rules
    }

    private static func loadPreferences(from defaults: UserDefaults) -> HighlightPreferences {
        guard let data = defaults.data(forKey: preferencesKey),
              let preferences = try? JSONDecoder().decode(HighlightPreferences.self, from: data) else {
            return HighlightPreferences()
        }
        return preferences
    }

    private func loadFollowedCache() -> FollowedUsersCache {
        guard let data = defaults.data(forKey: Self.followedCacheKey),
              let cache = try? JSONDecoder().decode(FollowedUsersCache.self, from: data) else {
            return FollowedUsersCache()
        }
        return cache
    }

    private func saveFollowedCache(_ cache: FollowedUsersCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.followedCacheKey)
    }

    private static func normalizedRule(_ rule: KeywordHighlightRule) -> KeywordHighlightRule {
        KeywordHighlightRule(
            id: rule.id,
            keyword: rule.keyword,
            colorHex: normalizedColor(rule.colorHex, fallback: defaultKeywordColor),
            enabled: rule.enabled
        )
    }

    private static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    private static func normalizedColor(_ value: String, fallback: String) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^#[0-9A-F]{6}$"#
        guard candidate.range(of: pattern, options: .regularExpression) != nil else {
            return fallback
        }
        return candidate
    }

    private static func accountKey(_ owner: String) -> String {
        "user:\(normalizedUsername(owner))"
    }

    private static func localDayKey(date: Date = Date()) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct HighlightPreferences: Codable {
    var followedHighlightEnabled = true
    var followedColorHex = "#40B883"
    var keywordsEnabled = true
    var keywordRules: [KeywordHighlightRule] = []
}

private struct FollowedUsersCache: Codable {
    var version = 1
    var accounts: [String: FollowedUsersRecord] = [:]
}

private struct FollowedUsersRecord: Codable {
    var users: [String] = []
    var lastAttemptDay = ""
    var lastSuccessAt: Date?
}
