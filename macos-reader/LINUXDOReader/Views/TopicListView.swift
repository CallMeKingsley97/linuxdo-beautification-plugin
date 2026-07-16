//
//  TopicListView.swift
//

import SwiftUI

struct TopicListView: View {
    @ObservedObject var viewModel: TopicListViewModel
    @Binding var selectedTopicID: Int?
    let selection: BrowseSelection

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading where viewModel.topics.isEmpty:
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
                TopicRowView(topic: topic)
                    .tag(topic.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            if viewModel.hasMore || isLoadingMore {
                Section {
                    loadMoreRow
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay(alignment: .bottom) {
            if let updated = viewModel.lastUpdated {
                Text("更新于 \(updated.formatted(date: .omitted, time: .shortened)) · 共 \(viewModel.topics.count) 条")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.bar)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
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
            Button {
                viewModel.loadMore()
            } label: {
                Text("加载更多")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 6)
        }
    }
}
