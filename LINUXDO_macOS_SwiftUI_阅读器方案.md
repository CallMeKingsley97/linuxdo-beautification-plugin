# LINUX DO macOS 阅读器方案（SwiftUI）

> 状态：方案文档（未开工实现）  
> 平台范围：**仅 macOS**  
> UI 技术栈：**SwiftUI + Apple 原生框架**  
> 站点：`https://linux.do`（Discourse）  
> 分发方式：**直接分发（已确认，不走 App Store）**  
> 关联项目：本仓库油猴脚本 `linuxdo-beautification.user.js`（网页增强继续维护；桌面端为独立产品线）

---

## 1. 文档目标

本文档定义 **LINUX DO macOS 原生阅读器** 的产品定位、技术架构、模块拆分、接口策略、UI 信息架构、分期计划与验收标准。

本文档只描述方案与约束，**不代表代码已实现**。

### 1.1 要解决的问题

| 问题 | 油猴脚本现状 | 桌面端目标 |
|---|---|---|
| UI 自由度 | 受 Discourse DOM / CSS 限制 | 完全自绘，可做到系统级观感 |
| 阅读体验 | 浏览器标签页，干扰多 | 三栏阅读工作台，沉浸模式 |
| 性能与资源 | 依赖整站 SPA + 浏览器开销 | 按需请求、本地缓存、更低内存 |
| 增强能力上限 | 只能装饰现有页面 | 信息架构可重构，功能可原生实现 |
| 配置与数据 | GM 存储 | Keychain + SwiftData/SQLite，可导入油猴配置 |

### 1.2 非目标（明确不做）

- 不做 Windows / Linux 同步适配（本阶段仅 macOS）。
- 不做站点管理后台、审核工具。
- 不做爬虫式批量抓取、自动顶贴、绕过权限。
- 不伪装成 LINUX DO 官方客户端（关于页必须标明第三方 / 非官方）。
- 不默认开启高频轮询或后台持续刷接口。

---

## 2. 产品定位

### 2.1 一句话

**面向日常读帖与回帖的 macOS 原生 LINUX DO 阅读工作台**：用官方合法 API 获取数据，用 SwiftUI 自由构建 UI，并把油猴脚本中已验证的增强能力（关注高亮、关键词、书签视觉、状态徽章等）升级为原生模块。

### 2.2 目标用户

- 每天在 macOS 上长时间浏览 LINUX DO 的用户。
- 希望「比浏览器更干净、比油猴更自由」的阅读体验用户。
- 需要本地标签、关键词、关注高亮等个人工作流的用户。

### 2.3 成功标准（产品层）

1. 日常 **80%+** 的浏览 / 读帖 / 回复可在 App 内完成，无需打开浏览器。
2. 有缓存时冷启动到可读列表 **不超过 2 秒**（M 系列 Mac，正常网络）。
3. 长帖阅读体验（目录、只看楼主、跳楼层、字体密度）明显优于网页默认。
4. 注销后本地敏感凭据与账号隔离缓存可彻底清除。
5. 不出现未授权批量请求；空闲时不后台狂刷接口。

---

## 3. 技术选型

### 3.1 为什么选 SwiftUI（仅 macOS）

| 维度 | 选择 | 说明 |
|---|---|---|
| UI | **SwiftUI** | 与 macOS 系统控件、深浅色、动态字体、无障碍天然契合；迭代快 |
| 最低系统 | **macOS 14 Sonoma**（可评估 13） | 使用较新的 NavigationSplitView、Observation、SwiftData 能力 |
| 架构语言 | **Swift 5.9+** | 类型安全、并发模型（async/await、Actor）清晰 |
| 网络 | **URLSession** | 系统级 TLS、HTTP/2、后台传输可控 |
| 本地存储 | **SwiftData** 或 **GRDB/SQLite** | 列表缓存、已读进度、本地标签；凭据走 Keychain |
| 安全存储 | **Keychain Services** | User API Key / Client ID 等敏感信息 |
| 富文本 | **WKWebView 沙箱（MVP）** + 逐步原生组件化 | Discourse cooked HTML 兼容性优先 |
| 图片 | **Nuke / 自研 ImageLoader**（可选） | 头像与正文图缓存、解码限流 |
| 更新分发 | **Sparkle 2**（直接分发） | **已确认不走 App Store**；Developer ID + 公证 + Sparkle |

### 3.2 不采用的方案（本阶段）

| 方案 | 原因 |
|---|---|
| Electron / Tauri 套壳 | 本阶段要 macOS 原生质感与系统集成，不优先跨端 |
| 纯 WKWebView 加载整站 | 无法真正自由 UI，又回到油猴赛道 |
| 解析网页 HTML 当主数据源 | 脆弱、难维护；主路径必须是 JSON API |
| 存储明文密码做登录 | 安全与合规风险高；优先 User API Key |

