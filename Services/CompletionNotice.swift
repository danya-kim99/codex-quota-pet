import Foundation
import CoreFoundation
import CryptoKit
import Darwin
import OSLog

enum CompletionTrace {
    #if DEBUG
    static let enabled = ProcessInfo.processInfo.environment["BLACK_HOLE_COMPLETION_TRACE"] == "1"
    private static let logger = Logger(subsystem: "com.blackholecodex.quotaindicator", category: "CompletionNotice")
    #else
    static let enabled = false
    #endif

    // Call sites contain only fixed labels, booleans, counts and relative times.
    static func event(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard enabled else { return }
        let rendered = message()
        logger.info("\(rendered, privacy: .public)")
        #endif
    }
}

struct CompletionHint: Equatable {
    let threadID: String
    let turnID: String
    var key: String { threadID + ":" + turnID }

    init?(threadID: String, turnID: String) {
        // Codex currently emits UUIDs. Bound identifiers without depending on their version.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard [threadID, turnID].allSatisfy({
            !$0.isEmpty && $0.utf8.count <= 128 && $0.unicodeScalars.allSatisfy(allowed.contains)
        }) else { return nil }
        self.threadID = threadID
        self.turnID = turnID
    }

    init?(rawEvent: String) {
        guard rawEvent.utf8.count <= 2_000_000,
              let data = rawEvent.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "agent-turn-complete",
              let threadID = event["thread-id"] as? String,
              let turnID = event["turn-id"] as? String else { return nil }
        self.init(threadID: threadID, turnID: turnID)
    }
}

struct CompletionNotice: Equatable {
    let id: UUID
    var deadline: Date
    var pausedRemaining: TimeInterval? = nil
    var count: Int
    var title: String

    var heading: String {
        count == 1 ? NSLocalizedString("completion.ready", comment: "Response ready")
            : String.localizedStringWithFormat(NSLocalizedString("completion.count", comment: "Ready response count"), count)
    }
    var accessibilitySummary: String { heading + ". " + title }
}

enum CompletionNoticeInteraction: Hashable {
    case hover, keyboardFocus, accessibilityFocus
}

enum CompletionVerification {
    case pending, rejected, completed(title: String)

    static func evaluate(hint: CompletionHint, thread: [String: Any], turns: [String: Any], since: Date, now: Date) -> Self {
        guard thread["id"] as? String == hint.threadID,
              thread["threadSource"] as? String == "user",
              thread["parentThreadId"] is NSNull,
              let data = turns["data"] as? [[String: Any]] else { return .rejected }
        guard let turn = data.first(where: { $0["id"] as? String == hint.turnID }) else { return .pending }
        switch turn["status"] as? String {
        case "inProgress": return .pending
        case "interrupted":
            // A separate App Server normalizes an unfinished persisted turn to interrupted.
            // notify can arrive before the terminal write; retry only this ambiguous shape.
            return (turn["completedAt"] == nil || turn["completedAt"] is NSNull)
                && (turn["error"] == nil || turn["error"] is NSNull) ? .pending : .rejected
        case "completed":
            guard turn["error"] == nil || turn["error"] is NSNull,
                  let completedAt = turn["completedAt"] as? NSNumber,
                  CFGetTypeID(completedAt) != CFBooleanGetTypeID() else { return .rejected }
            let date = Date(timeIntervalSince1970: completedAt.doubleValue)
            guard date >= since.addingTimeInterval(-1), date <= now.addingTimeInterval(1),
                  now.timeIntervalSince(date) <= 20 else { return .rejected }
            let name = (thread["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .completed(title: name.flatMap { !$0.isEmpty && $0.utf8.count <= 4096 ? $0 : nil } ?? "Codex")
        default: return .rejected
        }
    }
}

// The wrapper's only persistent data is the original command and its ownership token.
// Event content is forwarded unchanged, never saved or logged.
struct CompletionNotifyAdapter: Codable, Equatable {
    static let argument = "--black-hole-notify-v1"
    static let notification = Notification.Name("local.black-hole.response-ready.v1")
    let originalCommand: [String]?
    let token: String

    static func fingerprint(_ command: [String]) -> String {
        SHA256.hash(data: try! JSONEncoder().encode(command)).map { String(format: "%02x", $0) }.joined()
    }

    var encoded: String { (try! JSONEncoder().encode(self)).base64EncodedString() }
    func command(executable: String) -> [String] { [executable, Self.argument, encoded] }

    static func decode(_ value: String) -> Self? {
        guard value.utf8.count < 131_072, let data = Data(base64Encoded: value),
              let adapter = try? JSONDecoder().decode(Self.self, from: data),
              UUID(uuidString: adapter.token) != nil,
              adapter.originalCommand?.contains(argument) != true,
              adapter.originalCommand?.allSatisfy({ !$0.contains("\0") }) != false else { return nil }
        return adapter
    }

    // Called before SwiftUI creates AppDelegate or NSApplication. No launch/open API is used.
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == argument else { return nil }
        guard arguments.count == 4, let adapter = decode(arguments[2]) else { return 2 }
        let raw = arguments[3]
        _ = forward(adapter.originalCommand, rawEvent: raw)
        if let hint = CompletionHint(rawEvent: raw) {
            DistributedNotificationCenter.default().postNotificationName(
                notification, object: adapter.token,
                userInfo: ["thread": hint.threadID, "turn": hint.turnID,
                           "sentAt": Date().timeIntervalSince1970], deliverImmediately: true
            )
        }
        return 0
    }

    private static var defaultExecutablePath: String {
        let length = confstr(_CS_PATH, nil, 0)
        guard length > 0 else { return "/usr/bin:/bin" }
        var buffer = [CChar](repeating: 0, count: length)
        confstr(_CS_PATH, &buffer, length)
        return String(cString: buffer)
    }

    static func forward(_ command: [String]?, rawEvent: String) -> Process? {
        guard let command, let executable = command.first, !executable.isEmpty else { return nil }
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
        } else {
            process.executableURL = (ProcessInfo.processInfo.environment["PATH"] ?? defaultExecutablePath)
                .split(separator: ":", omittingEmptySubsequences: false)
                .map { URL(fileURLWithPath: $0.isEmpty ? FileManager.default.currentDirectoryPath : String($0)).appendingPathComponent(executable) }
                .first {
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                        && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: $0.path)
                }
        }
        guard process.executableURL != nil else { return nil }
        process.arguments = Array(command.dropFirst()) + [rawEvent]
        // Do not inherit a pipe into which a previous notifier might echo message content.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); return process } catch { return nil }
    }
}

