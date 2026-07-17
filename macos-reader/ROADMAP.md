# LINUX DO macOS 阅读器 · 开发路线图

> 工程目录：`macos-reader/`  
> 技术栈：SwiftUI + Swift · 仅 macOS · 直接分发（非 App Store）  
> 关联方案：`LINUXDO_macOS_SwiftUI_阅读器方案.md`  
> 最后更新：2026-07-17

---

## 进度总览

| 阶段 | 名称 | 状态 | 目标一句话 |
|---|---|---|---|
| P0 | 工程与纪律 | ✅ 完成 | Xcode 工程 + 路线图 + 请求门禁 |
| P1 | 匿名读帖 MVP | ✅ 完成 | 官方 RSS 最新/热门 + 详情 + cooked HTML |
| P2 | 导航增强 | 🚧 分类/长帖分页已做 | 搜索、跳楼、只看楼主后续 |
| P3 | 登录与账号 | ✅ 核心完成 | WebKit 站内登录、会话恢复、当前用户 |
| P4 | 互动闭环 | 🚧 回复已做 | 通知、书签、回应、已读进度后续 |
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
| App 内兼容网页入口 | ✅ |
| Mac 编译运行 | ✅ |

---

## P2 · 导航增强 — 🚧

| 项 | 状态 | 说明 |
|---|---|---|
| 分类目录 | ✅ | 已核验的公开顶层分类 URL |
| 分类主题 `/c/{slug}/{id}.rss` | ✅ | 点选分类切换 RSS 列表 |
| 列表分页「加载更多」 | ✅ | 登录后 JSON `page` 分页；匿名 RSS 无下一页 |
| 搜索 | ⏳ | 建议登录后（P3）再做 |
| 长帖楼层分页 | ✅ | 按 `post_stream.stream` 每次加载 20 层 |
| 楼层跳转 / 只看楼主 | ⏳ | |
| 子分类展开 | ⏳ | 当前只展示无 parent 的顶层分类 |
| Mac 编译运行 | ✅ | 最新、热门、详情已真机验收 |

---

## P3 · 登录与账号 — ✅ 核心完成

- 站点管理员禁用了 Discourse User API Key 发布，授权页真实验证失败，方案已撤销。
- 使用 App 内持久化 WKWebView 完成正常网页登录与 Cloudflare 验证。
- 常驻同源请求宿主与登录 WebView 共用 WebKit 数据存储。
- 仅将 linux.do 域会话 Cookie 加密保存在 macOS Keychain，启动时恢复到 WebKit；不显示、记录或导出 Cookie。
- `/session/current.json` 检测当前用户；写操作未登录时引导登录。
- App 不保存账号密码；设置页清除站点数据时同步删除 Keychain 会话。

---

## P4 · 互动闭环 — 🚧

| 项 | 状态 | 说明 |
|---|---|---|
| 回复主题 | ✅ | 原生编辑器 + `POST /posts` |
| 回复指定楼层 | ✅ | 携带 `reply_to_post_number` |
| 通知 | ⏳ | |
| 书签 / 表情回应 | ⏳ | |
| 已读进度 | ⏳ | |

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

### 2026-07-17 · macOS 真机验收 + RSS 适配

- Xcode 26.3 / macOS 15.7.7 编译运行通过。
- Cloudflare 阻止原生 JSON 请求，WebKit 挑战也无法稳定完成。
- 改用站点官方只读 RSS：最新、热门、公开分类与主题楼层均可加载。
- 实时验证最新列表 30 条，长主题正文可按楼层号顺序显示。
- 版本 **0.3.0**。

### 2026-07-17 · App 内完整模式

- 确认站点禁用 User API Key，改用持久化 WKWebView 登录。
- 登录、受限主题、完整网页回复均可在 App 内完成，作为 JSON 桥完成前的兼容路径。
- 版本 **0.4.0**。

### 2026-07-17 · WebKit 会话 JSON 桥 + 原生回复

- 参考 ArkDO 的同源浏览器请求思路，在 macOS 常驻请求 WKWebView 中执行带 Cookie 的 `fetch`。
- 登录后最新/热门/分类/主题详情切回原生 JSON 数据；匿名状态保留 RSS 回退。
- 支持 `post_stream` 长帖分页和原生回复主题/指定楼层。
- 真机验证 `kingsley9527` 会话恢复成功；等级受限《秘密花园园丁邀请函》原生打开，显示 4,119 层。
- 真机验证分页由 20/4,119 增至 40/4,119；主题回复与“回复 #43”编辑器可打开，未发送测试内容。
- 增加 linux.do 会话 Cookie 的 Keychain 保存/启动恢复，避免仅依赖 WebKit 在强制终止时落盘；已通过 `SIGKILL` 强制退出后的跨进程回归，无需再次登录即可恢复 `kingsley9527`。
- 版本 **0.5.0**。

### 2026-07-17 · macOS 原生视觉系统

- 建立 `DesignSystem.swift`，统一语义色、阅读宽度、间距、圆角、标签、状态徽章和数据指标。
- 侧栏改为系统材质与紧凑账号状态；主题列表改为 Mail 风格平面列表与原生状态栏。
- 详情页由楼层卡片堆叠改为连续文档式会话流，分页使用底部原生状态栏，回复保留在系统工具栏。
- WebView 正文同步优化系统字体、引用、代码、表格和明暗模式表现。
- UI 标准写入仓库根目录 `AGENTS.md`，后续 UI 修改必须遵守并复用设计系统。
- 版本 **0.6.0**。

### 2026-07-17 · 正文图片渲染修复

- 隐藏 Discourse lightbox 附带的文件名、分辨率和大小元数据，避免显示 `image567×217 4.53 KB` 一类链接。
- 使用 `ResizeObserver` 与 WebKit 消息同步图片加载后的真实正文高度，消除图片楼层中的多余空白。
- 图片加载失败时显示轻量占位状态，不再暴露原始文件元数据。
- 版本 **0.6.1**。

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
