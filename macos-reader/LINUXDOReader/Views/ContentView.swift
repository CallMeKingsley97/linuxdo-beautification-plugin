//
//  ContentView.swift
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.selection == .site {
                siteLayout
            } else {
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
            } else {
                appState.listViewModel.bind(selection: appState.selection)
                appState.listViewModel.loadIfNeeded()
            }
        }
        .onChange(of: appState.selection) { _, newSelection in
            appState.selectedTopicID = nil
            if newSelection == .site {
                appState.siteSession.loadHomeIfNeeded()
            } else {
                appState.listViewModel.bind(selection: newSelection)
                appState.listViewModel.refresh(force: false)
            }
        }
        .onChange(of: appState.selectedTopicID) { _, newID in
            if let newID {
                appState.detailViewModel.load(topicID: newID)
            }
        }
        .onChange(of: appState.siteSession.currentUser) { _, _ in
            appState.sessionDidChange()
        }
    }

    private var nativeLayout: some View {
        NavigationSplitView {
            sidebar
        } content: {
            TopicListView(
                viewModel: appState.listViewModel,
                selectedTopicID: $appState.selectedTopicID,
                selection: appState.selection
            )
            .navigationSplitViewColumnWidth(
                min: LDOTheme.listMinWidth,
                ideal: LDOTheme.listIdealWidth,
                max: LDOTheme.listMaxWidth
            )
        } detail: {
            TopicDetailView(
                viewModel: appState.detailViewModel,
                topicID: appState.selectedTopicID
            )
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

    private var sidebar: some View {
        SidebarView(
            selection: $appState.selection,
            categoryStore: appState.categoryStore,
            siteSession: appState.siteSession,
            onOpenLogin: appState.openLogin
        )
    }
}
#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 1100, height: 720)
}
