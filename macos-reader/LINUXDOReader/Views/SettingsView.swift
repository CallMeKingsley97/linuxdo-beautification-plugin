//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("关于") {
                LabeledContent("应用") { Text("LINUX DO 阅读器") }
                LabeledContent("版本") { Text("0.2.0-P2") }
                LabeledContent("阶段") { Text("P2 分类浏览 + 分页") }
                Text("本应用为第三方非官方客户端，与 LINUX DO / Discourse 官方无隶属关系。数据来自站点公开 API。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("网络") {
                LabeledContent("站点") { Text("https://linux.do") }
                LabeledContent("列表缓存") { Text("\(Int(appState.apiClient.listTTL)) 秒") }
                LabeledContent("详情缓存") { Text("\(Int(appState.apiClient.detailTTL)) 秒") }
                LabeledContent("分类缓存") { Text("\(Int(appState.apiClient.categoryTTL)) 秒") }
                Text("当前不登录、不写入、不后台轮询。分页仅在点击「加载更多」时请求。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
        .navigationTitle("设置")
    }
}
