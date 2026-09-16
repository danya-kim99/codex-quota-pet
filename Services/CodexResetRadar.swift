import Foundation

enum CodexResetType: String, Decodable, Sendable {
    case regular
    case banked
}

enum CodexResetSignal: Equatable, Sendable {
    case watch(chancePercent: Int?, expiresAt: Date)
    case scheduled(resetType: CodexResetType, scheduledFor: Date?)

    func valid(at date: Date) -> CodexResetSignal? {
        if case let .watch(_, expiresAt) = self, expiresAt <= date {
            return nil
        }
        return self
    }
}

struct CodexResetRadar {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    enum FetchResult: Equatable, Sendable {
        case updated(signal: CodexResetSignal?, eTag: String?, maxAge: TimeInterval)
        case notModified(maxAge: TimeInterval)
    }

    enum FetchError: Error, Equatable {
        case invalidResponse
        case unexpectedEndpoint
        case unexpectedStatus(Int)
        case unexpectedContentType
        case bodyTooLarge
        case invalidSchema
        case retryAfter(TimeInterval)
    }

    static let endpoint = URL(string: "https://codex-resets.com/api/v1/status")!
    static let requestTimeout: TimeInterval = 10
    static let maximumBodyBytes = 128 * 1_024
    static let fallbackFreshness: TimeInterval = 5 * 60
    static let maximumFreshness: TimeInterval = 60 * 60
    static let maximumRetryAfter: TimeInterval = 24 * 60 * 60

    private let transport: Transport

    init() {
        transport = { request in
            try await CodexResetRadar.liveTransport(request)
        }
    }

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    func fetch(eTag: String?) async throws -> FetchResult {
        var request = URLRequest(
            url: Self.endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: Self.requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("*", forHTTPHeaderField: "Accept-Language")
        if let eTag = Self.validatedETag(eTag) {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }

        let (body, response) = try await transport(request)
        guard body.count <= Self.maximumBodyBytes else {
            throw FetchError.bodyTooLarge
        }
        guard let response = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        try Self.validateFinalEndpoint(response.url)

        let maxAge = Self.freshness(
            from: response.value(forHTTPHeaderField: "Cache-Control")
        )
        switch response.statusCode {
        case 200:
            guard response.mimeType?.lowercased() == "application/json" else {
                throw FetchError.unexpectedContentType
            }
            let payload: StatusResponse
            do {
                payload = try JSONDecoder().decode(StatusResponse.self, from: body)
            } catch {
                throw FetchError.invalidSchema
            }
            let signal = try payload.validatedSignal()
            return .updated(
                signal: signal,
                eTag: Self.validatedETag(
                    response.value(forHTTPHeaderField: "ETag")
                ),
                maxAge: maxAge
            )
        case 304:
            guard Self.validatedETag(eTag) != nil else {
                throw FetchError.unexpectedStatus(response.statusCode)
            }
            return .notModified(maxAge: maxAge)
        case 429, 503:
            throw FetchError.retryAfter(
                Self.retryDelay(
                    from: response.value(forHTTPHeaderField: "Retry-After")
                )
            )
        default:
            throw FetchError.unexpectedStatus(response.statusCode)
        }
    }

    private static func liveTransport(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        let redirectDelegate = RedirectRejectingDelegate()
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumBodyBytes) {
            throw FetchError.bodyTooLarge
        }
        var body = Data()
        body.reserveCapacity(
            max(0, min(maximumBodyBytes, Int(response.expectedContentLength)))
        )
        for try await byte in bytes {
            guard body.count < maximumBodyBytes else {
                throw FetchError.bodyTooLarge
            }
            body.append(byte)
        }
        return (body, response)
    }

    private static func validateFinalEndpoint(_ url: URL?) throws {
        guard url?.absoluteString == endpoint.absoluteString else {
            throw FetchError.unexpectedEndpoint
        }
    }

    private static func freshness(from cacheControl: String?) -> TimeInterval {
        guard let cacheControl else { return fallbackFreshness }
        for rawDirective in cacheControl.split(separator: ",") {
            let parts = rawDirective.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "max-age" else {
                continue
            }
            let rawValue = parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let seconds = TimeInterval(rawValue), seconds >= 0 {
                return min(seconds, maximumFreshness)
            }
        }
        return fallbackFreshness
    }