### 3.3 系统能力清单（macOS 集成）

- 菜单栏：刷新、标记已读、沉浸模式、设置、注销。
- 快捷键：Cmd+R 刷新、Cmd+F 搜索、Cmd+1/2/3 切换导航区、J/K 列表导航（可选）。
- 通知：用户显式开启后，可用 UserNotifications 展示重要通知摘要（可关）。
- 外链：正文外链用系统浏览器打开（可配置）。
- 窗口：分栏比例记忆；多窗口打开同一主题（可选 Stage 3）。

---

## 4. 总体架构

### 4.1 分层

```text
App / UI（SwiftUI）
  - NavigationSplitView 三栏壳
  - 列表、详情、通知、设置、写作 Sheet
  - Design System（颜色 / 字体 / 间距 / 组件）
Presentation（ViewModel）
  - @Observable 状态对象
  - 页面状态：loading / content / empty / error
  - 用户意图 → 用例调用
Domain（领域层）
  - UseCase：登录、拉列表、读主题、回复、通知、关注同步
  - Entity：Topic / Post / User / Notification / Vote
  - Feature 插件：Keyword / FollowHighlight / LocalTag
Data（数据层）
  - DiscourseAPIClient（URLSession）
  - DTO ↔ Domain Mapper
  - CacheRepository（SwiftData/SQLite）
  - AuthStore（Keychain）
  - RequestGate（in-flight 合并、TTL、失败不自动重试）
Platform（系统）
  - Keychain / Notifications / AppStorage / FileManager
        |
        v
https://linux.do  （Discourse）
```

### 4.2 核心设计原则

1. **UI 与 API 解耦**：换皮肤不影响业务；业务不依赖 View 生命周期乱发请求。
2. **主路径走 JSON API**，不把 HTML 页面当数据源。
3. **增强能力插件化**：关注高亮、关键词、本地标签等可独立开关、独立测试。
4. **请求预算可控**：无隐蔽轮询；同资源 in-flight 合并；失败不连打。
5. **隐私优先**：凭据仅本地；不上传用户内容到第三方；多账号数据隔离。
6. **优雅降级**：字段缺失 / 403 / 插件未启用时隐藏能力，不崩溃、不绕过。

### 4.3 并发模型

- 网络与磁盘 IO：async/await。
- 共享可变状态（缓存字典、in-flight map）：actor（如 RequestGate、FollowCacheStore）。
- UI 更新：主线程（@MainActor ViewModel）。
- 图片解码与 HTML 预处理：后台任务，结果回主线程。

---

## 5. 登录与鉴权

### 5.1 首选：Discourse User API Key

Discourse 官方支持第三方客户端通过 **User API Key** 访问用户权限范围内的接口。

**推荐授权流程：**

```text
1. App 生成 client_id（本地 UUID，持久化）
2. 组装 User API Key 授权 URL（含 application_name、client_id、scopes、public_key 等）
3. 用 ASWebAuthenticationSession 或独立窗口打开授权页
4. 用户在 linux.do 确认授权
5. 回调携带 payload（按官方协议解密）
6. 将 User API Key + username 写入 Keychain
7. 之后请求携带官方约定 Header
```

> 第 0 阶段必须在真实站点验证：linux.do 是否开放 User API、可用 scopes、回调方式与字段。

### 5.2 Header 约定（实现时以官方文档与实测为准）

常见形式（示意）：

```http
User-Api-Key: <key>
User-Api-Client-Id: <client_id>
```

本 App **主路径避免依赖浏览器 Cookie**。若个别写操作 User API 不可用，再评估受限 fallback，不作为默认登录。

### 5.3 申请 Scope 建议（按阶段）

| 阶段 | Scope 意图 | 用途 |
|---|---|---|
| MVP | 读主题/帖子、通知、书签、用户信息 | 阅读闭环 |
| MVP | 发帖/回复 | 写作 |
| V1 | 书签写、已读状态 | 完整互动 |
| V1+ | 若存在投票/关注相关 scope | 投票与关注增强 |

原则：**最小权限**；未用到的 scope 不申请。

### 5.4 会话生命周期

| 事件 | 行为 |
|---|---|
| 首次启动未登录 | 展示引导 +「连接 LINUX DO」 |
| 登录成功 | 拉 current user、site 基础配置、写入本地资料缓存 |
| 401 / 鉴权失效 | 清 Keychain 会话态，回到登录，保留非敏感偏好设置 |
| 用户注销 | 删除 Keychain 凭据 + 该账号隔离缓存；可选保留全局外观设置 |
| 多账号（V2） | 每账号独立 store 命名空间 |

