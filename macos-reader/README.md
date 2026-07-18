# LINUX DO macOS 阅读器

第三方 **非官方** macOS 原生客户端，用 SwiftUI 阅读 [LINUX DO](https://linux.do)。  
与仓库内油猴脚本并行：网页继续美化，桌面端自由做 UI。

| 项 | 说明 |
|---|---|
| 工程 | `LINUXDOReader.xcodeproj` |
| 最低系统 | macOS 14 Sonoma |
| 当前版本 | **0.7.0 · 关注作者与关键词高亮** |
| 进度 | 见 [ROADMAP.md](./ROADMAP.md) |
| UI 标准 | [../AGENTS.md](../AGENTS.md) 的 `macos-reader UI 设计标准` |
| 总方案 | [../LINUXDO_macOS_SwiftUI_阅读器方案.md](../LINUXDO_macOS_SwiftUI_阅读器方案.md) |

---

## 当前能做什么

- 三栏布局：侧栏（最新 / 热门）→ 主题列表 → 主题详情
- 统一 macOS 原生视觉系统：系统材质侧栏、Mail 风格列表、连续文档式楼层流、原生工具栏与状态栏
- 在 App 内完成 LINUX DO 网页登录；仅 linux.do 域会话 Cookie 加密保存在 macOS 钥匙串，用于跨启动恢复
- 登录后通过常驻同源 WKWebView 执行 Discourse JSON `fetch`，原生显示完整列表和等级受限主题
- 未登录或会话请求宿主不可用时，公开阅读回退官方 RSS
- 整个主题使用单个 WKWebView 连续渲染 Discourse `cooked` HTML，正文中央可直接滚动，长帖与多图帖更流畅
- 长帖按 20 层原生分页加载，不跳外部浏览器
- 主题列表不做定时自动刷新；首次进入数据源后，仅由下拉手势、工具栏或 ⌘R 主动刷新
- 设置完整整合进主窗口侧边栏，同时保留 macOS 标准 ⌘, 设置窗口
- 原生回复主题或指定楼层；CSRF 与 Cookie 均由 WebKit 同源请求处理
- 登录后每天自动同步当前账号的关注名单；主题列表按接口返回的参与作者、楼层按回复作者高亮
- 可配置多条主题标题关键词、独立颜色与启用状态；不区分大小写并按规则顺序匹配
- 加载中 / 失败重试 / 手动刷新（⌘R）
- 请求去重 + 短时缓存（RequestGate）
- 侧栏使用已核验的公开分类目录，并读取分类 RSS

## 当前尚未完成

- 通知、书签、表情回应、已读进度
- 搜索、跳楼、只看楼主、子分类树
- 已读淡化、书签与更多油猴对齐能力（P5）
- App Store / Sparkle 分发（P6）

---

## 在 Mac 上运行

> 必须在 **Mac + Xcode 15+** 上编译。Windows 只能改源码，不能 Run。

1. 安装 Xcode（App Store），打开一次并同意许可。  
2. 双击打开：

```text
macos-reader/LINUXDOReader.xcodeproj
```

3. 顶部 Scheme 选 **LINUXDOReader**，目标选 **My Mac**。  
4. 若签名报错：Signing & Capabilities → Team 选个人团队，或暂时 **Sign to Run Locally**。  
5. ⌘R 运行。

命令行（可选）：

```bash
cd macos-reader
xcodebuild -scheme LINUXDOReader -configuration Debug -destination 'platform=macOS' build
```

---

## 目录结构

```text
macos-reader/
├── ROADMAP.md                 # 分阶段进度（请持续更新）
├── README.md
├── LINUXDOReader.xcodeproj/
└── LINUXDOReader/
    ├── App/                   # 入口、全局状态
    ├── Models/                # 领域模型 + JSON DTO
    ├── Network/               # APIClient、端点、RequestGate、错误
    ├── ViewModels/            # 列表 / 详情
    ├── Views/                 # SwiftUI + WKWebView；Components/DesignSystem.swift 为视觉基线
    └── Resources/             # Assets
```

---

## 会话与网络架构

1. **Base URL**：`https://linux.do`  
2. **登录**：使用 `WKWebsiteDataStore.default()`；App 不保存账号密码
3. **会话恢复**：仅将 linux.do 域 Cookie 序列化后加密保存在 macOS Keychain，启动时先恢复到 WebKit Cookie Store
4. **原生请求**：在同源请求 WKWebView 中执行 `fetch`；Cookie 仅由 WebKit 自动携带
5. **写请求**：每次从 `/session/csrf.json` 取得 CSRF，再提交 `/posts`
6. **隐私边界**：Cookie 不显示、不记录、不导出；清除登录数据时同步删除 WebKit 站点数据与 Keychain 会话
7. **匿名回退**：公开列表和主题仍可通过官方 RSS 阅读
8. **参考实现**：网络桥思路参考 MIT 开源项目 [ArkDO](https://github.com/EnjoySR/ArkDO)，macOS 端为独立 Swift/WebKit 实现

LINUX DO 当前禁用了 Discourse User API Key 发布，因此本项目不再走 User API Key 授权方案。Keychain 只用于保存 App 内网页登录已产生的 linux.do 会话 Cookie。

---

## 下一阶段（摘自 ROADMAP）

| 阶段 | 内容 |
|---|---|
| P2 | 搜索、跳楼层、只看楼主、子分类 |
| P3 | WebKit 登录会话完善、注销与账号页 |
| P4 | 通知 / 书签 / 表情回应 / 已读进度 |
| P5 | 关注高亮、关键词已完成；继续补齐已读淡化等能力 |
| P6 | Developer ID 签名、公证、Sparkle |

---

## 开发机说明

真机验证环境：macOS 15.7.7、Xcode 26.3。已验证登录用户识别、受限主题原生打开、4,120 层主题分页从 20 层增至 40 层，以及主题/指定楼层回复编辑器（未发送测试内容）。使用 `SIGKILL` 强制退出后重新启动，Keychain 会话可自动恢复 `kingsley9527`，无需再次登录。

所有后续 UI 修改必须遵循仓库根目录 [AGENTS.md](../AGENTS.md) 中的 macOS 原生设计标准，并优先复用 `Views/Components/DesignSystem.swift`。