    private static func retryDelay(from retryAfter: String?) -> TimeInterval {
        guard let retryAfter,
              let seconds = TimeInterval(
                retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              seconds >= 0 else {
            return fallbackFreshness
        }
        return min(seconds, maximumRetryAfter)
    }

    private static func validatedETag(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.utf8.count <= 1_024,
              !value.contains("\r"),
              !value.contains("\n") else {
            return nil
        }
        return value
    }
}

extension CodexResetRadar {
    final class RedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        static func requestToFollow(for request: URLRequest) -> URLRequest? {
            nil
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(Self.requestToFollow(for: request))
        }
    }
}

private extension CodexResetRadar {
    struct StatusResponse: Decodable {
        let data: StatusData
        let meta: Meta

        func validatedSignal() throws -> CodexResetSignal? {
            guard meta.apiVersion == "v1",
                  Self.date(meta.generatedAt) != nil,
                  data.stats.isValid,
                  data.latestReset?.isValid != false else {
                throw FetchError.invalidSchema
            }

            if let scheduled = data.scheduledReset {
                return try scheduled.signal()
            }
            return try data.activeWatch?.signal()
        }

        private static func date(_ value: String) -> Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            return standard.date(from: value)
        }

        struct StatusData: Decodable {
            let latestReset: Reset?
            let scheduledReset: ScheduledReset?
            let activeWatch: Watch?
            let stats: Stats

            enum CodingKeys: String, CodingKey, CaseIterable {
                case latestReset = "latest_reset"
                case scheduledReset = "scheduled_reset"
                case activeWatch = "active_watch"
                case stats
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                for key in CodingKeys.allCases where !container.contains(key) {
                    throw DecodingError.keyNotFound(
                        key,
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing key")
                    )
                }
                latestReset = try container.decodeIfPresent(Reset.self, forKey: .latestReset)
                scheduledReset = try container.decodeIfPresent(
                    ScheduledReset.self,
                    forKey: .scheduledReset
                )
                activeWatch = try container.decodeIfPresent(Watch.self, forKey: .activeWatch)
                stats = try container.decode(Stats.self, forKey: .stats)
            }
        }

        struct Meta: Decodable {
            let apiVersion: String
            let generatedAt: String

            enum CodingKeys: String, CodingKey, CaseIterable {
                case apiVersion = "api_version"
                case generatedAt = "generated_at"
            }
        }

        struct Reset: Decodable {
            let id: String
            let resetType: CodexResetType
            let announcedAt: String
            let text: String
            let source: Source

            enum CodingKeys: String, CodingKey {
                case id
                case resetType = "reset_type"
                case announcedAt = "announced_at"
                case text
                case source
            }

            var isValid: Bool {
                !id.isEmpty && id.count <= 64
                    && StatusResponse.date(announcedAt) != nil
                    && source.isValid
            }
        }

        struct ScheduledReset: Decodable {
            enum Status: String, Decodable { case scheduled }

            let id: String
            let status: Status
            let resetType: CodexResetType
            let announcedAt: String
            let scheduledFor: String?
            let text: String
            let source: Source

            enum CodingKeys: String, CodingKey, CaseIterable {
                case id
                case status
                case resetType = "reset_type"
                case announcedAt = "announced_at"
                case scheduledFor = "scheduled_for"
                case text
                case source
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                for key in CodingKeys.allCases where !container.contains(key) {
                    throw DecodingError.keyNotFound(
                        key,
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing key")
                    )
                }
                id = try container.decode(String.self, forKey: .id)
                status = try container.decode(Status.self, forKey: .status)
                resetType = try container.decode(CodexResetType.self, forKey: .resetType)
                announcedAt = try container.decode(String.self, forKey: .announcedAt)
                scheduledFor = try container.decodeIfPresent(String.self, forKey: .scheduledFor)
                text = try container.decode(String.self, forKey: .text)
                source = try container.decode(Source.self, forKey: .source)
            }

