import AppKit
import Foundation

struct QuotaWindow: Decodable, Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int64?
    let resetsAt: Int64?

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    var resetDate: Date? {
        resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

struct QuotaSnapshot: Decodable, Equatable, Sendable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
}

struct RateLimitsResult: Decodable {
    let rateLimits: QuotaSnapshot
    let rateLimitsByLimitId: [String: QuotaSnapshot]?

    var codex: QuotaSnapshot {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }
}

struct ConfigReadResult: Decodable {
    struct Config: Decodable {
        let serviceTier: String?

        enum CodingKeys: String, CodingKey {
            case serviceTier = "service_tier"
        }
    }

    let config: Config

    var speedMode: SpeedMode {
        switch config.serviceTier?.lowercased() {
        case "fast", "priority":
            .turbo
        default:
            .standard
        }
    }
}

struct RPCResponse<Value: Decodable>: Decodable {
    let id: Int
    let result: Value
}

protocol CodexAppServerClient: AnyObject {
    func start(
        onSnapshot: @escaping (QuotaSnapshot) -> Void,
        onSpeedMode: @escaping (SpeedMode) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws

    func stop()
}

final class CodexAppServer: CodexAppServerClient {
    private struct Envelope: Decodable {
        let id: Int?
        let method: String?
    }

    private struct RPCErrorResponse: Decodable {
        struct Body: Decodable {
            let message: String
        }

        let id: Int
        let error: Body
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextRequestID = 1
    private var rateLimitRequestIDs = Set<Int>()
    private var configTimer: Timer?
    private var onSnapshot: ((QuotaSnapshot) -> Void)?
    private var onSpeedMode: ((SpeedMode) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var sessionID = 0
    private var hasReportedFailure = false

    func start(
        onSnapshot: @escaping (QuotaSnapshot) -> Void,
        onSpeedMode: @escaping (SpeedMode) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        stop()

        guard let executableURL = Self.codexExecutableURL else {
            throw AppServerError.codexNotFound
        }

        let activeSessionID = sessionID
        self.onSnapshot = onSnapshot
        self.onSpeedMode = onSpeedMode
        self.onFailure = onFailure
        hasReportedFailure = false

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.reportFailure(
                    "Codex App Server stopped",
                    sessionID: activeSessionID
                )
            }
        }

        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { [weak self] in
                self?.receive(data, sessionID: activeSessionID)
            }
        }

        do {
            try process.run()
            self.process = process

            try send([
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "black_hole_codex_quota_indicator",
                        "title": AppConstants.displayName,
                        "version": "0.1.0"
                    ]
                ]
            ])
            try send(["method": "initialized", "params": [:]])
            try requestRateLimits()
            try requestConfig()
            configTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                guard let self, self.sessionID == activeSessionID else {
                    return
                }

                do {
                    try self.requestConfig()
                } catch {
                    self.reportFailure(error.localizedDescription, sessionID: activeSessionID)
                }
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        sessionID += 1
        configTimer?.invalidate()
        configTimer = nil
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }

        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
        buffer.removeAll(keepingCapacity: true)
        nextRequestID = 1
        rateLimitRequestIDs.removeAll(keepingCapacity: true)
        onSnapshot = nil
        onSpeedMode = nil
        onFailure = nil
        hasReportedFailure = false
    }

    deinit {
        stop()
    }

    private func receive(_ data: Data, sessionID: Int) {
        guard sessionID == self.sessionID else {
            return
        }

        guard !data.isEmpty else {
            reportFailure("Codex App Server disconnected", sessionID: sessionID)
            return
        }

        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: line) else {
            return
        }

        if envelope.method == "account/rateLimits/updated" {
            try? requestRateLimits()
            return
        }

        guard let responseID = envelope.id, responseID != 0 else {
            return
        }

        if let response = try? decoder.decode(RPCResponse<RateLimitsResult>.self, from: line) {
            rateLimitRequestIDs.remove(response.id)
            onSnapshot?(response.result.codex)
        } else if let response = try? decoder.decode(RPCResponse<ConfigReadResult>.self, from: line) {
            onSpeedMode?(response.result.speedMode)
        } else if let response = try? decoder.decode(RPCErrorResponse.self, from: line) {
            if rateLimitRequestIDs.remove(responseID) != nil {
                reportFailure(response.error.message, sessionID: sessionID)
            }
        }
    }

    private func reportFailure(_ message: String, sessionID: Int) {
        guard sessionID == self.sessionID, !hasReportedFailure else {
            return
        }

        hasReportedFailure = true
        configTimer?.invalidate()
        configTimer = nil
        output?.readabilityHandler = nil
        onFailure?(message)
    }

    private func requestRateLimits() throws {
        let requestID = takeRequestID()
        rateLimitRequestIDs.insert(requestID)
        try send(["method": "account/rateLimits/read", "id": requestID])
    }

    private func requestConfig() throws {
        try send([
            "method": "config/read",
            "id": takeRequestID(),
            "params": ["includeLayers": false]
        ])
    }

    private func takeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else {
            throw AppServerError.notRunning
        }

        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private static var codexExecutableURL: URL? {
        let fileManager = FileManager.default

        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) {
            let bundledCodex = appURL.appendingPathComponent("Contents/Resources/codex")
            if fileManager.isExecutableFile(atPath: bundledCodex.path) {
                return bundledCodex
            }
        }

        // ponytail: standard CLI locations cover the MVP; onboarding can add a custom path.
        return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .first(where: fileManager.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}

private enum AppServerError: LocalizedError {
    case codexNotFound
    case notRunning

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            "Codex executable not found"
        case .notRunning:
            "Codex App Server is not running"
        }
    }
}
