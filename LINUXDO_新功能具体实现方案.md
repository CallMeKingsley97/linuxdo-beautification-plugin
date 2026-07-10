# LINUX DO 美化脚本：8 项新功能具体实现方案

## 1. 文档目标

本文档描述以下 8 项功能的具体实现方案：

1. 扩展通知特殊样式。
2. 显示主题投票数和当前用户投票状态。
3. 在个人菜单显示剩余投票额度。
4. 增加本地收藏标签。
5. 增加常用官方页面快捷入口。
6. 在编辑器中显示社区规则提醒。
7. 用户点击时查看投票者名单。
8. 用户点击时显示个人动态或徽章卡片。

本文档只定义实现方式，不代表这些功能已经进入现有脚本。

## 2. 核心约束

### 2.1 请求约束

- 不新增后台轮询。
- 不主动请求 `/latest.json`、`/search.json` 或主题 `.json`。
- 不为主题列表中的每个用户请求用户卡。
- 不自动翻页，不预加载下一页。
- 功能 1～6 只能读取页面已经加载的模型和 DOM，新增请求数必须为 0。
- 功能 7～8 只能由用户明确点击触发请求。
- 同一资源存在进行中的请求时，后续点击必须复用同一个 Promise。
- 请求成功后按 TTL 缓存；失败后禁止自动重试。
- Discourse 自身的 MessageBus `poll` 不属于脚本接口，脚本不得通过频繁
  增删、隐藏或重排大批 DOM 节点放大页面更新行为。

### 2.2 DOM 约束

- 所有增强函数必须幂等。
- 插入的节点必须使用 `ldo-` 前缀 class。
- 更新文字、`title`、`aria-*` 前必须比较新旧值。
- 不得每轮增强都删除并重新创建相同节点。
- MutationObserver 只负责发现页面新增内容，不承担定时刷新。
- 离开对应页面后，临时弹层和事件监听必须能正常清理。

### 2.3 隐私和权限

- 只使用当前登录用户本来可以访问的数据。
- 遇到 `403`、`404` 或字段缺失时降级，不尝试绕过权限。
- 个人动态缓存不跨账号共享。
- 不把用户名、通知内容或个人动态发送到第三方。

## 3. 已确认的 LINUX DO 能力

LINUX DO 的公开 `site.json` 已确认以下能力：

- 通知类型包含书签、投票、活动、聊天、指派、Boost、Suggested Edit、
  Follow 和 Circles。
- 主题列表包含 `hot`、`bookmarks`、`posted`、`votes` 等过滤器。
- 已启用 Discourse Topic Voting。
- 已启用 Discourse Follow。
- 已启用徽章、标签、聊天、活动和用户目录等核心或官方插件能力。

## 4. 统一架构设计

### 4.1 建议新增的状态

```js
const state = {
  // 已有状态省略
  favoriteTags: new Set(),
  onDemandRequests: new Map(),
  onDemandCache: new Map(),
  openedOverlay: null,
};
```

### 4.2 建议新增的存储键

```js
const FAVORITE_TAGS_KEY = "ldo-beautification-favorite-tags-v1";
const PROFILE_CARD_CACHE_KEY = "ldo-beautification-profile-card-cache-v1";
const COMPOSER_RULES_COLLAPSED_KEY = "ldo-composer-rules-collapsed";
```

收藏标签必须按当前登录账号隔离：

```json
{
  "version": 1,
  "accounts": {
    "user:example": {
      "tags": ["人工智能", "软件开发"]
    }
  }
}
```

### 4.3 统一按需请求门禁

功能 7～8 必须复用同一个请求门禁：

```js
async function requestOnDemand(cacheKey, ttlMs, requestFactory) {
  const cached = state.onDemandCache.get(cacheKey);
  if (cached && Date.now() - cached.cachedAt < ttlMs) {
    return cached.value;
  }

  const loading = state.onDemandRequests.get(cacheKey);
  if (loading) {
    return loading;
  }

  const request = requestFactory()
    .then((value) => {
      state.onDemandCache.set(cacheKey, {
        value,
        cachedAt: Date.now(),
      });
      return value;
    })
    .finally(() => {
      state.onDemandRequests.delete(cacheKey);
    });

  state.onDemandRequests.set(cacheKey, request);
  return request;
}
```

约束：

- `requestFactory` 只能在点击事件中调用。
- 不允许增强函数自动调用 `requestOnDemand`。
- 请求失败只展示错误信息，不自动重试。
- 用户再次点击”重试”才允许重新发起请求。

调用者的 UI 状态管理：

`requestOnDemand` 返回 Promise，调用者负责在调用前后管理 UI 状态：

