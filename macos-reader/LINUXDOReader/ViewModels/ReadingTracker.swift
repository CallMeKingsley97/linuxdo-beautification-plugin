//
//  ReadingTracker.swift
//  对齐 Discourse screen-track：累计可见楼层停留时间并批量上报 /topics/timings。
//

import Foundation

@MainActor
final class ReadingTracker {
    typealias Reporter = (_ topicID: Int, _ timings: [Int: Int], _ topicTime: Int) async throws -> Void
    typealias ReportingStateHandler = (_ postNumbers: Set<Int>, _ reporting: Bool) -> Void
    typealias ReadStateHandler = (_ postNumbers: Set<Int>) -> Void
    typealias SyncFailureHandler = (_ postNumbers: Set<Int>, _ error: Error) -> Void

    private struct Batch {
        let topicID: Int
        var timings: [Int: Int]
        var topicTime: Int
    }

    private static let tickInterval: Duration = .seconds(1)
    private static let regularFlushMilliseconds = 60_000
    private static let reportBatchMilliseconds = 5_000
    private static let minimumReadMilliseconds = 2_000
    private static let pauseUnlessScrolledMilliseconds = 3 * 60_000
    private static let maximumPostTrackingMilliseconds = 6 * 60_000
    private static let retryDelays: [Duration] = [
        .seconds(5), .seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(90),
    ]
    private static let retryableHTTPStatuses: Set<Int> = [405, 429, 500, 501, 502, 503, 504]
    private static let postDiscardCooldown: TimeInterval = 30

    private var topicID: Int?
    private var reporter: Reporter?
    private var onReporting: ReportingStateHandler?
    private var onPendingRead: ReadStateHandler?
    private var onRead: ReadStateHandler?
    private var onSyncFailed: SyncFailureHandler?

    private var visiblePostNumbers: Set<Int> = []
    private var readPostNumbers: Set<Int> = []
    private var pendingReadPostNumbers: Set<Int> = []
    /// 服务端已确认的已读楼层（初始种子或上报成功），失败回滚时不该被抹掉。
    private var serverConfirmedPostNumbers: Set<Int> = []
    /// 是否由服务端持久化阅读状态；为 false 时（未登录）本地停留即视为已读。
    private var reportsRemotely = false
    private var timings: [Int: Int] = [:]
    private var totalTimings: [Int: Int] = [:]
    private var topicTime = 0
    private var lastFlushMilliseconds = 0
    private var lastTick = Date()
    private var lastScrolled = Date()
    private var lastReportAt = Date()
    private var queuedBatch: Batch?
    private var inProgress = false
    private var retryCount = 0
    private var blockSendingUntil: Date?
    private var isRunning = false
    private var isFocused = true
    private var generation = 0
    private var tickTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    func start(
        topicID: Int,
        initiallyRead: Set<Int>,
        focused: Bool,
        reportsRemotely: Bool,
        reporter: @escaping Reporter,
        onReporting: @escaping ReportingStateHandler,
        onPendingRead: @escaping ReadStateHandler,
        onRead: @escaping ReadStateHandler,
        onSyncFailed: @escaping SyncFailureHandler
    ) {
        stop()
        generation &+= 1
        self.topicID = topicID
        self.reporter = reporter
        self.onReporting = onReporting
        self.onPendingRead = onPendingRead
        self.onRead = onRead
        self.onSyncFailed = onSyncFailed
        readPostNumbers = initiallyRead
        serverConfirmedPostNumbers = initiallyRead
        pendingReadPostNumbers = []
        self.reportsRemotely = reportsRemotely
        isFocused = focused
        isRunning = true

        let now = Date()
        lastTick = now
        lastScrolled = now
        lastReportAt = now.addingTimeInterval(
            -Double(Self.reportBatchMilliseconds) / 1_000
        )
        if focused {
            startTicking()
        }

        #if DEBUG
        print("[LINUXDOReader][Reading] start topic=\(topicID) seeded=\(initiallyRead.count)")
        #endif
    }

    func stop() {
        guard isRunning else { return }

        if isFocused {
            tick()
        }
        flushAndQueue()
        drainQueuedBatch()

        tickTask?.cancel()
        tickTask = nil
        retryTask?.cancel()
        retryTask = nil
        generation &+= 1
        resetState()
    }