### 5.5 备选登录（仅验证失败时的研究项）

若站点关闭 User API：研究「App 内受限 Web 登录换取 Cookie + 本地隔离」——安全与稳定性差，**仅作应急附录，不进 MVP 主路径**。

---

## 6. API 与请求策略

### 6.1 基础

- Base URL：`https://linux.do`
- 格式：Discourse 标准 `.json` 端点
- 编码：UTF-8
- 客户端标识：合理 User-Agent（含 App 名与版本；不做伪装浏览器刷量）

### 6.2 MVP 需要的能力矩阵（第 0 阶段验证）

| 能力 | 典型端点（示意） | MVP | 备注 |
|---|---|---|---|
| 站点能力 | `/site.json` | 是 | 分类、插件、时区等 |
| 当前用户 | `/session/current.json` 或 User API 对应用户接口 | 是 | 头像、用户名、信任级等 |
| 最新主题 | `/latest.json` | 是 | 分页 |
| 分类主题 | `/c/{slug}/{id}.json` | 是 | |
| 热门 | `/hot.json` 或站点等价路由 | 是 | 以 site 为准 |
| 主题详情 | `/t/{id}.json` 或 `/t/{slug}/{id}.json` | 是 | post_stream |
| 帖子分窗 | posts 加载接口 | 是 | 长帖按窗加载 |
| 通知 | `/notifications.json` | 是 | |
| 搜索 | `/search.json` | 是 | 防抖 + 手动触发 |
| 书签 | 书签列表相关 JSON | 是 | 读；写放 V1 亦可 |
| 回复 | POST 创建 post | 是 | |
| 关注列表 | `/u/{username}/follow/following.json` | V1 | 对齐油猴日同步 |
| 投票字段 | topic 上 vote_count 等 | V1 | 插件依赖 |
| 投票者 | 点击才请求 | V2 | 按需 |
| 用户卡片/徽章 | 点击才请求 | V2 | 按需 |

> 具体路径与字段以第 0 阶段实测为准，实现时写入 `docs/api-matrix.md`。

### 6.3 请求门禁（RequestGate）

桌面端**允许**为功能主动请求官方列表/详情 JSON，但纪律如下：

1. **禁止后台隐蔽轮询**（系统通知默认关闭；若开启须长间隔且可关）。
2. **同 URL + 同参数** 存在进行中请求时，复用同一个 Task。
3. **成功缓存 TTL**：列表 30–120s 可配；详情按更新时间 / posts_count 失效。
4. **失败不自动重试**；由用户「重试」或下拉刷新触发。
5. **不为列表每一行预拉用户卡 / 完整主题 JSON**。
6. **搜索必须防抖**（300–500ms）且优先手动回车触发。
7. **分页不自动连翻**；滚到底再加载下一页。
8. **写操作**需明确用户手势；显示提交中状态，防止连点。

### 6.4 错误模型

```swift
enum LDOError: Error {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case network(URLError)
    case decoding(Error)
    case server(status: Int, message: String?)
    case cancelled
}
```

UI 层映射为可读中文文案。

---

## 7. 领域模型（核心实体）

### 7.1 建议实体

```text
User
  - id, username, name, avatarTemplate, trustLevel
  - title?, primaryGroup?

Topic
  - id, title, slug
  - categoryId, categoryName?, tags[]
  - postsCount, replyCount, views
  - lastPostedAt, createdAt, bumpedAt
  - closed, archived, pinned, visible
  - likeCount?, voteCount?, userVoted?
  - posters: [TopicPoster]
  - excerpt?
  - bookmarked?
  - unreadPosts? / lastReadPostNumber?

Post
  - id, topicId, postNumber
  - username, userId, avatarTemplate
  - createdAt, updatedAt
  - cookedHTML
  - replyToPostNumber?
  - likeCount, acceptedAnswer?
  - bookmarked?, yours?

Notification
  - id, type, read, createdAt
  - topicId?, postNumber?, fancyTitle?
  - data

LocalTag（仅本地）
  - id, name, color
  - topicIds: Set<Int>

KeywordRule（本地，可导入油猴）
  - keyword, color, enabled

AppSettings
  - appearance, density, fontSize
  - featureToggles
  - followHighlightColor
```

### 7.2 DTO 映射

- 网络层只解码 DTO（未知字段忽略）。
- Mapper 转 Domain Entity，UI 不直接依赖 JSON 键名。
- snake_case 用 convertFromSnakeCase 或显式 CodingKeys。

---

## 8. 本地存储设计

### 8.1 分层存储

