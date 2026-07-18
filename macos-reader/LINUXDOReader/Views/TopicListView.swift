//
//  TopicListView.swift
//

import SwiftUI

struct TopicListView: View {
    @ObservedObject var viewModel: TopicListViewModel
    @Binding var selectedTopicID: Int?
    let selection: BrowseSelection
    @ObservedObject var highlightStore: HighlightStore

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle where viewModel.topics.isEmpty,
                 .loading where viewModel.topics.isEmpty:
                LoadingPane(message: "正在加载\(selection.title)…")
            case .failed(let message) where viewModel.topics.isEmpty:
                ErrorPane(message: message) {
                    viewModel.refresh(force: true)
                }
            default:
                listContent
            }
        }
        .navigationTitle(selection.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refresh(force: true)
                } label: {
                    if case .loading = viewModel.phase {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .help("刷新列表（⌘R）")
                .disabled(viewModel.isRequestInFlight)
            }
        }
        .onAppear {
            viewModel.bind(selection: selection)
            viewModel.loadIfNeeded()
        }
    }

    private var listContent: some View {
        List(selection: $selectedTopicID) {
            if case .failed(let message) = viewModel.phase {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            ForEach(viewModel.topics) { topic in
                let followedUsername = highlightStore.followedHighlightEnabled
                    ? highlightStore.followedUsername(in: topic)
                    : nil
                TopicRowView(
                    topic: topic,
                    highlight: highlightStore.topicHighlight(for: topic),
                    followedUsername: followedUsername,
                    followedColor: highlightStore.followedColor
                )
                    .tag(topic.id)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(LDOTheme.separator)
                    .listRowBackground(Color.clear)
            }

            if viewModel.hasMore || isLoadingMore {
                Section {
                    loadMoreRow
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refreshFromPullGesture()
        }
        .scrollContentBackground(.hidden)
        .background(LDOTheme.contentBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let updated = viewModel.lastUpdated {
                statusBar(updated: updated)
            }
        }
    }

    private var isLoadingMore: Bool {
        if case .loadingMore = viewModel.phase { return true }
        return false
    }

    @ViewBuilder
    private var loadMoreRow: some View {
        if isLoadingMore {
            HStack {
                Spacer()
                ProgressView("加载更多…")
                    .controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 8)
        } else {
            HStack {
                Spacer()
                Button("加载更多") {
                    viewModel.loadMore()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private func statusBar(updated: Date) -> some View {
        HStack(spacing: 6) {
            if viewModel.needsRefresh {
                Image(systemName: "arrow.down.circle")
                Text("登录状态已变化，请下拉刷新")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "clock")
                Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
            }
            Spacer()
            Text("\(viewModel.topics.count.formatted()) 个主题")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