            func signal() throws -> CodexResetSignal {
                guard !id.isEmpty,
                      StatusResponse.date(announcedAt) != nil,
                      source.isValid else {
                    throw FetchError.invalidSchema
                }
                let scheduledDate: Date?
                if let scheduledFor {
                    guard let date = StatusResponse.date(scheduledFor) else {
                        throw FetchError.invalidSchema
                    }
                    scheduledDate = date
                } else {
                    scheduledDate = nil
                }
                return .scheduled(resetType: resetType, scheduledFor: scheduledDate)
            }
        }

        struct Watch: Decodable {
            enum Level: String, Decodable { case elevated, strong }

            let level: Level
            let chancePercent: Int?
            let forecastWindow: String
            let observedAt: String
            let expiresAt: String
            let text: String
            let source: Source

            enum CodingKeys: String, CodingKey, CaseIterable {
                case level
                case chancePercent = "reset_chance_percent"
                case forecastWindow = "forecast_window"
                case observedAt = "observed_at"
                case expiresAt = "expires_at"
                case text
                case source
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                for key in CodingKeys.allCases where !container.contains(key) {
                    throw DecodingError.keyNotFound(
                        key,
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing key")
                    )
                }
                level = try container.decode(Level.self, forKey: .level)
                chancePercent = try container.decodeIfPresent(Int.self, forKey: .chancePercent)
                forecastWindow = try container.decode(String.self, forKey: .forecastWindow)
                observedAt = try container.decode(String.self, forKey: .observedAt)
                expiresAt = try container.decode(String.self, forKey: .expiresAt)
                text = try container.decode(String.self, forKey: .text)
                source = try container.decode(Source.self, forKey: .source)
            }

            func signal() throws -> CodexResetSignal {
                guard chancePercent.map({ 0...100 ~= $0 }) ?? true,
                      let observedDate = StatusResponse.date(observedAt),
                      let expiryDate = StatusResponse.date(expiresAt),
                      expiryDate > observedDate,
                      source.isValid else {
                    throw FetchError.invalidSchema
                }
                return .watch(chancePercent: chancePercent, expiresAt: expiryDate)
            }
        }

        struct Stats: Decodable {
            let total: Int
            let lastResetAt: String?
            let daysSinceLast: Double?
            let averageIntervalDays: Double?

            enum CodingKeys: String, CodingKey, CaseIterable {
                case total
                case lastResetAt = "last_reset_at"
                case daysSinceLast = "days_since_last"
                case averageIntervalDays = "avg_interval_days"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                for key in CodingKeys.allCases where !container.contains(key) {
                    throw DecodingError.keyNotFound(
                        key,
                        .init(codingPath: decoder.codingPath, debugDescription: "Missing key")
                    )
                }
                total = try container.decode(Int.self, forKey: .total)
                lastResetAt = try container.decodeIfPresent(String.self, forKey: .lastResetAt)
                daysSinceLast = try container.decodeIfPresent(Double.self, forKey: .daysSinceLast)
                averageIntervalDays = try container.decodeIfPresent(
                    Double.self,
                    forKey: .averageIntervalDays
                )
            }

            var isValid: Bool {
                total >= 0
                    && lastResetAt.map { StatusResponse.date($0) != nil } ?? true
                    && daysSinceLast.map { $0.isFinite && $0 >= 0 } ?? true
                    && averageIntervalDays.map { $0.isFinite && $0 >= 0 } ?? true
            }
        }

        struct Source: Decodable {
            enum Kind: String, Decodable { case xPost = "x_post", observed }
            enum Author: String, Decodable { case thsottiaux }

            let type: Kind
            let author: Author?
            let url: String?

            enum CodingKeys: String, CodingKey {
                case type
                case author
                case url
            }

            var isValid: Bool {
                switch type {
                case .xPost:
                    author == .thsottiaux && url.flatMap(Self.validURL) != nil
                case .observed:
                    author == nil && (url == nil || url.flatMap(Self.validURL) != nil)
                }
            }

            private static func validURL(_ value: String) -> URL? {
                guard let url = URL(string: value), url.scheme != nil else { return nil }
                return url
            }
        }
    }
}