| 存储 | 内容 | 说明 |
|---|---|---|
| Keychain | User API Key、client_id | 不进 UserDefaults |
| SwiftData / SQLite | 列表缓存、帖子摘要、已读进度、本地标签、关注名单缓存 | 按 username 隔离 |
| AppStorage / UserDefaults | 外观、密度、功能开关、窗口状态 | 非敏感 |
| 文件缓存目录 | 图片磁盘缓存 | 可清空 |

### 8.2 账号隔离键

```text
ownerKey = username.lowercased()
followCache:{owner}:{date}
localTags:{owner}
readState:{owner}:{topicId}
```

禁止跨账号读取关注名单、通知缓存、本地标签。

### 8.3 缓存失效

| 数据 | 策略 |
|---|---|
| latest 列表 | 下拉刷新强制失效；TTL 软失效 |
| 主题详情 | posts_count 变化或超过 TTL 则增量拉 |
| 关注名单 | **每天最多全量同步 1 次**；关注/取关本地增量改 |
| 通知 | 打开通知页刷新；可选手动 |

---

## 9. UI 信息架构（SwiftUI）

### 9.1 主结构：NavigationSplitView 三栏

```text
Sidebar          Content（列表）           Detail（阅读）
首页最新          工具条：排序/筛选         标题 + 状态徽章 + 元信息
热门             主题行（虚拟化列表）       楼层流
分类…            关键词/关注/本地标签色     TOC / 只看楼主 / 跳楼层
书签                                       底部快速回复
通知
搜索
设置
```

- 窄窗口自动折叠为双栏或单栏。
- 记忆 sidebar 选中项与 split 比例（SceneStorage / AppStorage）。

### 9.2 关键页面

#### A. 登录 / 引导

- 产品说明（非官方）
- 「连接 LINUX DO」主按钮
- 隐私说明：凭据仅本机、无第三方上传

#### B. 主题列表行

1. 标题（关键词高亮）
2. 分类色点 + 标签
3. 状态胶囊：已解决 / 置顶 / 精华 / 热门 / 关闭 / 抽奖（字段可得时）
4. 最后活动时间、回复数、浏览
5. 参与者头像叠放
6. 书签色条 / 本地标签色条 / 已读淡化

#### C. 主题详情

- 顶栏：标题、分类、标签、投票数（V1）、书签按钮
- 工具：只看楼主、跳楼层、目录、字体密度
- 楼层卡片：头像、用户名、楼层号、时间、「已关注」徽标
- 正文：见第 10 节
- 底栏：快速回复（可展开完整写作器）

#### D. 通知

- 分组：全部 / 未读
- 类型色条
- 点击跳转主题 + 楼层

#### E. 设置

1. 账号（用户信息、注销）
2. 外观（浅/深/跟随系统、强调色、密度、字号）
3. 增强功能开关
4. 关键词规则编辑
5. 网络与缓存
6. 关于：非官方声明、开源许可

### 9.3 设计系统（LDO Mac Design Tokens）

```text
颜色
  - ldoBackground / ldoSurface / ldoSurfaceElevated
  - ldoLabel / ldoLabelSecondary / ldoLabelTertiary
  - ldoSeparator
  - ldoAccent
  - ldoBookmark / ldoFollow / ldoDanger / ldoSuccess

圆角
  - sm 8 / md 12 / lg 16

密度
  - compact / regular / comfortable
```

视觉方向：延续油猴的 Apple 风格层级，使用原生 Material、系统分组与 SF Symbols。

### 9.4 无障碍

- Dynamic Type + 独立阅读字号
- VoiceOver：列表行读出标题、未读、书签状态
- 暗色下书签金、已读淡化单独校验对比度

---

## 10. 正文渲染策略（最大技术风险）

Discourse 帖子正文是服务端 **cooked HTML**。

### 10.1 分阶段

| 阶段 | 策略 | 优点 | 缺点 |
|---|---|---|---|
| MVP | WKWebView 沙箱 + 注入阅读 CSS | 兼容最快 | 与 SwiftUI 滚动联动需处理 |
| V1 | 常见节点解析为原生组件 | 性能与选中更好 | 开发量大 |
| V2 | 未知节点回退 HTML；插件白名单 | 长期可维护 | 需持续适配 |

### 10.2 MVP WKWebView 约束

1. 默认不向页面暴露不必要 JS 桥。
2. 外链点击拦截 → App 打开。
3. 图片点击 → 原生预览。
4. 注入阅读 CSS：字体、行高、代码块、引用与 App 主题一致。
5. 高度自适应：JS 测高回传，防抖避免抖动。
6. HTML 消毒：白名单去掉 script、on* 事件。

### 10.3 代码块 / 长图 / 引用

- 代码块：复制按钮
- 长图：默认限高，点击展开
- 多层引用：默认折叠过深 quote

---

## 11. 功能模块规划