```js
async function openVoterList(topicId, anchor) {
  const overlay = showOverlay(anchor, { state: “loading” });
  try {
    const data = await requestOnDemand(`voters:${topicId}`, 10 * 60_000, () => ...);
    overlay.update({ state: “loaded”, content: renderVoterList(extractVoters(data)) });
  } catch (error) {
    overlay.update({
      state: “error”,
      message: error.status === 403 ? “无权查看投票者名单” : “加载失败”,
      onRetry: () => {
        state.onDemandCache.delete(`voters:${topicId}`);
        openVoterList(topicId, anchor);
      },
    });
  }
}
```

三种 UI 状态：loading（加载中 spinner）、loaded（显示内容）、error（显示
错误信息和重试按钮）。

### 4.4 增强入口建议

```js
function enhancePage() {
  // 已有逻辑省略

  // 账号切换检测：清空用户隔离的内存缓存
  checkAccountSwitch();

  // 按页面类型裁剪增强范围，避免所有功能在每次 DOM 变化时全量执行
  const pageType = detectPageType(); // "topic" | "list" | "user" | "other"

  // 通知增强：仅当通知面板可见时执行
  if (isNotificationPanelVisible()) {
    enhanceExtendedNotifications();
  }

  // 主题列表相关
  if (pageType === "list") {
    enhanceVoteIndicators();
    enhanceFavoriteTags();
  }

  // 主题页相关
  if (pageType === "topic") {
    enhanceVoteIndicators();
    bindVoterListActions();
  }

  // 用户菜单相关：仅当菜单可见时执行
  if (isUserMenuVisible()) {
    enhanceVoteQuota();
    enhanceQuickLinks();
  }

  // 编辑器相关：仅当编辑器打开时执行
  if (isComposerOpen()) {
    enhanceComposerRules();
  }

  // 用户卡片/资料页相关
  if (pageType === "user" || isUserCardVisible()) {
    bindUserInsightActions();
  }
}
```

性能要求：

- `detectPageType()` 只读取 `location.pathname`，无 DOM 查询。
- `isNotificationPanelVisible()` 等守卫函数只做单次 `querySelector` 存在性检查。
- 各增强函数内部仍须保持幂等，但因为有守卫裁剪，不会在无关页面空跑。
- 避免在一次 MutationObserver 回调中运行超过 3 个增强函数。

其中只有 `bindVoterListActions` 和 `bindUserInsightActions` 注册点击事件，
注册过程本身不得发起请求。

## 5. 功能一：扩展通知特殊样式

### 5.1 功能目标

**替换**现有 `enhanceFollowNotifications()` 实现，将其统一纳入新的通知装饰
系统。新实现覆盖所有 LINUX DO 已启用的通知类型，包括现有脚本已处理的
800/801/802：

| 类型 | 含义 | 建议标签 | 验证状态 |
|---:|---|---|---|
| 24 | 书签提醒 | 书签到期提醒 | Discourse 核心，已确认 |
| 25 | 表情回应 | 收到回应 | 需确认 discourse-reactions 插件已启用 |
| 26 | 投票额度释放 | 投票已返还 | 需在 LINUX DO 实际收到后用 DevTools 确认类型码 |
| 27 | 活动提醒 | 活动提醒 | 需确认 discourse-calendar 插件已启用 |
| 28 | 活动邀请 | 活动邀请 | 同上 |
| 29 | Chat 新消息 | 聊天新消息 | Discourse Chat 核心 |
| 30 | Chat 提及 | 聊天提及 | Discourse Chat 核心 |
| 31 | Chat 邀请 | 聊天邀请 | Discourse Chat 核心 |
| 32 | Chat 个人消息 | 聊天私信 | 需确认实际类型码 |
| 33 | Chat 频道消息 | 聊天频道 | 需确认实际类型码 |
| 34 | 指派任务 | 新任务 | 需确认 discourse-assign 插件 |
| 35 | 问答评论 | 问答新评论 | 需确认 discourse-question-answer 插件 |
| 43 | Boost | Boost 动态 | 需确认 |
| 44 | Suggested Edit 创建 | 新修改建议 | 需确认 |
| 45 | Suggested Edit 接受 | 修改已接受 | 需确认 |
| 800 | 新增关注者 | 新增关注者 | 已确认（现有代码已处理） |
| 801 | 关注用户新主题 | 关注用户新主题 | 已确认（现有代码已处理） |
| 802 | 关注用户新回复 | 关注用户新回复 | 已确认（现有代码已处理） |
| 900 | Circles 活动 | Circles 动态 | 需确认 |

实现前必须通过以下步骤验证类型码：

