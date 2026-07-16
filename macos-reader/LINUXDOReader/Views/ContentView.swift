//
//  ContentView.swift
//  三栏：侧栏 / 列表 / 详情
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $appState.selection,
                categoryStore: appState.categoryStore
            )
        } content: {
            TopicListView(
                viewModel: appState.listViewModel,
                selectedTopicID: $appState.selectedTopicID,
                selection: appState.selection
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            TopicDetailView(
                viewModel: appState.detailViewModel,
                topicID: appState.selectedTopicID
            )
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            appState.categoryStore.loadIfNeeded()
            appState.listViewModel.bind(selection: appState.selection)
            appState.listViewModel.loadIfNeeded()
        }
        .onChange(of: appState.selection) { _, newSelection in
            appState.listViewModel.bind(selection: newSelection)
            appState.listViewModel.refresh(force: false)
            appState.selectedTopicID = nil
        }
        .onChange(of: appState.selectedTopicID) { _, newID in
            if let newID {
                appState.detailViewModel.load(topicID: newID)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 1100, height: 720)
}