    func setFocused(_ focused: Bool) {
        guard isRunning, focused != isFocused else { return }

        if focused {
            isFocused = true
            lastTick = Date()
            lastScrolled = lastTick
            startTicking()
        } else {
            tick()
            isFocused = false
            flushAndQueue()
            sendNextIfNeeded()
            tickTask?.cancel()
            tickTask = nil
        }
    }

    func updateVisiblePostNumbers(_ postNumbers: Set<Int>) {
        visiblePostNumbers = Set(postNumbers.filter { $0 > 0 })
        lastScrolled = Date()
    }

    func seedRead(_ postNumbers: Set<Int>) {
        readPostNumbers.formUnion(postNumbers)
        serverConfirmedPostNumbers.formUnion(postNumbers)
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRunning, isFocused else { return }

        let now = Date()
        let elapsed = max(0, Int(now.timeIntervalSince(lastTick) * 1_000))
        let milliseconds = min(elapsed, 2_000)
        lastTick = now

        guard now.timeIntervalSince(lastScrolled) * 1_000
                <= Double(Self.pauseUnlessScrolledMilliseconds) else {
            return
        }

        topicTime += milliseconds
        lastFlushMilliseconds += milliseconds

        for postNumber in visiblePostNumbers where !readPostNumbers.contains(postNumber) {
            let total = totalTimings[postNumber] ?? 0
            guard total < Self.maximumPostTrackingMilliseconds else { continue }
            timings[postNumber, default: 0] += milliseconds
        }

        let locallyRead = visiblePostNumbers.filter { postNumber in
            !readPostNumbers.contains(postNumber)
                && !pendingReadPostNumbers.contains(postNumber)
                && (totalTimings[postNumber] ?? 0) + (timings[postNumber] ?? 0)
                    >= Self.minimumReadMilliseconds
        }
        if !locallyRead.isEmpty {
            if reportsRemotely {
                // 等服务端确认后再标记已读：小标先消失会让本地与服务端状态不一致。
                pendingReadPostNumbers.formUnion(locallyRead)
                onPendingRead?(Set(locallyRead))
            } else {
                readPostNumbers.formUnion(locallyRead)
                onRead?(Set(locallyRead))
            }
        }

        let hasNewReadablePost = timings.contains { postNumber, milliseconds in
            milliseconds >= Self.minimumReadMilliseconds
                && (totalTimings[postNumber] ?? 0) == 0
                && !readPostNumbers.contains(postNumber)
        }
        let batchIsDue = now.timeIntervalSince(lastReportAt) * 1_000
            >= Double(Self.reportBatchMilliseconds)

        if !inProgress,
           lastFlushMilliseconds >= Self.regularFlushMilliseconds
            || (hasNewReadablePost && batchIsDue) {
            flushAndQueue()
        }
        sendNextIfNeeded()
    }

    private func flushAndQueue() {
        guard let topicID else { return }

        var newTimings: [Int: Int] = [:]
        for (postNumber, milliseconds) in timings {
            let total = totalTimings[postNumber] ?? 0
            if milliseconds > 0,
               total < Self.maximumPostTrackingMilliseconds,
               !readPostNumbers.contains(postNumber) {
                let accepted = min(
                    milliseconds,
                    Self.maximumPostTrackingMilliseconds - total
                )
                totalTimings[postNumber] = total + accepted
                newTimings[postNumber] = accepted
            }
        }
        timings.removeAll(keepingCapacity: true)
        lastFlushMilliseconds = 0

        guard !newTimings.isEmpty else { return }
        enqueue(Batch(topicID: topicID, timings: newTimings, topicTime: topicTime))
        topicTime = 0
        lastReportAt = Date()
        sendNextIfNeeded()
    }

    private func enqueue(_ batch: Batch) {
        guard var queuedBatch, queuedBatch.topicID == batch.topicID else {
            self.queuedBatch = batch
            return
        }
        for (postNumber, milliseconds) in batch.timings {
            queuedBatch.timings[postNumber, default: 0] += milliseconds
        }
        queuedBatch.topicTime += batch.topicTime
        self.queuedBatch = queuedBatch
    }