1. 在 LINUX DO 通知面板打开 DevTools，检查通知 DOM 元素的
   `data-notification-type` 属性值。
2. 对无法触发的类型（如 Boost、Suggested Edit），检查
   `/notifications.json` 响应中 `notification_type` 字段。
3. 未验证的类型保留在配置表中但默认不启用装饰，避免误匹配。

### 5.2 迁移策略

新实现完全替代现有 `enhanceFollowNotifications()` 函数：

- 删除原有 `ldo-follow-notification-*` 系列 CSS 类。
- 新类名统一为 `ldo-notification-{category}` 格式。
- 原有 Follow 通知的色条和标签效果在新系统中保持一致，避免视觉回退。
- 迁移后旧函数标记为删除，不保留兼容层。

### 5.3 数据来源

优先级如下：

1. 通知 DOM 的 `data-notification-type` 属性（最可靠）。
2. 通知 SVG 图标的 class 或 `<use href="#icon-name">`（无类型属性时降级）。
3. 不依赖通知模型查找——Discourse 通知下拉使用 Widget/Glimmer 组件渲染，
   通知数据不一定挂在 container controller 上，跨版本兼容性差。

禁止为了判断类型调用 `/notifications.json`。

### 5.4 UI 设计

- 通知项左侧增加 3px 类型色条。
- 通知背景使用透明渐变，不改变可读性。
- 描述后增加小型类型标签。
- 未读状态仍以站点原有样式为主，不覆盖未读圆点。

建议配色：

- 书签：金色。
- 投票：紫色。
- 活动：青色。
- 聊天：蓝色。
- 指派：橙色。
- Boost：粉色。
- Suggested Edit：绿色。
- Circles：靛青色。

### 5.5 函数拆分

```js
function enhanceExtendedNotifications() {}
function resolveNotificationType(element) {}
function applyNotificationDecoration(element, definition) {}
```

类型识别不依赖通知模型查找，只通过 DOM 属性和图标识别：

```js
function resolveNotificationType(element) {
  // 优先读取 data-notification-type 属性
  const typeAttr = element.getAttribute("data-notification-type") ||
    element.closest("[data-notification-type]")?.getAttribute("data-notification-type");
  if (typeAttr) return Number(typeAttr);

  // 降级：通过 SVG 图标 class 或 use href 推断
  const icon = element.querySelector("svg use, .d-icon");
  const iconId = icon?.getAttribute("href")?.replace("#", "") ||
    icon?.className?.baseVal || "";
  return ICON_TO_TYPE_MAP.get(iconId) || null;
}
```

通知定义使用静态配置表，不在循环中创建：

```js
const NOTIFICATION_DECORATIONS = new Map([
  [24, { className: "ldo-notification-bookmark", label: "书签到期提醒" }],
  [26, { className: "ldo-notification-vote", label: "投票已返还" }],
  [900, { className: "ldo-notification-circles", label: "Circles 动态" }],
]);
```

### 5.6 边界处理

- 无法识别类型时保持原样。
- 同一通知重复增强不能重复插入标签。
- 通知下拉菜单关闭后，不保留悬空节点。
- 主题、用户或帖子不可访问时不改写链接。

### 5.7 测试

- 每个通知类型至少构造一个 DOM fixture。
- 连续执行增强函数 10 次，标签数量保持为 1。
- 打开、关闭通知菜单多次，MutationObserver 不形成循环。
- 网络面板确认新增请求数为 0。

## 6. 功能二：显示投票数和已投票状态

### 6.1 功能目标

- 在支持投票的主题列表项上显示票数。
- 当前用户已经投票时显示”已投票”（仅在数据可用时）。
- 在主题页显示该主题的票数和当前用户投票状态。
- 不替代站点原有投票按钮，只补充展示信息。

### 6.2 数据来源

官方 Topic Voting 序列化字段：

- `vote_count`：已确认在 `TopicListItemSerializer` 中序列化，主题列表可用。
- `can_vote`：可能仅在 `TopicViewSerializer` 中序列化，**主题列表不一定可用**。
- `user_voted`：可能仅在 `TopicViewSerializer` 中序列化，**主题列表不一定可用**。

数据可用性分级：

| 页面类型 | `vote_count` | `user_voted` | `can_vote` |
|---|---|---|---|
| 主题列表 | 可用 | 需验证，可能不可用 | 需验证，可能不可用 |
| 主题页 | 可用 | 可用 | 可用 |

实现前验证步骤：

1. 打开 LINUX DO 主题列表，在 DevTools 中执行
   `Discourse.__container__.lookup(“controller:discovery/topics”).model.topics[0]`
   检查返回的 topic 对象是否包含 `user_voted` 和 `can_vote` 字段。
