import AppKit
import CryptoKit
import Sparkle
import XCTest
@testable import Black_Hole_Codex_Quota_Indicator

final class AppUpdateTests: XCTestCase {
    func testConfigurationRequiresRealKeyAndEverySecuritySetting() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Support/Info.plist")
        var info = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(contentsOf: source), format: nil
        ) as? [String: Any])
        XCTAssertFalse(AppUpdateConfiguration.isValid(info))
        info["SUPublicEDKey"] = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertTrue(AppUpdateConfiguration.isValid(info))
        for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableAutomaticChecks",
                    "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling", "SUEnableJavaScript"] {
            var invalid = info
            invalid[key] = !(info[key] as! Bool)
            XCTAssertFalse(AppUpdateConfiguration.isValid(invalid), key)
        }
        var invalid = info
        invalid["SUFeedURL"] = "https://example.com/appcast.xml"
        XCTAssertFalse(AppUpdateConfiguration.isValid(invalid))
        invalid = info
        invalid["SUPublicEDKey"] = Data(repeating: 0, count: 32).base64EncodedString()
        XCTAssertFalse(AppUpdateConfiguration.isValid(invalid))
        for expiry: Any in [0.5, true, "0"] {
            invalid = info
            invalid["SUSignedFeedFailureExpirationInterval"] = expiry
            XCTAssertFalse(AppUpdateConfiguration.isValid(invalid))
        }
    }

    @MainActor
    func testUpdaterDelegatePinsFeedDespiteStoredOverride() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = directory.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = "AppUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: identifier))
        defer { defaults.removePersistentDomain(forName: identifier) }
        defaults.set("https://example.com/untrusted.xml", forKey: "SUFeedURL")
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": identifier, "CFBundleVersion": "22",
            "SUFeedURL": AppUpdateConfiguration.feedURL
        ], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: directory))
        let state = AppState(defaults: defaults, appServer: UpdateTestAppServer(), historyStore: .init(fileURL: nil))
        let adapter = AppUpdater(appState: state, beforePresentation: {}, prepareTermination: { $0(true) }, didCancel: {})
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: adapter)
        XCTAssertEqual(updater.feedURL?.absoluteString, AppUpdateConfiguration.feedURL)
    }

    func testHandoffRestoresExpectedBuildOnceAndDiscardsStaleCorruptRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("handoff.json")
        let record = UpdateHandoff(
            sourceBuild: "22", targetBuild: "23",
            frame: CGRect(x: -800, y: 200, width: 400, height: 220), isPetVisible: false
        )
        try record.save(to: url)
        XCTAssertEqual(UpdateHandoff.consume(for: "23", at: url), record)
        XCTAssertNil(UpdateHandoff.consume(for: "23", at: url))
        try record.save(to: url)
        XCTAssertNil(UpdateHandoff.consume(for: "22", at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try Data("invalid".utf8).write(to: url)
        XCTAssertNil(UpdateHandoff.consume(for: "23", at: url))
        try record.save(to: url)
        try UpdateHandoff.clear(at: url)
        XCTAssertNil(UpdateHandoff.consume(for: "23", at: url))
    }

    @MainActor
    func testTerminationDeadlineNeverCommitsLateResultAndCanRetry() async {
        let gate = UpdateTerminationGate()
        var suspended: CheckedContinuation<Bool, Never>?
        var results: [Bool] = []
        var commits = 0
        gate.prepare(timeout: .milliseconds(10), operation: {
            await withCheckedContinuation { suspended = $0 }
        }, commit: { commits += 1; return true }, completion: { results.append($0) })
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(results, [false])
        XCTAssertEqual(commits, 0)
        gate.prepare(operation: { true }, commit: { commits += 1; return true }, completion: { results.append($0) })
        for _ in 0..<100 where !gate.isPrepared { await Task.yield() }
        XCTAssertTrue(gate.isPrepared)
        suspended?.resume(returning: true)
        await Task.yield()
        XCTAssertEqual(results, [false, true])
        XCTAssertEqual(commits, 1)
    }

    @MainActor
    func testHistoryDrainPreservesAcceptedSamplesAndRecoversFromWriteFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedParent = directory.appendingPathComponent("blocked")
        try Data("file, not directory".utf8).write(to: blockedParent)
        let store = QuotaHistoryStore(fileURL: blockedParent.appendingPathComponent("history.json"))
        let server = UpdateTestAppServer()
        let suite = "AppUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 5_000_000)
        let state = AppState(defaults: defaults, appServer: server, now: { now }, historyStore: store)
        state.start()
        func send(_ remaining: Int) async {
            now.addTimeInterval(60)
            server.send(snapshot: QuotaSnapshot(
                limitId: "codex", limitName: nil, planType: nil,
                primary: QuotaWindow(usedPercent: 100 - remaining, windowDurationMins: 300, resetsAt: 6_000_000),
                secondary: nil
            ))
            for _ in 0..<100 where state.quota?.primary?.remainingPercent != remaining { await Task.yield() }
        }
        await send(80)
        state.beginTermination()
        let failed = await state.drainHistoryForTermination()
        XCTAssertFalse(failed)
        state.retryNow()
        XCTAssertEqual(server.startCount, 1)
        state.cancelTermination()
        XCTAssertEqual(server.startCount, 2)
        XCTAssertEqual(state.quotaHistoryIssue, .notSaved)
        try FileManager.default.removeItem(at: blockedParent)
        await send(79)
        state.beginTermination()
        let saved = await state.drainHistoryForTermination()
        XCTAssertTrue(saved)
        let samples = await store.storedSamples()
        XCTAssertEqual(samples.compactMap { $0.primary?.remainingPercent }, [80, 79])
        XCTAssertEqual(samples.last?.primaryBoundary, .gap)
        let reload = QuotaHistoryStore(fileURL: blockedParent.appendingPathComponent("history.json"))
        _ = await reload.load(at: now)
        let reloaded = await reload.storedSamples()
        XCTAssertEqual(reloaded.count, 2)
        state.stop()
    }

    @MainActor
    func testHistoryDrainIncludesQueuedClearBeforeLaterAcceptedRecord() async {
        let store = QuotaHistoryStore(fileURL: nil)
        let server = UpdateTestAppServer()
        let suite = "AppUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 5_000_000)
        let state = AppState(defaults: defaults, appServer: server, now: { now }, historyStore: store)
        state.start()
        func send(_ used: Int) async {
            server.send(snapshot: QuotaSnapshot(
                limitId: "codex", limitName: nil, planType: nil,
                primary: QuotaWindow(usedPercent: used, windowDurationMins: 300, resetsAt: 6_000_000),
                secondary: nil
            ))
            for _ in 0..<100 where state.quota?.primary?.usedPercent != used { await Task.yield() }
        }
        await send(20)
        state.clearQuotaHistory()
        now.addTimeInterval(60)
        await send(21)
        state.beginTermination()
        let success = await state.drainHistoryForTermination()
        XCTAssertTrue(success)
        let samples = await store.storedSamples()
        XCTAssertEqual(samples.compactMap { $0.primary?.remainingPercent }, [79])
        state.stop()
    }
}

private final class UpdateTestAppServer: CodexAppServerClient {
    private var onSnapshot: ((QuotaSnapshot, Int?) -> Void)?
    private(set) var startCount = 0

    func start(
        onSnapshot: @escaping (QuotaSnapshot, Int?) -> Void,
        onSpeedMode: @escaping (SpeedMode) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        startCount += 1
        self.onSnapshot = onSnapshot
    }

    func stop() { onSnapshot = nil }
    func refreshRateLimits() {}
    func send(snapshot: QuotaSnapshot) { onSnapshot?(snapshot, nil) }
}
