import Foundation
import CoreFoundation
import Observation
import ServiceManagement

enum QuotaConsumptionReactionKind: Int, CaseIterable, Equatable, Sendable {
    case small = 1
    case medium
    case large
    case lastLight

    var packetCount: Int {
        switch self {
        case .small: 1
        case .medium: 3
        case .large, .lastLight: 5
        }
    }

    var normalDuration: TimeInterval {
        switch self {
        case .small: 0.46
        case .medium: 0.67
        case .large: 0.83
        case .lastLight: 1.15
        }
    }

    var reducedMotionDuration: TimeInterval {
        switch self {
        case .small: 0.16
        case .medium: 0.20
        case .large: 0.24
        case .lastLight: 0.28
        }
    }
}

struct QuotaConsumptionEvent: Equatable, Identifiable, Sendable {
    let id: Int
    let kind: QuotaConsumptionReactionKind
}

struct QuotaConsumptionCadence: Equatable, Sendable {
    private(set) var position = 0

    mutating func advance(
        by delta: Int,
        reachesZero: Bool
    ) -> QuotaConsumptionReactionKind? {
        guard delta > 0 else { return nil }
        let previousPosition = position
        let total = previousPosition + delta
        position = total % 10
        if reachesZero { return .lastLight }
        if total >= 10 { return .large }
        if previousPosition < 5, total >= 5 { return .medium }
        return .small
    }

    mutating func reset() {
        position = 0
    }
}

struct QuotaReactionQueue: Equatable, Sendable {
    private(set) var active: QuotaConsumptionEvent?
    private(set) var pending: QuotaConsumptionEvent?

    mutating func receive(
        _ event: QuotaConsumptionEvent,
        deferPlayback: Bool
    ) -> QuotaConsumptionEvent? {
        if deferPlayback {
            pending = Self.stronger(pending, event)
            return nil
        }
        if event.kind == .lastLight {
            active = event
            pending = nil
            return event
        }
        guard active == nil else {
            pending = Self.stronger(pending, event)
            return nil
        }
        active = event
        return event
    }

    mutating func completeActive(
        id: Int,
        startPending: Bool
    ) -> QuotaConsumptionEvent? {
        guard active?.id == id else { return nil }
        active = nil
        return startPending ? resumePending() : nil
    }

    mutating func cancelActive() {
        active = nil
    }

    mutating func resumePending() -> QuotaConsumptionEvent? {
        guard active == nil, let pending else { return nil }
        active = pending
        self.pending = nil
        return pending
    }

    mutating func reset() {
        active = nil
        pending = nil
    }

    private static func stronger(
        _ current: QuotaConsumptionEvent?,
        _ candidate: QuotaConsumptionEvent
    ) -> QuotaConsumptionEvent {
        guard let current else { return candidate }
        return candidate.kind.rawValue > current.kind.rawValue ? candidate : current
    }
}

@MainActor
@Observable
final class AppState {
    nonisolated static let reconnectDelays: [TimeInterval] = [1, 2, 5, 10, 30]
    nonisolated static let quotaRefreshMaxAge: TimeInterval = 30

    private(set) var connectionState: ConnectionState = .connecting
    private(set) var quota: QuotaSnapshot?
    private(set) var speedMode: SpeedMode = .standard
    private(set) var errorMessage: String?
    private(set) var isPetVisible = true
    private(set) var petSize: PetSize
    private(set) var tooltipStyle: TooltipStyle
    private(set) var showsQuotaDynamics: Bool
    private(set) var isPetPositionLocked: Bool
    private(set) var passesPointerInputThrough: Bool
    private(set) var quotaHistory: QuotaHistoryPresentation
    private(set) var quotaHistoryIssue: QuotaHistoryIssue?
    private(set) var hidesInFullScreenApps: Bool
    private(set) var launchAtLoginStatus: SMAppService.Status
    private(set) var launchAtLoginError: String?
    private(set) var absorptionRequestID = 0
    private(set) var absorptionResetID = 0
    private(set) var quotaConsumptionEvent: QuotaConsumptionEvent?
    private(set) var quotaReactionResetID = 0
    private(set) var quotaReactionPresentationAllowed = true