2. 如果列表中不包含这些字段，则列表页只显示票数，不显示”已投票”状态。

读取方式：通过现有 `getDiscourseLoadedTopics()` 返回的 topic 对象调用
`readValue(topic, [“vote_count”])` 读取。主题页通过
`getDiscourseTopicController().model` 读取完整投票状态。

禁止为单个主题请求 `.json`。

### 6.3 UI 设计

主题列表：

```text
▲ 42  已投票
```

- 未投票只显示 `▲ 42`。
- 已投票使用强调色并增加”已投票”标签。
- `can_vote=false` 时不展示自定义投票信息。
- **如果 `user_voted` 字段在列表模型中不可用，列表页只显示票数，不显示
  “已投票”标签**。此时主题页仍可显示完整状态。

主题页：

- 优先美化官方投票组件。
- 官方组件不存在但模型存在时，在主题标题元数据区域插入只读徽标。
- 不创建自定义投票提交按钮，避免重复实现站点交互。

### 6.4 函数拆分

```js
function enhanceVoteIndicators() {}
function collectLoadedTopicVoteRelations() {}
function getTopicRowVoteState(row, relationMap) {}
function updateTopicVoteBadge(container, voteState) {}
function updateTopicPageVoteBadge(topicModel) {}
```

建议关系结构：

```js
{
  topicId: 123,
  canVote: true,
  voteCount: 42,
  userVoted: true,
}
```

### 6.5 边界处理

- 投票数缺失时不显示 `0`，直接不增强。
- 官方组件已经显示相同信息时，只增加 class，不插入重复徽标。
- 关闭或归档主题可能返还票数，页面模型更新后同步刷新显示。
- 列表虚拟滚动重新创建行时，徽标必须能重新绑定。

### 6.6 测试

- 可投票、不可投票、已投票、未投票四种状态。
- 投票数从 9 更新为 10 时只修改文本。
- 连续增强不重复插入徽标。
- 网络面板确认新增请求数为 0。

## 7. 功能三：个人菜单显示剩余投票额度

### 7.1 功能目标

在当前用户菜单中显示：

```text
今日/当前可用投票：3
```

如果能同时读取已用票数，则显示：

```text
投票额度：已用 7，剩余 3
```

### 7.2 数据来源

官方 Topic Voting 为 current user 序列化以下字段（通过 `CurrentUserSerializer`
扩展，在 preload 阶段注入）：

- `votes_count`
- `votes_left`
- `votes_exceeded`

只从当前用户模型读取，不调用用户接口。

访问方式：

```js
function getCurrentUserVoteQuota() {
  const pageWindow = getPageWindow();
  const currentUser = pageWindow.Discourse?.User?.current?.() ||
    pageWindow.Discourse?.__container__?.lookup?.("service:current-user");
  if (!currentUser) return null;

  const votesLeft = readValue(currentUser, ["votes_left", "votesLeft"]);
  if (votesLeft === undefined) return null;

  return {
    votesCount: toNumber(readValue(currentUser, ["votes_count", "votesCount"])) || 0,
    votesLeft: toNumber(votesLeft) || 0,
    votesExceeded: Boolean(readValue(currentUser, ["votes_exceeded", "votesExceeded"])),
  };
}
```

实时性说明：`votes_left` 在 preload 时注入，用户在当前会话中投票/取消投票后，
Discourse Topic Voting 插件会通过 Ember 模型自动更新 current user 的属性。
因此每次打开菜单时重新读取 `currentUser` 模型即可获取最新值，不需要额外的
变更监听机制。如果实测发现模型不会自动更新，则在显示区域增加"数据可能延迟"
提示文案。

### 7.3 UI 位置

优先位置：

1. 当前用户菜单中的个人信息区域。
2. 用户菜单快捷链接上方。
3. 如果主题支持投票，可在投票组件 tooltip 中补充剩余额度。

### 7.4 函数拆分

```js
function enhanceVoteQuota() {}
function getCurrentUserVoteQuota() {}
function updateVoteQuotaMenuItem(menu, quota) {}
```

### 7.5 边界处理

- 字段缺失说明站点或当前账号不可用，直接隐藏。
- `votes_exceeded=true` 时显示“剩余 0”。
- 菜单关闭后不保留浮层。
- 用户投票或取消投票后，以站点模型最新值为准。

### 7.6 测试

- 剩余票数为正数、0、字段缺失三种状态。
- 重复打开用户菜单不能重复插入。
- 网络面板确认新增请求数为 0。

## 8. 功能四：本地收藏标签

### 8.1 功能目标

