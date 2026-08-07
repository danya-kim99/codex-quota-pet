import AppKit
import XCTest
@testable import Black_Hole_Codex_Quota_Indicator

final class QuotaHistoryTests: XCTestCase {
    func testStoreClassifiesContinuousResetCorrectionIdentityAndMissingBoundaries() async {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let oldReset = Int64(start.addingTimeInterval(30 * 60).timeIntervalSince1970)
        let newReset = Int64(start.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)

        let continuousStore = QuotaHistoryStore(fileURL: nil)
        _ = await continuousStore.record(
            snapshot: Self.snapshot(remainingPercent: 85, resetsAt: oldReset),
            at: start,
            forceGap: true
        )
        _ = await continuousStore.record(
            snapshot: Self.snapshot(remainingPercent: 77, resetsAt: oldReset),
            at: start.addingTimeInterval(20 * 60),
            forceGap: false
        )
        let continuous = await continuousStore.storedSamples()
        XCTAssertEqual(continuous.map(\.primaryBoundary), [.baseline, .continuous])

        let resetStore = QuotaHistoryStore(fileURL: nil)
        _ = await resetStore.record(
            snapshot: Self.snapshot(remainingPercent: 77, resetsAt: oldReset),
            at: start,
            forceGap: true
        )
        _ = await resetStore.record(
            snapshot: Self.snapshot(remainingPercent: 100, resetsAt: newReset),
            at: start.addingTimeInterval(40 * 60),
            forceGap: false
        )
        let resetSamples = await resetStore.storedSamples()
        XCTAssertEqual(resetSamples.last?.primaryBoundary, .reset)

        let gapCases: [(QuotaSnapshot, TimeInterval)] = [
            (Self.snapshot(remainingPercent: 80, resetsAt: oldReset), 10 * 60),
            (
                Self.snapshot(
                    remainingPercent: 70,
                    resetsAt: oldReset,
                    limitId: "another-limit"
                ),
                10 * 60
            ),
            (Self.snapshot(remainingPercent: nil, resetsAt: nil), 10 * 60),
            (Self.snapshot(remainingPercent: 70, resetsAt: nil), 10 * 60),
            (Self.snapshot(remainingPercent: 70, resetsAt: oldReset), 91 * 60),
            (Self.snapshot(remainingPercent: 70, resetsAt: oldReset), -60)
        ]
        for (current, elapsed) in gapCases {
            let store = QuotaHistoryStore(fileURL: nil)
            _ = await store.record(
                snapshot: Self.snapshot(remainingPercent: 77, resetsAt: oldReset),
                at: start,
                forceGap: true
            )
            _ = await store.record(
                snapshot: current,
                at: start.addingTimeInterval(elapsed),
                forceGap: false
            )
            let gapSamples = await store.storedSamples()
            XCTAssertEqual(gapSamples.last?.primaryBoundary, .gap)
        }

        let forcedGapStore = QuotaHistoryStore(fileURL: nil)
        _ = await forcedGapStore.record(
            snapshot: Self.snapshot(remainingPercent: 77, resetsAt: oldReset),
            at: start,
            forceGap: true
        )
        _ = await forcedGapStore.record(
            snapshot: Self.snapshot(remainingPercent: 76, resetsAt: oldReset),
            at: start.addingTimeInterval(10 * 60),
            forceGap: true
        )
        let forcedGapSamples = await forcedGapStore.storedSamples()
        XCTAssertEqual(forcedGapSamples.last?.primaryBoundary, .gap)
    }

