# 项目协作规范

本文件仅约束当前仓库。修改仓库内容时，应保留用户已有改动，避免无关重写；涉及 macOS App UI 的工作必须遵守下述规范。

## macos-reader UI 设计标准（强制）

### 设计目标

- 以 Apple Human Interface Guidelines 和 macOS 系统应用为视觉基线，优先呈现 SwiftUI、AppKit 与 SF Symbols 的原生质感。
- 界面应像为 Mac 专门设计的桌面应用，而不是网页套壳、iOS 放大版或卡片式 Dashboard。
- 信息层级、阅读舒适度和操作可发现性优先于装饰；克制使用强调色、阴影、圆角和材质。

### 结构与层级

- 主导航保持 `NavigationSplitView` 三栏结构：系统材质侧栏、主题列表、连续阅读详情。
- 侧栏使用 `.sidebar` 列表样式和系统选中态，不自行绘制导航按钮背景。
- 主题列表遵循 Mail / News 风格：平面列表、清晰分隔线、原生整行选中态；禁止斑马纹和逐行大卡片。
- 主题详情采用连续文档/会话流，楼层之间使用留白和分隔线；禁止每个楼层都套独立大圆角卡片。
- 常用操作放在系统工具栏；状态与分页使用轻量状态栏。避免在桌面端使用贯穿整栏的 iOS 式大按钮。

### 视觉语言

- 基础颜色必须优先使用系统语义色：`primary`、`secondary`、`tint`、`windowBackgroundColor`、`textBackgroundColor`、`separatorColor`。
- 浅色与深色模式必须自动适配。除站点分类色、品牌色和语义状态色外，不硬编码界面 RGB 颜色。
- 字体只使用系统字体与系统文本样式；正文默认遵循 SF Pro Text，代码使用系统等宽字体。
- 使用统一间距节奏：4 / 8 / 12 / 16 / 24。阅读正文最大宽度以 `LDOTheme.readerMaxWidth` 为准。
- 圆角只用于输入框、标签、状态徽章和确有容器语义的控件；常规使用 8 或 12，禁止随意新增不同半径。
- 阴影仅用于需要表达层级的浮层或 App 标记，且必须轻微；普通列表和正文不使用投影。

### 组件与代码约束

- 新 UI 必须先复用 `macos-reader/LINUXDOReader/Views/Components/DesignSystem.swift` 中的 `LDOTheme`、`LDOAppMark`、`LDOTag`、`LDOStatusBadge`、`LDOMetric`。
- 新的共享视觉常量或组件应加入 `DesignSystem.swift`，禁止在多个 View 中复制颜色、间距、圆角和标签实现。
- 优先使用原生 `List`、`Form`、`Toolbar`、`ContentUnavailableView`、`ProgressView`、`Button` 和系统材质，不引入第三方 UI 框架。
- SF Symbols 应表达真实语义；图标按钮必须提供 `.help` 或可访问性标签。
- Hover、键盘快捷键、焦点状态和窗口缩放属于 macOS 基本体验，新增交互时应一并考虑。
- WKWebView 正文样式也要匹配系统字体、动态明暗配色和统一阅读宽度，不得恢复网页默认的强边框/重卡片视觉。

### 可访问性与验证

- 不得只依赖颜色表达状态；状态需要文字或图标辅助。
- 文本应支持系统字体缩放，布局不能依赖固定文本高度。
- UI 改动后至少验证默认窗口尺寸与最小窗口尺寸；检查浅色、深色模式和主要 Hover/选中状态。
- 必须运行：

```bash
xcodebuild -project macos-reader/LINUXDOReader.xcodeproj \
  -scheme LINUXDOReader \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build
```

### UI 评审清单

- 是否优先使用系统控件和语义色？
- 是否减少了视觉噪声，而非增加装饰？
- 是否仍存在网页式卡片堆叠、斑马纹或全宽移动端按钮？
- 三栏信息层级、标题、正文、辅助信息是否一眼可辨？
- 浅色/深色、选中、Hover、加载、错误、空状态是否都自然？
- 新样式是否已收敛进 `DesignSystem.swift`，而不是散落魔法数字？
