//
//  LINUXDOReaderApp.swift
//  LINUX DO 原生阅读器入口
//

import SwiftUI

@main
struct LINUXDOReaderApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("浏览") {
                Button("刷新当前列表") {
                    appState.refreshList()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("最新") {
                    appState.selectLatest()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("热门") {
                    appState.selectHot()
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("通知") {
                    appState.select(.notifications)
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("登录与验证") {
                    appState.openLogin()
                }
                .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Button("检查登录状态") {
                    appState.siteSession.refreshSession()
                }
            }
        }

        Settings {
            SettingsView(usesStandaloneWindowSize: true)
                .environmentObject(appState)
        }
    }
}
