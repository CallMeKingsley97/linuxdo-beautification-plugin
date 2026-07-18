//
//  TopicListViewModel.swift
//

import Foundation

@MainActor
final class TopicListViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loadingMore
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var topics: [TopicSummary] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var currentPage: Int = 0
    @Published private(set) var needsRefresh = false

    private let api: APIClient
    private var selection: BrowseSelection = .latest
    private var loadTask: Task<Void, Never>?
    private var contentRevision = 0

    init(api: APIClient) {
        self.api = api
    }

    var isRequestInFlight: Bool {
        switch phase {
        case .loading, .loadingMore:
            return true
        case .idle, .loaded, .failed:
            return false
        }
    }

    func bind(selection: BrowseSelection) {
        if self.selection != selection {
            self.selection = selection
            topics = []
            currentPage = 0
            hasMore = false
            needsRefresh = false
            phase = .idle
        }
    }

    func loadIfNeeded() {
        if case .loaded = phase, !topics.isEmpty { return }
        if case .loading = phase { return }
        if case .loadingMore = phase { return }
        refresh(force: false)
    }

    func refresh(force: Bool) {
        guard !isRequestInFlight else { return }
        _ = startLoad(page: 0, append: false, force: force)
    }

    /// List.refreshable 使用；等待请求结束，让系统下拉指示器与真实加载状态一致。
    func refreshFromPullGesture() async {
        if isRequestInFlight {
            if let loadTask { await loadTask.value }
            return
        }
        let task = startLoad(page: 0, append: false, force: true)
        await task.value
    }

    func markNeedsRefresh() {
        contentRevision += 1
        needsRefresh = true
    }

    /// 用户点击「加载更多」时调用（不自动连翻）
    func loadMore() {
        guard hasMore else { return }
        if case .loading = phase { return }
        if case .loadingMore = phase { return }
        let next = currentPage + 1
        _ = startLoad(page: next, append: true, force: true)
    }

    @discardableResult
    private func startLoad(page: Int, append: Bool, force: Bool) -> Task<Void, Never> {
        loadTask?.cancel()
        let revision = contentRevision
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(
                page: page,
                append: append,
                force: force,
                startedAtRevision: revision
            )
        }
        loadTask = task
        return task
    }

    private func performLoad(
        page: Int,
        append: Bool,
        force: Bool,
        startedAtRevision: Int
    ) async {
        phase = append ? .loadingMore : .loading
        do {
            let result = try await fetchPage(page: page, force: force)
            if Task.isCancelled { return }

            if append {
                var merged = topics
                let existing = Set(merged.map(\.id))
                for topic in result.topics where !existing.contains(topic.id) {
                    merged.append(topic)
                }
                topics = merged
            } else {
                topics = result.topics
            }

            // 空页或无 more → 停止；否则保留 hasMore
            if result.topics.isEmpty {
                hasMore = false
            } else {
                hasMore = result.hasMore
            }
            currentPage = page
            lastUpdated = Date()
            if !append {
                needsRefresh = contentRevision != startedAtRevision
            }
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as LDOError where error == .cancelled {
            return
        } catch {
            if Task.isCancelled { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if append, !topics.isEmpty {
                // 加载更多失败时保留已有列表
                phase = .loaded
            } else {
                phase = .failed(message)
            }
        }
    }

    private func fetchPage(page: Int, force: Bool) async throws -> TopicListPage {
        switch selection {
        case .latest:
            return try await api.fetchLatest(page: page, force: force)
        case .hot:
            return try await api.fetchHot(page: page, force: force)
        case .site:
            return TopicListPage(
                topics: [],
                usersByID: [:],
                canCreateTopic: false,
                hasMore: false
            )
        case .settings:
            return TopicListPage(
                topics: [],
                usersByID: [:],
                canCreateTopic: false,
                hasMore: false
            )
        case .category(let category):
            return try await api.fetchCategoryTopics(
                slug: category.slug,
                id: category.id,
                page: page,
                force: force
            )
        }
    }
}