- 用户可把任意标签加入本地收藏。
- 当前主题列表命中收藏标签时增加高亮或星标。
- 不隐藏、不排序、不移动主题行。
- 收藏标签按登录账号分别存储。

### 8.2 数据来源

- 当前页面已渲染的标签链接。
- topic list model 中已加载的 tags。
- 站点模型中已加载的 top tags。

禁止为了收藏标签调用 `/tags.json`。

### 8.3 交互设计

方案 A：标签旁星标按钮。

- 鼠标悬停标签时显示空心星标。
- 点击星标只修改本地收藏，不触发标签导航。
- 已收藏显示实心星标。

方案 B：设置面板管理。

- 在脚本设置中增加“收藏标签”输入区。
- 每行一个标签，支持删除和去重。

建议同时支持 A 和 B。两者之间的同步策略：

- 单一数据源：收藏标签始终存储在 `state.favoriteTags` 和 localStorage 中。
- 方案 A 的星标点击和方案 B 的面板编辑都直接修改同一数据源。
- 方案 B 保存后调用 `scheduleEnhance(0)` 触发页面重新增强，所有星标和
  徽标会基于最新数据源重新渲染。
- 方案 A 的星标点击后同样调用 `scheduleEnhance(0)`。
- 如果设置面板当前打开，面板内的标签列表不自动更新（避免用户正在编辑时
  列表突变），只在下次打开面板时重新读取。

### 8.4 高亮设计

- 主题行右侧增加 `★ 收藏标签` 小徽标。
- 标题只增加轻量背景或下划线，不覆盖关注作者高亮。
- 同时命中关注作者与收藏标签时，关注作者作为左侧色条，标签作为徽标。

### 8.5 函数拆分

```js
function loadFavoriteTags(owner) {}
function saveFavoriteTags(owner, tags) {}
function enhanceFavoriteTags() {}
function collectTopicRowTags(row, topicRelation) {}
function toggleFavoriteTag(tag) {}
function updateFavoriteTagDecoration(row, matches) {}
```

标签标准化：

```js
function normalizeTag(value) {
  return String(value || "").trim().toLowerCase();
}
```

### 8.6 边界处理

- 标签改名后按新 slug 视为新标签。
- 不收藏空字符串。
- 同一主题命中多个收藏标签时只插入一个容器。
- 未登录状态使用单独的 `anonymous` 本地空间，或直接禁用收藏。

### 8.7 测试

- 添加、删除、去重、账号切换。
- 新加载主题行自动获得高亮。
- 连续增强不重复插入星标和徽标。
- 网络面板确认新增请求数为 0。

## 9. 功能五：官方页面快捷入口

### 9.1 功能目标

增加以下快捷入口：

- Hot
- 我的书签
- 我的投票
- 关注动态

这些入口只生成普通 `<a>` 链接，不进行后台预取。

### 9.2 路由解析

优先复用页面已经存在的链接，避免硬编码：

```js
function resolveExistingRoute(selector, fallback) {
  return document.querySelector(selector)?.getAttribute("href") || fallback;
}
```

建议 fallback：

```text
Hot：/hot
我的书签：/u/{username}/activity/bookmarks
我的投票：/u/{username}/activity/votes
关注动态：/u/{username}/follow/feed
```

注意：`/topics/voted-by/{username}` 不是有效的 Discourse 路由。Topic Voting
插件注册的用户投票页面路径为 `/u/{username}/activity/votes`。实现前应在
LINUX DO 实际验证该路径是否可访问。

### 9.3 可用性判断

通过 Discourse container 获取站点过滤器列表：

```js
function getAvailableSiteFilters() {
  const site = getPageWindow().Discourse?.__container__?.lookup?.("service:site");
  const filters = site?.get?.("filters") || site?.filters;
  return Array.isArray(filters) ? filters : [];
}
```

判断规则：

- `filters` 包含 `"hot"` 时显示 Hot。
- `filters` 包含 `"votes"` 时显示我的投票。
- 能识别当前用户名时显示个人路由。
- 关注插件可用性判断：检查 `site.discourse_follow_enabled` 或
  页面中是否存在 Follow 相关导航链接。

### 9.4 UI 位置

优先放入现有用户菜单或侧边栏的独立“快捷入口”分组。

- 不修改原有菜单项顺序。
- 不复制站点已经存在的相同链接。
- 移动端只保留图标和简短文字。

### 9.5 函数拆分

```js
function enhanceQuickLinks() {}
function getAvailableSiteFilters() {}
function buildQuickLinkDefinitions(currentUsername) {}
function ensureQuickLink(container, definition) {}
```

### 9.6 边界处理

