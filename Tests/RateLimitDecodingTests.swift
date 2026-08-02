import AppKit
import ServiceManagement
import XCTest
@testable import Black_Hole_Codex_Quota_Indicator

final class RateLimitDecodingTests: XCTestCase {
    func testBundledIconsAreConfigured() {
        XCTAssertNotNil(NSImage(named: "MenuBarIcon"))
        XCTAssertEqual(
            Bundle(for: AppDelegate.self).object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            "AppIcon"
        )
    }

    func testDecodesMainCodexQuota() throws {
        let json = #"""
        {
          "id": 1,
          "result": {
            "rateLimits": {
              "limitId": "legacy",
              "primary": { "usedPercent": 50 }
            },
            "rateLimitsByLimitId": {
              "codex": {
                "limitId": "codex",
                "planType": "pro",
                "primary": {
                  "usedPercent": 2,
                  "windowDurationMins": 10080,
                  "resetsAt": 1786175912
                }
              }
            }
          }
        }
        """#

        let response = try JSONDecoder().decode(
            RPCResponse<RateLimitsResult>.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.result.codex.limitId, "codex")
        XCTAssertEqual(response.result.codex.primary?.remainingPercent, 98)
        XCTAssertEqual(response.result.codex.primary?.windowDurationMins, 10_080)
    }

    func testDecodesTurboFromEffectiveCodexConfig() throws {
        let turboJSON = #"{"id":2,"result":{"config":{"service_tier":"priority"}}}"#
        let standardJSON = #"{"id":3,"result":{"config":{"service_tier":null}}}"#

        let turbo = try JSONDecoder().decode(
            RPCResponse<ConfigReadResult>.self,
            from: Data(turboJSON.utf8)
        )
        let standard = try JSONDecoder().decode(
            RPCResponse<ConfigReadResult>.self,
            from: Data(standardJSON.utf8)
        )

        XCTAssertEqual(turbo.result.speedMode, .turbo)
        XCTAssertEqual(standard.result.speedMode, .standard)
    }

    @MainActor
    func testTooltipFollowsPetAndChoosesVisibleScreenSide() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let cases: [(CGRect, QuotaTooltipView.Placement)] = [
            (CGRect(x: 0, y: 340, width: 400, height: 220), .right),
            (CGRect(x: 520, y: 0, width: 400, height: 220), .above),
            (CGRect(x: 1_040, y: 340, width: 400, height: 220), .left),
            (CGRect(x: 520, y: 680, width: 400, height: 220), .below)
        ]

        for (petFrame, expectedPlacement) in cases {
            let layout = PetPanelController.tooltipLayout(
                petFrame: petFrame,
                visibleFrame: screen
            )
            let tooltipFrame = CGRect(origin: layout.origin, size: QuotaTooltipView.panelSize)

            XCTAssertEqual(layout.placement, expectedPlacement)
            XCTAssertTrue(screen.contains(tooltipFrame))
        }

        let first = PetPanelController.tooltipLayout(
            petFrame: cases[0].0,
            visibleFrame: screen
        )
        let moved = PetPanelController.tooltipLayout(
            petFrame: cases[2].0,
            visibleFrame: screen
        )
        XCTAssertNotEqual(first.origin, moved.origin)
        XCTAssertEqual(BlackHoleView.size, cases[0].0.size)
    }

    @MainActor
    func testTooltipRestoresAfterDragOnlyWhileCursorRemainsOverPet() {
        let petFrame = CGRect(x: 500, y: 300, width: 400, height: 220)

        XCTAssertTrue(
            PetPanelController.shouldRestoreTooltipAfterDrag(
                wasVisible: true,
                cursorLocation: CGPoint(x: petFrame.midX, y: petFrame.midY),
                petFrame: petFrame
            )
        )
        XCTAssertFalse(
            PetPanelController.shouldRestoreTooltipAfterDrag(
                wasVisible: true,
                cursorLocation: CGPoint(x: petFrame.maxX + 1, y: petFrame.midY),
                petFrame: petFrame
            )
        )
        XCTAssertFalse(
            PetPanelController.shouldRestoreTooltipAfterDrag(
                wasVisible: false,
                cursorLocation: CGPoint(x: petFrame.midX, y: petFrame.midY),
                petFrame: petFrame
            )
        )
    }

    func testTooltipLocalizationsAreBundled() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let englishPath = try XCTUnwrap(
            appBundle.path(forResource: "en", ofType: "lproj")
        )
        let russianPath = try XCTUnwrap(
            appBundle.path(forResource: "ru", ofType: "lproj")
        )
        let english = try XCTUnwrap(Bundle(path: englishPath))
        let russian = try XCTUnwrap(Bundle(path: russianPath))

        XCTAssertEqual(
            english.localizedString(forKey: "quota.available", value: nil, table: nil),
            "Available"
        )
        XCTAssertEqual(
            russian.localizedString(forKey: "quota.available", value: nil, table: nil),
            "Доступно"
        )
        XCTAssertEqual(
            russian.localizedString(forKey: "reset.days.remaining", value: nil, table: nil),
            "%@ до сброса"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "reset.compact.absolute", value: nil, table: nil),
            "%1$@, %2$@"
        )

        let menuTranslations = [
            "menu.quota.short": ("Quota", "Квота"),
            "menu.retry": ("Retry Now", "Повторить сейчас"),
            "menu.hide_pet": ("Hide Pet", "Скрыть питомца"),
            "menu.show_pet": ("Show Pet", "Показать питомца"),
            "menu.hide_full_screen": ("Hide in Full Screen", "Скрывать в полноэкранном режиме"),
            "menu.launch_at_login": ("Launch at Login", "Запускать при входе"),
            "menu.approval_required": ("Approval Required", "Требуется разрешение"),
            "menu.open_login_items": ("Open Login Items", "Открыть объекты входа")
        ]
        for (key, translation) in menuTranslations {
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

    @MainActor
    func testTooltipProgressPresentationUsesRealSpeedMode() {
        XCTAssertEqual(
            QuotaTooltipView.progressPresentation(for: .standard),
            .standard
        )
        XCTAssertEqual(
            QuotaTooltipView.progressPresentation(for: .turbo),
            .turbo
        )
    }

    @MainActor
    func testTooltipDaySegmentsComeFromQuotaWindow() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(5 * 86_400 + 23 * 3_600)

        XCTAssertEqual(
            QuotaTooltipView.dayIndicator(
                resetDate: resetDate,
                now: now,
                windowDurationMinutes: 10_080
            ),
            .init(activeSegments: 5, totalSegments: 7)
        )
        XCTAssertNil(
            QuotaTooltipView.dayIndicator(
                resetDate: nil,
                now: now,
                windowDurationMinutes: 10_080
            )
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertTrue(
            QuotaTooltipView.localizedDayCount(
                1,
                locale: Locale(identifier: "ru_RU"),
                calendar: calendar
            ).contains("день")
        )
        XCTAssertTrue(
            QuotaTooltipView.localizedDayCount(
                2,
                locale: Locale(identifier: "ru_RU"),
                calendar: calendar
            ).contains("дня")
        )
        XCTAssertTrue(
            QuotaTooltipView.localizedDayCount(
                5,
                locale: Locale(identifier: "ru_RU"),
                calendar: calendar
            ).contains("дней")
        )
    }

    @MainActor
    func testTooltipQuotaLevelsUseRequestedBoundaries() {
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 100), .normal)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 30), .normal)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 29), .warning)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 10), .warning)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 9), .critical)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 0), .critical)
    }

    @MainActor
    func testTooltipResetDateOmitsOnlyCurrentYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 12))
        )
        let thisYear = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 10, minute: 58))
        )
        let nextYear = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2027, month: 8, day: 8, hour: 10, minute: 58))
        )

        let currentParts = QuotaTooltipView.resetDateParts(
            thisYear,
            relativeTo: now,
            locale: Locale(identifier: "ru_RU"),
            calendar: calendar
        )
        let futureParts = QuotaTooltipView.resetDateParts(
            nextYear,
            relativeTo: now,
            locale: Locale(identifier: "ru_RU"),
            calendar: calendar
        )

        XCTAssertFalse(currentParts.date.contains("2026"))
        XCTAssertTrue(futureParts.date.contains("2027"))
        XCTAssertFalse(currentParts.time.isEmpty)
    }

    func testTurboAnimationIsFasterAndPulses() {
        let full = PetVisualState(remainingPercent: 100)
        let empty = PetVisualState(remainingPercent: 0)

        XCTAssertEqual(
            full.rotationSpeed(for: .turbo),
            full.rotationSpeed(for: .standard) * 1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(empty.rotationSpeed(for: .standard), 0.1, accuracy: 0.001)
        XCTAssertTrue(full.shouldPulse(in: .turbo))
        XCTAssertFalse(full.shouldPulse(in: .standard))
        XCTAssertFalse(empty.shouldPulse(in: .turbo))
    }

    func testQuotaSelectsNearestSpriteState() {
        let expectations = [
            (100, 100), (95, 100), (94, 90),
            (55, 60), (54, 50),
            (25, 30), (24, 20),
            (5, 10), (4, 0), (0, 0)
        ]

        for (remainingPercent, spritePercent) in expectations {
            XCTAssertEqual(
                PetVisualState(remainingPercent: remainingPercent).spriteStatePercent,
                spritePercent
            )
        }
    }

    func testEveryQuotaStateHasSixBundledFrames() {
        let appBundle = Bundle(for: AppDelegate.self)

        for percent in stride(from: 100, through: 0, by: -10) {
            let state = PetVisualState(remainingPercent: percent)
            XCTAssertEqual(state.spriteStatePercent, percent)

            for frame in 0..<PetVisualState.spriteFrameCount {
                XCTAssertNotNil(
                    appBundle.url(
                        forResource: "quota-\(percent)-frame-\(frame)",
                        withExtension: "png",
                        subdirectory: "frames"
                    ),
                    "Missing \(percent)% frame \(frame)"
                )
            }
        }
    }

    func testSpriteFramesLoopAndTurboAdvancesFaster() {
        let state = PetVisualState(remainingPercent: 100)

        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0, speedMode: .standard), 0)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.10, speedMode: .standard), 0)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.10, speedMode: .turbo), 1)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.14, speedMode: .standard), 1)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.85, speedMode: .standard), 0)
        XCTAssertEqual(state.frameInterval(for: .standard), 0.14, accuracy: 0.001)
        XCTAssertEqual(state.frameInterval(for: .turbo), 0.14 / 1.5, accuracy: 0.001)
        XCTAssertEqual(
            PetVisualState(remainingPercent: 0).frameInterval(for: .standard),
            1.4,
            accuracy: 0.001
        )
    }

    @MainActor
    func testPetVisibilityTogglesWithoutStartingConnection() {
        let appState = AppState()

        XCTAssertTrue(appState.isPetVisible)
        appState.togglePetVisibility()
        XCTAssertFalse(appState.isPetVisible)
        appState.togglePetVisibility()
        XCTAssertTrue(appState.isPetVisible)
    }

    @MainActor
    func testPanelHidesAndRestores() {
        let appState = AppState()
        let controller = PetPanelController()

        controller.show(appState: appState)
        XCTAssertTrue(controller.isVisible)
        controller.setTooltipVisible(true)
        XCTAssertTrue(controller.isTooltipVisible)

        controller.hide()
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.isTooltipVisible)

        controller.show(appState: appState)
        XCTAssertTrue(controller.isVisible)
        controller.hide()
    }

    @MainActor
    func testFullScreenPreferencePersists() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(defaults: defaults)
        XCTAssertFalse(appState.hidesInFullScreenApps)

        appState.setHidesInFullScreenApps(true)
        XCTAssertTrue(appState.hidesInFullScreenApps)
        XCTAssertTrue(AppState(defaults: defaults).hidesInFullScreenApps)
    }

    @MainActor
    func testFullScreenSuppressionDoesNotOverrideManualVisibility() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var isFullScreen = false
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController(
            isFrontmostApplicationFullScreen: { isFullScreen }
        )
        appState.setHidesInFullScreenApps(true)

        controller.updateVisibility(appState: appState)
        XCTAssertTrue(controller.isVisible)

        isFullScreen = true
        controller.updateVisibility(appState: appState)
        XCTAssertFalse(controller.isVisible)

        appState.togglePetVisibility()
        isFullScreen = false
        controller.updateVisibility(appState: appState)
        XCTAssertFalse(controller.isVisible)

        appState.togglePetVisibility()
        controller.updateVisibility(appState: appState)
        XCTAssertTrue(controller.isVisible)
        controller.hide()
    }

    @MainActor
    func testLaunchAtLoginUsesSystemStatusAndAction() {
        let service = FakeLaunchAtLoginService()
        let appState = AppState(
            launchAtLoginStatusProvider: { service.status },
            updateLaunchAtLogin: service.setEnabled
        )

        XCTAssertFalse(appState.launchesAtLogin)

        appState.setLaunchesAtLogin(true)
        XCTAssertTrue(appState.launchesAtLogin)
        XCTAssertNil(appState.launchAtLoginError)

        appState.setLaunchesAtLogin(false)
        XCTAssertFalse(appState.launchesAtLogin)

        service.status = .requiresApproval
        appState.refreshLaunchAtLoginStatus()
        XCTAssertTrue(appState.launchesAtLogin)
    }

    @MainActor
    func testLaunchAtLoginKeepsActualStatusAfterFailure() {
        let service = FakeLaunchAtLoginService()
        service.error = .denied
        let appState = AppState(
            launchAtLoginStatusProvider: { service.status },
            updateLaunchAtLogin: service.setEnabled
        )

        appState.setLaunchesAtLogin(true)

        XCTAssertFalse(appState.launchesAtLogin)
        XCTAssertEqual(appState.launchAtLoginError, "Login item denied")
    }

    @MainActor
    func testFailureSchedulesReconnectAndRetryNowReconnectsImmediately() async {
        let appServer = FakeAppServer()
        let appState = AppState(appServer: appServer, retryDelays: [60])

        appState.start()
        XCTAssertEqual(appServer.startCount, 1)
        XCTAssertEqual(appState.connectionState, .connecting)

        appServer.fail(with: "Connection lost")
        await Self.waitUntil { appState.connectionState == .reconnecting }
        XCTAssertEqual(appState.connectionState, .reconnecting)
        XCTAssertEqual(appState.errorMessage, "Connection lost")

        appState.retryNow()
        XCTAssertEqual(appServer.startCount, 2)
        XCTAssertEqual(appState.connectionState, .connecting)

        appServer.send(snapshot: Self.snapshot(remainingPercent: 80))
        await Self.waitUntil { appState.connectionState == .connected }
        XCTAssertEqual(appState.quota?.primary?.remainingPercent, 80)
        XCTAssertEqual(appState.connectionState, .connected)
        XCTAssertNil(appState.errorMessage)

        appState.stop()
    }

    @MainActor
    func testAutomaticReconnectUsesSingleActiveAttempt() async {
        let appServer = FakeAppServer()
        let appState = AppState(appServer: appServer, retryDelays: [0])

        appState.start()
        appServer.fail(with: "Connection lost")
        appServer.fail(with: "Duplicate failure")
        await Self.waitUntil { appServer.startCount == 2 }

        XCTAssertEqual(appServer.startCount, 2)
        XCTAssertEqual(appState.connectionState, .reconnecting)
        appState.stop()
    }

    func testReconnectBackoffIsBounded() {
        XCTAssertEqual(AppState.reconnectDelays, [1, 2, 5, 10, 30])
    }

    private static func snapshot(remainingPercent: Int) -> QuotaSnapshot {
        QuotaSnapshot(
            limitId: "codex",
            limitName: nil,
            planType: "pro",
            primary: QuotaWindow(
                usedPercent: 100 - remainingPercent,
                windowDurationMins: nil,
                resetsAt: nil
            ),
            secondary: nil
        )
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}

private final class FakeAppServer: CodexAppServerClient {
    private var onSnapshot: ((QuotaSnapshot) -> Void)?
    private var onFailure: ((String) -> Void)?
    private(set) var startCount = 0

    func start(
        onSnapshot: @escaping (QuotaSnapshot) -> Void,
        onSpeedMode: @escaping (SpeedMode) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        startCount += 1
        self.onSnapshot = onSnapshot
        self.onFailure = onFailure
    }

    func stop() {
        onSnapshot = nil
        onFailure = nil
    }

    func fail(with message: String) {
        onFailure?(message)
    }

    func send(snapshot: QuotaSnapshot) {
        onSnapshot?(snapshot)
    }
}

private final class FakeLaunchAtLoginService {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? { "Login item denied" }
    }

    var status: SMAppService.Status = .notRegistered
    var error: Failure?

    func setEnabled(_ isEnabled: Bool) throws {
        if let error { throw error }
        status = isEnabled ? .enabled : .notRegistered
    }
}
