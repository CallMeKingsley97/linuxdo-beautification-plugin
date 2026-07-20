//
//  UserProfileViewModel.swift
//

import Foundation

@MainActor
final class UserProfileViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var profile: UserProfileDetail?
    @Published private(set) var summary: UserProfileSummary?
    @Published private(set) var activityItems: [UserActivityItem] = []
    @Published private(set) var hasMoreActivity = false
    @Published private(set) var isLoadingActivity = false
    @Published var activityFilter: UserActivityFilter = .posts

    @Published private(set) var badgeGroups: [UserBadgeGroup] = []
    @Published private(set) var isLoadingBadges = false
    @Published private(set) var badgesError: String?

    @Published private(set) var solvedItems: [SolvedPostItem] = []
    @Published private(set) var hasMoreSolved = false
    @Published private(set) var isLoadingSolved = false
    @Published private(set) var solvedError: String?

    @Published private(set) var endorsableCategories: [EndorsableCategory] = []
    @Published private(set) var remainingEndorsements = 0
    @Published private(set) var isLoadingEndorsements = false
    @Published private(set) var isSubmittingEndorsement = false
    @Published private(set) var isChangingFollow = false
    @Published var actionMessage: String?

    private let api: APIClient
    private let highlightStore: HighlightStore
    private var username: String?
    private var loadTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var badgesTask: Task<Void, Never>?
    private var solvedTask: Task<Void, Never>?
    private var endorsementsTask: Task<Void, Never>?

    init(api: APIClient, highlightStore: HighlightStore) {
        self.api = api
        self.highlightStore = highlightStore
    }

    deinit {
        loadTask?.cancel()
        activityTask?.cancel()
        badgesTask?.cancel()
        solvedTask?.cancel()
        endorsementsTask?.cancel()
    }

    func load(username: String, force: Bool = false) {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            phase = .failed("用户名为空")
            return
        }
        if !force, self.username?.caseInsensitiveCompare(normalized) == .orderedSame,
           case .loaded = phase {
            return
        }

        let changedUser = self.username?.caseInsensitiveCompare(normalized) != .orderedSame
        self.username = normalized
        loadTask?.cancel()
        activityTask?.cancel()
        if changedUser {
            cancelSupplementaryTasks()
            resetContent()
        }
        phase = .loading

        loadTask = Task { [weak self] in
            guard let self else { return }
            async let summaryValue: UserProfileSummary? = try? self.api.fetchUserProfileSummary(
                username: normalized,
                force: force
            )
            async let activityValue: UserActivityPage? = try? self.api.fetchUserActivity(
                username: normalized,
                filter: self.activityFilter,
                offset: 0,
                force: force
            )

            do {
                let profile = try await self.api.fetchUserProfile(username: normalized, force: force)
                let summary = await summaryValue
                let activity = await activityValue
                guard !Task.isCancelled,
                      self.username?.caseInsensitiveCompare(normalized) == .orderedSame else { return }

                self.profile = profile
                self.summary = summary
                self.activityItems = activity?.items ?? []
                self.hasMoreActivity = activity?.hasMore ?? false
                self.phase = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(Self.message(for: error))
            }
        }
    }

    func reload() {
        guard let username else { return }
        load(username: username, force: true)
    }

    func selectActivityFilter(_ filter: UserActivityFilter) {
        guard activityFilter != filter else { return }
        activityFilter = filter
        activityItems = []
        hasMoreActivity = false
        loadActivity(reset: true)
    }

    func loadMoreActivity() {
        guard hasMoreActivity else { return }
        loadActivity(reset: false)
    }

    func loadBadges(force: Bool = false) {
        guard let username, !isLoadingBadges else { return }
        if !force, !badgeGroups.isEmpty { return }
        isLoadingBadges = true
        badgesError = nil
        badgesTask?.cancel()
        badgesTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentUser(username) { self.isLoadingBadges = false }
            }
            do {
                let groups = try await self.api.fetchUserBadges(
                    username: username,
                    force: force
                )
                guard !Task.isCancelled, self.isCurrentUser(username) else { return }
                self.badgeGroups = groups
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrentUser(username) else { return }
                self.badgesError = Self.message(for: error)
            }
        }
    }

    func loadSolved(reset: Bool = true) {
        guard let username, !isLoadingSolved else { return }
        if !reset, !hasMoreSolved { return }
        isLoadingSolved = true
        solvedError = nil
        let offset = reset ? 0 : solvedItems.count
        solvedTask?.cancel()
        solvedTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentUser(username) { self.isLoadingSolved = false }
            }
            do {
                let page = try await self.api.fetchSolvedPosts(username: username, offset: offset)
                guard !Task.isCancelled, self.isCurrentUser(username) else { return }
                self.solvedItems = reset ? page.items : self.solvedItems + page.items
                self.hasMoreSolved = page.hasMore
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrentUser(username) else { return }
                self.solvedError = Self.message(for: error)
            }
        }
    }

    func toggleFollow() {
        guard let profile, profile.canFollow, !isChangingFollow else { return }
        let original = profile
        let target = !profile.isFollowed
        self.profile = profile.withFollowed(target)
        isChangingFollow = true
        actionMessage = nil

        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentUser(original.username) { self.isChangingFollow = false }
            }
            do {
                try await self.api.setFollowing(target, username: original.username)
                self.highlightStore.setFollowing(original.username, isFollowing: target)
            } catch {
                guard self.isCurrentUser(original.username) else { return }
                self.profile = original
                self.actionMessage = Self.message(for: error)
            }
        }
    }

    func loadEndorsableCategories() {
        guard let username, !isLoadingEndorsements else { return }
        isLoadingEndorsements = true
        actionMessage = nil
        endorsementsTask?.cancel()
        endorsementsTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentUser(username) { self.isLoadingEndorsements = false }
            }
            do {
                let result = try await self.api.fetchEndorsableCategories(username: username)
                guard !Task.isCancelled, self.isCurrentUser(username) else { return }
                self.endorsableCategories = result.categories
                self.remainingEndorsements = result.remainingEndorsements
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrentUser(username) else { return }
                self.actionMessage = Self.message(for: error)
            }
        }
    }

    func endorse(categoryIDs: Set<Int>) async -> Bool {
        guard let username, !isSubmittingEndorsement else { return false }
        isSubmittingEndorsement = true
        actionMessage = nil
        defer {
            if isCurrentUser(username) { isSubmittingEndorsement = false }
        }
        do {
            try await api.endorse(username: username, categoryIDs: categoryIDs)
            guard isCurrentUser(username) else { return true }
            let existing = Set(profile?.endorsedCategoryIDs ?? [])
            profile = profile?.withEndorsedCategoryIDs(existing.union(categoryIDs))
            remainingEndorsements = max(0, remainingEndorsements - categoryIDs.count)
            return true
        } catch {
            actionMessage = Self.message(for: error)
            return false
        }
    }

    func clearActionMessage() {
        actionMessage = nil
    }

    private func loadActivity(reset: Bool) {
        guard let username, !isLoadingActivity else { return }
        isLoadingActivity = true
        activityTask?.cancel()
        let offset = reset ? 0 : activityItems.count
        let filter = activityFilter
        activityTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingActivity = false }
            do {
                let page = try await self.api.fetchUserActivity(
                    username: username,
                    filter: filter,
                    offset: offset,
                    force: reset
                )
                guard !Task.isCancelled, self.activityFilter == filter else { return }
                self.activityItems = reset ? page.items : self.activityItems + page.items
                self.hasMoreActivity = page.hasMore
            } catch is CancellationError {
                return
            } catch {
                self.actionMessage = Self.message(for: error)
            }
        }
    }

    private func resetContent() {
        profile = nil
        summary = nil
        activityItems = []
        hasMoreActivity = false
        badgeGroups = []
        badgesError = nil
        solvedItems = []
        hasMoreSolved = false
        solvedError = nil
        endorsableCategories = []
        remainingEndorsements = 0
        actionMessage = nil
        activityFilter = .posts
        isLoadingBadges = false
        isLoadingSolved = false
        isLoadingEndorsements = false
        isSubmittingEndorsement = false
        isChangingFollow = false
    }

    private func cancelSupplementaryTasks() {
        badgesTask?.cancel()
        solvedTask?.cancel()
        endorsementsTask?.cancel()
        badgesTask = nil
        solvedTask = nil
        endorsementsTask = nil
    }

    private func isCurrentUser(_ candidate: String) -> Bool {
        username?.caseInsensitiveCompare(candidate) == .orderedSame
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
