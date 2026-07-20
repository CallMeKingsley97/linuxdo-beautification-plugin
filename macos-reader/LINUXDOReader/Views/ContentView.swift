//
//  ContentView.swift
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.selection {
            case .notifications:
                notificationsLayout
            case .site:
                siteLayout
            case .settings:
                settingsLayout
            case .latest, .hot, .category:
                nativeLayout
            }
        }
        .background {
            SiteRequestHostView(store: appState.siteSession)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            appState.siteSession.prepareRequestHost()
            appState.categoryStore.loadIfNeeded()
            if appState.selection == .site {
                appState.siteSession.loadHomeIfNeeded()
            }
        }
        .onChange(of: appState.selection) { _, newSelection in
            appState.selectedTopicID = nil
            switch newSelection {
            case .notifications:
                appState.notificationViewModel.loadIfNeeded()
            case .site:
                appState.siteSession.loadHomeIfNeeded()
            case .settings:
                break
            case .latest, .hot, .category:
                appState.listViewModel.bind(selection: newSelection)
                appState.listViewModel.loadIfNeeded()
            }
        }
        .onChange(of: appState.selectedTopicID) { _, newID in
            if let newID {
                appState.dismissUserProfiles()
                appState.detailViewModel.load(topicID: newID)
            }
        }
        .onReceive(appState.siteSession.$currentUser) { user in
            appState.sessionDidChange(to: user)
        }
    }

    private var nativeLayout: some View {
        NavigationSplitView {
            sidebar
        } content: {
            TopicListView(
                viewModel: appState.listViewModel,
                selectedTopicID: $appState.selectedTopicID,
                selection: appState.selection,
                highlightStore: appState.highlightStore
            )
            .navigationSplitViewColumnWidth(
                min: LDOTheme.listMinWidth,
                ideal: LDOTheme.listIdealWidth,
                max: LDOTheme.listMaxWidth
            )
        } detail: {
            if let route = appState.currentProfileRoute {
                UserProfileView(
                    viewModel: appState.profileViewModel,
                    route: route
                )
            } else {
                TopicDetailView(
                    viewModel: appState.detailViewModel,
                    topicID: appState.selectedTopicID,
                    targetPostNumber: appState.targetTopicID == appState.selectedTopicID
                        ? appState.targetPostNumber
                        : nil,
                    highlightStore: appState.highlightStore
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(LDOTheme.windowBackground)
    }

    private var siteLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            SiteBrowserView(store: appState.siteSession)
        }
        .navigationSplitViewStyle(.balanced)
        .background(LDOTheme.windowBackground)
    }

    private var notificationsLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NotificationCenterView(
                viewModel: appState.notificationViewModel,
                siteSession: appState.siteSession
            )
        }
        .navigationSplitViewStyle(.balanced)
        .background(LDOTheme.windowBackground)
    }

    private var settingsLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            SettingsView()
        }
        .navigationSplitViewStyle(.balanced)
        .background(LDOTheme.windowBackground)
    }

    private var sidebar: some View {
        SidebarView(
            selection: $appState.selection,
            categoryStore: appState.categoryStore,
            siteSession: appState.siteSession,
            notificationViewModel: appState.notificationViewModel,
            onOpenLogin: appState.openLogin,
            onOpenProfile: { user in
                appState.openUserProfile(
                    username: user.username,
                    displayName: user.displayName,
                    avatarTemplate: user.avatarTemplate
                )
            }
        )
    }
}
#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 1100, height: 720)
}