### 11.1 与油猴能力对照

| 能力 | 油猴 | macOS App | 阶段 |
|---|---|---|---|
| Apple 风格 UI | CSS | 原生设计系统 | MVP |
| 书签标识 | DOM | 列表/详情书签态 | MVP/V1 |
| 关注名单同步 | 日更 + 缓存 | 同策略原生实现 | V1 |
| 关注徽标 | DOM | 列表/楼层 | V1 |
| 关注类通知样式 | DOM | 通知类型色条 | V1 |
| 关键词标题高亮 | GM 配置 | 设置页 + 列表 | V1 |
| 代码复制 | DOM | 渲染层 | MVP |
| 长图折叠 | DOM | 渲染层 | MVP |
| 引用折叠 | DOM | 渲染层 | MVP |
| 主题状态徽章 | DOM | 列表原生胶囊 | MVP |
| 已读淡化 | CSS | 列表样式 | MVP |
| 回顶/底 | DOM | 详情滚动工具 | MVP |
| 功能开关 | 面板 | 设置页 | MVP |
| 长帖目录 | 未做 | TOC | V1 |
| 只看楼主 | 未做 | 过滤 | V1 |
| 跳楼层 | 未做 | 跳转 | V1 |
| 投票展示/额度 | 方案中 | 字段可得时 | V1 |
| 本地收藏标签 | 方案中 | 本地 DB | V1 |
| 投票者名单 | 方案中 | 点击请求 | V2 |
| 用户动态/徽章卡 | 方案中 | 点击请求 | V2 |

### 11.2 Feature Toggle

```text
features.codeCopy
features.longImageCollapse
features.quoteCollapse
features.topicBadges
features.visitedFade
features.followHighlight
features.keywordHighlight
features.localTags
features.voteIndicators
features.toc
features.opOnly
```

### 11.3 配置互通（油猴 ↔ App）

```json
{
  "version": 1,
  "followedColor": "#40b883",
  "keywordsEnabled": true,
  "keywordRules": [
    { "keyword": "例", "color": "#ff375f", "enabled": true }
  ],
  "features": {
    "visitedFade": true,
    "topicBadges": true
  }
}
```

未知字段忽略，不中断导入。

---

## 12. 工程结构（建议）

建议独立 Xcode 工程（如 `linuxdo-macos`）；本仓库先放方案。若 monorepo，可新增 `macos-reader/`。

```text
LINUXDOReader/
  App/
    LINUXDOReaderApp.swift
    AppComposition.swift
  Features/
    Auth/
    HomeFeed/
    TopicDetail/
    Notifications/
    Search/
    Composer/
    Settings/
  Domain/
    Entities/
    UseCases/
    Repositories/
  Data/
    API/
    Persistence/
    Auth/
    RequestGate.swift
  DesignSystem/
    Colors.swift
    Typography.swift
    Components/
  Support/
    HTML/
    Utilities/
  Resources/
  Tests/
```

依赖方向：

```text
App → Features → Domain
Features → DesignSystem
Data → Domain（实现 Repository）
App 组装注入
```

禁止 Domain 依赖 SwiftUI。

---

## 13. 关键交互时序

### 13.1 冷启动

```text
启动 → 读 Keychain
 → 有会话：主界面先渲染磁盘缓存列表
 → 并行刷新 current user + 过期列表
 → 无会话：引导登录
```

### 13.2 打开主题

```text
点击列表行 → 骨架屏
 → /t/{id}.json → 渲染第一窗 posts
 → 近底部加载更多
 → 记录 lastReadPostNumber
```

### 13.3 回复

```text
输入 → POST 创建 post
 → 成功插入楼层并清草稿
 → 失败保留草稿并提示
```

### 13.4 关注同步（V1）

```text
每日首次需要关注数据
 → 今日未同步则全量 following.json
 → 已同步用本地 Set
 → App 内关注/取关成功后增量更新
```

---

## 14. 安全与隐私

1. 凭据仅 Keychain；日志禁止打印 Key。
2. 仅 HTTPS。
3. 默认无第三方分析 SDK。
4. 默认无自建后端，不上传用户内容。
5. HTML 消毒 + 外链拦截。
6. 遵守 ATS，不为省事全局关闭。
7. 关于页：非官方声明、许可、注销与清缓存入口。

---

## 15. 性能目标

| 指标 | 目标 |
|---|---|
| 冷启动到首屏（有缓存） | 不超过 2s |
| 列表滚动 | 60fps（常规帖量） |
| 打开主题（网络正常） | 首屏正文不超过 1.5s |
| 内存 | 显著低于 Chrome 多标签整站 |
| 图片缓存 | 上限可配（如 200MB），可清理 |

