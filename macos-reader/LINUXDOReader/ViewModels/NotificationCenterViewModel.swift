//
//  NotificationCenterViewModel.swift
//

import Foundation

@MainActor
final class NotificationCenterViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [LDOUserNotification] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var unreadCount = 0
    @Published private(set) var unseenReviewableCount = 0
    @Published private(set) var hasMore = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isMarkingAllRead = false
    @Published private(set) var actionMessage: String?
    @Published var selectedGroup: NotificationGroup = .all

    private let api: APIClient
    private var sessionUsername: String?
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var markingIDs: Set<Int> = []

    init(api: APIClient) {
        self.api = api
    }

    deinit {
        loadTask?.cancel()
        loadMoreTask?.cancel()
    }

    var filteredItems: [LDOUserNotification] {
        items.filter { selectedGroup.contains($0.kind) }
    }

    var hasUnread: Bool {
        unreadCount > 0 || items.contains(where: { !$0.isRead })
    }

    func count(in group: NotificationGroup) -> Int {
        items.lazy.filter { group.contains($0.kind) }.count
    }

    func unreadCount(in group: NotificationGroup) -> Int {
        items.lazy.filter { !$0.isRead && group.contains($0.kind) }.count
    }

    func sessionDidChange(_ user: SiteUser?) {
        let username = user?.username.lowercased()
        guard username != sessionUsername else { return }
        sessionUsername = username
        reset()
    }

    func loadIfNeeded() {
        guard phase == .idle else { return }
        load(force: false)
    }

    func reload() {
        load(force: true)
    }

    func load(force: Bool) {
        guard sessionUsername != nil else {
            phase = .failed("需要先登录 LINUX DO 才能查看通知。")
            return
        }
        if !force, case .loaded = phase { return }

        loadTask?.cancel()
        actionMessage = nil
        if items.isEmpty {
            phase = .loading
        } else {
            isRefreshing = true
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            async let totalsValue: NotificationTotals? = try? self.api.fetchNotificationTotals()
            do {
                let page = try await self.api.fetchNotifications()
                let totals = await totalsValue
                guard !Task.isCancelled else { return }
                self.items = page.items
                self.totalCount = page.totalCount
                self.hasMore = page.hasMore
                self.unreadCount = totals?.totalUnread
                    ?? page.items.lazy.filter { !$0.isRead }.count
                self.unseenReviewableCount = totals?.unseenReviewables ?? 0
                self.phase = .loaded
                self.isRefreshing = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.isRefreshing = false
                if self.items.isEmpty {
                    self.phase = .failed(Self.message(for: error))
                } else {
                    self.actionMessage = Self.message(for: error)
                }
            }
        }
    }

    func loadMore() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        actionMessage = nil
        let offset = items.count
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }
            do {
                let page = try await self.api.fetchNotifications(offset: offset)
                guard !Task.isCancelled else { return }
                let existingIDs = Set(self.items.map(\.id))
                self.items.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
                self.totalCount = page.totalCount
                self.hasMore = page.hasMore
            } catch is CancellationError {
                return
            } catch {
                self.actionMessage = Self.message(for: error)
            }
        }
    }

    func markRead(_ notification: LDOUserNotification) {
        guard !notification.isRead, !markingIDs.contains(notification.id) else { return }
        guard let index = items.firstIndex(where: { $0.id == notification.id }) else { return }
        markingIDs.insert(notification.id)
        items[index] = items[index].withRead(true)
        unreadCount = max(0, unreadCount - 1)

        Task { [weak self] in
            guard let self else { return }
            defer { self.markingIDs.remove(notification.id) }
            do {
                try await self.api.markNotificationRead(id: notification.id)
            } catch {
                guard let currentIndex = self.items.firstIndex(where: { $0.id == notification.id }) else {
                    return
                }
                self.items[currentIndex] = self.items[currentIndex].withRead(false)
                self.unreadCount += 1
                self.actionMessage = Self.message(for: error)
            }
        }
    }

    func markAllRead() {
        guard hasUnread, !isMarkingAllRead else { return }
        isMarkingAllRead = true
        actionMessage = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.isMarkingAllRead = false }
            do {
                try await self.api.markAllNotificationsRead()
                self.items = self.items.map { $0.withRead(true) }
                self.unreadCount = 0
            } catch {
                self.actionMessage = Self.message(for: error)
            }
        }
    }

    func clearActionMessage() {
        actionMessage = nil
    }

    private func reset() {
        loadTask?.cancel()
        loadMoreTask?.cancel()
        items = []
        totalCount = 0
        unreadCount = 0
        unseenReviewableCount = 0
        hasMore = false
        isRefreshing = false
        isLoadingMore = false
        isMarkingAllRead = false
        actionMessage = nil
        selectedGroup = .all
        markingIDs = []
        phase = .idle
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
