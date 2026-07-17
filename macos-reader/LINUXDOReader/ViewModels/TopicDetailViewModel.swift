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

    private let api: APIClient
    private var topicID: Int?
    private var loadTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    func load(topicID: Int, force: Bool = false) {
        if self.topicID != topicID {
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
                self.detail = self.detail?.merging(posts: posts)
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
                self.detail = self.detail?.merging(posts: [post])
            }
            replyMessage = outcome.pending ? "回复已提交，正在等待审核。" : nil
            return true
        } catch {
            replyMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func performLoad(topicID: Int, force: Bool) async {
        phase = .loading
        do {
            let detail = try await api.fetchTopic(id: topicID, force: force)
            if Task.isCancelled { return }
            self.detail = detail
            phase = .loaded
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
}
