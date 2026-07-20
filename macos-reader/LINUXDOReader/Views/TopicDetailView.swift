//
//  TopicDetailView.swift
//

import SwiftUI

struct TopicDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: TopicDetailViewModel
    let topicID: Int?
    let targetPostNumber: Int?
    @ObservedObject var highlightStore: HighlightStore
    @State private var replyContext: ReplyContext?
    @State private var actionPresentation: PostActionPresentation?
    @State private var destructiveAction: PostDestructiveAction?

    var body: some View {
        Group {
            if topicID == nil {
                emptySelection
            } else {
                switch viewModel.phase {
                case .idle where viewModel.detail == nil,
                     .loading where viewModel.detail == nil:
                    LoadingPane(message: "正在加载主题…")
                case .failed(let message) where viewModel.detail == nil:
                    failurePane(message: message)
                case .loaded, .idle, .loading, .failed:
                    if let detail = viewModel.detail {
                        detailScroll(detail)
                    } else {
                        LoadingPane(message: "正在加载主题…")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $replyContext) { context in
            ReplyComposerView(
                viewModel: viewModel,
                context: context
            )
        }
        .sheet(item: $actionPresentation) { presentation in
            switch presentation {
            case .reactions(let postID):
                ReactionPickerView(viewModel: viewModel, postID: postID)
            case .bookmark(let postID):
                BookmarkEditorView(viewModel: viewModel, postID: postID)
            case .report(let postID):
                FlagPostView(viewModel: viewModel, postID: postID)
            case .boost(let postID):
                BoostComposerView(viewModel: viewModel, postID: postID)
            case .edit(let postID, let raw):
                EditPostView(viewModel: viewModel, postID: postID, initialRaw: raw)
            }
        }
        .alert(item: $destructiveAction) { action in
            Alert(
                title: Text("删除这条帖子？"),
                message: Text("删除后内容将从主题中隐藏；如果站点允许，之后仍可恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    Task { _ = await viewModel.deletePost(postID: action.postID) }
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear { updateReadingSession() }
        .onDisappear { viewModel.stopReading() }
        .onChange(of: scenePhase) { _, _ in
            updateReadingSession()
        }
        .onChange(of: topicID) { _, newTopicID in
            if newTopicID == nil {
                viewModel.stopReading()
            } else {
                updateReadingSession()
            }
        }
        .onReceive(appState.siteSession.$currentUser) { _ in
            updateReadingSession()
        }
    }

    private var emptySelection: some View {
        ContentUnavailableView {
            Label("选择一个主题", systemImage: "sidebar.right")
        } description: {
            Text("主题正文会在这里以原生阅读视图显示。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LDOTheme.contentBackground)
    }

    private func failurePane(message: String) -> some View {
        ContentUnavailableView {
            Label("主题加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { viewModel.reload() }
            if let topicID {
                Button(appState.siteSession.isLoggedIn ? "打开登录与验证" : "登录后重试") {
                    if appState.siteSession.isLoggedIn {
                        appState.openTopicInSite(id: topicID)
                    } else {
                        appState.openLogin()
                    }
                }
            }
        }
    }

    private func detailScroll(_ detail: TopicDetail) -> some View {
        VStack(spacing: 0) {
            if case .failed(let message) = viewModel.phase {
                HStack(spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Spacer()
                    Button("重试") { viewModel.reload() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
            }

            if let actionMessage = viewModel.actionMessage {
                HStack(spacing: 8) {
                    Label(actionMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.clearActionMessage()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("关闭提示")
                }
                .padding(.horizontal, 24)
                .frame(minHeight: 34)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }

            TopicDocumentWebView(
                detail: detail,
                followedUsernames: highlightStore.followedUsernames,
                followedHighlightEnabled: highlightStore.followedHighlightEnabled,
                followedColorHex: highlightStore.followedColorHex,
                readPostNumbers: viewModel.readPostNumbers,
                reportingPostNumbers: viewModel.reportingPostNumbers,
                runningPostActions: viewModel.runningPostActions,
                isLoggedIn: appState.siteSession.isLoggedIn,
                targetPostNumber: targetPostNumber,
                onOpenTopic: { appState.selectTopic(id: $0) },
                onOpenUser: { post in
                    appState.openUserProfile(
                        username: post.username,
                        displayName: post.name,
                        avatarTemplate: post.avatarTemplate
                    )
                },
                onReply: { beginReply(to: $0.postNumber) },
                onPostAction: handlePostAction,
                onVisiblePostsChanged: viewModel.updateVisiblePostNumbers
            )
        }
        .background(LDOTheme.contentBackground)
        .task(id: targetLoadID(detail: detail)) {
            guard let targetPostNumber else { return }
            await viewModel.loadTargetPostIfNeeded(postNumber: targetPostNumber)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.canLoadMore || viewModel.isLoadingMore {
                pagingBar(detail)
            }
        }
        .navigationTitle(detail.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.reload()
                } label: {
                    if case .loading = viewModel.phase {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }

                Button {
                    appState.openTopicInSite(id: detail.id, slug: detail.slug)
                } label: {
                    Label("兼容网页", systemImage: "globe")
                }
                .help("仅在原生内容异常时使用站内网页")

                Button {
                    if appState.siteSession.isLoggedIn {
                        beginReply(to: nil)
                    } else {
                        appState.openLogin()
                    }
                } label: {
                    Label(appState.siteSession.isLoggedIn ? "回复" : "登录", systemImage: "square.and.pencil")
                }
                .help(appState.siteSession.isLoggedIn ? "在 App 内回复此主题" : "登录后回复和访问受限主题")
            }
        }
    }

    private func pagingBar(_ detail: TopicDetail) -> some View {
        HStack(spacing: 12) {
            Text("已显示 \(detail.posts.count.formatted()) / \(detail.postsCount.formatted()) 层")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button(action: viewModel.loadMore) {
                HStack(spacing: 6) {
                    if viewModel.isLoadingMore {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.isLoadingMore ? "正在加载…" : "加载更多")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoadingMore)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func beginReply(to postNumber: Int?) {
        guard appState.siteSession.isLoggedIn else {
            appState.openLogin()
            return
        }
        viewModel.clearReplyMessage()
        replyContext = ReplyContext(postNumber: postNumber)
    }

    private func handlePostAction(_ post: PostItem, action: PostMenuAction) {
        switch action {
        case .like:
            guard requireLogin() else { return }
            Task { _ = await viewModel.toggleLike(postID: post.id) }
        case .reactions:
            guard requireLogin() else { return }
            actionPresentation = .reactions(postID: post.id)
        case .bookmark:
            guard requireLogin() else { return }
            actionPresentation = .bookmark(postID: post.id)
        case .report:
            guard requireLogin() else { return }
            actionPresentation = .report(postID: post.id)
        case .boost:
            guard requireLogin() else { return }
            actionPresentation = .boost(postID: post.id)
        case .edit:
            guard requireLogin() else { return }
            Task {
                if let raw = await viewModel.editableRaw(postID: post.id) {
                    actionPresentation = .edit(postID: post.id, raw: raw)
                }
            }
        case .delete:
            guard requireLogin() else { return }
            destructiveAction = PostDestructiveAction(postID: post.id)
        case .recover:
            guard requireLogin() else { return }
            Task { _ = await viewModel.recoverPost(postID: post.id) }
        case .wiki:
            guard requireLogin() else { return }
            Task { _ = await viewModel.toggleWiki(postID: post.id) }
        case .solution:
            guard requireLogin() else { return }
            Task { _ = await viewModel.toggleAcceptedAnswer(postID: post.id) }
        case .sharedIssue:
            guard requireLogin() else { return }
            Task { _ = await viewModel.toggleSharedIssue() }
        case .reply:
            beginReply(to: post.postNumber)
        case .copyLink, .share, .more:
            break
        }
    }

    private func requireLogin() -> Bool {
        guard appState.siteSession.isLoggedIn else {
            appState.openLogin()
            return false
        }
        return true
    }

    private func updateReadingSession() {
        viewModel.updateReadingSession(
            isLoggedIn: appState.siteSession.isLoggedIn,
            isFocused: scenePhase == .active
        )
    }

    private func targetLoadID(detail: TopicDetail) -> String {
        "\(detail.id):\(targetPostNumber ?? 0)"
    }

}

private struct ReplyContext: Identifiable {
    let id = UUID()
    let postNumber: Int?
}

private enum PostActionPresentation: Identifiable {
    case reactions(postID: Int)
    case bookmark(postID: Int)
    case report(postID: Int)
    case boost(postID: Int)
    case edit(postID: Int, raw: String)

    var id: String {
        switch self {
        case .reactions(let postID): return "reactions-\(postID)"
        case .bookmark(let postID): return "bookmark-\(postID)"
        case .report(let postID): return "report-\(postID)"
        case .boost(let postID): return "boost-\(postID)"
        case .edit(let postID, _): return "edit-\(postID)"
        }
    }
}

private struct PostDestructiveAction: Identifiable {
    let postID: Int
    var id: Int { postID }
}

private struct ReactionPickerView: View {
    private struct Option: Identifiable {
        let id: String
        let emoji: String
        let title: String
    }

    private static let options = [
        Option(id: "heart", emoji: "♥", title: "喜欢"),
        Option(id: "+1", emoji: "👍", title: "赞同"),
        Option(id: "laughing", emoji: "😆", title: "好笑"),
        Option(id: "open_mouth", emoji: "😮", title: "惊讶"),
        Option(id: "clap", emoji: "👏", title: "鼓掌"),
        Option(id: "confetti_ball", emoji: "🎉", title: "庆祝"),
        Option(id: "hugs", emoji: "🤗", title: "拥抱"),
        Option(id: "distorted_face", emoji: "🫠", title: "融化"),
        Option(id: "tieba_087", emoji: "😭", title: "泪目"),
        Option(id: "bili_057", emoji: "✨", title: "闪亮"),
    ]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TopicDetailViewModel
    let postID: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("选择回应")
                    .font(.headline)
                Text("再次选择当前回应会取消；每个账号在同一楼层保留一个回应。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(Self.options) { option in
                    Button {
                        Task {
                            if await viewModel.toggleReaction(
                                postID: postID,
                                reaction: option.id
                            ) {
                                dismiss()
                            }
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(option.emoji)
                                .font(.system(size: 24))
                            HStack(spacing: 3) {
                                Text(option.title)
                                if currentReaction == option.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(
                            currentReaction == option.id
                                ? Color.accentColor.opacity(0.12)
                                : LDOTheme.subtleFill,
                            in: RoundedRectangle(
                                cornerRadius: LDOTheme.compactCornerRadius,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRunning(postID: postID, action: .reaction))
                    .help(option.title)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(LDOTheme.windowBackground)
    }

    private var currentReaction: String? {
        viewModel.post(id: postID)?.currentUserReaction
    }
}

private struct BookmarkEditorView: View {
    private enum ReminderChoice: String, CaseIterable, Identifiable {
        case none
        case twoHours
        case tomorrow
        case threeDays
        case custom

        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "不提醒"
            case .twoHours: return "2 小时后"
            case .tomorrow: return "明天上午"
            case .threeDays: return "3 天后"
            case .custom: return "自定义时间"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TopicDetailViewModel
    let postID: Int
    @State private var name: String
    @State private var reminderChoice: ReminderChoice
    @State private var customDate: Date
    @State private var autoDeletePreference: BookmarkAutoDeletePreference

    init(viewModel: TopicDetailViewModel, postID: Int) {
        self.viewModel = viewModel
        self.postID = postID
        let post = viewModel.post(id: postID)
        _name = State(initialValue: post?.bookmarkName ?? "")
        _reminderChoice = State(
            initialValue: post?.bookmarkReminderAt == nil ? .none : .custom
        )
        _customDate = State(
            initialValue: post?.bookmarkReminderAt ?? Date().addingTimeInterval(2 * 60 * 60)
        )
        _autoDeletePreference = State(
            initialValue: post?.bookmarkAutoDeletePreference ?? .clearReminder
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(isBookmarked ? "编辑收藏" : "收藏楼层", systemImage: "bookmark")
                    .font(.headline)
                Text("可以只收藏，也可以让系统在指定时间提醒你回来阅读。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("名称（可选）", text: $name)

                Picker("提醒", selection: $reminderChoice) {
                    ForEach(ReminderChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }

                if reminderChoice == .custom {
                    DatePicker(
                        "提醒时间",
                        selection: $customDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Picker("自动删除", selection: $autoDeletePreference) {
                    ForEach(BookmarkAutoDeletePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if isBookmarked {
                    Button("取消收藏", role: .destructive) {
                        Task {
                            if await viewModel.removeBookmark(postID: postID) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    Task {
                        if await viewModel.saveBookmark(
                            postID: postID,
                            name: name,
                            reminderAt: reminderDate,
                            autoDeletePreference: autoDeletePreference
                        ) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 540, height: 430)
        .background(LDOTheme.windowBackground)
    }

    private var post: PostItem? { viewModel.post(id: postID) }
    private var isBookmarked: Bool { post?.bookmarked == true }
    private var isSaving: Bool { viewModel.isRunning(postID: postID, action: .bookmark) }

    private var reminderDate: Date? {
        switch reminderChoice {
        case .none:
            return nil
        case .twoHours:
            return Date().addingTimeInterval(2 * 60 * 60)
        case .tomorrow:
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        case .threeDays:
            return Calendar.current.date(byAdding: .day, value: 3, to: Date())
        case .custom:
            return customDate
        }
    }
}

private struct FlagPostView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TopicDetailViewModel
    let postID: Int
    @State private var selectedTypeID: Int?
    @State private var message = ""
    @State private var confirmsIllegalContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("举报或联系作者", systemImage: "flag")
                    .font(.headline)
                Text("请选择最准确的原因。举报会进入站点审核流程，不会在 App 内公开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isLoadingFlagTypes && availableTypes.isEmpty {
                ProgressView("正在读取站点举报类型…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableTypes.isEmpty {
                ContentUnavailableView(
                    "当前无法举报",
                    systemImage: "flag.slash",
                    description: Text("该楼层可能已举报，或当前账号没有相应权限。")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(availableTypes) { type in
                            Button {
                                selectedTypeID = type.id
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selectedTypeID == type.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(selectedTypeID == type.id ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayName(for: type))
                                            .foregroundStyle(.primary)
                                        Text(description(for: type))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 230)

                if selectedType?.requiresMessage == true {
                    TextEditor(text: $message)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 86)
                        .background(LDOTheme.contentBackground)
                        .clipShape(RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius)
                                .strokeBorder(LDOTheme.separator)
                        }
                    Text("请输入 10–500 个字符。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if selectedType?.isIllegal == true {
                    Toggle("我确认该内容可能违反适用法律，并愿意提供必要说明", isOn: $confirmsIllegalContent)
                        .font(.caption)
                }
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(selectedType?.isNotifyUser == true ? "发送消息" : "提交举报") {
                    guard let selectedType else { return }
                    Task {
                        if await viewModel.flagPost(
                            postID: postID,
                            type: selectedType,
                            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
                        ) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || viewModel.isRunning(postID: postID, action: .report))
            }
        }
        .padding(24)
        .frame(width: 570, height: 560)
        .background(LDOTheme.windowBackground)
        .task {
            await viewModel.loadFlagTypesIfNeeded()
            selectFirstTypeIfNeeded()
        }
        .onChange(of: viewModel.flagTypes) { _, _ in
            selectFirstTypeIfNeeded()
        }
    }

    private var availableTypes: [PostFlagType] {
        guard let post = viewModel.post(id: postID) else { return [] }
        return viewModel.availableFlagTypes(for: post)
    }

    private var selectedType: PostFlagType? {
        availableTypes.first { $0.id == selectedTypeID }
    }

    private var canSubmit: Bool {
        guard let selectedType else { return false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedType.requiresMessage && !(10...500).contains(trimmed.count) {
            return false
        }
        if selectedType.isIllegal && !confirmsIllegalContent {
            return false
        }
        return true
    }

    private func selectFirstTypeIfNeeded() {
        if selectedTypeID == nil || !availableTypes.contains(where: { $0.id == selectedTypeID }) {
            selectedTypeID = availableTypes.first?.id
        }
    }

    private func displayName(for type: PostFlagType) -> String {
        let username = viewModel.post(id: postID)?.username ?? "作者"
        return type.name.replacingOccurrences(of: "%{username}", with: username)
    }

    private func description(for type: PostFlagType) -> String {
        switch type.nameKey {
        case "notify_user": return "私下提醒作者修改内容，不进入版主举报队列。"
        case "off_topic": return "内容与当前主题无关，影响讨论连贯性。"
        case "inappropriate": return "内容冒犯、不文明或不适合公开讨论。"
        case "spam": return "广告、重复灌水或明显的垃圾内容。"
        case "illegal": return "内容可能违反法律，需要附加说明。"
        case "notify_moderators": return "其他需要版主处理的问题，请填写说明。"
        default: return type.requiresMessage ? "请填写说明后提交。" : "提交给站点审核团队处理。"
        }
    }
}

private struct BoostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TopicDetailViewModel
    let postID: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("发送 Boost", systemImage: "rocket")
                    .font(.headline)
                Text("用一句不超过 16 个字符的短消息为这层内容助力。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("发一个 Boost…", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: text) { _, newValue in
                    if newValue.count > 16 {
                        text = String(newValue.prefix(16))
                    }
                }
            HStack {
                Text("\(text.count) / 16")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("发送") {
                    Task {
                        if await viewModel.createBoost(postID: postID, raw: text) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(LDOTheme.windowBackground)
        .onAppear { focused = true }
    }

    private var isSending: Bool {
        viewModel.isRunning(postID: postID, action: .boost)
    }
}

private struct EditPostView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TopicDetailViewModel
    let postID: Int
    @State private var raw: String
    @State private var reason = ""
    @FocusState private var focused: Bool

    init(viewModel: TopicDetailViewModel, postID: Int, initialRaw: String) {
        self.viewModel = viewModel
        self.postID = postID
        _raw = State(initialValue: initialRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("编辑帖子", systemImage: "pencil")
                    .font(.headline)
                Text("保存后由 LINUX DO 重新渲染正文，修订记录仍由站点保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $raw)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .focused($focused)
                .background(LDOTheme.contentBackground)
                .clipShape(RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius)
                        .strokeBorder(LDOTheme.separator)
                }

            TextField("编辑原因（可选）", text: $reason)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存修改") {
                    Task {
                        if await viewModel.editPost(
                            postID: postID,
                            raw: raw,
                            reason: reason
                        ) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 680, height: 540)
        .background(LDOTheme.windowBackground)
        .onAppear { focused = true }
    }

    private var isSaving: Bool {
        viewModel.isRunning(postID: postID, action: .edit)
    }
}

private struct ReplyComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TopicDetailViewModel
    let context: ReplyContext
    @State private var text = ""
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.postNumber.map { "回复 #\($0)" } ?? "回复主题")
                        .font(.headline)
                    Text("回复将使用当前 LINUX DO 账号发布")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("写下你的回复…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($isTextFocused)
            }
            .background(LDOTheme.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LDOTheme.compactCornerRadius, style: .continuous)
                    .strokeBorder(LDOTheme.separator)
            }

            if let message = viewModel.replyMessage {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        if await viewModel.submitReply(
                            raw: text,
                            replyToPostNumber: context.postNumber
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSubmittingReply {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("发送回复")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingReply)
            }
        }
        .padding(24)
        .frame(width: 600, height: 410)
        .background(LDOTheme.windowBackground)
        .onAppear { isTextFocused = true }
    }
}
