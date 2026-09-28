//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    var usesStandaloneWindowSize = false
    @State private var showsClearDataConfirmation = false

    var body: some View {
        Group {
            if usesStandaloneWindowSize {
                settingsForm
                    .frame(width: 620, height: 680)
            } else {
                settingsForm
                    .frame(maxWidth: LDOTheme.settingsMaxWidth)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .background(LDOTheme.windowBackground)
            }
        }
        .navigationTitle("设置")
    }

    private var sessionStatusText: String {
        if appState.siteSession.isSessionChecking { return "正在检查会话" }
        if let user = appState.siteSession.currentUser {
            return "已登录 @\(user.username)"
        }
        return "未登录 · 使用官方 RSS 阅读"
    }

    private var sessionStatusIcon: String {
        if appState.siteSession.isSessionChecking { return LDOIcon.refresh }
        return appState.siteSession.isLoggedIn ? LDOIcon.connected : LDOIcon.person
    }

    private var settingsForm: some View {
        Form {
            Section {
                HStack(spacing: LDOTheme.spacing12) {
                    LDOAppMark(size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LINUX DO 阅读器")
                            .font(.headline)
                        Text("为 macOS 设计的第三方原生阅读体验")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section("关于") {
                LabeledContent("应用") { Text("LINUX DO 阅读器") }
                LabeledContent("版本") { Text("0.7.0") }
                LabeledContent("阅读来源") { Text("站内会话 · 未登录时用 RSS") }
                LDOFooterText(text: "第三方非官方客户端，与 LINUX DO / Discourse 官方无隶属关系。")
            }

            Section {
                LabeledContent("状态") {
                    HStack(spacing: LDOTheme.spacing8) {
                        if appState.siteSession.isSessionChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label(sessionStatusText, systemImage: sessionStatusIcon)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: LDOTheme.spacing8) {
                    Button("登录与验证") {
                        appState.openLogin()
                    }
                    .buttonStyle(.bordered)
                    .help("在 App 内的 WebKit 中完成登录与 Cloudflare 验证")

                    Button(role: .destructive) {
                        showsClearDataConfirmation = true
                    } label: {
                        Text("清除登录数据")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.siteSession.isClearingData)
                    .help("清除 App 内的登录会话与站点数据")

                    if appState.siteSession.isClearingData {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在清除…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("站内登录")
            } footer: {
                LDOFooterText(text: "登录在 App 内的 WebKit 中完成；只有 linux.do 的会话 Cookie 会加密存入 macOS 钥匙串，用于重启后恢复登录，App 不保存账号密码。")
            }

            HighlightSettingsSections(
                store: appState.highlightStore,
                isLoggedIn: appState.siteSession.isLoggedIn
            )

            Section("网络") {
                LabeledContent("站点") {
                    Text(verbatim: "https://linux.do")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("列表缓存") { Text("\(Int(appState.apiClient.listTTL)) 秒") }
                LabeledContent("详情缓存") { Text("\(Int(appState.apiClient.detailTTL)) 秒") }
                LabeledContent("列表刷新") { Text("仅手动，无定时刷新") }
                LDOFooterText(text: "Cookie 由 WebKit 随 linux.do 同源请求自动发送，App 不读取也不导出；未登录或请求宿主不可用时，公开阅读回退到官方 RSS。")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "清除 LINUX DO 登录数据？",
            isPresented: $showsClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                appState.siteSession.clearWebsiteData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 App 内保存的登录会话与站点数据，之后需要重新登录并完成验证。")
        }
    }
}

private struct HighlightSettingsSections: View {
    @ObservedObject var store: HighlightStore
    let isLoggedIn: Bool
    @State private var editingKeywordRuleID: UUID?

    var body: some View {
        Section {
            Toggle("启用关注作者高亮", isOn: $store.followedHighlightEnabled)

            LabeledContent("强调色") {
                ColorPicker(
                    "关注作者强调色",
                    selection: followedColorBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
                .controlSize(.small)
            }

            LabeledContent("同步状态") {
                HStack(spacing: 6) {
                    if store.isSyncingFollowedUsers {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(followedSyncDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = store.followedUsersSyncError {
                Label(error, systemImage: LDOIcon.warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                store.syncFollowedUsers(force: true)
            } label: {
                Label("同步关注名单", systemImage: LDOIcon.refreshCategories)
            }
            .buttonStyle(.bordered)
            .disabled(!isLoggedIn || store.isSyncingFollowedUsers)
            .help(isLoggedIn ? "立即重新同步关注名单" : "登录后可同步关注名单")
        } header: {
            Text("关注作者高亮")
        } footer: {
            LDOFooterText(text: "登录后每天同步一次关注名单。主题列表按参与作者标记，楼层按回复作者标记；关注与关键词同时命中时，两种状态都会保留。名单仅存储在本机。")
        }

        Section {
            Toggle("启用关键词高亮", isOn: $store.keywordsEnabled)

            if store.keywordRules.isEmpty {
                Label("尚未添加关键词", systemImage: LDOIcon.search)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.keywordRules) { rule in
                    KeywordRuleSettingsRow(
                        store: store,
                        rule: rule,
                        isEditorPresented: editorBinding(for: rule.id)
                    )
                }
            }

            Button {
                editingKeywordRuleID = store.addKeywordRule()
            } label: {
                Label("添加关键词", systemImage: LDOIcon.plus)
            }
            .buttonStyle(.bordered)
            .help("新增一条关键词高亮规则")
        } header: {
            Text("帖子关键词高亮")
        } footer: {
            LDOFooterText(text: "仅匹配主题标题且不区分大小写；多条规则同时命中时，列表中靠前的规则优先。")
        }
    }

    private var followedColorBinding: Binding<Color> {
        Binding(
            get: { store.followedColor },
            set: { store.setFollowedColor($0) }
        )
    }

    private func editorBinding(for ruleID: UUID) -> Binding<Bool> {
        Binding(
            get: { editingKeywordRuleID == ruleID },
            set: { isPresented in
                editingKeywordRuleID = isPresented ? ruleID : nil
            }
        )
    }

    private var followedSyncDescription: String {
        if !isLoggedIn {
            return "登录后自动同步"
        }
        if store.isSyncingFollowedUsers {
            return "正在同步…"
        }
        if let date = store.lastFollowedUsersSyncAt {
            return "已同步 \(store.followedUsernames.count) 人 · \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "等待首次同步"
    }
}

private struct KeywordRuleSettingsRow: View {
    @ObservedObject var store: HighlightStore
    let rule: KeywordHighlightRule
    @Binding var isEditorPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            keywordColorChip

            Text(displayKeyword)
                .foregroundStyle(displayKeywordStyle)
                .lineLimit(1)

            if !rule.enabled {
                Text("已停用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("启用关键词 " + displayKeyword, isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(rule.enabled ? "停用此关键词" : "启用此关键词")

            Button {
                isEditorPresented = true
            } label: {
                Image(systemName: LDOIcon.ellipsisCircle)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("编辑关键词")
            .accessibilityLabel("编辑关键词 " + displayKeyword)
            .popover(isPresented: $isEditorPresented, arrowEdge: .trailing) {
                keywordEditor
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("编辑关键词") {
                isEditorPresented = true
            }

            Toggle("启用关键词", isOn: enabledBinding)

            Divider()

            Button("删除关键词", role: .destructive) {
                removeRule()
            }
        }
    }

    private var keywordEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: LDOIcon.search)
                    .foregroundStyle(colorBinding.wrappedValue)
                Text("编辑关键词")
                    .font(.headline)
            }

            LabeledContent("关键词") {
                TextField("输入关键词", text: keywordBinding)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityLabel("关键词")
            }

            LabeledContent("强调色") {
                ColorPicker(
                    "关键词强调色",
                    selection: colorBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
                .controlSize(.small)
            }

            Divider()

            HStack(spacing: LDOTheme.spacing8) {
                Button("删除关键词", role: .destructive) {
                    removeRule()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)

                Spacer(minLength: LDOTheme.spacing12)

                Button("完成") {
                    isEditorPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var keywordColorChip: some View {
        LDOCategoryDot(
            color: colorBinding.wrappedValue,
            size: 10,
            isOutlined: true
        )
        .opacity(rule.enabled ? 1 : 0.45)
    }

    private var displayKeyword: String {
        let keyword = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty ? "未命名关键词" : keyword
    }

    private var displayKeywordStyle: HierarchicalShapeStyle {
        rule.enabled && !rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .primary
            : .secondary
    }

    private func removeRule() {
        isEditorPresented = false
        store.removeKeywordRule(id: rule.id)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { store.setKeywordEnabled($0, ruleID: rule.id) }
        )
    }

    private var keywordBinding: Binding<String> {
        Binding(
            get: { rule.keyword },
            set: { store.setKeyword($0, ruleID: rule.id) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { store.keywordColor(ruleID: rule.id) },
            set: { store.setKeywordColor($0, ruleID: rule.id) }
        )
    }
}