- 点击链接交由 Discourse 路由处理。
- 不监听链接后自动请求任何接口。
- 当前路由与目标相同时增加 active 状态，不重复导航。

### 9.7 测试

- 登录、未登录、插件缺失三种状态。
- 桌面端和移动端菜单。
- 点击前网络请求数为 0，点击后只有站点正常导航请求。

## 10. 功能六：编辑器社区规则提醒

### 10.1 功能目标

在新建主题或回复时显示简洁规则提醒，降低以下违规概率：

- AIGC 内容未截图。
- 违规推广。
- 通过凑字数规避最低字数要求。

提醒只做提示，不阻止提交，不自动举报。

### 10.2 数据来源

优先读取站点已加载的 `post_action_types`：

- `1001`：违规推广。
- `1002`：AIGC 未截图。
- `1003`：凑字数。

这些是 LINUX DO 的自定义举报类型。验证方式：

```js
const site = getPageWindow().Discourse?.__container__?.lookup?.(“service:site”);
const actionTypes = site?.get?.(“post_action_types”) || site?.postActionTypes || [];
// 检查是否包含 id >= 1001 的自定义类型
```

如果站点模型中不包含这些自定义类型（标准 Discourse `post_action_types` 只
到 id=12 左右），则直接使用静态文案，不依赖这些字段。

### 10.3 UI 设计

在编辑器字段区域增加可折叠提示条：

```text
发帖前检查：AIGC 请截图 · 推广请遵守规则 · 请勿凑字数
```

- 默认展开一次。
- 用户折叠后保存本地状态。
- 提供”查看社区规范”链接，指向 `/faq`。
- 使用站点返回的规则描述时只写入 `textContent`，不直接注入 HTML。

### 10.4 可选的轻量提示

只允许确定性较高的本地提示。此功能需要读取编辑器 DOM 中当前已输入的文本
（注意：这不同于调用草稿 API，见 10.6 说明）：

- 帖子包含外部推广链接且选择推广类标签时，突出推广规则。
- 文本中出现明显 AI 生成声明（如”以下由 AI 生成”）但没有图片附件时，
  突出 AIGC 截图规则。

约束：

- 不得因为关键词命中而阻止提交，也不得自动修改用户内容。
- 检测逻辑只在用户手动展开提示条时执行，不在每次输入时触发。
- 检测频率最多每 3 秒一次，避免频繁 DOM 读取影响编辑器性能。

### 10.5 函数拆分

```js
function enhanceComposerRules() {}
function getLoadedCommunityRules() {}
function getComposerContext() {}
function updateComposerRuleHints(context, rules) {}
```

### 10.6 边界处理

- 编辑器关闭后节点自动销毁。
- 多开草稿时每个编辑器只插入一次。
- 站点规则字段缺失时使用简短静态文案。
- **不调用草稿存取 API**（`/drafts.json`）。10.4 中的内容检测仅读取
  编辑器 textarea/contenteditable DOM 中的当前文本，属于纯本地 DOM 操作，
  不产生网络请求，不访问其他用户的草稿。
- 不上传或发送用户正在编辑的内容到任何外部服务。

### 10.7 测试

- 新主题、回复、编辑帖子三种编辑器模式。
- 有附件、无附件、包含链接等状态。
- 折叠状态持久化。
- 网络面板确认新增请求数为 0。

## 11. 功能七：用户点击时查看投票者名单

### 11.1 功能目标

在投票主题中增加“查看投票者”按钮。用户点击后显示投票者头像、用户名和
用户卡入口。

### 11.2 官方接口

```text
GET /voting/who.json?topic_id={topicId}
```

接口属于官方 Discourse Topic Voting 插件。

### 11.3 请求策略

- 只能点击按钮后请求。
- 同一 topicId 的并发点击合并为一次请求。
- 成功结果在当前会话缓存 10 分钟。
- 不持久化投票者名单。
- 请求失败不自动重试。
- 用户点击”重试”后才允许再次请求。

### 11.4 UI 设计

按钮可见性判断：

- 非投票主题不显示按钮。
- 尝试检查站点设置 `voting_show_who_voted`：如果该设置为 `false` 且当前
  用户不是 staff，不显示按钮（避免普通用户每次点击都收到 403）。
- 检查方式：`siteSettings.voting_show_who_voted`，通过
  `Discourse.__container__.lookup(“service:site-settings”)` 获取。
- 如果无法读取该设置（字段不存在），则默认显示按钮，由后端权限控制最终
  是否返回数据。

按钮和弹层：