    private let appServer: any CodexAppServerClient
    private let defaults: UserDefaults
    private let retryDelays: [TimeInterval]
    private let launchAtLoginStatusProvider: () -> SMAppService.Status
    private let updateLaunchAtLogin: (Bool) throws -> Void
    private let now: () -> Date
    private let historyStore: QuotaHistoryStore
    private var hasStarted = false
    private var quotaUpdatedAt: Date?
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var requiresHistoryGap = true
    private var requiresQuotaReactionBaseline = true
    private var historyRevision = -1
    private var quotaConsumptionCadence = QuotaConsumptionCadence()
    private var quotaConsumptionEventID = 0

    init(
        defaults: UserDefaults = .standard,
        appServer: any CodexAppServerClient = CodexAppServer(),
        retryDelays: [TimeInterval] = AppState.reconnectDelays,
        launchAtLoginStatusProvider: @escaping () -> SMAppService.Status = {
            SMAppService.mainApp.status
        },
        updateLaunchAtLogin: @escaping (Bool) throws -> Void = { isEnabled in
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        },
        now: @escaping () -> Date = Date.init,
        historyStore: QuotaHistoryStore = QuotaHistoryStore()
    ) {
        self.defaults = defaults
        self.appServer = appServer
        self.retryDelays = retryDelays
        self.launchAtLoginStatusProvider = launchAtLoginStatusProvider
        self.updateLaunchAtLogin = updateLaunchAtLogin
        self.now = now
        self.historyStore = historyStore
        quotaHistory = .empty(now: now())
        launchAtLoginStatus = launchAtLoginStatusProvider()
        petSize = PetSize(
            rawValue: defaults.string(forKey: AppConstants.petSizeKey) ?? ""
        ) ?? .large
        #if DEBUG
        if let previewSize = ProcessInfo.processInfo.environment["BLACK_HOLE_SIZE_PREVIEW"],
           let size = PetSize(rawValue: previewSize) {
            petSize = size
        }
        #endif
        tooltipStyle = TooltipStyle(
            rawValue: defaults.string(forKey: AppConstants.tooltipStyleKey) ?? ""
        ) ?? .smooth
        showsQuotaDynamics = defaults.object(forKey: AppConstants.showQuotaDynamicsKey)
            as? Bool ?? true
        isPetPositionLocked = Self.storedBoolean(
            in: defaults,
            forKey: AppConstants.petPositionLockedKey
        )
        passesPointerInputThrough = Self.storedBoolean(
            in: defaults,
            forKey: AppConstants.passesPointerInputThroughKey
        )
        hidesInFullScreenApps = defaults.bool(forKey: AppConstants.hideInFullScreenAppsKey)
    }

