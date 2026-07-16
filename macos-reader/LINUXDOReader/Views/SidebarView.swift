//
//  SidebarView.swift
//

import SwiftUI

struct SidebarView: View {
    @Binding var selection: BrowseSelection
    @ObservedObject var categoryStore: CategoryStore

    var body: some View {
        List(selection: selectionBinding) {
            Section("浏览") {
                Label("最新", systemImage: "clock")
                    .tag(BrowseSelection.latest)
                Label("热门", systemImage: "flame")
                    .tag(BrowseSelection.hot)
            }

            Section("分类") {
                switch categoryStore.phase {
                case .idle, .loading where categoryStore.categories.isEmpty:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
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
                        HStack(spacing: 8) {
                            Circle()
                                .fill(categoryColor(category.color))
                                .frame(width: 8, height: 8)
                            Text(category.name)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if category.topicCount > 0 {
                                Text("\(category.topicCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
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

            Section("关于") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LINUX DO 阅读器")
                        .font(.headline)
                    Text("第三方非官方客户端 · P2 分类浏览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("数据来自 linux.do 公开 JSON API")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
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

private extension Color {
    /// 解析 Discourse 分类色（如 "0088CC" / "#0088CC"）
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
