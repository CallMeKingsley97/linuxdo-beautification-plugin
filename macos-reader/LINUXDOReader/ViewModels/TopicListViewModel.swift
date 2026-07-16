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

    private let api: APIClient
    private var selection: BrowseSelection = .latest
    private var loadTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    func bind(selection: BrowseSelection) {
        if self.selection != selection {
            self.selection = selection
            topics = []
            currentPage = 0
            hasMore = false
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
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(page: 0, append: false, force: force)
        }
    }

    /// 用户点击「加载更多」时调用（不自动连翻）
    func loadMore() {
        guard hasMore else { return }
        if case .loading = phase { return }
        if case .loadingMore = phase { return }
        let next = currentPage + 1
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(page: next, append: true, force: true)
        }
    }

    private func performLoad(page: Int, append: Bool, force: Bool) async {
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