手段：列表虚拟化、头像降采样、详情分窗、WebView 离屏回收。

---

## 16. 测试策略

### 16.1 单元测试

- DTO Mapper 边界
- RequestGate：合并 in-flight、TTL、失败不重试
- Keyword 匹配（大小写不敏感）
- Follow 缓存日切
- LocalTag 增删改

### 16.2 UI 测试（抽样）

- 未登录引导
- 列表失败重试
- 设置开关影响已读淡化

### 16.3 手工验收

- 深色 / 浅色、三档密度
- 长帖 100+ 楼
- 断网、401、403、404
- 注销后 Keychain 无残留

---

## 17. 分期路线图

### 第 0 阶段：可行性验证（约 3–7 天）

1. 确认 User API Key 可用性、scopes、回调。
2. POC：site / latest / topic / notifications。
3. 确认回复写接口与鉴权头。
4. 确认投票、关注、书签字段/接口。
5. 决定最低系统版本与分发方式。

**退出标准：** 授权登录 → 拉最新列表 → 打开主题 → 读取楼层。

### 第 1 阶段：MVP 可日用（约 3–5 周）

1. 工程骨架、Design System、三栏导航。
2. 登录 / 注销 / 会话恢复。
3. 最新 / 分类 / 热门列表 + 分页。
4. 主题详情分窗 + WKWebView 正文。
5. 通知列表与跳转。
6. 搜索（防抖/回车）。
7. 回复（最小写作器）。
8. 设置：外观、缓存、功能开关骨架。
9. 状态徽章、已读淡化、回顶/底、代码复制基础。

**退出标准：** 自己可连续 3 天当主阅读器。

### 第 2 阶段：增强对齐油猴 + 阅读三件套（约 2–3 周）

1. 关注同步与徽标、通知样式。
2. 关键词规则（导入导出）。
3. 本地收藏标签。
4. TOC / 只看楼主 / 跳楼层。
5. 长图、引用折叠打磨。
6. 投票数 / 已投 / 额度（字段可得时）。
7. 书签读写完善。

### 第 3 阶段：桌面化打磨（约 2 周）

1. 菜单栏与快捷键。
2. 多窗口（可选）。
3. 系统通知（可选、默认关）。
4. Sparkle 更新（若非 App Store）。
5. 性能与 WebView 回收。
6. 无障碍；本地化先中文。

### 第 4 阶段：按需深度能力（可选）

1. 投票者名单（点击 + TTL）。
2. 用户动态 / 徽章卡片。
3. 正文更多原生组件化。
4. 多账号切换。
5. 离线稍后再读。

---


---

## 18.A API 实测记录（自动探测，2026-07-16）

> 探测环境：Windows 开发机 / 自动化沙箱网络，**非**最终用户 Mac 真机。

### 探测结果摘要

| 项目 | 结果 | 说明 |
|---|---|---|
| DNS 解析 `linux.do` | 成功 | 返回 A/AAAA 记录 |
| HTTPS 访问 `/site.json` | **失败（超时 / CF 挑战）** | 先出现 Cloudflare「Just a moment…」，后续连接超时 |
| HTTPS 访问 `/latest.json` | 未完成 | 受同一网络路径限制 |
| User API Key 授权页 | 未完成 | 需浏览器登录态 + 站点是否开启 `enable user API key requests` |
| 油猴已用接口旁证 | 部分可用（浏览器内） | 脚本已使用 `/u/{username}/follow/following.json` 且依赖 Discourse 页面模型 |

### 结论（截至本次）

1. **从当前自动化环境无法完成完整 API 可用性证明**（Cloudflare / 出站网络限制）。
2. **Discourse 标准 JSON API 在浏览器会话内通常可用**——油猴脚本与既有方案文档已确认 `site.json` 能力、主题列表过滤器、投票字段、关注 following 接口等。
3. **User API Key 是否对第三方 App 开放 = 站点管理开关**，必须在已登录浏览器中人工验证，不能仅靠匿名 curl。
4. **直接分发（非 App Store）** 已作为产品决策写入方案：使用 Developer ID 签名 + 公证（Notarization）+ Sparkle 更新更合适。

### 请你本机 5 分钟完成的关键验证（最重要）

在 **已登录 linux.do 的浏览器** 中打开：

1. `https://linux.do/site.json`  
   - 应返回 JSON；搜索是否出现与 user api 相关的设置字段（不一定暴露）。
2. `https://linux.do/latest.json`  
   - 应看到 `topic_list.topics` 数组。
3. 任意主题：`https://linux.do/t/<id>.json`  
   - 应看到 `post_stream.posts` 或等价结构。
