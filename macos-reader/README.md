# LINUX DO macOS 阅读器

第三方 **非官方** macOS 原生客户端，用 SwiftUI 阅读 [LINUX DO](https://linux.do)。  
与仓库内油猴脚本并行：网页继续美化，桌面端自由做 UI。

| 项 | 说明 |
|---|---|
| 工程 | `LINUXDOReader.xcodeproj` |
| 最低系统 | macOS 14 Sonoma |
| 当前版本 | **0.2.0 · P2 分类浏览** |
| 进度 | 见 [ROADMAP.md](./ROADMAP.md) |
| 总方案 | [../LINUXDO_macOS_SwiftUI_阅读器方案.md](../LINUXDO_macOS_SwiftUI_阅读器方案.md) |

---

## P1 能做什么

- 三栏布局：侧栏（最新 / 热门）→ 主题列表 → 主题详情
- 拉公开 API：`/latest.json`、`/hot.json`、`/t/{id}.json`
- 正文用 WKWebView 渲染 Discourse `cooked` HTML
- 加载中 / 失败重试 / 手动刷新（⌘R）
- 在浏览器打开当前主题
- 请求去重 + 短时缓存（RequestGate）
- 侧栏分类（/categories.json）与分类主题列表
- 列表底部「加载更多」分页

## P1 明确不做

- 登录、通知、回复、书签写入
- 分类树、搜索、长帖分窗
- 关注高亮等油猴对齐能力（P5）
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
    ├── Views/                 # SwiftUI + WKWebView
    └── Resources/             # Assets
```

---

## 架构约定（P1）

1. **Base URL**：`https://linux.do`  
2. **User-Agent**：`LINUXDOReader/0.1.0 (macOS; third-party; not-affiliated)`  
3. **无私有轮询**：只在用户打开 / 刷新时请求  
4. **失败不自动连环重试**：UI 点「重试」  
5. **关于页声明非官方**

---

## 下一阶段（摘自 ROADMAP）

| 阶段 | 内容 |
|---|---|
| P2 | 分类、分页、跳楼层 |
| P3 | User API Key 登录 + Keychain |
| P4 | 通知 / 回复 / 书签 |
| P5 | 关注高亮、关键词等与油猴对齐 |
| P6 | Developer ID 签名、公证、Sparkle |

---

## 开发机说明

当前仓库可能在 Windows 上维护源码与文档；**真机编译、User API 授权 POC、Gatekeeper 分发** 必须在 Mac 完成。跑通 P1 后，请在 `ROADMAP.md` 的迭代记录里勾选「Mac 编译通过」。

