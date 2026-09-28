//
//  TopicDetailViewModel.swift
//

import Foundation

@MainActor
final class TopicDetailViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail: TopicDetail?
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isSubmittingReply = false
    @Published private(set) var replyMessage: String?
    @Published private(set) var readPostNumbers: Set<Int> = []
    @Published private(set) var reportingPostNumbers: Set<Int> = []
    @Published private(set) var runningPostActions: [Int: Set<PostActionKind>] = [:]
    @Published private(set) var flagTypes: [PostFlagType] = []
    @Published private(set) var isLoadingFlagTypes = false
    @Published private(set) var actionMessage: String?

    private let api: APIClient
    private let readingTracker = ReadingTracker()
    private var topicID: Int?
    private var loadTask: Task<Void, Never>?
    private var trackingTopicID: Int?
    private var isLoggedIn = false
    private var reportRemotely = false
    private var readingFocused = true

    init(api: APIClient) {
        self.api = api
    }

    func load(topicID: Int, force: Bool = false) {
        if self.topicID != topicID {
            stopReading()
            self.topicID = topicID
            detail = nil
            isLoadingMore = false
            replyMessage = nil
            runningPostActions = [:]
            actionMessage = nil
            phase = .idle
        }

        if !force, case .loaded = phase, detail?.id == topicID {
            return
        }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(topicID: topicID, force: force)
        }
    }

    func reload() {
        guard let topicID else { return }
        load(topicID: topicID, force: true)
    }

    var canLoadMore: Bool {
        detail?.remainingPostIDs.isEmpty == false
    }

    /// 通知可能指向尚未包含在首批数据中的楼层。根据 Discourse 的帖子流顺序，
    /// 优先只补取目标附近的一小段，避免为了定位高楼层而从头逐页请求。
    func loadTargetPostIfNeeded(postNumber: Int) async {
        guard postNumber > 0,
              !isLoadingMore,
              let detail,
              !detail.posts.contains(where: { $0.postNumber == postNumber }),
              !detail.postStreamIDs.isEmpty else { return }

        let topicID = detail.id
        let streamIDs = detail.postStreamIDs
        let targetUpperBound = min(postNumber, streamIDs.count)
        guard targetUpperBound > 0 else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        // 已删除楼层会让 postNumber 与 stream 下标产生偏移；从估算位置向前
        // 分段查找，通常一次请求即可命中，同时对少量缺口保持容错。
        let batchSize = 30
        let maximumBatches = 6
        var upperBound = targetUpperBound

        do {
            for _ in 0..<maximumBatches where upperBound > 0 {
                try Task.checkCancellation()
                guard self.topicID == topicID else { return }

                let lowerBound = max(0, upperBound - batchSize)
                let loadedIDs = Set(self.detail?.posts.map(\.id) ?? [])
                let ids = streamIDs[lowerBound..<upperBound].filter {
                    !loadedIDs.contains($0)
                }

                if !ids.isEmpty {
                    let posts = try await api.fetchPosts(topicID: topicID, postIDs: Array(ids))
                    try Task.checkCancellation()
                    guard self.topicID == topicID else { return }
                    merge(posts: posts)
                    if self.detail?.posts.contains(where: {
                        $0.postNumber == postNumber
                    }) == true {
                        return
                    }
                }

                upperBound = lowerBound
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.topicID == topicID else { return }
            phase = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    func loadMore() {
        guard !isLoadingMore,
              let detail,
              !detail.remainingPostIDs.isEmpty else { return }
        let ids = Array(detail.remainingPostIDs.prefix(20))
        isLoadingMore = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }
            do {
                let posts = try await self.api.fetchPosts(topicID: detail.id, postIDs: ids)
                if Task.isCancelled { return }
                self.merge(posts: posts)
            } catch {
                self.phase = .failed(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    func clearReplyMessage() {
        replyMessage = nil
    }

    func clearActionMessage() {
        actionMessage = nil
    }

    func post(id: Int) -> PostItem? {
        detail?.posts.first { $0.id == id }
    }

    func isRunning(postID: Int, action: PostActionKind) -> Bool {
        runningPostActions[postID]?.contains(action) == true
    }

    func loadFlagTypesIfNeeded() async {
        guard flagTypes.isEmpty, !isLoadingFlagTypes else { return }
        isLoadingFlagTypes = true
        defer { isLoadingFlagTypes = false }
        do {
            flagTypes = try await api.fetchPostActionTypes()
        } catch {
            showActionError(error)
        }
    }

    func availableFlagTypes(for post: PostItem) -> [PostFlagType] {
        flagTypes.filter { type in
            guard type.enabled, type.appliesToPost else { return false }
            if let action = post.actionsSummary.first(where: { $0.id == type.id }) {
                return action.canAct && !action.acted
            }
            return post.canFlag
        }
    }

    func toggleLike(postID: Int) async -> Bool {
        guard let post = post(id: postID), post.canToggleLike else { return false }
        if post.reactionsEnabled {
            return await toggleReaction(postID: postID, reaction: "heart")
        }
        guard beginAction(.reaction, postID: postID) else { return false }
        defer { endAction(.reaction, postID: postID) }

        let snapshot = post
        mutatePost(id: postID) { post in
            guard let index = post.actionsSummary.firstIndex(where: { $0.id == 2 }) else { return }
            let removing = post.actionsSummary[index].acted
            post.actionsSummary[index].acted = !removing
            post.actionsSummary[index].count = max(
                0,
                post.actionsSummary[index].count + (removing ? -1 : 1)
            )
            post.actionsSummary[index].canAct = removing
            post.actionsSummary[index].canUndo = !removing
            post.likeCount = max(0, post.likeCount + (removing ? -1 : 1))
        }

        do {
            let actions = try await api.toggleStandardLike(
                postID: post.id,
                topicID: post.topicID,
                remove: snapshot.likeAction?.acted == true
            )
            if let actions {
                mutatePost(id: postID) { $0.actionsSummary = actions }
            }
            return true
        } catch {
            replacePost(snapshot)
            showActionError(error)
            return false
        }
    }

    func toggleReaction(postID: Int, reaction: String) async -> Bool {
        guard let post = post(id: postID), post.canToggleLike,
              beginAction(.reaction, postID: postID) else { return false }
        defer { endAction(.reaction, postID: postID) }

        let snapshot = post
        mutatePost(id: postID) { Self.applyReactionToggle(to: &$0, reaction: reaction) }
        do {
            try await api.toggleReaction(
                postID: post.id,
                topicID: post.topicID,
                reaction: reaction
            )
            return true
        } catch {
            replacePost(snapshot)
            showActionError(error)
            return false
        }
    }

    func saveBookmark(
        postID: Int,
        name: String?,
        reminderAt: Date?,
        autoDeletePreference: BookmarkAutoDeletePreference
    ) async -> Bool {
        guard let post = post(id: postID),
              beginAction(.bookmark, postID: postID) else { return false }
        defer { endAction(.bookmark, postID: postID) }

        let snapshot = post
        mutatePost(id: postID) {
            $0.bookmarked = true
            $0.bookmarkName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.bookmarkReminderAt = reminderAt
            $0.bookmarkAutoDeletePreference = autoDeletePreference
        }
        do {
            let result = try await api.saveBookmark(
                postID: post.id,
                topicID: post.topicID,
                bookmarkID: post.bookmarkID,
                name: name,
                reminderAt: reminderAt,
                autoDeletePreference: autoDeletePreference
            )
            mutatePost(id: postID) { $0.bookmarkID = result.bookmarkID }
            if var detail {
                detail.bookmarked = true
                self.detail = detail
            }
            actionMessage = reminderAt == nil ? "已收藏该楼层" : "已收藏并设置提醒"
            return true
        } catch {
            replacePost(snapshot)
            showActionError(error)
            return false
        }
    }

    func removeBookmark(postID: Int) async -> Bool {
        guard let post = post(id: postID),
              beginAction(.bookmark, postID: postID) else { return false }
        defer { endAction(.bookmark, postID: postID) }

        let snapshot = post
        mutatePost(id: postID) {
            $0.bookmarked = false
            $0.bookmarkID = nil
            $0.bookmarkName = nil
            $0.bookmarkReminderAt = nil
        }
        do {
            let result = try await api.removeBookmark(
                bookmarkID: post.bookmarkID,
                postID: post.id,
                topicID: post.topicID
            )
            if var detail {
                detail.bookmarked = result.topicBookmarked
                    ?? detail.posts.contains(where: { $0.bookmarked })
                self.detail = detail
            }
            actionMessage = "已取消收藏"
            return true
        } catch {
            replacePost(snapshot)
            showActionError(error)
            return false
        }
    }

    func flagPost(postID: Int, type: PostFlagType, message: String?) async -> Bool {
        guard let post = post(id: postID),
              beginAction(.report, postID: postID) else { return false }
        defer { endAction(.report, postID: postID) }

        do {
            let actions = try await api.flagPost(
                postID: post.id,
                topicID: post.topicID,
                typeID: type.id,
                message: message
            )
            if let actions {
                mutatePost(id: postID) { $0.actionsSummary = actions }
            } else {
                mutatePost(id: postID) { post in
                    guard let index = post.actionsSummary.firstIndex(where: { $0.id == type.id }) else {
                        return
                    }
                    post.actionsSummary[index].acted = true
                    post.actionsSummary[index].canAct = false
                    post.actionsSummary[index].canUndo = true
                    post.actionsSummary[index].count += 1
                }
            }
            actionMessage = type.isNotifyUser ? "消息已发送给作者" : "举报已提交"
            return true
        } catch {
            showActionError(error)
            return false
        }
    }

    func createBoost(postID: Int, raw: String) async -> Bool {
        guard let post = post(id: postID),
              beginAction(.boost, postID: postID) else { return false }
        defer { endAction(.boost, postID: postID) }

        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 16 else {
            actionMessage = "Boost 内容需为 1–16 个字符"
            return false
        }
        do {
            let boost = try await api.createBoost(
                postID: post.id,
                topicID: post.topicID,
                raw: text
            )
            mutatePost(id: postID) {
                $0.boosts.append(boost)
                $0.canBoost = false
            }
            actionMessage = "Boost 已发送"
            return true
        } catch {
            showActionError(error)
            return false
        }
    }

    func toggleSharedIssue() async -> Bool {
        guard let detail,
              let firstPost = detail.posts.first,
              beginAction(.sharedIssue, postID: firstPost.id) else { return false }
        defer { endAction(.sharedIssue, postID: firstPost.id) }
        do {
            let result = try await api.toggleSharedIssue(topicID: detail.id)
            var updated = detail
            updated.userCreatedSharedIssue = result.created
            updated.sharedIssueCount = result.count
            self.detail = updated
            return true
        } catch {
            showActionError(error)
            return false
        }
    }

    func editableRaw(postID: Int) async -> String? {
        guard let post = post(id: postID),
              beginAction(.edit, postID: postID) else { return nil }
        defer { endAction(.edit, postID: postID) }
        if let raw = post.raw { return raw }
        do {
            return try await api.fetchEditableRaw(postID: postID)
        } catch {
            showActionError(error)
            return nil
        }
    }

    func editPost(postID: Int, raw: String, reason: String?) async -> Bool {
        guard let post = post(id: postID),
              beginAction(.edit, postID: postID) else { return false }
        defer { endAction(.edit, postID: postID) }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            actionMessage = "帖子内容不能为空"
            return false
        }
        do {
            try await api.editPost(
                postID: post.id,
                topicID: post.topicID,
                raw: text,
                editReason: reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await reloadAfterMutation(topicID: post.topicID)
            actionMessage = "修改已保存"
            return true
        } catch {
            showActionError(error)
            return false
        }
    }

    func deletePost(postID: Int) async -> Bool {
        await mutateAndReload(postID: postID, action: .delete) { api, post in
            try await api.deletePost(postID: post.id, topicID: post.topicID)
        }
    }

    func recoverPost(postID: Int) async -> Bool {
        await mutateAndReload(postID: postID, action: .recover) { api, post in
            try await api.recoverPost(postID: post.id, topicID: post.topicID)
        }
    }

    func toggleWiki(postID: Int) async -> Bool {
        await mutateAndReload(postID: postID, action: .wiki) { api, post in
            try await api.setPostWiki(postID: post.id, topicID: post.topicID, wiki: !post.wiki)
        }
    }

    func toggleAcceptedAnswer(postID: Int) async -> Bool {
        await mutateAndReload(postID: postID, action: .solution) { api, post in
            try await api.setAcceptedAnswer(
                postID: post.id,
                topicID: post.topicID,
                accepted: !post.acceptedAnswer
            )
        }
    }

    func submitReply(raw: String, replyToPostNumber: Int?) async -> Bool {
        guard let detail, !isSubmittingReply else { return false }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            replyMessage = "回复内容不能为空。"
            return false
        }

        isSubmittingReply = true
        replyMessage = nil
        defer { isSubmittingReply = false }
        do {
            let outcome = try await api.createReply(
                topicID: detail.id,
                categoryID: detail.categoryID,
                raw: text,
                replyToPostNumber: replyToPostNumber
            )
            if let post = outcome.post {
                if let merged = self.detail?.merging(posts: [post]) {
                    self.detail = merged
                    let serverRead = merged.initiallyReadPostNumbers
                    readPostNumbers.formUnion(serverRead)
                    readingTracker.seedRead(serverRead)
                }
            }
            replyMessage = outcome.pending ? "回复已提交，正在等待审核。" : nil
            return true
        } catch {
            replyMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func updateReadingSession(isLoggedIn: Bool, isFocused: Bool) {
        self.isLoggedIn = isLoggedIn
        readingFocused = isFocused

        if trackingTopicID == nil {
            startReadingIfPossible(reportRemotely: isLoggedIn)
        } else if reportRemotely != isLoggedIn {
            readingTracker.stop()
            trackingTopicID = nil
            startReadingIfPossible(reportRemotely: isLoggedIn)
        } else {
            readingTracker.setFocused(isFocused)
        }
    }

    func updateVisiblePostNumbers(_ postNumbers: Set<Int>) {
        readingTracker.updateVisiblePostNumbers(postNumbers)
    }

    func stopReading() {
        readingTracker.stop()
        trackingTopicID = nil
        reportingPostNumbers = []
    }

    private func performLoad(topicID: Int, force: Bool) async {
        phase = .loading
        do {
            let detail = try await api.fetchTopic(id: topicID, force: force)
            if Task.isCancelled { return }
            readingTracker.stop()
            trackingTopicID = nil
            self.detail = detail
            readPostNumbers = detail.initiallyReadPostNumbers
            reportingPostNumbers = []
            phase = .loaded
            startReadingIfPossible(reportRemotely: isLoggedIn)
        } catch is CancellationError {
            return
        } catch let error as LDOError where error == .cancelled {
            return
        } catch {
            if Task.isCancelled { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
        }
    }

    private func startReadingIfPossible(reportRemotely: Bool) {
        guard let detail,
              reportRemotely == false || detail.hasServerReadState,
              trackingTopicID != detail.id else { return }

        trackingTopicID = detail.id
        self.reportRemotely = reportRemotely
        // 重启跟踪时清掉上一次会话遗留的“同步中”标记。
        reportingPostNumbers = []
        readingTracker.start(
            topicID: detail.id,
            initiallyRead: readPostNumbers,
            focused: readingFocused,
            reportsRemotely: reportRemotely,
            reporter: reportRemotely
                ? { [api] topicID, timings, topicTime in
                    try await api.reportTopicTimings(
                        topicID: topicID,
                        timings: timings,
                        topicTime: topicTime
                    )
                }
                : { _, _, _ in },
            onReporting: { [weak self] postNumbers, reporting in
                guard let self else { return }
                if reporting {
                    self.reportingPostNumbers.formUnion(postNumbers)
                } else {
                    self.reportingPostNumbers.subtract(postNumbers)
                }
            },
            onPendingRead: { [weak self] postNumbers in
                // 停留时长达标只代表"本地读完"，先显示为同步中，等服务端确认。
                self?.reportingPostNumbers.formUnion(postNumbers)
            },
            onRead: { [weak self] postNumbers in
                guard let self else { return }
                self.readPostNumbers.formUnion(postNumbers)
                self.reportingPostNumbers.subtract(postNumbers)
            },
            onSyncFailed: { [weak self] postNumbers, error in
                guard let self else { return }
                self.reportingPostNumbers.subtract(postNumbers)
                self.readPostNumbers.subtract(postNumbers)
                self.actionMessage = Self.readingSyncMessage(for: error)
            }
        )
    }

    private static func readingSyncMessage(for error: Error) -> String {
        guard let requestError = error as? SiteRequestError else {
            return "阅读状态暂时未能同步，稍后会自动重试。"
        }
        switch requestError {
        case .challengeRequired:
            return "阅读状态未能同步：请在“登录与验证”中完成 Cloudflare 验证。"
        case .hostNotReady:
            return "阅读状态未能同步：站内请求环境尚未就绪，稍后会自动重试。"
        default:
            return "阅读状态暂时未能同步，稍后会自动重试。"
        }
    }

    private func merge(posts: [PostItem]) {
        guard let merged = detail?.merging(posts: posts) else { return }
        detail = merged
        let serverRead = merged.initiallyReadPostNumbers
        readPostNumbers.formUnion(serverRead)
        readingTracker.seedRead(serverRead)
    }

    private func beginAction(_ action: PostActionKind, postID: Int) -> Bool {
        guard runningPostActions[postID]?.contains(action) != true else { return false }
        runningPostActions[postID, default: []].insert(action)
        return true
    }

    private func endAction(_ action: PostActionKind, postID: Int) {
        runningPostActions[postID]?.remove(action)
        if runningPostActions[postID]?.isEmpty == true {
            runningPostActions[postID] = nil
        }
    }

    private func mutatePost(id: Int, _ mutation: (inout PostItem) -> Void) {
        guard var detail,
              let index = detail.posts.firstIndex(where: { $0.id == id }) else { return }
        mutation(&detail.posts[index])
        self.detail = detail
    }

    private func replacePost(_ post: PostItem) {
        mutatePost(id: post.id) { $0 = post }
    }

    private static func applyReactionToggle(to post: inout PostItem, reaction: String) {
        let previous = post.currentUserReaction
        if previous == reaction {
            adjustReaction(&post.reactions, id: reaction, delta: -1)
            post.currentUserReaction = nil
            post.reactionUsersCount = max(0, post.reactionUsersCount - 1)
            return
        }
        if let previous {
            adjustReaction(&post.reactions, id: previous, delta: -1)
        } else {
            post.reactionUsersCount += 1
        }
        adjustReaction(&post.reactions, id: reaction, delta: 1)
        post.currentUserReaction = reaction
    }

    private static func adjustReaction(
        _ reactions: inout [PostReaction],
        id: String,
        delta: Int
    ) {
        if let index = reactions.firstIndex(where: { $0.id == id }) {
            reactions[index].count = max(0, reactions[index].count + delta)
            if reactions[index].count == 0 {
                reactions.remove(at: index)
            }
        } else if delta > 0 {
            reactions.append(PostReaction(id: id, count: delta))
        }
    }

    private func mutateAndReload(
        postID: Int,
        action: PostActionKind,
        operation: (APIClient, PostItem) async throws -> Void
    ) async -> Bool {
        guard let post = post(id: postID),
              beginAction(action, postID: postID) else { return false }
        defer { endAction(action, postID: postID) }
        do {
            try await operation(api, post)
            try await reloadAfterMutation(topicID: post.topicID)
            return true
        } catch {
            showActionError(error)
            return false
        }
    }

    private func reloadAfterMutation(topicID: Int) async throws {
        let refreshed = try await api.fetchTopic(id: topicID, force: true)
        guard self.topicID == topicID else { return }
        detail = refreshed
        readPostNumbers.formUnion(refreshed.initiallyReadPostNumbers)
        readingTracker.seedRead(refreshed.initiallyReadPostNumbers)
        phase = .loaded
    }

    private func showActionError(_ error: Error) {
        actionMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }
}
