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

    private let api: APIClient
    private let readingTracker = ReadingTracker()
    private var topicID: Int?
    private var loadTask: Task<Void, Never>?
    private var trackingTopicID: Int?
    private var readingEnabled = false
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
        readingEnabled = isLoggedIn
        readingFocused = isFocused

        guard isLoggedIn else {
            stopReading()
            return
        }

        if trackingTopicID == nil {
            startReadingIfPossible()
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
            startReadingIfPossible()
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

    private func startReadingIfPossible() {
        guard readingEnabled,
              let detail,
              detail.hasServerReadState,
              trackingTopicID != detail.id else { return }

        trackingTopicID = detail.id
        readingTracker.start(
            topicID: detail.id,
            initiallyRead: readPostNumbers,
            focused: readingFocused,
            reporter: { [api] topicID, timings, topicTime in
                try await api.reportTopicTimings(
                    topicID: topicID,
                    timings: timings,
                    topicTime: topicTime
                )
            },
            onReporting: { [weak self] postNumbers, reporting in
                guard let self else { return }
                if reporting {
                    self.reportingPostNumbers.formUnion(postNumbers)
                } else {
                    self.reportingPostNumbers.subtract(postNumbers)
                }
            },
            onRead: { [weak self] postNumbers in
                guard let self else { return }
                self.readPostNumbers.formUnion(postNumbers)
                self.reportingPostNumbers.subtract(postNumbers)
            }
        )
    }

    private func merge(posts: [PostItem]) {
        guard let merged = detail?.merging(posts: posts) else { return }
        detail = merged
        let serverRead = merged.initiallyReadPostNumbers
        readPostNumbers.formUnion(serverRead)
        readingTracker.seedRead(serverRead)
    }
}
