//
//  AppState.swift
//  全局导航与共享依赖
//

import Foundation
import SwiftUI

/// 侧栏 / 列表数据源（P1 最新热门 + P2 分类）
enum BrowseSelection: Hashable, Identifiable {
    case latest
    case hot
    case category(CategorySummary)

    var id: String {
        switch self {
        case .latest: return "feed-latest"
        case .hot: return "feed-hot"
        case .category(let category): return "category-\(category.id)"
        }
    }

    var title: String {
        switch self {
        case .latest: return "最新"
        case .hot: return "热门"
        case .category(let category): return category.name
        }
    }

    var systemImage: String {
        switch self {
        case .latest: return "clock"
        case .hot: return "flame"
        case .category: return "folder"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let apiClient: APIClient
    let listViewModel: TopicListViewModel
    let detailViewModel: TopicDetailViewModel
    let categoryStore: CategoryStore

    @Published var selection: BrowseSelection = .latest
    @Published var selectedTopicID: Int?

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
        self.listViewModel = TopicListViewModel(api: apiClient)
        self.detailViewModel = TopicDetailViewModel(api: apiClient)
        self.categoryStore = CategoryStore(api: apiClient)
    }

    func select(_ destination: BrowseSelection) {
        guard selection != destination else { return }
        selection = destination
        selectedTopicID = nil
    }

    /// 快捷键：最新
    func selectLatest() {
        select(.latest)
    }

    /// 快捷键：热门
    func selectHot() {
        select(.hot)
    }

    func selectTopic(id: Int?) {
        selectedTopicID = id
    }

    func refreshList() {
        listViewModel.refresh(force: true)
        if selectedTopicID != nil {
            detailViewModel.reload()
        }
    }
}