- 在官方投票区域旁增加”查看投票者”按钮。
- 使用轻量 popover；人数较多时使用可滚动弹层。
- 每位用户显示头像、用户名和用户卡触发属性。
- 不自动加载用户详情。
- 加载中状态显示 spinner 或”加载中…”文字，避免用户以为点击无效。

### 11.5 响应兼容

官方插件版本可能返回 `users`、`voters` 或嵌套结构，实现时需统一解析：

```js
function extractVoters(payload) {
  const users = payload?.users || payload?.voters || payload || [];
  return Array.isArray(users) ? users : [];
}
```

### 11.6 函数拆分

```js
function bindVoterListActions() {}
function openVoterList(topicId, anchor) {}
function loadVoters(topicId) {}
function extractVoters(payload) {}
function renderVoterList(users) {}
```

统一工具函数（在 4.3 节 `requestOnDemand` 同级定义）：

```js
function assertOk(response) {
  if (!response.ok) {
    const error = new Error(`HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return response;
}
```

请求必须通过统一门禁：

```js
requestOnDemand(`voters:${topicId}`, 10 * 60_000, () =>
  fetch(`/voting/who.json?topic_id=${encodeURIComponent(topicId)}`, {
    credentials: “include”,
    headers: {
      Accept: “application/json”,
      “X-Requested-With”: “XMLHttpRequest”,
    },
  }).then(assertOk).then((response) => response.json())
);
```

### 11.7 边界处理

- 非投票主题不显示入口。
- 没有查看权限时（403），显示友好提示”无权查看投票者名单”，不绕过权限。
- 空名单显示”暂无投票者”。
- 弹层关闭后取消未完成的渲染，但不强制中止已发送请求。
- 请求失败后弹层内显示”加载失败”和”重试”按钮。

### 11.8 测试

- 连续点击 10 次只产生 1 个请求。
- 10 分钟缓存期内重新打开不请求。
- 缓存过期后用户再次点击才请求。
- 403、404、500 和空响应。
- 网络面板确认没有后台预请求。

## 12. 功能八：个人动态或徽章卡片

### 12.1 功能目标

在用户卡或用户资料页增加“更多信息”入口，打开包含两个懒加载标签页的弹层：

- 最近动态
- 徽章

打开弹层时默认不同时加载两类数据，只加载用户选择的标签页。

### 12.2 官方接口

最近动态：

```text
GET /user_actions.json?username={username}&limit=20&offset=0
```

用户徽章：

```text
GET /user-badges/{username}.json
```

### 12.3 请求策略

最近动态：

- 点击“最近动态”后请求。
- 同一用户缓存 10 分钟。
- 加载更多必须显式点击，使用 `offset += 20`。
- 不自动翻页。

徽章：

- 点击“徽章”后请求。
- 优先使用用户卡已经加载的 featured badges。
- 完整徽章结果可缓存 24 小时。
- 只缓存必要字段：badge id、名称、图标、授予时间和次数。

### 12.4 UI 设计

最近动态项显示：

- 动作类型。
- 主题标题。
- 摘要。
- 时间。
- 原始链接。

徽章项显示：

- 徽章图标。
- 名称和描述。
- 获得次数。
- 获得时间。

### 12.5 函数拆分

```js
function bindUserInsightActions() {}
function openUserInsightCard(username) {}
function activateUserInsightTab(tabName) {}
function loadUserActions(username, offset = 0) {}
function loadUserBadges(username) {}
function renderUserActions(payload) {}
function renderUserBadges(payload) {}
```

缓存 key：

```text
activity:{currentOwner}:{targetUsername}:{offset}
badges:{currentOwner}:{targetUsername}
```

### 12.6 权限和安全

- 用户资料不可见时不显示内容。
- 私信和私密主题必须完全遵守接口返回，不从 DOM 猜测。
- 响应文本使用 `textContent` 渲染。
- 不缓存 403、404 或错误响应。
- 退出账号或切换账号时清空内存缓存。

账号切换检测机制：

```js
function checkAccountSwitch() {
  const currentUsername = getCurrentUsername();
  if (!currentUsername) {
    // 未登录，清空所有按需缓存
    if (state.onDemandCache.size > 0) {
      state.onDemandCache.clear();
    }
    return;
  }
  if (state.followedUsersOwner && state.followedUsersOwner !== currentUsername) {
    // 账号已切换，清空包含用户隔离数据的缓存
    state.onDemandCache.clear();
  }
}
```

在 `enhancePage()` 入口处调用 `checkAccountSwitch()`，利用现有的
`state.followedUsersOwner` 与当前用户名比较即可检测切换。

### 12.7 弹层管理

弹层与 Discourse 自身 modal/popover 的冲突处理：

- 弹层使用固定 `z-index: 1050`（高于 Discourse 的 user-card z-index 1000，
  但低于 Discourse modal 的 z-index 1100）。
- 监听 Discourse 路由变更（已有的 `patchHistory` 机制），路由变更时自动
  关闭弹层并调用 `state.openedOverlay = null`。
- 如果 Discourse modal 打开（检测 `.modal-backdrop` 或 `.d-modal` 存在），
  自动关闭自定义弹层，避免重叠。
- 弹层关闭时清理所有事件监听（ESC 键、backdrop 点击、路由变更）。

### 12.8 测试

- 只打开弹层不产生请求。
- 点击一个标签页只请求该标签页。
- 快速切换标签页不会重复请求。
- 活动分页只在点击”加载更多”后发生。
- 徽章缓存 TTL 正常。
- 账号切换后缓存隔离。

## 13. 请求预算总表

| 功能 | 自动请求 | 用户点击请求 | 缓存 |
|---|---:|---:|---|
| 扩展通知样式 | 0 | 0 | 不需要 |
| 投票状态展示 | 0 | 0 | 不需要 |
| 剩余投票额度 | 0 | 0 | 不需要 |
| 收藏标签 | 0 | 0 | 本地永久保存 |
| 快捷入口 | 0 | 正常页面导航 | 浏览器/站点负责 |
| 编辑器规则提醒 | 0 | 0 | 本地折叠状态 |
| 投票者名单 | 0 | 每主题点击时 1 次 | 会话 10 分钟 |
| 个人动态 | 0 | 每用户点击时 1 次 | 10 分钟 |
| 用户徽章 | 0 | 每用户点击时 1 次 | 24 小时 |

现有的每日关注名单同步仍保持每天最多 1 次，不因上述功能增加频率。

## 14. 建议开发顺序

### 第零阶段：前置验证

在编码前完成以下验证（均可通过 DevTools 在 LINUX DO 站点上完成）：

1. 确认主题列表模型中是否包含 `user_voted` 和 `can_vote` 字段（决定功能 2
   在列表页的能力边界）。
2. 确认 `CurrentUserSerializer` 中 `votes_left` 是否全局可用，以及投票后
   模型是否自动更新。
3. 确认通知 DOM 是否统一带有 `data-notification-type` 属性（决定功能 1 的
   主要识别策略）。
4. 确认 `post_action_types` 中是否存在 id >= 1001 的自定义类型（决定功能 6
   是否使用动态文案）。
5. 确认 `/u/{username}/activity/votes` 路由是否可访问（功能 5 的 fallback）。
6. 确认 `siteSettings.voting_show_who_voted` 是否可从前端读取（功能 7 的
   按钮可见性判断）。

### 第一阶段：纯本地增强

1. 扩展通知特殊样式。
2. 投票数和已投票状态。
3. 剩余投票额度。
4. 收藏标签。
5. 快捷入口。
6. 编辑器规则提醒。

第一阶段完成后，网络新增请求数应为 0。

### 第二阶段：按需接口

7. 投票者名单。
8. 个人动态和徽章卡片。

第二阶段必须先完成统一请求门禁和缓存测试，再接入 UI。

## 15. 验收标准

### 15.1 功能验收

- 8 项功能均有明确入口和关闭/清理方式。
- 所有增强在 SPA 路由切换后正常工作。
- 桌面端和移动端不遮挡站点原生按钮。
- 深色和浅色主题均可读。

### 15.2 性能验收

- 空闲 5 分钟不新增脚本接口请求。
- MutationObserver 回调不会形成持续循环。
- 连续执行增强函数 20 次，插入节点数量保持稳定。
- 主题列表滚动和打开通知菜单无明显卡顿。

### 15.3 网络验收

- 功能 1～6 的测试过程中新增请求数为 0。
- 功能 7 连续点击只产生 1 个请求。
- 功能 8 未点击标签页时请求数为 0。
- 所有失败请求均无自动重试。
- 脚本不主动调用 MessageBus `poll`。

## 16. 官方参考

- LINUX DO 公开站点能力：<https://linux.do/site.json>
- Discourse API：<https://docs.discourse.org/>
- Discourse Topic Voting：
  <https://github.com/discourse/discourse-topic-voting>
- Discourse Follow：<https://github.com/discourse/discourse-follow>
- Discourse Notifications：
  <https://github.com/discourse/discourse/blob/main/spec/requests/api/notifications_spec.rb>
- Discourse User Actions：
  <https://github.com/discourse/discourse/blob/main/app/controllers/user_actions_controller.rb>
- Discourse Badges：
  <https://github.com/discourse/discourse/blob/main/app/controllers/badges_controller.rb>

