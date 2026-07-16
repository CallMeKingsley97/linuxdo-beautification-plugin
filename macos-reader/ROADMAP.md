# LINUX DO macOS 阅读器 · 开发路线图

> 工程目录：`macos-reader/`  
> 技术栈：SwiftUI + Swift · 仅 macOS · 直接分发（非 App Store）  
> 关联方案：`LINUXDO_macOS_SwiftUI_阅读器方案.md`  
> 最后更新：2026-07-16

---

## 进度总览

| 阶段 | 名称 | 状态 | 目标一句话 |
|---|---|---|---|
| P0 | 工程与纪律 | ✅ 完成 | Xcode 工程 + 路线图 + 请求门禁 |
| P1 | 匿名读帖 MVP | ✅ 源码完成，待 Mac 验收 | 最新/热门 + 详情 + cooked HTML |
| P2 | 导航增强 | 🚧 分类+分页已做，待 Mac 验收 | 分类列表、加载更多；搜索/跳楼后续 |
| P3 | 登录与账号 | ⏳ 未开始 | User API Key + Keychain |
| P4 | 互动闭环 | ⏳ 未开始 | 通知、回复、书签 |
| P5 | 体验对齐油猴 | ⏳ 未开始 | 关注高亮、关键词等 |
| P6 | 分发与打磨 | ⏳ 未开始 | 签名 / 公证 / Sparkle |

**图例**：✅ 完成 · 🚧 进行中 · ⏳ 未开始 · ⛔ 阻塞

---

## P0 · 工程与纪律 — ✅

| 项 | 状态 |
|---|---|
| `macos-reader/` monorepo | ✅ |
| `ROADMAP.md` / `README.md` | ✅ |
| `LINUXDOReader.xcodeproj` | ✅ |
| Network / Models / VM / Views 分层 | ✅ |
| RequestGate | ✅ |
| 非官方声明 | ✅ |

---

## P1 · 匿名读帖 MVP — ✅ 源码（Mac 验收 ⏳）

| 项 | 状态 |
|---|---|
| 最新 / 热门列表 | ✅ |
| 主题详情 + 楼层 | ✅ |
| cooked HTML（WKWebView） | ✅ |
| 错误 / 重试 / ⌘R | ✅ |
| 浏览器打开 | ✅ |
| Mac 编译运行 | ⏳ |

---

## P2 · 导航增强 — 🚧

| 项 | 状态 | 说明 |
|---|---|---|
| 分类列表 `/categories.json` | ✅ | 侧栏展示顶层分类与色点 |
| 分类主题 `/c/{slug}/{id}.json` | ✅ | 点选分类切换列表 |
| 列表分页「加载更多」 | ✅ | 手动点击，不自动连翻 |
| 搜索 | ⏳ | 建议登录后（P3）再做 |
| 楼层跳转 / 只看楼主 | ⏳ | |
| 子分类展开 | ⏳ | 当前只展示无 parent 的顶层分类 |
| Mac 编译运行 | ⏳ | |

---

## P3 · 登录与账号 — ⏳

User API Key 授权 POC · Keychain · 当前用户 · 注销

---

## P4 · 互动闭环 — ⏳

通知 · 回复 · 书签 · 已读进度

---

## P5 · 体验对齐油猴 — ⏳

关注同步 / 高亮 · 关键词 · 已读淡化 · 状态徽章 · 开关

---

## P6 · 分发与打磨 — ⏳

Developer ID · 公证 · Sparkle · WebView 性能

---

## 每次迭代记录

### 2026-07-16 · 开工 P0 + P1

- 创建工程与匿名读帖全流程源码（约 19 个 Swift 文件）。
- 版本 **0.1.0**。

### 2026-07-16 · P2 分类 + 分页

- `BrowseSelection` 支持 latest / hot / category。
- `CategoryStore` + `/categories.json`；侧栏色点与主题数。
- 列表 `loadMore()`：page 递增、去重合并、空页停。
- 版本 **0.2.0**。
- 仍需 **Mac + Xcode ⌘R** 验收。

---

## 本地运行（Mac）

```bash
open macos-reader/LINUXDOReader.xcodeproj
# Scheme: LINUXDOReader → My Mac → ⌘R
```

---

## 与油猴关系

| 产物 | 路径 |
|---|---|
| 油猴 | `linuxdo-beautification.user.js` |
| 桌面端 | `macos-reader/` |
| 方案 | `LINUXDO_macOS_SwiftUI_阅读器方案.md` |