struct CompletionConfigPlan {
    let parameters: [String: Any]
    let wrapper: [String]?

    static func make(response: [String: Any], enable: Bool, executable: String, ownedFingerprint: String?, token: String) throws -> Self {
        guard let layers = response["layers"] as? [[String: Any]], !layers.isEmpty else { throw CompletionError.configuration }
        var user: (file: String, version: String, config: [String: Any])?
        for layer in layers {
            guard let name = layer["name"] as? [String: Any], let type = name["type"] as? String,
                  let config = layer["config"] as? [String: Any] else { throw CompletionError.configuration }
            if layer["disabledReason"] as? String != nil { continue }
            // Only the selected profile changes the active user layer. Inactive definitions are harmless.
            if config["profile"] as? String != nil || name["profile"] as? String != nil { throw CompletionError.configuration }
            if type == "user" {
                guard user == nil, let file = name["file"] as? String, file.hasPrefix("/"),
                      let version = layer["version"] as? String, !version.isEmpty else { throw CompletionError.configuration }
                user = (file, version, config)
            } else if config["notify"] != nil { throw CompletionError.configuration }
        }
        guard let user else { throw CompletionError.configuration }
        let current: [String]?
        if let raw = user.config["notify"] {
            guard let command = raw as? [String], command.allSatisfy({ !$0.contains("\0") }) else { throw CompletionError.configuration }
            current = command
        } else { current = nil }
        let wrapper: [String]?
        let value: Any
        if enable {
            if let current, CompletionNotifyAdapter.fingerprint(current) == ownedFingerprint {
                guard current.count == 3, current[1] == CompletionNotifyAdapter.argument,
                      CompletionNotifyAdapter.decode(current[2]) != nil else { throw CompletionError.configuration }
                wrapper = current
            } else {
                guard current?.contains(CompletionNotifyAdapter.argument) != true else { throw CompletionError.configuration }
                wrapper = CompletionNotifyAdapter(originalCommand: current, token: token).command(executable: executable)
            }
            value = wrapper!
        } else {
            guard let current, CompletionNotifyAdapter.fingerprint(current) == ownedFingerprint, current.count == 3,
                  current[1] == CompletionNotifyAdapter.argument,
                  let adapter = CompletionNotifyAdapter.decode(current[2]) else { throw CompletionError.configuration }
            wrapper = nil
            value = adapter.originalCommand as Any? ?? NSNull()
        }
        if let wrapper {
            guard CompletionNotifyAdapter.decode(wrapper[2]) != nil else { throw CompletionError.configuration }
        }
        return Self(parameters: ["keyPath": "notify", "value": value, "mergeStrategy": "replace",
                                 "filePath": user.file, "expectedVersion": user.version], wrapper: wrapper)
    }
}

enum CompletionError: Error { case configuration, unavailable }
