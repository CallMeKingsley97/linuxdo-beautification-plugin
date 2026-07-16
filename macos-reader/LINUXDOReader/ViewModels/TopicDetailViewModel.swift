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