4. 用户偏好 / 安全相关页面中是否有 **User API Keys / 用户 API 密钥** 入口；或访问：  
   `https://linux.do/user-api-key/new`（若 404/禁用，说明站点可能关闭第三方 User API）。
5. 关注接口（替换用户名）：  
   `https://linux.do/u/<你的用户名>/follow/following.json`

把这 5 项的 HTTP 状态 / 是否 JSON / 是否 403，发我即可把「能力矩阵」标成最终结论。


---

## 18.B 浏览器实测结果（2026-07-16，已完成）

> 探测方式：浏览器通道访问公开 JSON / 页面（非 curl；已绕过本机 CF 超时问题）。

### 总表

| 端点 | 结果 | 结论 |
|---|---|---|
| `GET /` | 成功，可渲染主题列表 | 站点可访问 |
| `GET /site.json` | **成功 JSON** | 公共能力配置可用 |
| `GET /latest.json` | **成功 JSON**（含 `users` + 主题列表） | 列表主路径可用 |
| `GET /hot.json` | **成功 JSON** | 热门流可用 |
| `GET /votes.json` | **成功 JSON** | 投票过滤器可用 |
| `GET /categories.json` | **成功 JSON** | 分类导航可用 |
| `GET /c/develop/4.json` | **成功 JSON** | 分类主题列表可用 |
| `GET /t/{id}.json`（样例 `2594988`） | **成功 JSON** | 主题详情 + `post_stream.posts` + `cooked` HTML 可用 |
| `GET /u/neo/follow/following.json` | **成功**，返回 `[]` | Follow 接口存在；匿名可读但可能空/受限 |
| `GET /user-api-key/new`（无参数） | JSON 错误：`param is missing ... nonce` | **User API 入口已启用**（不是 404） |
| `GET /user-api-key/new`（伪造 public_key） | 返回站点 HTML 页 | 参数校验存在；完整授权需合法 RSA + 用户登录 |
| `GET /search.json` | 本次失败/无内容 | 可能有防爬/登录门槛，需登录后再测 |
| `GET /notifications.json` | 本次失败 | 预期需登录 |
| `GET /session/current.json` | 无有效登录态内容 | 匿名未登录，符合预期 |

### `site.json` 关键发现

- **主题过滤器**含：`latest / unread / new / unseen / top / read / posted / bookmarks / hot / votes`
- **通知类型**已确认（节选）：
  - 核心：mentioned/replied/liked/private_message…
  - 插件：`bookmark_reminder(24)`、`reaction(25)`、`votes_released(26)`、`event_*`、`chat_*`、`assigned(34)`、`boost(43)`、`suggested_edit_*`
  - LINUX DO 扩展：`following(800)`、`following_created_topic(801)`、`following_replied(802)`、`circles_activity(900)`
- **自定义举报类型**存在：`1001 违规推广`、`1002 AIGC未截图`、`1003 凑字数`
- 匿名：`can_create_tag=false`，`can_tag_topics=false`（写权限需登录）

### 主题详情样例字段（`/t/2594988.json`）

已观察到：

- `post_stream.posts[]`：`id/post_number/username/cooked/created_at/avatar_template`
- 互动：`actions_summary`、`reactions`、`reaction_users_count`
- 扩展：`boosts[]`、`can_boost`、`can_accept_answer`、`accepted_answer`
- 帖级：`can_vote`（样例为 `false`）
- 正文为 **cooked HTML**（含 quote、图片 lightbox、emoji）—— 与方案「WKWebView 沙箱渲染」一致

### User API 判断

1. **站点已开放 User API 路由**（缺参数时报 `nonce` 缺失，而不是功能关闭）。
2. 完整授权流仍需：App 生成 RSA 密钥对 + `client_id/nonce/scopes/public_key/application_name` + 用户浏览器登录确认。
3. **MVP 登录主路径可以按 User API Key 继续设计**；下一步是在 Mac 上做一次真实授权 POC（拿 key 后读 `/notifications.json`、发测试回复到草稿/测试帖）。

### 对 macOS 客户端的直接含义

| 能力 | 匿名可读 | 需登录 | MVP 是否可做 |
|---|---|---|---|
| 最新/热门/分类/投票列表 | 是 | 否 | 是 |
| 主题详情与楼层正文 | 是 | 否（部分权限字段受限） | 是 |
| 通知 / 已读 / 回复 / 书签写 | 否 | 是 | 登录后做 |
| 关注名单 | 接口在 | 完整名单通常需本人 | V1 |
| 搜索 | 待复测 | 很可能要登录或限流 | 登录后再定 |

### 结论

- **公开读 API：可用，足够支撑「未登录浏览」与「已登录阅读闭环」的数据层。**
- **User API：入口开启，方向正确；完整拿 key 需真机授权 POC。**
- **写操作与私有数据：必须登录后二次验证。**
- 第 0 阶段公开读验证 **已通过**；剩余阻塞项只有「真实 User API 授权拿到 key」。


