//
//  SidebarView.swift
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: BrowseSelection
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var siteSession: SiteSessionStore
    let onOpenLogin: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                Section("浏览") {
                    Label("最新", systemImage: "clock")
                        .tag(BrowseSelection.latest)
                    Label("热门", systemImage: "flame")
                        .tag(BrowseSelection.hot)
                    Label("登录与验证", systemImage: "person.crop.circle.badge.checkmark")
                        .tag(BrowseSelection.site)
                }

                Section("账号") {
                    accountRow

                    Button {
                        siteSession.refreshSession()
                    } label: {
                        Label(
                            siteSession.isSessionChecking ? "正在检查会话" : "检查登录状态",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(siteSession.isSessionChecking)
                }

                Section("分类") {
                    categoryRows
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            sidebarFooter
        }
        .navigationSplitViewColumnWidth(
            min: LDOTheme.sidebarMinWidth,
            ideal: LDOTheme.sidebarIdealWidth,
            max: LDOTheme.sidebarMaxWidth
        )
        .navigationTitle("LINUX DO")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    categoryStore.refresh(force: true)
                } label: {
                    Label("刷新分类", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("重新拉取分类列表")
            }
        }
        .onAppear {
            categoryStore.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var accountRow: some View {
        if let user = siteSession.currentUser {
            Button(action: onOpenLogin) {
                HStack(spacing: 9) {
                    AvatarView(template: user.avatarTemplate, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("@\(user.username)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                        .help("原生会话已连接")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开站内账号页")
        } else {
            Button(action: onOpenLogin) {
                Label(
                    siteSession.isSessionChecking ? "正在检查登录状态…" : "登录 LINUX DO",
                    systemImage: "person.crop.circle.badge.plus"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var categoryRows: some View {
        switch categoryStore.phase {
        case .idle where categoryStore.categories.isEmpty,
             .loading where categoryStore.categories.isEmpty:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("加载分类…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message) where categoryStore.categories.isEmpty:
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试") {
                    categoryStore.refresh(force: true)
                }
                .buttonStyle(.borderless)
            }
        default:
            ForEach(categoryStore.rootCategories) { category in
                HStack(spacing: 9) {
                    Circle()
                        .fill(categoryColor(category.color))
                        .frame(width: 7, height: 7)
                    Text(category.name)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if category.topicCount > 0 {
                        Text(category.topicCount.formatted())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                .tag(BrowseSelection.category(category))
                .help(category.description ?? category.name)
            }

            if case .failed(let message) = categoryStore.phase {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            LDOAppMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("LINUX DO 阅读器")
                    .font(.caption.weight(.semibold))
                Text(siteSession.isLoggedIn ? "原生阅读 · 会话已连接" : "原生阅读 · RSS 回退")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// List(selection:) 需要 Optional Binding 时用包装；这里 BrowseSelection 非 Optional
    private var selectionBinding: Binding<BrowseSelection?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    private func categoryColor(_ hex: String?) -> Color {
        guard let hex, let color = Color(hex: hex) else {
            return Color.secondary.opacity(0.5)
        }
        return color
    }
}
