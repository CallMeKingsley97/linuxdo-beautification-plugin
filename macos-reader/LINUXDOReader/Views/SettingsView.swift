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
        Section("关注作者高亮") {
            Toggle("启用关注作者高亮", isOn: $store.followedHighlightEnabled)
            ColorPicker(
                "高亮颜色",
                selection: followedColorBinding,
                supportsOpacity: false
            )

            LabeledContent("同步状态") {
                HStack(spacing: 6) {
                    if store.isSyncingFollowedUsers {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(followedSyncDescription)
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
                Label("立即同步关注名单", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!isLoggedIn || store.isSyncingFollowedUsers)

            Text("登录后每天自动同步一次关注名单；主题列表按接口返回的参与作者高亮，楼层按当前回复作者高亮。关注高亮优先使用绿色，关键词徽章会同时保留。名单仅保存在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section("帖子关键词高亮") {
            Toggle("启用关键词高亮", isOn: $store.keywordsEnabled)

            if store.keywordRules.isEmpty {
                Text("暂未添加关键词")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.keywordRules) { rule in
                    HStack(spacing: 10) {
                        Toggle(
                            "启用",
                            isOn: Binding(
                                get: { rule.enabled },
                                set: { store.setKeywordEnabled($0, ruleID: rule.id) }
                            )
                        )
                            .labelsHidden()
                            .controlSize(.small)
                            .help("启用此关键词")

                        TextField(
                            "关键词",
                            text: Binding(
                                get: { rule.keyword },
                                set: { store.setKeyword($0, ruleID: rule.id) }
                            )
                        )
                            .textFieldStyle(.roundedBorder)

                        ColorPicker(
                            "颜色",
                            selection: keywordColorBinding(ruleID: rule.id),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .help("选择高亮颜色")

                        Button(role: .destructive) {
                            store.removeKeywordRule(id: rule.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除关键词")
                    }
                }
            }

            Button {
                store.addKeywordRule()
            } label: {
                Label("添加关键词", systemImage: "plus")
            }

            Text("与 userscript 保持一致：仅匹配主题标题、不区分大小写；多条规则同时命中时，列表中靠前的规则优先。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var followedColorBinding: Binding<Color> {
        Binding(
            get: { store.followedColor },
            set: { store.setFollowedColor($0) }
        )
    }

    private func keywordColorBinding(ruleID: UUID) -> Binding<Color> {
        Binding(
            get: { store.keywordColor(ruleID: ruleID) },
            set: { store.setKeywordColor($0, ruleID: ruleID) }
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
