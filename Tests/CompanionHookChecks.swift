// Standalone headless checks; no NSApplication, window, real config or user data.
import Foundation
@testable import Black_Hole_Codex_Quota_Indicator

private final class HookCheckServer: CodexAppServerClient {
    var failure: ((String) -> Void)?
    func start(onSnapshot: @escaping (QuotaSnapshot, Int?) -> Void, onSpeedMode: @escaping (SpeedMode) -> Void,
               onFailure: @escaping (String) -> Void) throws {
        failure = onFailure
        onSnapshot(QuotaSnapshot(limitId: "codex", limitName: nil, planType: nil,
            primary: QuotaWindow(usedPercent: 50, windowDurationMins: nil, resetsAt: nil), secondary: nil), nil)
    }
    func stop() {}
    func refreshRateLimits() {}
}

@MainActor private final class HookProbe {
    var events: [CompanionHookHint] = []
    var keys = Set<String>()
}

@main struct CompanionHookChecks {
    @MainActor static func main() async throws {
        try parserChecks()
        trackerChecks()
        try await stateChecks()
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--app-executable" else {
            fatalError("Pass the actual built app executable")
        }
        try await helperChecks(app: CommandLine.arguments[2])
        print("PASS: companion hook parser/privacy, bounded tracker/order/dedup/tombstones/TTL, AppState lifecycle/default-off, actual helper→DNC→AppState, fail-open stdin/output")
    }

    static func payload(_ event: CompanionHookHint.Event, session: String = "session-1", turn: String? = "turn-1") throws -> Data {
        var json: [String: Any] = ["hook_event_name": event.rawValue, "session_id": session,
            "prompt": "SYNTHETIC-PRIVATE-MARKER", "tool_input": ["data": "SYNTHETIC-PRIVATE-MARKER"],
            "tool_response": "SYNTHETIC-PRIVATE-MARKER", "transcript_path": "/never/read/this/path"]
        if let turn { json["turn_id"] = turn }
        return try JSONSerialization.data(withJSONObject: json)
    }

    static func parserChecks() throws {
        let now = Date()
        for event in CompanionHookHint.Event.allCases {
            let hint = CompanionHookHint(data: try payload(event, turn: event == .sessionEnd ? nil : "turn-1"), startedAt: now)!
            assert(hint.event == event && hint.sessionID == "session-1" && hint.startedAt == now)
            assert(hint.turnID == (event == .sessionEnd ? nil : "turn-1"))
            let decoded = CompanionHookHint(userInfo: hint.userInfo)!
            assert(decoded.id == hint.id && decoded.event == hint.event
                && decoded.sessionID == hint.sessionID && decoded.turnID == hint.turnID)
            assert(abs(decoded.startedAt.timeIntervalSince(hint.startedAt)) < 0.000_001)
            let forwarded = try JSONSerialization.data(withJSONObject: hint.userInfo)
            assert(!String(decoding: forwarded, as: UTF8.self).contains("SYNTHETIC-PRIVATE-MARKER"))
            assert(Set(hint.userInfo.keys).isSubset(of: ["id", "event", "session", "turn", "startedAt"]))
        }
        for raw in ["", "{}", "[]", "not-json", "{\"hook_event_name\":\"Unknown\",\"session_id\":\"s\",\"turn_id\":\"t\"}"] {
            assert(CompanionHookHint(data: Data(raw.utf8), startedAt: now) == nil)
        }
        assert(CompanionHookHint(data: Data(repeating: 32, count: CompanionActivityHook.maximumInputBytes + 1), startedAt: now) == nil)
        assert(CompanionHookHint(event: .stop, sessionID: "s", turnID: nil, startedAt: now) == nil)
        assert(CompanionHookHint(event: .stop, sessionID: "s/../private", turnID: "t", startedAt: now) == nil)
        assert(CompanionHookHint(event: .stop, sessionID: "s", turnID: String(repeating: "t", count: 129), startedAt: now) == nil)
        assert(CompanionActivityHook.token(nil) == nil && CompanionActivityHook.token("invalid") == nil)
        assert(CompanionActivityHook.token(UUID().uuidString.lowercased()) != nil)
        var injected = CompanionHookHint(data: try payload(.stop), startedAt: now)!.userInfo
        injected["prompt"] = "do not accept extras"
        assert(CompanionHookHint(userInfo: injected) == nil)
    }

    static func hint(_ event: CompanionHookHint.Event, _ time: Double, session: String = "root", turn: String = "one", id: UUID = UUID()) -> CompanionHookHint {
        CompanionHookHint(event: event, sessionID: session, turnID: turn, startedAt: Date(timeIntervalSince1970: time), id: id)!
    }

    static func trackerChecks() {
        var tracker = CompanionHookTracker(acceptSince: Date(timeIntervalSince1970: 100))
        func send(_ event: CompanionHookHint.Event, _ time: Double, session: String = "root", turn: String = "one") {
            tracker.receive(hint(event, time, session: session, turn: turn), now: Date(timeIntervalSince1970: time))
        }
        send(.permissionRequest, 101)
        assert(tracker.activity == .unavailable)
        let duplicate = hint(.userPromptSubmit, 102)
        tracker.receive(duplicate, now: duplicate.startedAt)
        send(.permissionRequest, 103)
        assert(tracker.activity == .waiting && tracker.nextExpiry == Date(timeIntervalSince1970: 702))
        tracker.receive(duplicate, now: Date(timeIntervalSince1970: 103))
        tracker.receive(hint(.postToolUse, 102.5), now: Date(timeIntervalSince1970: 104))
        assert(tracker.activity == .waiting)
        send(.preToolUse, 104, session: "child")
        assert(tracker.activity == .working)
        send(.subagentStop, 105, session: "child")
        assert(tracker.activity == .waiting)
        send(.postToolUse, 106, session: "child")
        assert(tracker.activity == .waiting) // terminal child cannot revive from a late tool hook
        send(.stop, 107)
        assert(tracker.activity == .idle)
        send(.userPromptSubmit, 108)
        assert(tracker.activity == .idle) // intentionally conservative same-turn continuation
        send(.preToolUse, 109, turn: "two")
        send(.preToolUse, 110, turn: "three")
        send(.interrupt, 111, turn: "two")
        assert(tracker.activity == .working)
        send(.sessionEnd, 112)
        assert(tracker.activity == .idle)
        tracker.receive(hint(.postToolUse, 111.5, turn: "three"), now: Date(timeIntervalSince1970: 113))
        assert(tracker.activity == .idle)
        send(.userPromptSubmit, 114, turn: "four")
        send(.permissionRequest, 200, turn: "four")
        tracker.expire(at: Date(timeIntervalSince1970: 713.9))
        assert(tracker.activity == .waiting)
        tracker.expire(at: Date(timeIntervalSince1970: 714))
        assert(tracker.activity == .unavailable && tracker.nextExpiry == nil)
        tracker.reset(at: Date(timeIntervalSince1970: 800))
        tracker.receive(hint(.preToolUse, 799), now: Date(timeIntervalSince1970: 801))
        tracker.receive(hint(.preToolUse, 900), now: Date(timeIntervalSince1970: 801))
        tracker.receive(hint(.preToolUse, 801), now: Date(timeIntervalSince1970: 820))
        assert(tracker.activity == .unavailable)
        send(.preToolUse, 821)
        tracker.expire(at: Date(timeIntervalSince1970: 1421))
        assert(tracker.activity == .unavailable) // missing failure/terminal hook never means completed
        tracker.reset(at: Date(timeIntervalSince1970: 1500))
        for number in 0...CompanionHookTracker.maximumTurns { send(.preToolUse, 1501, turn: "turn-\(number)") }
        assert(tracker.activity == .unavailable)
        send(.preToolUse, 1502, turn: "after-overload")
        assert(tracker.activity == .unavailable)
        tracker.reset(at: Date(timeIntervalSince1970: 1503))
        send(.preToolUse, 1504)
        assert(tracker.activity == .working)
        print("PASS: tracker multi-turn/subagent stop, waiting TTL, missing failure expiry, duplicate/reordered/stale events, overload and epoch reset")
    }

    @MainActor static func stateChecks() async throws {
        var date = Date(timeIntervalSince1970: 2000)
        let suite = "local.black-hole.hook-state-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for token in [nil, "invalid"] as [String?] {
            let state = makeState(defaults: defaults, token: token, now: { date })
            state.start(); state.setCompanionPanelVisible(true)
            try await wait { state.connectionState == .connected }
            date.addTimeInterval(1)
            state.receiveCompanionHook(hint(.preToolUse, date.timeIntervalSince1970))
            assert(state.companionActivity == .unavailable)
            state.stop()
        }
        let server = HookCheckServer()
        let state = makeState(defaults: defaults, token: UUID().uuidString, server: server, now: { date })
        state.start()
        try await wait { state.connectionState == .connected }
        date.addTimeInterval(1)
        state.receiveCompanionHook(hint(.preToolUse, date.timeIntervalSince1970))
        assert(state.companionActivity == .unavailable) // actual panel visibility, not only the manual preference
        state.setCompanionPanelVisible(true)
        func startTurn(_ turn: String = "one") {
            date.addTimeInterval(1)
            state.receiveCompanionHook(hint(.preToolUse, date.timeIntervalSince1970, turn: turn))
            assert(state.companionActivity == .working)
        }
        startTurn()
        let old = hint(.postToolUse, date.timeIntervalSince1970)
        for reset in [
            { state.setCompanionPanelVisible(false); state.setCompanionPanelVisible(true) },
            { state.setCompletionSleeping(true); state.setCompletionSleeping(false) },
            { state.resetAbsorptionScene() },
            { state.togglePetVisibility(); state.togglePetVisibility() }
        ] {
            date.addTimeInterval(1); reset()
            assert(state.companionActivity == .unavailable)
            state.receiveCompanionHook(old)
            assert(state.companionActivity == .unavailable)
            startTurn()
        }
        date.addTimeInterval(600)
        state.expireCompanionActivity()
        assert(state.companionActivity == .unavailable)
        startTurn("expiry-recovery")
        date.addTimeInterval(1)
        server.failure?("synthetic disconnect")
        try await wait { state.connectionState == .reconnecting }
        assert(state.companionActivity == .unavailable)
        state.retryNow()
        try await wait { state.connectionState == .connected }
        assert(state.companionActivity == .unavailable)
        startTurn("reconnect")
        date.addTimeInterval(1)
        state.beginTermination()
        assert(state.companionActivity == .unavailable)
        state.cancelTermination()
        try await wait { state.connectionState == .connected }
        assert(state.companionActivity == .unavailable)
        startTurn("cancel-termination")
        state.stop()
        assert(state.companionActivity == .unavailable)
        assert(defaults.object(forKey: "companionActivity") == nil)
    }

    @MainActor private static func makeState(defaults: UserDefaults, token: String?, server: HookCheckServer = HookCheckServer(), now: @escaping () -> Date = Date.init) -> AppState {
        AppState(defaults: defaults, appServer: server, retryDelays: [1000], launchAtLoginStatusProvider: { .notRegistered },
            updateLaunchAtLogin: { _ in fatalError("No real preferences") }, now: now,
            historyStore: QuotaHistoryStore(fileURL: nil), absorptionCatalog: nil, companionExperimentToken: token)
    }

    @MainActor static func helperChecks(app: String) async throws {
        let token = UUID().uuidString
        let probe = HookProbe()
        let observer = DistributedNotificationCenter.default().addObserver(forName: CompanionActivityHook.notification, object: token, queue: .main) { notification in
            let keys = Set(notification.userInfo?.keys.compactMap { $0 as? String } ?? [])
            guard let info = notification.userInfo, let hint = CompanionHookHint(userInfo: info) else { return }
            Task { @MainActor in probe.events.append(hint); probe.keys.formUnion(keys) }
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }
        let suite = "local.black-hole.hook-ipc-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = makeState(defaults: defaults, token: token)
        defer { state.stop() }
        state.start(); state.setCompanionPanelVisible(true)
        try await wait { state.connectionState == .connected }
        let sequence: [(CompanionHookHint.Event, String, CompanionActivity)] = [
            (.userPromptSubmit, "root", .working), (.preToolUse, "child", .working),
            (.permissionRequest, "root", .working), (.subagentStop, "child", .waiting),
            (.postToolUse, "root", .working), (.stop, "root", .idle),
            (.preToolUse, "root", .idle), (.interrupt, "root", .idle), (.sessionEnd, "root", .idle)
        ]
        for (index, item) in sequence.enumerated() {
            let before = Date()
            try runHelper(app: app, token: token, data: payload(item.0, session: item.1))
            try await wait { probe.events.count == index + 1 && state.companionActivity == item.2 }
            assert(probe.events.last!.startedAt >= before && probe.events.last!.startedAt <= Date())
        }
        assert(probe.keys == Set(["id", "event", "session", "turn", "startedAt"]))
        let count = probe.events.count
        for raw in [Data("broken".utf8), Data("{}".utf8), Data(repeating: 65, count: 70_000)] {
            try runHelper(app: app, token: token, data: raw)
        }
        try runHelper(app: app, token: nil, data: payload(.preToolUse))
        try runHelper(app: app, token: "invalid", data: payload(.preToolUse))
        try runHelper(app: app, token: token, data: Data("{".utf8), leaveInputOpen: true)
        try await Task.sleep(for: .milliseconds(100))
        assert(probe.events.count == count)
        print("PASS: real executable→DNC→AppState, all eight event names, no sensitive fields, malformed/oversized/missing-token/unterminated input returns {} and exit0")
    }

    static func runHelper(app: String, token: String?, data: Data, leaveInputOpen: Bool = false) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-hook-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        let input = try FileHandle(forReadingFrom: temporary)
        defer { try? input.close() }
        let pending = Pipe()
        let output = Pipe(), errors = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: app)
        process.arguments = [CompanionActivityHook.argument]
        var environment = ProcessInfo.processInfo.environment
        environment[CompanionActivityHook.environmentKey] = token
        process.environment = environment
        process.standardInput = leaveInputOpen ? pending : input
        process.standardOutput = output
        process.standardError = errors
        let began = ProcessInfo.processInfo.systemUptime
        try process.run()
        if leaveInputOpen { try pending.fileHandleForWriting.write(contentsOf: data) }
        process.waitUntilExit()
        assert(ProcessInfo.processInfo.systemUptime - began < 3)
        try? pending.fileHandleForWriting.close()
        assert(process.terminationStatus == 0)
        assert(output.fileHandleForReading.readDataToEndOfFile() == Data("{}\n".utf8))
        assert(errors.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Timed out waiting for headless IPC/state check")
    }
}