    private func sendNextIfNeeded() {
        guard !inProgress,
              let batch = queuedBatch,
              let reporter else { return }
        if let blockSendingUntil, blockSendingUntil > Date() {
            return
        }

        queuedBatch = nil
        inProgress = true
        let postNumbers = Set(batch.timings.keys)
        onReporting?(postNumbers, true)
        let requestGeneration = generation

        Task { [weak self] in
            do {
                try await reporter(batch.topicID, batch.timings, batch.topicTime)
                guard let self,
                      self.generation == requestGeneration,
                      self.topicID == batch.topicID else { return }

                self.inProgress = false
                self.retryCount = 0
                self.blockSendingUntil = nil
                self.pendingReadPostNumbers.subtract(postNumbers)
                self.readPostNumbers.formUnion(postNumbers)
                self.serverConfirmedPostNumbers.formUnion(postNumbers)
                self.onReporting?(postNumbers, false)
                self.onRead?(postNumbers)
                #if DEBUG
                print("[LINUXDOReader][Reading] report success topic=\(batch.topicID) posts=\(postNumbers.sorted())")
                #endif
                self.sendNextIfNeeded()
            } catch {
                guard let self,
                      self.generation == requestGeneration,
                      self.topicID == batch.topicID else { return }

                self.inProgress = false
                self.onReporting?(postNumbers, false)
                self.handleFailure(batch, error: error)
            }
        }
    }

    private func handleFailure(_ batch: Batch, error: Error) {
        guard shouldRetry(error), retryCount < Self.retryDelays.count else {
            discard(batch, error: error)
            return
        }

        let delay = Self.retryDelays[retryCount]
        retryCount += 1
        enqueue(batch)
        blockSendingUntil = Date().addingTimeInterval(delay.timeInterval)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.sendNextIfNeeded()
        }

        #if DEBUG
        print("[LINUXDOReader][Reading] retry topic=\(batch.topicID) attempt=\(retryCount)")
        #endif
    }

    /// 重试用尽后放弃这批计时：本地回到"未读"，等待下次停留重新累计并上报。
    private func discard(_ batch: Batch, error: Error) {
        let batchPostNumbers = Set(batch.timings.keys)
        var unconfirmed: Set<Int> = []
        for postNumber in batchPostNumbers {
            totalTimings.removeValue(forKey: postNumber)
            timings.removeValue(forKey: postNumber)
            pendingReadPostNumbers.remove(postNumber)
            guard !serverConfirmedPostNumbers.contains(postNumber) else { continue }
            readPostNumbers.remove(postNumber)
            unconfirmed.insert(postNumber)
        }
        // 失败后短暂退避，避免长时间异常时反复冲击站点。
        blockSendingUntil = Date().addingTimeInterval(Self.postDiscardCooldown)
        retryCount = 0

        #if DEBUG
        print("[LINUXDOReader][Reading] report dropped topic=\(batch.topicID) posts=\(batchPostNumbers.sorted()) error=\(error.localizedDescription)")
        #endif

        if reportsRemotely, !unconfirmed.isEmpty {
            onSyncFailed?(unconfirmed, error)
        }
        sendNextIfNeeded()
    }

    private func drainQueuedBatch() {
        guard let batch = queuedBatch, let reporter else { return }
        queuedBatch = nil
        Task {
            try? await reporter(batch.topicID, batch.timings, batch.topicTime)
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        guard let requestError = error as? SiteRequestError else { return false }
        switch requestError {
        case .hostNotReady, .challengeRequired:
            // 宿主页被 Cloudflare 挑战或尚未就绪时，重建宿主页后重试即可恢复。
            return true
        case .http(let status, _):
            return Self.retryableHTTPStatuses.contains(status)
        case .invalidResponse, .loginRequired:
            return false
        }
    }

    private func resetState() {
        topicID = nil
        reporter = nil
        onReporting = nil
        onPendingRead = nil
        onRead = nil
        onSyncFailed = nil
        visiblePostNumbers = []
        readPostNumbers = []
        serverConfirmedPostNumbers = []
        pendingReadPostNumbers = []
        reportsRemotely = false
        timings = [:]
        totalTimings = [:]
        topicTime = 0
        lastFlushMilliseconds = 0
        queuedBatch = nil
        inProgress = false
        retryCount = 0
        blockSendingUntil = nil
        isRunning = false
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