    var launchesAtLogin: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        let loadedAt = now()
        Task { [weak self, historyStore] in
            let update = await historyStore.load(at: loadedAt)
            self?.applyHistoryUpdate(update)
        }
        connect(isRetry: false)
    }

    func retryNow() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        requiresHistoryGap = true
        requiresQuotaReactionBaseline = true
        resetQuotaConsumptionContinuity()

        if hasStarted {
            connect(isRetry: false)
        } else {
            start()
        }
    }

    func stop() {
        hasStarted = false
        reconnectTask?.cancel()
        reconnectTask = nil
        appServer.stop()
        connectionState = .disconnected
        requiresHistoryGap = true
        requiresQuotaReactionBaseline = true
        resetQuotaConsumptionContinuity()
    }

    func refreshQuotaIfStale(
        maxAge: TimeInterval = AppState.quotaRefreshMaxAge
    ) {
        guard hasStarted, connectionState == .connected else { return }
        if maxAge > 0, let quotaUpdatedAt {
            let age = now().timeIntervalSince(quotaUpdatedAt)
            if age >= 0, age < maxAge { return }
        }

        appServer.refreshRateLimits()
    }

    private func connect(isRetry: Bool) {
        connectionState = isRetry ? .reconnecting : .connecting
        errorMessage = nil

        do {
            try appServer.start(
                onSnapshot: { [weak self] snapshot in
                    Task { @MainActor [weak self] in
                        self?.didReceive(snapshot)
                    }
                },
                onSpeedMode: { [weak self] speedMode in
                    Task { @MainActor [weak self] in
                        self?.speedMode = speedMode
                    }
                },
                onFailure: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.didFail(message)
                    }
                }
            )
        } catch {
            didFail(error.localizedDescription)
        }
    }

    private func didReceive(_ snapshot: QuotaSnapshot) {
        let observedAt = now()
        let forceHistoryGap = requiresHistoryGap
        let forceQuotaReactionBaseline = requiresQuotaReactionBaseline
        requiresHistoryGap = false
        requiresQuotaReactionBaseline = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        let currentSample = QuotaHistorySample(snapshot: snapshot, observedAt: observedAt)
        let quotaTransition: QuotaSnapshotTransition?
        let reachesZero: Bool
        if let quota, let quotaUpdatedAt {
            let acceptedPreviousSample = QuotaHistorySample(
                snapshot: quota,
                observedAt: quotaUpdatedAt
            )
            quotaTransition = QuotaHistoryClassifier.transition(
                previousSample: acceptedPreviousSample,
                currentSample: currentSample,
                previousWindow: acceptedPreviousSample.primary,
                currentWindow: currentSample.primary,
                forceGap: forceQuotaReactionBaseline
            )
            reachesZero = (acceptedPreviousSample.primary?.remainingPercent ?? 0) > 0
                && currentSample.primary?.remainingPercent == 0
        } else {
            quotaTransition = nil
            reachesZero = false
        }

        quota = snapshot
        quotaUpdatedAt = observedAt
        errorMessage = nil
        connectionState = .connected
        if let quotaTransition {
            applyQuotaTransition(
                quotaTransition,
                reachesZero: reachesZero
            )
        } else {
            resetQuotaConsumptionContinuity()
        }
        Task { [weak self, historyStore] in
            let update = await historyStore.record(
                snapshot: snapshot,
                at: observedAt,
                forceGap: forceHistoryGap
            )
            self?.applyHistoryUpdate(update)
        }
    }

    private func didFail(_ message: String) {
        guard hasStarted, reconnectTask == nil else {
            return
        }

        errorMessage = message
        connectionState = .reconnecting
        requiresHistoryGap = true
        requiresQuotaReactionBaseline = true
        resetQuotaConsumptionContinuity()

        let delay = retryDelays.isEmpty
            ? 0
            : retryDelays[min(reconnectAttempt, retryDelays.count - 1)]
        reconnectAttempt += 1

        reconnectTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self, self.hasStarted else {
                return
            }

            self.reconnectTask = nil
            self.connect(isRetry: true)
        }
    }

    func togglePetVisibility() {
        isPetVisible.toggle()
        if !isPetVisible {
            setQuotaReactionPresentationAllowed(false)
        }
    }

    func requestAbsorption() {
        absorptionRequestID &+= 1
    }

    func resetAbsorptionScene() {
        absorptionResetID &+= 1
    }

    func cancelQuotaReactionPresentation() {
        quotaReactionResetID &+= 1
    }

    func setQuotaReactionPresentationAllowed(_ isAllowed: Bool) {
        guard isAllowed != quotaReactionPresentationAllowed else { return }
        quotaReactionPresentationAllowed = isAllowed
        if !isAllowed {
            cancelQuotaReactionPresentation()
        }
    }

    func setPetSize(_ size: PetSize) {
        guard size != petSize else { return }
        petSize = size
        defaults.set(size.rawValue, forKey: AppConstants.petSizeKey)
        resetAbsorptionScene()
        cancelQuotaReactionPresentation()
    }

    func setTooltipStyle(_ style: TooltipStyle) {
        guard style != tooltipStyle else { return }
        tooltipStyle = style
        defaults.set(style.rawValue, forKey: AppConstants.tooltipStyleKey)
    }

    func setShowsQuotaDynamics(_ isEnabled: Bool) {
        guard isEnabled != showsQuotaDynamics else { return }
        showsQuotaDynamics = isEnabled
        defaults.set(isEnabled, forKey: AppConstants.showQuotaDynamicsKey)
    }

    func setPetPositionLocked(_ isLocked: Bool) {
        guard isLocked != isPetPositionLocked else { return }
        isPetPositionLocked = isLocked
        defaults.set(isLocked, forKey: AppConstants.petPositionLockedKey)
    }

    func setPassesPointerInputThrough(_ passesThrough: Bool) {
        guard passesThrough != passesPointerInputThrough else { return }
        passesPointerInputThrough = passesThrough
        defaults.set(passesThrough, forKey: AppConstants.passesPointerInputThroughKey)
    }

    func noteWakeForQuotaHistory() {
        requiresHistoryGap = true
        requiresQuotaReactionBaseline = true
        resetQuotaConsumptionContinuity()
    }

    func clearQuotaHistory() {
        let clearedAt = now()
        Task { [weak self, historyStore] in
            let update = await historyStore.clear(at: clearedAt)
            self?.applyHistoryUpdate(update)
            self?.requiresHistoryGap = true
        }
    }

    func setHidesInFullScreenApps(_ isEnabled: Bool) {
        hidesInFullScreenApps = isEnabled
        defaults.set(isEnabled, forKey: AppConstants.hideInFullScreenAppsKey)
    }

    func setLaunchesAtLogin(_ isEnabled: Bool) {
        guard isEnabled != launchesAtLogin else { return }

        do {
            try updateLaunchAtLogin(isEnabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginStatusProvider()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func applyHistoryUpdate(_ update: QuotaHistoryStoreUpdate) {
        guard update.revision >= historyRevision else { return }
        historyRevision = update.revision
        quotaHistory = update.presentation
        quotaHistoryIssue = update.issue
    }

    private func applyQuotaTransition(
        _ transition: QuotaSnapshotTransition,
        reachesZero: Bool
    ) {
        switch transition {
        case .duplicate:
            return
        case let .consumption(delta):
            guard let kind = quotaConsumptionCadence.advance(
                by: delta,
                reachesZero: reachesZero
            ) else { return }
            quotaConsumptionEventID &+= 1
            let event = QuotaConsumptionEvent(id: quotaConsumptionEventID, kind: kind)
            if quotaReactionPresentationAllowed {
                quotaConsumptionEvent = event
            }
        case .reset:
            resetQuotaConsumptionContinuity()
        case .correction, .discontinuity:
            resetQuotaConsumptionContinuity()
        }
    }

    private func resetQuotaConsumptionContinuity() {
        quotaConsumptionCadence.reset()
        cancelQuotaReactionPresentation()
    }

    nonisolated private static func storedBoolean(
        in defaults: UserDefaults,
        forKey key: String
    ) -> Bool {
        guard let value = defaults.object(forKey: key) as CFTypeRef?,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }
        return (value as! NSNumber).boolValue
    }
}

enum TooltipStyle: String, CaseIterable, Sendable {
    case smooth
    case pixel

    var title: String {
        NSLocalizedString(
            self == .smooth ? "tooltip_style.smooth" : "tooltip_style.pixel",
            comment: "Tooltip visual style"
        )
    }
}

enum PetSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    var label: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    var sceneSize: CGSize {
        switch self {
        case .small: CGSize(width: 240, height: 132)
        case .medium: CGSize(width: 320, height: 176)
        case .large: CGSize(width: 400, height: 220)
        }
    }

    var scale: CGFloat {
        sceneSize.width / PetSize.large.sceneSize.width
    }
}

enum SpeedMode: Equatable, Sendable {
    case standard
    case turbo

    var title: String {
        NSLocalizedString(
            self == .turbo ? "mode.turbo" : "mode.standard",
            comment: "Codex speed mode"
        )
    }
}

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case reconnecting
    case connected

    var title: String {
        let key = switch self {
        case .disconnected:
            "connection.disconnected"
        case .connecting:
            "connection.connecting"
        case .reconnecting:
            "connection.reconnecting"
        case .connected:
            "connection.connected"
        }
        return NSLocalizedString(key, comment: "Codex connection state")
    }
}
