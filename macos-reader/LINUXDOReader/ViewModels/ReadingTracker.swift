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
        .seconds(5), .seconds(10), .seconds(20), .seconds(40),
    ]
    private static let retryableHTTPStatuses: Set<Int> = [405, 429, 500, 501, 502, 503, 504]

    private var topicID: Int?
    private var reporter: Reporter?
    private var onReporting: ReportingStateHandler?
    private var onRead: ReadStateHandler?

    private var visiblePostNumbers: Set<Int> = []
    private var readPostNumbers: Set<Int> = []
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
        reporter: @escaping Reporter,
        onReporting: @escaping ReportingStateHandler,
        onRead: @escaping ReadStateHandler
    ) {
        stop()
        generation &+= 1
        self.topicID = topicID
        self.reporter = reporter
        self.onReporting = onReporting
        self.onRead = onRead
        readPostNumbers = initiallyRead
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
                self.readPostNumbers.formUnion(postNumbers)
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
            #if DEBUG
            print("[LINUXDOReader][Reading] report dropped topic=\(batch.topicID) error=\(error.localizedDescription)")
            #endif
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
        case .hostNotReady:
            return true
        case .http(let status, _):
            return Self.retryableHTTPStatuses.contains(status)
        case .invalidResponse, .loginRequired, .challengeRequired:
            return false
        }
    }

    private func resetState() {
        topicID = nil
        reporter = nil
        onReporting = nil
        onRead = nil
        visiblePostNumbers = []
        readPostNumbers = []
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
