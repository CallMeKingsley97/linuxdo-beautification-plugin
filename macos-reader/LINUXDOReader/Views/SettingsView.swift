//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    var usesStandaloneWindowSize = false

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

    private var settingsForm: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    LDOAppMark(size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LINUX DO 阅读器")
                            .font(.headline)
                        Text("为 macOS 设计的第三方原生阅读体验")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("关于") {
                LabeledContent("应用") { Text("LINUX DO 阅读器") }
                LabeledContent("版本") { Text("0.7.0") }
                LabeledContent("模式") { Text("WebKit 会话 JSON + RSS 回退") }
                Text("本应用为第三方非官方客户端，与 LINUX DO / Discourse 官方无隶属关系。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("站内登录") {
                Text("登录由 App 内 WebKit 完成。仅 linux.do 域的会话 Cookie 会加密保存在 macOS 钥匙串，用于 App 重启后恢复登录；账号密码不会由 App 保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    appState.siteSession.clearWebsiteData()
                } label: {
                    if appState.siteSession.isClearingData {
                        ProgressView("正在清除…")
                    } else {
                        Text("清除 LINUX DO 登录数据")
                    }
                }
                .disabled(appState.siteSession.isClearingData)
            }

            HighlightSettingsSections(
                store: appState.highlightStore,
                isLoggedIn: appState.siteSession.isLoggedIn
            )

            Section("网络") {
                LabeledContent("站点") { Text("https://linux.do") }
                LabeledContent("列表缓存") { Text("\(Int(appState.apiClient.listTTL)) 秒") }
                LabeledContent("详情缓存") { Text("\(Int(appState.apiClient.detailTTL)) 秒") }
                LabeledContent("列表刷新") { Text("仅手动，无定时刷新") }
                Text("Cookie 不会显示、记录或导出；仅由 WebKit 自动随 linux.do 同源请求发送。未登录或请求宿主不可用时，公开阅读回退到官方 RSS。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HighlightSettingsSections: View {
    @ObservedObject var store: HighlightStore
    let isLoggedIn: Bool

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
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                store.syncFollowedUsers(force: true)
            } label: {
                Label("同步关注名单", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .disabled(!isLoggedIn || store.isSyncingFollowedUsers)
        } header: {
            Text("关注作者高亮")
        } footer: {
            Text("登录后每天同步一次关注名单。主题列表按参与作者标记，楼层按回复作者标记；关注与关键词同时命中时，两种状态都会保留。名单仅存储在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Toggle("启用关键词高亮", isOn: $store.keywordsEnabled)

            if store.keywordRules.isEmpty {
                Label("尚未添加关键词", systemImage: "text.magnifyingglass")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.keywordRules) { rule in
                    KeywordRuleSettingsRow(store: store, rule: rule)
                }
            }

            Button {
                store.addKeywordRule()
            } label: {
                Label("添加关键词", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("帖子关键词高亮")
        } footer: {
            Text("仅匹配主题标题且不区分大小写；多条规则同时命中时，列表中靠前的规则优先。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var followedColorBinding: Binding<Color> {
        Binding(
            get: { store.followedColor },
            set: { store.setFollowedColor($0) }
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

    var body: some View {
        HStack(spacing: 10) {
            Toggle("启用规则", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help(rule.enabled ? "停用此关键词" : "启用此关键词")

            TextField("输入关键词", text: keywordBinding)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .frame(minWidth: 180, maxWidth: .infinity)
                .accessibilityLabel("关键词")

            ColorPicker(
                "关键词颜色",
                selection: colorBinding,
                supportsOpacity: false
            )
            .labelsHidden()
            .controlSize(.small)
            .help("选择强调色")

            Button {
                store.removeKeywordRule(id: rule.id)
            } label: {
                Image(systemName: "minus.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("删除关键词")
        }
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