## 18. 第 0 阶段验证清单（编码前）

- [x] User API Key 入口是否启用（浏览器实测：已启用；完整授权 POC 待 Mac 真机）
- [x] `/latest.json` 匿名可读（已验证）
- [x] `/t/{id}.json` 含 `post_stream.posts` + `cooked`（已验证样例）
- [ ] `/notifications.json` 结构与类型字段
- [ ] 发帖/回复参数（topic_id、raw、reply_to_post_number 等）
- [ ] 书签列表与添加/删除接口
- [x] following 接口存在（`/u/{user}/follow/following.json` 已通）
- [ ] topic 是否带 vote_count / user_voted；current user 是否有 votes_left
- [ ] avatar_template 尺寸替换规则
- [ ] 429 与错误体格式

---

## 19. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 站点未开放 User API | 无法正规登录 | 第 0 阶段一票否决；备选仅研究 |
| 插件接口不稳 | 投票/关注缺失 | 能力矩阵标注；UI 隐藏 |
| cooked HTML 复杂 | 样式错乱、高度抖动 | MVP 沙箱 + 阅读 CSS；V1 组件化 |
| 多 WebView 内存 | 长帖卡顿 | 窗口化、离屏回收、减 WebView |
| 被误认为官方客户端 | 合规/舆论 | 关于页声明；命名避免误导 |
| API 变更 | 解析失败 | 宽容解码 + Mapper 测试 |
| App Store 审核 | 若上架 | UGC 合规、登录与内容政策 |

---

## 20. 与本仓库油猴项目的关系

| 项目 | 路径 | 职责 |
|---|---|---|
| 油猴美化脚本 | `linuxdo-beautification.user.js` | 浏览器内增强 |
| 油猴新功能方案 | `LINUXDO_新功能具体实现方案.md` | 网页端 8 项增强约束 |
| **本方案** | `LINUXDO_macOS_SwiftUI_阅读器方案.md` | macOS 原生阅读器蓝图 |

协作原则：

1. **双轨并行**：网页与桌面互补。
2. **体验对齐、实现重做**：桌面不移植 DOM 脚本。
3. **配置可互通**：关键词/开关 JSON。
4. **请求纪律同源**：可关、可观测、不骚扰站点。

---

## 21. 验收标准（汇总）

### 21.1 功能

- 登录、列表、详情、通知、搜索、回复主路径可用。
- 深浅色与三档密度可用。
- 增强功能均可开关且立即生效。

### 21.2 网络

- 默认无后台轮询。
- 同资源并发合并。
- 失败无自动重试风暴。
- 列表不为每行额外打用户卡接口。

### 21.3 安全

- Keychain 存凭据；注销可清除。
- 主路径无明文密码。
- 日志无 Key、无完整 Cookie 转储。

### 21.4 性能

- 达到第 15 节指标；长帖可完成阅读与回复。

---

## 22. 建议的立即下一步

1. **分发形态已确认**：直接分发（非 App Store），使用 Developer ID 签名 + 苹果公证 + Sparkle 更新。
2. **完成第 0 阶段 API / User API 验证**，产出能力矩阵表。
3. **建立 linuxdo-macos Xcode 工程骨架**（空壳三栏 + 假数据 UI）。
4. **登录 POC 通过后** 再进入 MVP 正式开发。

---

## 23. 附录

### 23.1 参考

- Discourse 官方 API：https://docs.discourse.org/
- Discourse User API keys 开发者文档（以官方当前文档为准）
- LINUX DO 公开站点能力：https://linux.do/site.json
- 本仓库：`README.md`、`LINUXDO_新功能具体实现方案.md`、`linuxdo-beautification.user.js`

### 23.2 名词

| 名词 | 含义 |
|---|---|
| cooked HTML | Discourse 服务端渲染后的帖子 HTML |
| User API Key | 用户授权给第三方客户端的访问密钥 |
| RequestGate | 请求合并、TTL、防重试的统一门禁 |
| NavigationSplitView | SwiftUI 多栏导航容器 |

### 23.3 文档修订

| 版本 | 日期 | 说明 |
|---|---|---|
| 0.1 | 2026-07-16 | 首版：仅 macOS + SwiftUI 详细方案 |

---

**结论：** 在 macOS 上用 SwiftUI 做 LINUX DO 阅读器，是突破油猴 UI 上限的正确路径；关键路径是 **User API 登录闭环 + JSON 主数据 + 分阶段正文渲染 + 插件化增强**。先完成第 0 阶段验证，再开工 MVP，可最大程度降低返工风险。


