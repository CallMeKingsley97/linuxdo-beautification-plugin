//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
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
                LabeledContent("版本") { Text("0.6.1") }
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

            Section("网络") {
                LabeledContent("站点") { Text("https://linux.do") }
                LabeledContent("列表缓存") { Text("\(Int(appState.apiClient.listTTL)) 秒") }
                LabeledContent("详情缓存") { Text("\(Int(appState.apiClient.detailTTL)) 秒") }
                Text("Cookie 不会显示、记录或导出；仅由 WebKit 自动随 linux.do 同源请求发送。未登录或请求宿主不可用时，公开阅读回退到官方 RSS。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 480)
        .navigationTitle("设置")
    }
}
