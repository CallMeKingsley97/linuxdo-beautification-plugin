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
    case notifications
    case site
    case settings
    case category(CategorySummary)

    var id: String {
        switch self {
        case .latest: return "feed-latest"
        case .hot: return "feed-hot"
        case .notifications: return "account-notifications"
        case .site: return "site-full"
        case .settings: return "app-settings"
        case .category(let category): return "category-\(category.id)"
        }
    }

    var title: String {
        switch self {
        case .latest: return "最新"
        case .hot: return "热门"
        case .notifications: return "通知"
        case .site: return "登录与验证"
        case .settings: return "设置"
        case .category(let category): return category.name
        }
    }

    var systemImage: String {
        switch self {
        case .latest: return "clock"
        case .hot: return "flame"
        case .notifications: return "bell"
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
    let profileViewModel: UserProfileViewModel
    let notificationViewModel: NotificationCenterViewModel

    @Published var selection: BrowseSelection = .latest
    @Published var selectedTopicID: Int?
    @Published var targetPostNumber: Int?
    @Published private(set) var targetTopicID: Int?
    @Published private(set) var profileHistory: [UserProfileRoute] = []

    private var hasObservedSession = false
    private var observedSessionUsername: String?

    init() {
        let siteSession = SiteSessionStore()
        let client = APIClient(siteSession: siteSession)
        let highlightStore = HighlightStore(api: client)
        self.apiClient = client
        self.listViewModel = TopicListViewModel(api: client)
        self.detailViewModel = TopicDetailViewModel(api: client)
        self.categoryStore = CategoryStore(api: client)
        self.siteSession = siteSession
        self.highlightStore = highlightStore
        self.profileViewModel = UserProfileViewModel(api: client, highlightStore: highlightStore)
        self.notificationViewModel = NotificationCenterViewModel(api: client)
    }

    var currentProfileRoute: UserProfileRoute? {
        profileHistory.last
    }

    func select(_ destination: BrowseSelection) {
        guard selection != destination else { return }
        selection = destination
        selectedTopicID = nil
        targetPostNumber = nil
        targetTopicID = nil
        profileHistory = []
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
        if id != nil {
            profileHistory = []
        }
        targetPostNumber = nil
        targetTopicID = nil
        selectedTopicID = id
    }

    func openUserProfile(
        username: String,
        displayName: String? = nil,
        avatarTemplate: String? = nil
    ) {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if selection == .site || selection == .settings || selection == .notifications {
            selection = .latest
        }
        let route = UserProfileRoute(
            username: normalized,
            displayName: displayName,
            avatarTemplate: avatarTemplate
        )
        guard profileHistory.last?.id != route.id else { return }
        profileHistory.append(route)
    }

    func closeUserProfile() {
        if !profileHistory.isEmpty {
            profileHistory.removeLast()
        }
    }

    func dismissUserProfiles() {
        profileHistory = []
    }

    func openTopicFromProfile(id: Int) {
        profileHistory = []
        targetPostNumber = nil
        targetTopicID = nil
        selectedTopicID = id
        detailViewModel.load(topicID: id)
    }

    func openTopicFromNotification(id: Int, postNumber: Int?) {
        selection = .latest
        profileHistory = []
        selectedTopicID = nil
        targetTopicID = id
        targetPostNumber = postNumber
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.selection == .latest, self.targetTopicID == id else { return }
            self.selectedTopicID = id
            self.detailViewModel.load(topicID: id)
        }
    }

    func openSitePath(_ path: String) {
        guard let url = URL(string: path, relativeTo: Endpoints.baseURL)?.absoluteURL else { return }
        siteSession.load(url)
        select(.site)
    }

    func refreshList() {
        if currentProfileRoute != nil {
            profileViewModel.reload()
            return
        }
        if selection == .site {
            siteSession.reload()
            return
        }
        if selection == .notifications {
            notificationViewModel.reload()
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
        notificationViewModel.sessionDidChange(user)
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
