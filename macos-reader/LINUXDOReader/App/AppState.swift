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
    case site
    case category(CategorySummary)

    var id: String {
        switch self {
        case .latest: return "feed-latest"
        case .hot: return "feed-hot"
        case .site: return "site-full"
        case .category(let category): return "category-\(category.id)"
        }
    }

    var title: String {
        switch self {
        case .latest: return "最新"
        case .hot: return "热门"
        case .site: return "登录与验证"
        case .category(let category): return category.name
        }
    }

    var systemImage: String {
        switch self {
        case .latest: return "clock"
        case .hot: return "flame"
        case .site: return "person.crop.circle.badge.checkmark"
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
    let siteSession: SiteSessionStore

    @Published var selection: BrowseSelection = .latest
    @Published var selectedTopicID: Int?

    init() {
        let siteSession = SiteSessionStore()
        let client = APIClient(siteSession: siteSession)
        self.apiClient = client
        self.listViewModel = TopicListViewModel(api: client)
        self.detailViewModel = TopicDetailViewModel(api: client)
        self.categoryStore = CategoryStore(api: client)
        self.siteSession = siteSession
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
        if selection == .site {
            siteSession.reload()
            return
        }
        listViewModel.refresh(force: true)
        if selectedTopicID != nil {
            detailViewModel.reload()
        }
    }

    func openTopicInSite(id: Int, slug: String? = nil) {
        siteSession.loadTopic(id: id, slug: slug)
        select(.site)
    }

    func openLogin() {
        siteSession.loadLogin()
        select(.site)
    }

    func sessionDidChange() {
        apiClient.invalidateCaches()
        guard selection != .site else { return }
        listViewModel.refresh(force: true)
        if selectedTopicID != nil {
            detailViewModel.reload()
        }
    }
}
