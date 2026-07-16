//
//  CategoryStore.swift
//  侧栏分类数据
//

import Foundation

@MainActor
final class CategoryStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var categories: [CategorySummary] = []

    private let api: APIClient
    private var loadTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    /// 顶层分类（无 parent）
    var rootCategories: [CategorySummary] {
        categories.filter { !$0.isSubcategory }
    }

    func loadIfNeeded() {
        if case .loaded = phase, !categories.isEmpty { return }
        if case .loading = phase { return }
        refresh(force: false)
    }

    func refresh(force: Bool) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(force: force)
        }
    }

    private func performLoad(force: Bool) async {
        phase = .loading
        do {
            let list = try await api.fetchCategories(force: force)
            if Task.isCancelled { return }
            categories = list
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as LDOError where error == .cancelled {
            return
        } catch {
            if Task.isCancelled { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
        }
    }
}
