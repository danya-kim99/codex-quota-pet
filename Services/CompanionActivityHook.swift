import CoreFoundation
import Darwin
import Foundation

struct CompanionHookHint: Equatable {
    enum Event: String, CaseIterable {
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case permissionRequest = "PermissionRequest"
        case stop = "Stop"
        case subagentStop = "SubagentStop"
        case interrupt = "Interrupt"
        case sessionEnd = "SessionEnd"
    }

    let id: UUID
    let event: Event
    let sessionID: String
    let turnID: String?
    let startedAt: Date
    var key: String { sessionID + ":" + (turnID ?? "") }

    init?(event: Event, sessionID: String, turnID: String?, startedAt: Date, id: UUID = UUID()) {
        let validID: (String) -> Bool = { value in
            !value.isEmpty && value.utf8.count <= 128
                && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0)
                    || (97...122).contains($0) || $0 == 45 || $0 == 95 }
        }
        guard validID(sessionID), startedAt.timeIntervalSince1970.isFinite,
              event == .sessionEnd || turnID.map(validID) == true else { return nil }
        self.id = id
        self.event = event
        self.sessionID = sessionID
        self.turnID = event == .sessionEnd ? nil : turnID
        self.startedAt = startedAt
    }

    init?(data: Data, startedAt: Date) {
        guard data.count <= CompanionActivityHook.maximumInputBytes,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = payload["hook_event_name"] as? String, let event = Event(rawValue: raw),
              let session = payload["session_id"] as? String else { return nil }
        self.init(event: event, sessionID: session, turnID: payload["turn_id"] as? String, startedAt: startedAt)
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard Set(userInfo.keys.compactMap { $0 as? String }).isSubset(of: ["id", "event", "session", "turn", "startedAt"]),
              let id = userInfo["id"] as? String, let uuid = UUID(uuidString: id),
              let raw = userInfo["event"] as? String, let event = Event(rawValue: raw),
              let session = userInfo["session"] as? String,
              let timestamp = userInfo["startedAt"] as? NSNumber,
              CFGetTypeID(timestamp) != CFBooleanGetTypeID() else { return nil }
        self.init(event: event, sessionID: session, turnID: userInfo["turn"] as? String,
                  startedAt: Date(timeIntervalSince1970: timestamp.doubleValue), id: uuid)
    }

    var userInfo: [String: Any] {
        var value: [String: Any] = ["id": id.uuidString, "event": event.rawValue, "session": sessionID,
                                  "startedAt": startedAt.timeIntervalSince1970]
        if let turnID { value["turn"] = turnID }
        return value
    }
}

enum CompanionActivityHook {
    static let argument = "--black-hole-activity-hook-v1"
    static let environmentKey = "BLACK_HOLE_COMPANION_HOOK_TOKEN"
    static let notification = Notification.Name("local.black-hole.experimental-companion-activity.v1")
    static let maximumInputBytes = 65_536

    static func token(_ value: String?) -> String? {
        value.flatMap(UUID.init(uuidString:))?.uuidString
    }

    // Invoked before App.main/AppDelegate. No app, window, config or transcript is opened.
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard arguments.dropFirst().first == argument else { return nil }
        let startedAt = Date()
        defer { try? FileHandle.standardOutput.write(contentsOf: Data("{}\n".utf8)) }
        guard arguments.count == 2,
              let token = token(ProcessInfo.processInfo.environment[environmentKey]),
              let data = readBoundedInput(), let hint = CompanionHookHint(data: data, startedAt: startedAt) else { return 0 }
        DistributedNotificationCenter.default().postNotificationName(
            notification, object: token, userInfo: hint.userInfo, deliverImmediately: true
        )
        return 0
    }

    private static func readBoundedInput() -> Data? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while ProcessInfo.processInfo.systemUptime < deadline {
            var input = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&input, 1, 25)
            if result == 0 { continue }
            if result < 0 { if errno == EINTR { continue }; return nil }
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 { if errno == EINTR { continue }; return nil }
            guard data.count + count <= maximumInputBytes else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        return nil
    }
}

/// Approximate, ephemeral hook state. It never upgrades a timeout into proof of completion.
struct CompanionHookTracker {
    static let timeToLive: TimeInterval = 10 * 60
    static let maximumHintAge: TimeInterval = 10
    static let maximumTurns = 128
    private struct Turn {
        var activity: CompanionActivity
        var lastEvent: Date
        var lastPositive: Date
    }
    private var turns: [String: Turn] = [:]
    private var stoppedTurns: [String: Date] = [:]
    private var endedSessions: [String: Date] = [:]
    private var seen: [UUID] = []
    private var saturated = false
    private(set) var acceptSince: Date
    private(set) var activity: CompanionActivity = .unavailable

    init(acceptSince: Date) { self.acceptSince = acceptSince }
    var nextExpiry: Date? { turns.values.map { $0.lastPositive.addingTimeInterval(Self.timeToLive) }.min() }

    mutating func reset(at date: Date) { self = Self(acceptSince: date) }

    mutating func receive(_ hint: CompanionHookHint, now: Date) {
        expire(at: now)
        guard !saturated, hint.startedAt >= acceptSince, hint.startedAt <= now.addingTimeInterval(1),
              now.timeIntervalSince(hint.startedAt) <= Self.maximumHintAge,
              !seen.contains(hint.id) else { return }
        seen.append(hint.id)
        if seen.count > 512 { seen.removeFirst(seen.count - 512) }
        if let cutoff = endedSessions[hint.sessionID], hint.startedAt <= cutoff { return }
        if hint.event == .sessionEnd {
            endedSessions[hint.sessionID] = hint.startedAt
            turns = turns.filter { !$0.key.hasPrefix(hint.sessionID + ":") || $0.value.lastEvent > hint.startedAt }
            aggregate(empty: .idle)
        } else {
            guard stoppedTurns[hint.key] == nil else { return }
            if let turn = turns[hint.key], hint.startedAt <= turn.lastEvent { return }
            switch hint.event {
            case .userPromptSubmit, .preToolUse, .postToolUse:
                turns[hint.key] = Turn(activity: .working, lastEvent: hint.startedAt, lastPositive: hint.startedAt)
            case .permissionRequest:
                guard var turn = turns[hint.key] else { return }
                turn.activity = .waiting
                turn.lastEvent = hint.startedAt
                turns[hint.key] = turn // Permission prompts do not extend the positive-hint TTL.
            case .stop, .subagentStop, .interrupt:
                stoppedTurns[hint.key] = hint.startedAt
                turns.removeValue(forKey: hint.key)
            case .sessionEnd: break
            }
            aggregate(empty: .idle)
        }
        // Fail closed on overload rather than evicting a live turn or terminal tombstone.
        if turns.count > Self.maximumTurns || stoppedTurns.count > 512 || endedSessions.count > 128 {
            reset(at: now)
            saturated = true
        }
    }

    mutating func expire(at date: Date) {
        let previousCount = turns.count
        turns = turns.filter { date.timeIntervalSince($0.value.lastPositive) < Self.timeToLive }
        stoppedTurns = stoppedTurns.filter { date.timeIntervalSince($0.value) < Self.timeToLive }
        endedSessions = endedSessions.filter { date.timeIntervalSince($0.value) < Self.timeToLive }
        if turns.count != previousCount { aggregate(empty: .unavailable) }
    }

    private mutating func aggregate(empty: CompanionActivity) {
        activity = turns.values.contains { $0.activity == .working } ? .working
            : turns.isEmpty ? empty : .waiting
    }
}
