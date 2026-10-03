// Standalone, headless checks. Run script/check_completion_notices.sh.
import AppKit
import SwiftUI
@testable import Black_Hole_Codex_Quota_Indicator

final class NoticeServer: CodexAppServerClient {
    var snapshot: ((QuotaSnapshot, Int?) -> Void)?
    var failure: ((String) -> Void)?
    var requests: [String] = []
    var turnStatus = "completed"
    var threadSource = "user"
    var title: String? = "Verified chat name"
    var completedAt: Date
    var turnSequence: [[String: Any]] = []
    var turnOverride: [String: Any]?
    var requestDelay: TimeInterval = 0
    var config: [String: Any]
    var writeStatus = "ok"
    var writes: [[String: Any]] = []

    init(date: Date, command: [String]? = nil) {
        completedAt = date
        config = Self.config(command)
    }
    static func config(_ command: [String]?) -> [String: Any] {
        var config: [String: Any] = ["model": "untouched", "profiles": ["unused": ["model": "other"]]]
        if let command { config["notify"] = command }
        return ["layers": [["name": ["type": "user", "file": "/tmp/synthetic-codex-config.toml"],
                            "version": "expected-version", "config": config]], "origins": [:], "config": [:]]
    }
    func start(onSnapshot: @escaping (QuotaSnapshot, Int?) -> Void, onSpeedMode: @escaping (SpeedMode) -> Void,
               onFailure: @escaping (String) -> Void) throws {
        snapshot = onSnapshot; failure = onFailure
        onSnapshot(QuotaSnapshot(limitId: "codex", limitName: nil, planType: nil,
                                 primary: QuotaWindow(usedPercent: 100, windowDurationMins: nil, resetsAt: nil), secondary: nil), nil)
    }
    func stop() {}
    func refreshRateLimits() {}
    @MainActor
    func request(method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        requests.append(method)
        if requestDelay > 0 { try await Task.sleep(for: .seconds(requestDelay)) }
        switch method {
        case "config/read": return config
        case "config/value/write":
            writes.append(params)
            if writeStatus == "ok" { config = Self.config(params["value"] as? [String]) }
            return ["status": writeStatus]
        case "thread/read":
            assert(params["includeTurns"] as? Bool == false)
            return ["thread": ["id": params["threadId"]!, "parentThreadId": NSNull(), "threadSource": threadSource,
                               "name": title as Any? ?? NSNull()]]
        case "thread/turns/list":
            assert(params["itemsView"] as? String == "notLoaded")
            assert(params["limit"] as? Int == 8 && params["sortDirection"] as? String == "desc")
            if !turnSequence.isEmpty { return ["data": [turnSequence.removeFirst()]] }
            if let turnOverride { return ["data": [turnOverride]] }
            return ["data": (1...30).map { turn($0) }]
        default: throw CompletionError.unavailable
        }
    }
    func turn(_ id: Int) -> [String: Any] {
        ["id": "turn-\(id)", "status": turnStatus, "completedAt": completedAt.timeIntervalSince1970,
         "error": NSNull(), "items": []]
    }
}

@MainActor
private final class CompletionIPCProbe {
    var keys: Set<String> = []
    var thread: String?
}

