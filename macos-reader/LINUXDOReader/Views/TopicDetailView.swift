//
//  TopicDetailView.swift
//

import SwiftUI

struct TopicDetailView: View {
    @ObservedObject var viewModel: TopicDetailViewModel
    let topicID: Int?

    var body: some View {
        Group {
            if topicID == nil {
                emptySelection
            } else {
                switch viewModel.phase {
                case .idle, .loading where viewModel.detail == nil:
                    LoadingPane(message: "正在加载主题…")
                case .failed(let message) where viewModel.detail == nil:
                    ErrorPane(message: message) {
                        viewModel.reload()
                    }
                case .loaded, .loading, .failed:
                    if let detail = viewModel.detail {
                        detailScroll(detail)
                    } else {
                        LoadingPane(message: "正在加载主题…")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySelection: some View {
        ContentUnavailableView {
            Label("选择主题", systemImage: "doc.text")
        } description: {
            Text("从中间列表点开一个主题，即可阅读楼层正文。")
        }
    }

    private func detailScroll(_ detail: TopicDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(detail)

                if case .failed(let message) = viewModel.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                ForEach(detail.posts) { post in
                    PostCardView(post: post)
                }

                if detail.posts.count < detail.postsCount {
                    Text("已加载 \(detail.posts.count)/\(detail.postsCount) 层 · 长帖完整分页将在后续版本支持")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(detail.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.reload()
                } label: {
                    if case .loading = viewModel.phase {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                if let url = URL(string: "https://linux.do/t/\(detail.slug)/\(detail.id)") {
                    Link(destination: url) {
                        Label("在浏览器打开", systemImage: "safari")
                    }
                }
            }
        }
    }

    private func header(_ detail: TopicDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.title)
                .font(.title.weight(.semibold))
                .textSelection(.enabled)

            HStack(spacing: 10) {
                if detail.pinned {
                    statusChip("置顶", color: .orange)
                }
                if detail.closed {
                    statusChip("已关闭", color: .secondary)
                }
                if detail.archived {
                    statusChip("已归档", color: .secondary)
                }
                Text("\(detail.postsCount) 层")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !detail.tags.isEmpty {
                    Text(detail.tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .clipShape(Capsule())
    }
}
