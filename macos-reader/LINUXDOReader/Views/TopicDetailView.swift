//
//  TopicDetailView.swift
//

import SwiftUI

struct TopicDetailView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: TopicDetailViewModel
    let topicID: Int?
    @ObservedObject var highlightStore: HighlightStore
    @State private var replyContext: ReplyContext?

    var body: some View {
        Group {
            if topicID == nil {
                emptySelection
            } else {
                switch viewModel.phase {
                case .idle where viewModel.detail == nil,
                     .loading where viewModel.detail == nil:
                    LoadingPane(message: "正在加载主题…")
                case .failed(let message) where viewModel.detail == nil:
                    failurePane(message: message)
                case .loaded, .idle, .loading, .failed:
                    if let detail = viewModel.detail {
                        detailScroll(detail)
                    } else {
                        LoadingPane(message: "正在加载主题…")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $replyContext) { context in
            ReplyComposerView(
                viewModel: viewModel,
                context: context
            )
        }
    }

    private var emptySelection: some View {
        ContentUnavailableView {
            Label("选择一个主题", systemImage: "sidebar.right")
        } description: {
            Text("主题正文会在这里以原生阅读视图显示。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LDOTheme.contentBackground)
    }

    private func failurePane(message: String) -> some View {
        ContentUnavailableView {
            Label("主题加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { viewModel.reload() }
            if let topicID {
                Button(appState.siteSession.isLoggedIn ? "打开登录与验证" : "登录后重试") {
                    if appState.siteSession.isLoggedIn {
                        appState.openTopicInSite(id: topicID)
                    } else {
                        appState.openLogin()
                    }
                }
            }
        }
    }

    private func detailScroll(_ detail: TopicDetail) -> some View {
        VStack(spacing: 0) {
            if case .failed(let message) = viewModel.phase {
                HStack(spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Spacer()
                    Button("重试") { viewModel.reload() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
            }

            TopicDocumentWebView(
                detail: detail,
                followedUsernames: highlightStore.followedUsernames,
                followedHighlightEnabled: highlightStore.followedHighlightEnabled,
                followedColorHex: highlightStore.followedColorHex,
                onOpenTopic: { appState.selectTopic(id: $0) },
                onReply: { beginReply(to: $0.postNumber) }
            )
        }
        .background(LDOTheme.contentBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.canLoadMore || viewModel.isLoadingMore {
                pagingBar(detail)
            }
        }
        .navigationTitle(detail.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.reload()
                } label: {
                    if case .loading = viewModel.phase {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }

                Button {
                    appState.openTopicInSite(id: detail.id, slug: detail.slug)
                } label: {
                    Label("兼容网页", systemImage: "globe")
                }
                .help("仅在原生内容异常时使用站内网页")

                Button {
                    if appState.siteSession.isLoggedIn {
                        beginReply(to: nil)
                    } else {
                        appState.openLogin()
                    }
                } label: {
                    Label(appState.siteSession.isLoggedIn ? "回复" : "登录", systemImage: "square.and.pencil")
                }
                .help(appState.siteSession.isLoggedIn ? "在 App 内回复此主题" : "登录后回复和访问受限主题")
            }
        }
    }

    private func pagingBar(_ detail: TopicDetail) -> some View {
        HStack(spacing: 12) {
            Text("已显示 \(detail.posts.count.formatted()) / \(detail.postsCount.formatted()) 层")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button(action: viewModel.loadMore) {
                HStack(spacing: 6) {
                    if viewModel.isLoadingMore {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.isLoadingMore ? "正在加载…" : "加载更多")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoadingMore)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func beginReply(to postNumber: Int?) {
        guard appState.siteSession.isLoggedIn else {
            appState.openLogin()
            return
        }
        viewModel.clearReplyMessage()
        replyContext = ReplyContext(postNumber: postNumber)
    }

}

private struct ReplyContext: Identifiable {
    let id = UUID()
    let postNumber: Int?
}

private struct ReplyComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TopicDetailViewModel
    let context: ReplyContext
    @State private var text = ""
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.postNumber.map { "回复 #\($0)" } ?? "回复主题")
                        .font(.headline)
                    Text("回复将使用当前 LINUX DO 账号发布")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("写下你的回复…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($isTextFocused)
            }
            .background(LDOTheme.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius, style: .continuous)
                    .strokeBorder(LDOTheme.separator)
            }

            if let message = viewModel.replyMessage {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        if await viewModel.submitReply(
                            raw: text,
                            replyToPostNumber: context.postNumber
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSubmittingReply {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("发送回复")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingReply)
            }
        }
        .padding(24)
        .frame(width: 600, height: 410)
        .background(LDOTheme.windowBackground)
        .onAppear { isTextFocused = true }
    }
}