@main
struct CompletionNoticeChecks {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "--capture" {
            try JSONEncoder().encode(Array(args.dropFirst(3))).write(to: URL(fileURLWithPath: args[2]))
            return
        }
        if args.count >= 3, args[1] == "--preview" {
            try renderPreview(path: args[2]); return
        }
        try parserAndConfigChecks()
        try await nativeMenuTrackingChecks()
        try await persistenceRaceChecks()
        try await stateChecks()
        try await dismissalAndPauseChecks()
        try await configurationChecks()
        if args.count == 3, args[1] == "--app-executable" { try await forwardingChecks(app: args[2]) }
        print("PASS: completion parser, exact status/scope/freshness, config ownership, AppState lifecycle/count/dedup/dismiss/pause, forwarding")
    }

    static func parserAndConfigChecks() throws {
        let valid = "{\"type\":\"agent-turn-complete\",\"thread-id\":\"thread-1\",\"turn-id\":\"turn-1\",\"last-assistant-message\":\"ignored\"}"
        assert(CompletionHint(rawEvent: valid)?.key == "thread-1:turn-1")
        assert(CompletionHint(rawEvent: valid.replacingOccurrences(of: "agent-turn-complete", with: "tool-complete")) == nil)
        assert(CompletionHint(rawEvent: "{}") == nil)
        assert(CompletionHint(threadID: "\n", turnID: "id") == nil)
        assert(CompletionHint(threadID: String(repeating: "x", count: 129), turnID: "id") == nil)
        assert((try? CompletionConfigPlan.make(response: NoticeServer.config([String(repeating: "x", count: 131_072)]), enable: true,
                    executable: "/tmp/pet", ownedFingerprint: nil, token: UUID().uuidString)) == nil)
        assert((try? CompletionConfigPlan.make(response: NoticeServer.config(nil), enable: true,
                    executable: "/tmp/pet", ownedFingerprint: nil, token: "malformed")) == nil)
        let prior = ["/Applications/Synthetic Notifier.app/bin/helper", "a b;$(do-not-execute)", "--flag"]
        let token = UUID().uuidString
        let plan = try CompletionConfigPlan.make(response: NoticeServer.config(prior), enable: true, executable: "/tmp/pet",
                                                  ownedFingerprint: nil, token: token)
        let wrapper = plan.wrapper!
        assert(plan.parameters["expectedVersion"] as? String == "expected-version")
        assert(plan.parameters["keyPath"] as? String == "notify")
        assert(CompletionNotifyAdapter.decode(wrapper[2])?.originalCommand == prior)
        let restore = try CompletionConfigPlan.make(response: NoticeServer.config(wrapper), enable: false, executable: "/tmp/pet",
                    ownedFingerprint: CompletionNotifyAdapter.fingerprint(wrapper), token: token)
        assert(restore.parameters["value"] as? [String] == prior)
        let absent = try CompletionConfigPlan.make(response: NoticeServer.config(nil), enable: true, executable: "/tmp/pet", ownedFingerprint: nil, token: token)
        let remove = try CompletionConfigPlan.make(response: NoticeServer.config(absent.wrapper), enable: false, executable: "/tmp/pet",
                    ownedFingerprint: CompletionNotifyAdapter.fingerprint(absent.wrapper!), token: token)
        assert(remove.parameters["value"] is NSNull)
        assert((try? CompletionConfigPlan.make(response: NoticeServer.config(prior), enable: false, executable: "/tmp/pet",
                    ownedFingerprint: CompletionNotifyAdapter.fingerprint(wrapper), token: token)) == nil)
        var conflicting = NoticeServer.config(prior)
        var layers = conflicting["layers"] as! [[String: Any]]
        layers.append(["name": ["type": "sessionFlags"], "config": ["notify": ["override"]], "version": "another"])
        conflicting["layers"] = layers
        assert((try? CompletionConfigPlan.make(response: conflicting, enable: true, executable: "/tmp/pet", ownedFingerprint: nil, token: token)) == nil)
        layers.removeLast()
        layers[0]["name"] = ["type": "user", "file": "/tmp/profile.toml", "profile": "selected"]
        conflicting["layers"] = layers
        assert((try? CompletionConfigPlan.make(response: conflicting, enable: true, executable: "/tmp/pet", ownedFingerprint: nil, token: token)) == nil)

        let now = Date()
        let hint = CompletionHint(threadID: "thread-1", turnID: "turn-1")!
        var thread: [String: Any] = ["id": hint.threadID, "threadSource": "user", "parentThreadId": NSNull()]
        var turn: [String: Any] = ["id": hint.turnID, "status": "completed", "completedAt": now.timeIntervalSince1970, "error": NSNull()]
        func result() -> CompletionVerification { CompletionVerification.evaluate(hint: hint, thread: thread, turns: ["data": [turn]], since: now, now: now) }
        if case .completed(let name) = result() { assert(name == "Codex") } else { assertionFailure("Missing optional title/client/historyMode must work") }
        for state in ["interrupted", "failed", "notLoaded", "idle", "waitingForApproval"] {
            turn["status"] = state
            guard case .rejected = result() else { fatalError("Accepted \(state)") }
        }
        turn["status"] = "inProgress"
        guard case .pending = result() else { fatalError("Persistence lag must retry") }
        turn["status"] = "interrupted"
        for timestamp in [nil, NSNull()] as [Any?] {
            turn["completedAt"] = timestamp
            guard case .pending = result() else { fatalError("Undated normalized interruption must retry") }
            turn["error"] = ["message": "synthetic failure"]
            guard case .rejected = result() else { fatalError("Interrupted error must not retry") }
            turn["error"] = NSNull()
        }
        turn["completedAt"] = "invalid"
        guard case .rejected = result() else { fatalError("Malformed timestamp must not retry") }
        turn["completedAt"] = now.timeIntervalSince1970
        turn["status"] = "completed"
        for scope in ["automation", "unknown"] {
            thread["threadSource"] = scope
            guard case .rejected = result() else { fatalError("Accepted wrong source") }
        }
        thread["threadSource"] = "user"
        thread["parentThreadId"] = "parent"
        guard case .rejected = result() else { fatalError("Accepted child") }
        thread["parentThreadId"] = NSNull()
        turn["completedAt"] = now.addingTimeInterval(-120).timeIntervalSince1970
        guard case .rejected = result() else { fatalError("Accepted old turn") }
        turn["completedAt"] = NSNull()
        guard case .rejected = result() else { fatalError("Accepted unknown freshness") }
    }

    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        fatalError("Timed out waiting for check")
    }

    @MainActor static func makeState(server: NoticeServer, defaults: UserDefaults, now: @escaping () -> Date) -> AppState {
        AppState(defaults: defaults, appServer: server, retryDelays: [3600], launchAtLoginStatusProvider: { .notRegistered },
                 updateLaunchAtLogin: { _ in }, now: now, historyStore: QuotaHistoryStore(fileURL: nil), absorptionCatalog: nil)
    }

    @MainActor static func nativeMenuTrackingChecks() async throws {
        let suite = "local.black-hole.completion-menu-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppConstants.responseNoticesKey)
        let date = Date()
        let server = NoticeServer(date: date)
        let state = makeState(server: server, defaults: defaults, now: { date })
        let delegate = AppDelegate(appState: state)
        defer { delegate.stopCompletionMenuTracking(); state.stop() }
        state.start()
        try await wait { state.connectionState == .connected }
        state.setCompletionPresentationAllowed(true)
        var changes = 0
        state.responseNoticeDidChange = { changes += 1 }
        delegate.startCompletionMenuTracking()
        delegate.startCompletionMenuTracking() // Registration is idempotent.
        let root = NSMenu(), nested = NSMenu(), unknown = NSMenu()
        let center = NotificationCenter.default
        func post(_ name: Notification.Name, _ object: Any?) {
            center.post(name: name, object: object)
        }
        func send(_ id: Int) {
            state.receiveCompletionHint(CompletionHint(threadID: "menu-thread", turnID: "turn-\(id)")!, sentAt: date)
        }
        send(1)
        try await wait { state.completionNotice != nil }
        let firstChanges = changes
        post(NSMenu.didEndTrackingNotification, unknown)
        post(NSMenu.didBeginTrackingNotification, NSObject())
        assert(state.completionNotice != nil && changes == firstChanges)

        post(NSMenu.didBeginTrackingNotification, root)
        assert(state.completionNotice == nil && changes == firstChanges + 1)
        let openChanges = changes
        post(NSMenu.didBeginTrackingNotification, root)
        post(NSMenu.didBeginTrackingNotification, nested)
        post(NSMenu.didEndTrackingNotification, unknown)
        post(NSMenu.didEndTrackingNotification, root)
        assert(changes == openChanges) // Nested tracking still suppresses; duplicate/unknown events do not reset twice.
        let requests = server.requests.count
        send(10)
        try await Task.sleep(for: .milliseconds(30))
        assert(state.completionNotice == nil && server.requests.count == requests)
        post(NSMenu.didEndTrackingNotification, nested)
        assert(changes == openChanges + 1) // Closure is delivered synchronously, without a deferred Task.
        send(2)
        try await wait { state.completionNotice != nil }
        let closedChanges = changes
        post(NSMenu.didEndTrackingNotification, nested)
        assert(state.completionNotice != nil && changes == closedChanges)

        post(NSMenu.didBeginTrackingNotification, root)
        assert(state.completionNotice == nil)
        delegate.stopCompletionMenuTracking() // Teardown clears an open set and removes both observers.
        let stoppedChanges = changes
        delegate.stopCompletionMenuTracking()
        post(NSMenu.didBeginTrackingNotification, root)
        post(NSMenu.didEndTrackingNotification, root)
        assert(changes == stoppedChanges)
        send(3)
        try await wait { state.completionNotice != nil }
        assert(state.completionNotice?.count == 1)
        print("PASS: native menu notifications, synchronous nested/duplicate balance, closed delivery, idempotent teardown; no GUI")
    }

    @MainActor static func persistenceRaceChecks() async throws {
        let date = Date()
        let completed: [String: Any] = ["id": "turn-1", "status": "completed",
                                      "completedAt": date.timeIntervalSince1970, "error": NSNull()]
        let undated: [String: Any] = ["id": "turn-1", "status": "interrupted", "error": NSNull()]
        var nullDated = undated; nullDated["completedAt"] = NSNull()
        var cancelled = undated; cancelled["completedAt"] = date.timeIntervalSince1970
        var errored = undated; errored["error"] = ["message": "synthetic interruption"]
        var failed = undated; failed["status"] = "failed"
        for (initial, final, expectedReads) in [
            (undated, completed as [String: Any]?, 2), (nullDated, completed, 2),
            (cancelled, nil, 1), (errored, nil, 1), (failed, nil, 1), (nullDated, nil, 4)
        ] {
            let suite = "local.black-hole.completion-persistence-race.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: AppConstants.responseNoticesKey)
            let server = NoticeServer(date: date)
            server.turnOverride = final ?? initial
            if let final { server.turnSequence = [initial, final] }
            let state = makeState(server: server, defaults: defaults, now: { date })
            defer { state.stop() }
            state.start()
            try await wait { state.connectionState == .connected }
            state.setCompletionPresentationAllowed(true)
            let hint = CompletionHint(threadID: "race-thread", turnID: "turn-1")!
            state.receiveCompletionHint(hint, sentAt: date)
            try await wait { server.requests.contains("thread/turns/list") }
            assert(state.completionNotice == nil) // The intermediate status is never displayed.
            if final != nil {
                try await wait { state.completionNotice != nil }
                assert(state.completionNotice?.count == 1)
            } else if expectedReads == 4 {
                // The existing four attempts finish at 0, 0.3, 1.3 and 3.3 seconds.
                try await Task.sleep(for: .seconds(3.6))
            }
            try await Task.sleep(for: .milliseconds(400))
            let reads = server.requests.filter { $0 == "thread/turns/list" }.count
            assert(reads == expectedReads)
            assert(final != nil || state.completionNotice == nil)
            state.receiveCompletionHint(hint, sentAt: date)
            try await Task.sleep(for: .milliseconds(350))
            assert(server.requests.filter { $0 == "thread/turns/list" }.count == reads)
            assert(final == nil || state.completionNotice?.count == 1)
            state.stop()
        }
        print("PASS: normalized interruption retries to one completion; real cancellation/error rejects; unresolved persistence stops after four attempts")
    }

    @MainActor static func stateChecks() async throws {
        let suite = "local.black-hole.completion-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppConstants.responseNoticesKey)
        var date = Date()
        let server = NoticeServer(date: date)
        for placement: ContextMenuPlacement in [.aboveLeft, .aboveRight, .belowLeft, .belowRight] {
            let single = PixelContextMenuView.menuFrames(placement: placement, requiresRetry: true, openGroup: .behavior,
                requiresLoginApproval: true, hasLoginError: true)
            let both = PixelContextMenuView.menuFrames(placement: placement, requiresRetry: true, openGroup: .behavior,
                requiresLoginApproval: true, hasLoginError: true, hasCompletionError: true)
            assert(both.submenu!.height == single.submenu!.height + 31)
            assert(CGRect(origin: .zero, size: PixelContextMenuView.panelSize).contains(both.submenu!))
            for size in PetSize.allCases {
                let bounds = CGRect(x: 0, y: 0, width: 640, height: 480)
                let layout = PetPanelController.tooltipLayout(petFrame: CGRect(origin: .zero, size: size.sceneSize), visibleFrame: bounds,
                                                              tooltipSize: CompletionNoticeView.panelSize)
                assert(bounds.contains(CGRect(origin: layout.origin, size: layout.size)))
            }
        }
        let state = makeState(server: server, defaults: defaults, now: { date })
        state.start(); defer { state.stop() }
        try await wait { state.connectionState == .connected }
        state.setCompletionPresentationAllowed(true)
        func send(_ id: Int, timestamp: Date? = nil) { state.receiveCompletionHint(CompletionHint(threadID: "thread-1", turnID: "turn-\(id)")!, sentAt: timestamp ?? date) }
        send(1)
        try await wait { state.completionNotice != nil }
        let first = state.completionNotice!
        assert(first.count == 1 && first.title == "Verified chat name")
        let requests = server.requests.count
        send(1)
        assert(server.requests.count == requests)
        date.addTimeInterval(4); server.completedAt = date
        send(2); send(3)
        try await wait { state.completionNotice?.count == 3 }
        assert(state.completionNotice?.deadline == first.deadline && state.completionNotice?.id == first.id)
        state.setCompletionNativeMenuOpen(true)
        assert(state.completionNotice == nil)
        send(4)
        state.setCompletionNativeMenuOpen(false); send(4)
        try await Task.sleep(for: .milliseconds(30)); assert(state.completionNotice == nil)
        server.requestDelay = 0.08
        send(5)
        state.setCompletionPresentationAllowed(false)
        state.setCompletionPresentationAllowed(true)
        try await Task.sleep(for: .milliseconds(200)); assert(state.completionNotice == nil)
        server.requestDelay = 0
        send(6, timestamp: date.addingTimeInterval(-4))
        assert(state.completionNotice == nil)
        server.turnStatus = "interrupted"; send(7)
        try await Task.sleep(for: .milliseconds(30)); assert(state.completionNotice == nil)
        server.turnStatus = "completed"; server.title = nil
        send(8); try await wait { state.completionNotice != nil }
        assert(state.completionNotice?.title == "Codex")
        state.setCompletionSleeping(true); assert(state.completionNotice == nil)
        send(9); state.setCompletionSleeping(false); send(9)
        assert(state.completionNotice == nil)
        send(10); try await wait { state.completionNotice != nil }
        server.failure?("synthetic disconnect")
        try await wait { state.connectionState == .reconnecting }
        assert(state.completionNotice == nil)
        state.retryNow(); try await wait { state.connectionState == .connected }
        send(10); assert(state.completionNotice == nil)
        send(11); try await wait { state.completionNotice != nil }
        state.togglePetVisibility(); assert(state.completionNotice == nil)
        send(12); state.togglePetVisibility(); send(12); assert(state.completionNotice == nil)
        send(13); try await wait { state.completionNotice != nil }
        try await Task.sleep(for: .seconds(8.1)); try await wait { state.completionNotice == nil }
        state.beginTermination()
        state.cancelTermination()
        try await wait { state.connectionState == .connected }
        send(14); try await wait { state.completionNotice != nil }
        assert(state.quota?.primary?.remainingPercent == 0 && state.connectionState == .connected)
    }

    @MainActor static func dismissalAndPauseChecks() async throws {
        let suite = "local.black-hole.completion-dismiss-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppConstants.responseNoticesKey)
        var date = Date()
        let server = NoticeServer(date: date)
        let state = makeState(server: server, defaults: defaults, now: { date })
        state.start(); defer { state.stop() }
        try await wait { state.connectionState == .connected }
        state.setCompletionPresentationAllowed(true)
        func send(_ id: Int) {
            server.completedAt = date
            state.receiveCompletionHint(CompletionHint(threadID: "pause-thread", turnID: "turn-\(id)")!, sentAt: date)
        }
        send(1); try await wait { state.completionNotice != nil }
        let originalID = state.completionNotice!.id
        let originalDeadline = state.completionNotice!.deadline
        date.addTimeInterval(2)
        state.setCompletionInteraction(.hover, active: true, id: originalID)
        assert(state.completionNotice?.pausedRemaining == 6)
        state.setCompletionInteraction(.keyboardFocus, active: true, id: originalID)
        state.setCompletionInteraction(.accessibilityFocus, active: true, id: originalID)
        date.addTimeInterval(100)
        send(2); try await wait { state.completionNotice?.count == 2 }
        assert(state.completionNotice?.id == originalID && state.completionNotice?.deadline == originalDeadline)
        assert(state.completionNotice?.pausedRemaining == 6)
        // Let the actual original timer deadline pass while interaction holds the card open.
        try await Task.sleep(for: .seconds(8.1))
        assert(state.completionNotice?.id == originalID)
        state.setCompletionInteraction(.hover, active: false, id: originalID)
        assert(state.completionNotice?.pausedRemaining == 6)
        state.setCompletionInteraction(.keyboardFocus, active: false, id: originalID)
        assert(state.completionNotice?.pausedRemaining == 6)
        state.setCompletionInteraction(.accessibilityFocus, active: false, id: originalID)
        assert(state.completionNotice?.pausedRemaining == nil)
        assert(state.completionNotice?.deadline == date.addingTimeInterval(6))
        let resumedDeadline = state.completionNotice!.deadline
        send(3); try await wait { state.completionNotice?.count == 3 }
        assert(state.completionNotice?.deadline == resumedDeadline)
        date.addTimeInterval(2)
        state.setCompletionInteraction(.hover, active: true, id: originalID)
        assert(state.completionNotice?.pausedRemaining == 4)

        server.requestDelay = 0.08
        send(4)
        try await Task.sleep(for: .milliseconds(20))
        state.dismissCompletionNotice(id: originalID)
        assert(state.completionNotice == nil)
        try await Task.sleep(for: .milliseconds(200))
        assert(state.completionNotice == nil)
        server.requestDelay = 0
        let requestCount = server.requests.count
        send(1); send(4)
        assert(state.completionNotice == nil && server.requests.count == requestCount)
        send(5); try await wait { state.completionNotice != nil }
        let nextID = state.completionNotice!.id
        assert(nextID != originalID)
        state.setCompletionInteraction(.hover, active: true, id: nextID)
        state.dismissCompletionNotice(id: originalID)
        state.setCompletionInteraction(.hover, active: false, id: originalID)
        state.setCompletionInteraction(.accessibilityFocus, active: true, id: originalID)
        assert(state.completionNotice?.id == nextID && state.completionNotice?.pausedRemaining == 8)
        state.setCompletionInteraction(.hover, active: false, id: nextID)
        date.addTimeInterval(7.8)
        state.setCompletionInteraction(.keyboardFocus, active: true, id: nextID)
        assert(abs(state.completionNotice!.pausedRemaining! - 0.2) < 0.001)
        state.setCompletionInteraction(.keyboardFocus, active: false, id: nextID)
        try await wait { state.completionNotice == nil }
        assert(state.responseNoticesEnabled && state.connectionState == .connected)

        let card = CGRect(origin: .zero, size: CompletionNoticeView.panelSize)
            .insetBy(dx: CompletionNoticeView.cardInset, dy: CompletionNoticeView.cardInset)
        let target = CGRect(x: card.maxX - CompletionNoticeView.closeButtonInset - CompletionNoticeView.closeButtonSize,
                            y: card.minY + CompletionNoticeView.closeButtonInset,
                            width: CompletionNoticeView.closeButtonSize, height: CompletionNoticeView.closeButtonSize)
        assert(target.width == 28 && target.height == 28 && card.contains(target))
        assert(card.maxX - target.maxX == 8 && target.minY - card.minY == 8)
        for (language, expected) in [("ru", "Закрыть уведомление"), ("en", "Dismiss notification")] {
            let bundle = Bundle(url: Bundle.main.url(forResource: language, withExtension: "lproj")!)!
            assert(bundle.localizedString(forKey: "completion.dismiss", value: nil, table: nil) == expected)
        }
    }

    @MainActor static func configurationChecks() async throws {
        let suite = "local.black-hole.completion-config-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = ["/tmp/original-notifier", "literal argument"]
        let server = NoticeServer(date: Date(), command: original)
        let state = makeState(server: server, defaults: defaults, now: Date.init)
        state.start(); defer { state.stop() }
        try await wait { state.connectionState == .connected }
        assert(!state.responseNoticesEnabled && server.writes.isEmpty)
        state.setResponseNoticesEnabled(true)
        try await wait { !state.responseNoticeConfigurationBusy }
        assert(state.responseNoticesEnabled && state.responseNoticeIssue == nil)
        assert(CompletionNotifyAdapter.decode((server.writes[0]["value"] as! [String])[2])?.originalCommand == original)
        let stored = defaults.persistentDomain(forName: suite)!
        assert(!String(describing: stored).contains("original-notifier"))
        state.setResponseNoticesEnabled(false)
        try await wait { !state.responseNoticeConfigurationBusy }
        assert(!state.responseNoticesEnabled && server.writes.last?["value"] as? [String] == original)
        server.writeStatus = "okOverridden"
        state.setResponseNoticesEnabled(true)
        try await wait { !state.responseNoticeConfigurationBusy }
        assert(!state.responseNoticesEnabled && state.responseNoticeIssue != nil)
        assert(state.connectionState == .connected)
    }

    @MainActor static func forwardingChecks(app: String) async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("completion-forward-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let ipcToken = UUID().uuidString
        let ipc = CompletionIPCProbe()
        let observer = DistributedNotificationCenter.default().addObserver(forName: CompletionNotifyAdapter.notification,
                      object: ipcToken, queue: .main) { notification in
            let keys = Set(notification.userInfo?.keys.compactMap { $0 as? String } ?? [])
            let thread = notification.userInfo?["thread"] as? String
            Task { @MainActor in ipc.keys = keys; ipc.thread = thread }
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }
        let shadow = temporary.appendingPathComponent("shadow/synthetic-notifier")
        let real = temporary.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: shadow, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: real.appendingPathComponent("synthetic-notifier"), withDestinationURL: URL(fileURLWithPath: CommandLine.arguments[0]))
        for (index, raw) in ["not-json", "{\"type\":\"different-event\",\"text\":\"a b;$(literal)\"}",
                              "{\"type\":\"agent-turn-complete\",\"thread-id\":\"synthetic-thread\",\"turn-id\":\"synthetic-turn\"}", "bare-path-command"].enumerated() {
            let output = temporary.appendingPathComponent("\(index).json")
            let original = [index == 3 ? "synthetic-notifier" : CommandLine.arguments[0], "--capture", output.path, "prior argument with spaces"]
            let wrapper = CompletionNotifyAdapter(originalCommand: original, token: ipcToken)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: app)
            process.arguments = [CompletionNotifyAdapter.argument, wrapper.encoded, raw]
            if index == 3 {
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = shadow.deletingLastPathComponent().path + ":" + real.path
                process.environment = environment
            }
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); assert(process.terminationStatus == 0)
            try await wait { FileManager.default.fileExists(atPath: output.path) }
            let received = try JSONDecoder().decode([String].self, from: Data(contentsOf: output))
            assert(received == ["prior argument with spaces", raw])
            if index == 2 {
                try await wait { ipc.thread != nil }
                assert(ipc.keys == Set(["thread", "turn", "sentAt"]))
                assert(ipc.thread == "synthetic-thread")
            }
        }
    }

    @MainActor static func renderPreview(path: String) throws {
        let view = VStack(alignment: .leading, spacing: 12) {
            ForEach([TooltipStyle.smooth, .pixel], id: \.self) { style in
                Text(style.rawValue.capitalized).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                CompletionNoticeView(notice: CompletionNotice(id: UUID(), deadline: Date(), count: style == .smooth ? 1 : 3,
                                                               title: "Исправление авторизации в приложении"), style: style)
                    .frame(width: CompletionNoticeView.panelSize.width, height: CompletionNoticeView.panelSize.height)
            }
        }.padding(24).background(Color(white: 0.12)).environment(\.colorScheme, .dark)
        // ImageRenderer omits native focus/accessibility wrappers. Rasterize the actual
        // hosting view offscreen instead; no window, App.main or AppDelegate is created.
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            fatalError("Offscreen bitmap allocation failed")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Offscreen rendering failed") }
        try data.write(to: URL(fileURLWithPath: path))
        print("Preview: \(path)")
    }
}