    func testStoreSavesMeaningfulChangesAndHourlyHeartbeats() async {
        let store = QuotaHistoryStore(fileURL: nil)
        let start = Date(timeIntervalSince1970: 3_000_000)
        let reset = Int64(start.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        let snapshot = Self.snapshot(
            remainingPercent: 85,
            resetsAt: reset,
            secondaryPercent: 40
        )

        _ = await store.record(snapshot: snapshot, at: start, forceGap: true)
        _ = await store.record(
            snapshot: snapshot,
            at: start.addingTimeInterval(10 * 60),
            forceGap: false
        )
        let samplesBeforeHeartbeat = await store.storedSamples()
        XCTAssertEqual(samplesBeforeHeartbeat.count, 1)

        _ = await store.record(
            snapshot: snapshot,
            at: start.addingTimeInterval(60 * 60),
            forceGap: false
        )
        _ = await store.record(
            snapshot: Self.snapshot(
                remainingPercent: 84,
                resetsAt: reset,
                secondaryPercent: 39
            ),
            at: start.addingTimeInterval(61 * 60),
            forceGap: false
        )

        let samples = await store.storedSamples()
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.last?.primary?.remainingPercent, 84)
        XCTAssertEqual(samples.last?.secondary?.remainingPercent, 39)
        XCTAssertEqual(samples.last?.primaryBoundary, .continuous)
        XCTAssertEqual(samples.last?.secondaryBoundary, .continuous)
    }

    func testPresentationUsesLatestComparableSegmentAndCapsRenderPoints() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        let reset = Int64(now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        var samples = (0..<1_000).map { index in
            var sample = QuotaHistorySample(
                snapshot: Self.snapshot(
                    remainingPercent: 100 - index % 100,
                    resetsAt: reset
                ),
                observedAt: now.addingTimeInterval(TimeInterval(index - 1_000) * 60)
            )
            sample.primaryBoundary = index == 0 ? .baseline : .continuous
            return sample
        }
        samples[800].primaryBoundary = .reset
        samples[900].primaryBoundary = .gap

        let presentation = QuotaHistoryPresentation.make(samples: samples, now: now)

        XCTAssertLessThanOrEqual(
            presentation.points.count,
            QuotaHistoryPresentation.maximumRenderPoints
        )
        XCTAssertTrue(presentation.containsReset)
        XCTAssertTrue(presentation.containsGap)
        XCTAssertEqual(presentation.startPercent, samples[900].primary?.remainingPercent)
        XCTAssertEqual(presentation.endPercent, samples.last?.primary?.remainingPercent)
        XCTAssertEqual(
            presentation.observedDuration,
            samples.last!.observedAt.timeIntervalSince(samples[900].observedAt)
        )
    }

    func testPersistenceRetentionCapPermissionsCorruptionAndClear() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaHistoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fileURL = directory.appendingPathComponent("quota-history-v1.json")
        let now = Date(timeIntervalSince1970: 5_000_000)
        let reset = Int64(now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        var samples = [QuotaHistorySample(
            snapshot: Self.snapshot(remainingPercent: 100, resetsAt: reset),
            observedAt: now.addingTimeInterval(-QuotaHistoryStore.retention - 1)
        )]
        samples += (0..<2_005).map { index in
            var sample = QuotaHistorySample(
                snapshot: Self.snapshot(
                    remainingPercent: 100 - index % 100,
                    resetsAt: reset
                ),
                observedAt: now.addingTimeInterval(TimeInterval(index - 2_005) * 30)
            )
            sample.primaryBoundary = index == 0 ? .baseline : .continuous
            return sample
        }
        try Self.writeDocument(samples, to: fileURL)

        let store = QuotaHistoryStore(fileURL: fileURL)
        let loadStart = ProcessInfo.processInfo.systemUptime
        let loaded = await store.load(at: now)
        var loadDurations = [ProcessInfo.processInfo.systemUptime - loadStart]
        for _ in 1..<10 {
            let reloadedStore = QuotaHistoryStore(fileURL: fileURL)
            let reloadStart = ProcessInfo.processInfo.systemUptime
            _ = await reloadedStore.load(at: now)
            loadDurations.append(ProcessInfo.processInfo.systemUptime - reloadStart)
        }
        let loadMedian = loadDurations.sorted()[loadDurations.count / 2]
        let stored = await store.storedSamples()

        XCTAssertEqual(loaded.sampleCount, QuotaHistoryStore.maximumSampleCount)
        XCTAssertEqual(stored.count, QuotaHistoryStore.maximumSampleCount)
        XCTAssertEqual(stored.first?.primaryBoundary, .baseline)
        XCTAssertTrue(stored.allSatisfy {
            now.timeIntervalSince($0.observedAt) <= QuotaHistoryStore.retention
        })
        XCTAssertLessThan(loadMedian, 0.1)
        await MainActor.run {
            XCTContext.runActivity(
                named: String(format: "Decode/prune median: %.3f ms", loadMedian * 1_000)
            ) { _ in }
        }

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(
            (fileAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )

        try Data("not json".utf8).write(to: fileURL, options: .atomic)
        let corruptStore = QuotaHistoryStore(fileURL: fileURL)
        let restarted = await corruptStore.load(at: now)
        XCTAssertEqual(restarted.issue, .restarted)
        XCTAssertEqual(restarted.sampleCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix("quota-history-v1.corrupt-") }
                .count,
            1
        )

        let cleared = await corruptStore.clear(at: now)
        XCTAssertNil(cleared.issue)
        XCTAssertEqual(cleared.sampleCount, 0)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty
        )

