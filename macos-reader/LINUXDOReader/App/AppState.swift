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
    case settings
    case category(CategorySummary)

    var id: String {
        switch self {
        case .latest: return "feed-latest"
        case .hot: return "feed-hot"
        case .site: return "site-full"
        case .settings: return "app-settings"
        case .category(let category): return "category-\(category.id)"
        }
    }

    var title: String {
        switch self {
        case .latest: return "最新"
        case .hot: return "热门"
        case .site: return "登录与验证"
        case .settings: return "设置"
        case .category(let category): return category.name
        }
    }

    var systemImage: String {
        switch self {
        case .latest: return "clock"
        case .hot: return "flame"
        case .site: return "person.crop.circle.badge.checkmark"
        case .settings: return "gearshape"
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
    let highlightStore: HighlightStore

    @Published var selection: BrowseSelection = .latest
    @Published var selectedTopicID: Int?

    private var hasObservedSession = false
    private var observedSessionUsername: String?

    init() {
        let siteSession = SiteSessionStore()
        let client = APIClient(siteSession: siteSession)
        self.apiClient = client
        self.listViewModel = TopicListViewModel(api: client)
        self.detailViewModel = TopicDetailViewModel(api: client)
        self.categoryStore = CategoryStore(api: client)
        self.siteSession = siteSession
        self.highlightStore = HighlightStore(api: client)
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
        if selection == .settings { return }
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

    func sessionDidChange(to user: SiteUser?) {
        highlightStore.sessionDidChange(user)
        let username = user?.username.lowercased()
        defer {
            hasObservedSession = true
            observedSessionUsername = username
        }

        guard hasObservedSession, observedSessionUsername != username else { return }
        apiClient.invalidateCaches()
        // 登录状态变化不自动请求列表，由用户通过下拉刷新或刷新按钮决定何时更新。
        listViewModel.markNeedsRefresh()
    }
}
