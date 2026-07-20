//
//  NotificationCenterView.swift
//

import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: NotificationCenterViewModel
    @ObservedObject var siteSession: SiteSessionStore

    var body: some View {
        Group {
            if !siteSession.isLoggedIn {
                loggedOutState
            } else {
                notificationContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LDOTheme.contentBackground)
        .navigationTitle("通知")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: viewModel.reload) {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新通知", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!siteSession.isLoggedIn || viewModel.isRefreshing)
                .help("仅在点击时刷新，不会后台轮询")

                Button(action: viewModel.markAllRead) {
                    if viewModel.isMarkingAllRead {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("全部标为已读", systemImage: "checkmark.circle")
                    }
                }
                .disabled(!siteSession.isLoggedIn || !viewModel.hasUnread || viewModel.isMarkingAllRead)
                .help("将全部通知标记为已读")
            }
        }
        .onAppear {
            viewModel.sessionDidChange(siteSession.currentUser)
            if siteSession.isLoggedIn {
                viewModel.loadIfNeeded()
            }
        }
        .onChange(of: siteSession.currentUser) { _, user in
            viewModel.sessionDidChange(user)
        }
    }

    @ViewBuilder
    private var notificationContent: some View {
        switch viewModel.phase {
        case .idle where viewModel.items.isEmpty:
            LoadingPane(message: "正在加载通知…")
        case .loading where viewModel.items.isEmpty:
            LoadingPane(message: "正在加载通知…")
        case .failed(let message) where viewModel.items.isEmpty:
            ContentUnavailableView {
                Label("通知加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重试", action: viewModel.reload)
            }
        default:
            VStack(spacing: 0) {
                filterBar
                Divider()
                if let message = viewModel.actionMessage {
                    errorBanner(message)
                }
                if viewModel.filteredItems.isEmpty {
                    emptyFilteredState
                } else {
                    notificationList
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("通知类型", selection: $viewModel.selectedGroup) {
                ForEach(NotificationGroup.allCases) { group in
                    Text(group.title).tag(group)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Text("共 \(viewModel.totalCount.formatted()) 条")
                if viewModel.unreadCount > 0 {
                    Text("· \(viewModel.unreadCount.formatted()) 条未读")
                        .foregroundStyle(.tint)
                }
                if viewModel.unseenReviewableCount > 0 {
                    Text("· \(viewModel.unseenReviewableCount.formatted()) 条待审核")
                        .foregroundStyle(.orange)
                }
                Spacer()
                let visibleUnread = viewModel.unreadCount(in: viewModel.selectedGroup)
                if visibleUnread > 0, viewModel.selectedGroup != .all {
                    Text("当前分类 \(visibleUnread.formatted()) 条未读")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var notificationList: some View {
        List {
            ForEach(viewModel.filteredItems) { notification in
                Button {
                    open(notification)
                } label: {
                    NotificationRow(notification: notification)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(
                    notification.isRead
                        ? Color.clear
                        : Color.accentColor.opacity(LDOTheme.highlightFillOpacity)
                )
                .help(notification.destinationHint)
                .contextMenu {
                    if !notification.isRead {
                        Button("标记为已读") {
                            viewModel.markRead(notification)
                        }
                    }
                    if let username = notification.actorUsername {
                        Button("查看 @\(username) 的资料") {
                            appState.openUserProfile(username: username)
                        }
                    }
                }
            }

            if viewModel.hasMore {
                HStack {
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
                    .disabled(viewModel.isLoadingMore)
                    Spacer()
                }
                .padding(.vertical, 12)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var emptyFilteredState: some View {
        ContentUnavailableView {
            Label("暂无\(viewModel.selectedGroup.title)通知", systemImage: viewModel.selectedGroup.systemImage)
        } description: {
            Text("切换分类或手动刷新后再试。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loggedOutState: some View {
        ContentUnavailableView {
            Label("登录后查看通知", systemImage: "bell.badge")
        } description: {
            Text("通知属于账号私有数据，需要使用当前 LINUX DO 会话。")
        } actions: {
            Button("登录 LINUX DO", action: appState.openLogin)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("关闭", action: viewModel.clearActionMessage)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func open(_ notification: LDOUserNotification) {
        viewModel.markRead(notification)
        switch notification.destination(currentUsername: siteSession.currentUser?.username) {
        case .topic(let id, _, let postNumber):
            appState.openTopicFromNotification(id: id, postNumber: postNumber)
        case .user(let username):
            appState.openUserProfile(username: username)
        case .site(let path):
            appState.openSitePath(path)
        case nil:
            break
        }
    }
}

private struct NotificationRow: View {
    let notification: LDOUserNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingVisual

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(notification.headline)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if notification.isHighPriority {
                        Image(systemName: "exclamationmark.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.orange)
                            .help("高优先级通知")
                    }
                    if !notification.kind.isKnown {
                        LDOStatusBadge(
                            text: "类型 \(notification.kind.rawValue)",
                            color: .secondary,
                            systemImage: "questionmark"
                        )
                    }
                }

                if let contextText = notification.contextText {
                    Text(contextText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Label(notification.kind.group.title, systemImage: notification.kind.systemImage)
                    Text("类型 \(notification.kind.rawValue)")
                    if let postNumber = notification.postNumber {
                        Text("#\(postNumber)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if let createdAt = notification.createdAt {
                    Text(createdAt.ldoRelativeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if !notification.isRead {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("未读")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if let avatar = notification.actingUserAvatarTemplate {
            AvatarView(template: avatar, size: 34)
        } else {
            ZStack {
                Circle().fill(groupColor.opacity(0.12))
                Image(systemName: notification.kind.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(groupColor)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
        }
    }

    private var groupColor: Color {
        switch notification.kind.group {
        case .all, .replies: return .accentColor
        case .likes: return .pink
        case .messages: return .purple
        case .chat: return .blue
        case .bookmarks: return .orange
        case .other: return .secondary
        }
    }
}
