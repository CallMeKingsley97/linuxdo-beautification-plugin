//
//  SiteBrowserView.swift
//

import SwiftUI
import WebKit

struct SiteBrowserView: View {
    @ObservedObject var store: SiteSessionStore

    var body: some View {
        VStack(spacing: 0) {
            browserBar
            Divider()
            ZStack {
                SiteWebView(store: store)
                if let error = store.errorMessage {
                    ContentUnavailableView {
                        Label("页面加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重新加载") { store.reload() }
                    }
                    .background(.background)
                }
            }
        }
        .navigationTitle(store.title)
        .onAppear {
            store.loadHomeIfNeeded()
        }
    }

    private var browserBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button(action: store.goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!store.canGoBack)
                .help("后退")

                Button(action: store.goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!store.canGoForward)
                .help("前进")

                Button(action: store.goHome) {
                    Image(systemName: "house")
                }
                .help("LINUX DO 首页")
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text(store.currentURL?.host ?? "linux.do")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(LDOTheme.subtleFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: store.reload) {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新加载")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.bar)
    }
}

private struct SiteWebView: NSViewRepresentable {
    @ObservedObject var store: SiteSessionStore

    func makeNSView(context: Context) -> WKWebView {
        store.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// 常驻在主界面背后的同源请求宿主。它与登录 WebView 共用 WebKit 数据存储，
/// 原生页面通过它执行带 Cookie/CSRF 的 fetch，但不会读取或导出 Cookie。
struct SiteRequestHostView: NSViewRepresentable {
    @ObservedObject var store: SiteSessionStore

    func makeNSView(context: Context) -> WKWebView {
        store.prepareRequestHost()
        return store.requestWebView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        store.prepareRequestHost()
    }
}