        let emptyStore = QuotaHistoryStore(
            fileURL: directory
                .appendingPathComponent("missing", isDirectory: true)
                .appendingPathComponent("quota-history-v1.json")
        )
        let emptyClear = await emptyStore.clear(at: now)
        XCTAssertNil(emptyClear.issue)
    }

    func testPersistenceFailureIsNonFatalAndReported() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaHistoryBlocked-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let blockedParent = directory.appendingPathComponent("regular-file")
        try Data().write(to: blockedParent)
        let store = QuotaHistoryStore(
            fileURL: blockedParent.appendingPathComponent("quota-history-v1.json")
        )
        let now = Date(timeIntervalSince1970: 6_000_000)

        let update = await store.record(
            snapshot: Self.snapshot(remainingPercent: 50, resetsAt: 7_000_000),
            at: now,
            forceGap: true
        )

        XCTAssertEqual(update.issue, .notSaved)
        XCTAssertEqual(update.sampleCount, 1)
        XCTAssertEqual(update.presentation.endPercent, 50)

        let failedClear = await store.clear(at: now)
        XCTAssertEqual(failedClear.issue, .notSaved)
        XCTAssertEqual(failedClear.sampleCount, 1)

        try FileManager.default.removeItem(at: blockedParent)
        try FileManager.default.createDirectory(at: blockedParent, withIntermediateDirectories: true)
        let recovered = await store.record(
            snapshot: Self.snapshot(remainingPercent: 49, resetsAt: 7_000_000),
            at: now.addingTimeInterval(60),
            forceGap: false
        )
        XCTAssertNil(recovered.issue)
        XCTAssertEqual(recovered.sampleCount, 2)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: blockedParent.appendingPathComponent("quota-history-v1.json").path
            )
        )
    }

    func testUnsupportedVersionAndFailedQuarantineAreSafe() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaHistoryQuarantine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("quota-history-v1.json")
        let now = Date(timeIntervalSince1970: 9_000_000)

        try Data(#"{"formatVersion":2,"samples":[]}"#.utf8).write(to: fileURL)
        let unsupportedStore = QuotaHistoryStore(fileURL: fileURL)
        let unsupported = await unsupportedStore.load(at: now)
        XCTAssertEqual(unsupported.issue, .restarted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        _ = await unsupportedStore.clear(at: now)

        try Data("invalid".utf8).write(to: fileURL)
        let collisionURL = directory.appendingPathComponent(
            "quota-history-v1.corrupt-\(Int(now.timeIntervalSince1970)).json"
        )
        try Data("existing quarantine".utf8).write(to: collisionURL)
        let collisionStore = QuotaHistoryStore(fileURL: fileURL)
        let collision = await collisionStore.load(at: now)

        XCTAssertEqual(collision.issue, .notSaved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        _ = await collisionStore.record(
            snapshot: Self.snapshot(remainingPercent: 60, resetsAt: 10_000_000),
            at: now.addingTimeInterval(60),
            forceGap: true
        )
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("invalid".utf8))
    }

    func testPersistedHistoryReloadsWithoutChangingPercentages() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaHistoryRelaunch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("quota-history-v1.json")
        let start = Date(timeIntervalSince1970: 6_500_000)
        let reset = Int64(start.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        let store = QuotaHistoryStore(fileURL: fileURL)
        _ = await store.record(
            snapshot: Self.snapshot(remainingPercent: 85, resetsAt: reset),
            at: start,
            forceGap: true
        )
        for hour in 1...5 {
            _ = await store.record(
                snapshot: Self.snapshot(remainingPercent: 85, resetsAt: reset),
                at: start.addingTimeInterval(TimeInterval(hour) * 60 * 60),
                forceGap: false
            )
        }
        _ = await store.record(
            snapshot: Self.snapshot(remainingPercent: 77, resetsAt: reset),
            at: start.addingTimeInterval(6 * 60 * 60),
            forceGap: false
        )

        let reloadedStore = QuotaHistoryStore(fileURL: fileURL)
        let reloaded = await reloadedStore.load(at: start.addingTimeInterval(6 * 60 * 60))
        XCTAssertEqual(reloaded.sampleCount, 7)
        XCTAssertEqual(reloaded.presentation.startPercent, 85)
        XCTAssertEqual(reloaded.presentation.endPercent, 77)
        XCTAssertEqual(reloaded.presentation.observedDuration, 6 * 60 * 60)
    }

    @MainActor
    func testDynamicsPreferenceIsVisibleByDefaultPersistsAndDoesNotStopCollection() async throws {
        let suiteName = "QuotaHistoryPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let server = HistoryFakeAppServer()
        let store = QuotaHistoryStore(fileURL: nil)
        var now = Date(timeIntervalSince1970: 7_000_000)
        let reset = Int64(now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        let appState = AppState(
            defaults: defaults,
            appServer: server,
            now: { now },
            historyStore: store
        )

        XCTAssertTrue(appState.showsQuotaDynamics)
        appState.setShowsQuotaDynamics(false)
        XCTAssertFalse(appState.showsQuotaDynamics)
        XCTAssertFalse(AppState(defaults: defaults, historyStore: .init(fileURL: nil)).showsQuotaDynamics)

        appState.start()
        server.send(Self.snapshot(remainingPercent: 85, resetsAt: reset))
        now.addTimeInterval(10 * 60)
        server.send(Self.snapshot(remainingPercent: 77, resetsAt: reset))
        for _ in 0..<100 {
            if await store.storedSamples().count == 2 { break }
            await Task.yield()
        }

        XCTAssertFalse(appState.showsQuotaDynamics)
        let collectedSamples = await store.storedSamples()
        XCTAssertEqual(collectedSamples.count, 2)
        appState.stop()
    }

    @MainActor
    func testApprovedTooltipHistorySizesAndLayoutFit() {
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .large, showsHistory: true),
            CGSize(width: 360, height: 252)
        )
        let smoothMedium = QuotaTooltipView.panelSize(for: .medium, showsHistory: true)
        XCTAssertEqual(smoothMedium.width, 288)
        XCTAssertEqual(smoothMedium.height, 201.6, accuracy: 0.0001)
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .small, showsHistory: true),
            CGSize(width: 272, height: 158)
        )
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .large, style: .pixel, showsHistory: true),
            CGSize(width: 420, height: 290)
        )
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .medium, style: .pixel, showsHistory: true),
            CGSize(width: 336, height: 232)
        )
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .small, style: .pixel, showsHistory: true),
            CGSize(width: 304, height: 174)
        )

        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        for style in TooltipStyle.allCases {
            for petSize in PetSize.allCases {
                let scene = petSize.sceneSize
                let petFrame = CGRect(
                    x: screen.midX - scene.width / 2,
                    y: screen.midY - scene.height / 2,
                    width: scene.width,
                    height: scene.height
                )
                let layout = PetPanelController.tooltipLayout(
                    petFrame: petFrame,
                    visibleFrame: screen,
                    tooltipStyle: style,
                    showsHistory: true
                )
                XCTAssertTrue(screen.contains(CGRect(origin: layout.origin, size: layout.size)))
            }
        }
    }

    @MainActor
    func testHistoryPresentationMeetsRenderBudget() {
        let now = Date(timeIntervalSince1970: 8_000_000)
        let reset = Int64(now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970)
        let samples = (0..<QuotaHistoryStore.maximumSampleCount).map { index in
            var sample = QuotaHistorySample(
                snapshot: Self.snapshot(
                    remainingPercent: 100 - index % 100,
                    resetsAt: reset
                ),
                observedAt: now.addingTimeInterval(TimeInterval(index - 2_000) * 30)
            )
            sample.primaryBoundary = index == 0 ? .baseline : .continuous
            return sample
        }
        var durations: [TimeInterval] = []
        for _ in 0..<10 {
            let start = ProcessInfo.processInfo.systemUptime
            _ = QuotaHistoryPresentation.make(samples: samples, now: now)
            durations.append(ProcessInfo.processInfo.systemUptime - start)
        }
        let median = durations.sorted()[durations.count / 2]

        XCTAssertLessThan(median, 0.01)
        XCTContext.runActivity(
            named: String(format: "Presentation median: %.3f ms", median * 1_000)
        ) { _ in }
    }

    func testHistoryLocalizationsAreBundled() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let english = try XCTUnwrap(
            Bundle(path: try XCTUnwrap(appBundle.path(forResource: "en", ofType: "lproj")))
        )
        let russian = try XCTUnwrap(
            Bundle(path: try XCTUnwrap(appBundle.path(forResource: "ru", ofType: "lproj")))
        )
        let translations = [
            "menu.show_quota_dynamics": ("Show Quota Dynamics", "Показывать динамику квоты"),
            "menu.clear_quota_history": ("Clear Local History…", "Очистить локальную историю…"),
            "history.title": ("Observed · 24 h", "Наблюдения · 24 ч"),
            "history.collecting": ("Collecting local history…", "Собираем локальную историю…"),
            "history.issue.not_saved": ("History not saved", "История не сохранена")
        ]

        for (key, translation) in translations {
            XCTAssertEqual(
                english.localizedString(forKey: key, value: nil, table: nil),
                translation.0
            )
            XCTAssertEqual(
                russian.localizedString(forKey: key, value: nil, table: nil),
                translation.1
            )
        }
    }

    private static func snapshot(
        remainingPercent: Int?,
        resetsAt: Int64?,
        limitId: String = "codex",
        secondaryPercent: Int? = nil
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            limitId: limitId,
            limitName: nil,
            planType: "pro",
            primary: remainingPercent.map {
                QuotaWindow(
                    usedPercent: 100 - $0,
                    windowDurationMins: 10_080,
                    resetsAt: resetsAt
                )
            },
            secondary: secondaryPercent.map {
                QuotaWindow(
                    usedPercent: 100 - $0,
                    windowDurationMins: 10_080,
                    resetsAt: resetsAt
                )
            }
        )
    }

    private static func writeDocument(
        _ samples: [QuotaHistorySample],
        to fileURL: URL
    ) throws {
        struct Document: Encodable {
            let formatVersion: Int
            let samples: [QuotaHistorySample]
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(
            Document(formatVersion: QuotaHistoryStore.formatVersion, samples: samples)
        ).write(to: fileURL, options: .atomic)
    }
}

private final class HistoryFakeAppServer: CodexAppServerClient {
    private var onSnapshot: ((QuotaSnapshot) -> Void)?

    func start(
        onSnapshot: @escaping (QuotaSnapshot) -> Void,
        onSpeedMode: @escaping (SpeedMode) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        self.onSnapshot = onSnapshot
    }

    func refreshRateLimits() {}

    func stop() {
        onSnapshot = nil
    }

    func send(_ snapshot: QuotaSnapshot) {
        onSnapshot?(snapshot)
    }
}
