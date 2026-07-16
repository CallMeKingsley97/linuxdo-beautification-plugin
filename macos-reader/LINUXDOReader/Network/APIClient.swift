//
//  APIClient.swift
//

import Foundation

final class APIClient: @unchecked Sendable {
    static let appUserAgent = "LINUXDOReader/0.1.0 (macOS; third-party; not-affiliated)"

    private let session: URLSession
    private let decoder: JSONDecoder
    private let gate = RequestGate()

    /// 列表成功缓存 TTL（秒）
    var listTTL: TimeInterval = 60
    /// 详情成功缓存 TTL（秒）
    var detailTTL: TimeInterval = 45
    /// 分类列表缓存 TTL（秒）
    var categoryTTL: TimeInterval = 300

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            config.httpAdditionalHeaders = [
                "User-Agent": Self.appUserAgent,
                "Accept": "application/json",
            ]
            self.session = URLSession(configuration: config)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.ldoFractional.date(from: raw)
                ?? ISO8601DateFormatter.ldo.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析日期：\(raw)"
            )
        }
        self.decoder = decoder
    }

    func fetchLatest(page: Int = 0, force: Bool = false) async throws -> TopicListPage {
        let url = Endpoints.latest(page: page)
        let dto: LatestJSON = try await get(url: url, ttl: listTTL, force: force)
        return TopicListPage.from(latest: dto)
    }

    func fetchHot(page: Int = 0, force: Bool = false) async throws -> TopicListPage {
        let url = Endpoints.hot(page: page)
        let dto: LatestJSON = try await get(url: url, ttl: listTTL, force: force)
        return TopicListPage.from(latest: dto)
    }

    func fetchCategoryTopics(slug: String, id: Int, page: Int = 0, force: Bool = false) async throws -> TopicListPage {
        let url = Endpoints.category(slug: slug, id: id, page: page)
        let dto: LatestJSON = try await get(url: url, ttl: listTTL, force: force)
        return TopicListPage.from(latest: dto)
    }

    func fetchCategories(force: Bool = false) async throws -> [CategorySummary] {
        let url = Endpoints.categories()
        let dto: CategoriesJSON = try await get(url: url, ttl: categoryTTL, force: force)
        let list = (dto.categoryList?.categories ?? []).map(CategorySummary.from)
        return list.sorted { lhs, rhs in
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            return lhs.id < rhs.id
        }
    }

    func fetchTopic(id: Int, force: Bool = false) async throws -> TopicDetail {
        let url = Endpoints.topic(id: id)
        let dto: TopicDetailJSON = try await get(url: url, ttl: detailTTL, force: force)
        return TopicDetail.from(dto: dto)
    }

    private func get<T: Decodable>(url: URL, ttl: TimeInterval?, force: Bool) async throws -> T {
        let key = url.absoluteString
        do {
            let data = try await gate.data(forKey: key, ttl: ttl, force: force) { [session] in
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue(Self.appUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let (data, response) = try await session.data(for: request)
                try Self.validate(response: response, data: data)
                return data
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw LDOError.decoding(error.localizedDescription)
            }
        } catch let error as LDOError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw LDOError.cancelled
        } catch let error as URLError {
            throw LDOError.network(error.localizedDescription)
        } catch {
            throw LDOError.network(error.localizedDescription)
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LDOError.network("无效的 HTTP 响应")
        }

        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw LDOError.unauthorized
        case 403:
            throw LDOError.forbidden
        case 404:
            throw LDOError.notFound
        case 429:
            throw LDOError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8).map { String($0.prefix(200)) }
            throw LDOError.server(status: http.statusCode, message: message)
        }
    }
}

private extension ISO8601DateFormatter {
    static let ldo: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let ldoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
