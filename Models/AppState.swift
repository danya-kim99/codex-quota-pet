import Foundation
import CoreFoundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppState {
    nonisolated static let reconnectDelays: [TimeInterval] = [1, 2, 5, 10, 30]
    nonisolated static let quotaRefreshMaxAge: TimeInterval = 30

    private(set) var connectionState: ConnectionState = .connecting
    private(set) var quota: QuotaSnapshot?
    private(set) var resetCreditsAvailableCount: Int?
    private(set) var speedMode: SpeedMode = .standard
    private(set) var errorMessage: String?
    private(set) var isPetVisible = true
    private(set) var petSize: PetSize
    private(set) var absorptionCategoryWeights: [String: Int]
    private(set) var tooltipStyle: TooltipStyle
    private(set) var showsQuotaDynamics: Bool
    private(set) var showsCodexResetForecast: Bool
    private(set) var isPetPositionLocked: Bool
    private(set) var passesPointerInputThrough: Bool
    private(set) var quotaHistory: QuotaHistoryPresentation
    private(set) var quotaHistoryIssue: QuotaHistoryIssue?
    private(set) var canCheckForUpdates = true
    private(set) var isPreparingToTerminate = false
    private(set) var hidesInFullScreenApps: Bool
    private(set) var showsOnlyWhenCodexIsActive: Bool
    private(set) var launchAtLoginStatus: SMAppService.Status
    private(set) var launchAtLoginError: String?
    private(set) var absorptionRequestID = 0
    private(set) var absorptionResetID = 0

    private let appServer: any CodexAppServerClient
    private let defaults: UserDefaults
    private let absorptionCatalog: AbsorbableObjectCatalog?
    private let retryDelays: [TimeInterval]
    private let launchAtLoginStatusProvider: () -> SMAppService.Status
    private let updateLaunchAtLogin: (Bool) throws -> Void
    private let now: () -> Date
    private let historyStore: QuotaHistoryStore
    private let fetchCodexResetStatus: @Sendable (String?) async throws -> CodexResetRadar.FetchResult
    private var hasStarted = false
    private var connectionGeneration: UInt64 = 0
    private var quotaUpdatedAt: Date?
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var requiresHistoryGap = true
    private var historyRevision = -1
    private var historyTask: Task<Void, Never>?
    private var previousAcceptedQuotaSample: QuotaHistorySample?
    private var codexResetSignalStorage: CodexResetSignal?
    private var codexResetETag: String?
    private var codexResetFreshUntil: Date?
    private var codexResetTask: Task<Void, Never>?
    private var codexResetGeneration: UInt64 = 0
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
        historyStore: QuotaHistoryStore = QuotaHistoryStore(),
        absorptionCatalog: AbsorbableObjectCatalog? = try? AbsorbableObjectCatalog(),
        fetchCodexResetStatus: @escaping @Sendable (String?) async throws -> CodexResetRadar.FetchResult = {
            try await CodexResetRadar().fetch(eTag: $0)
        }
    ) {
        self.defaults = defaults
        self.absorptionCatalog = absorptionCatalog
        self.appServer = appServer
        self.retryDelays = retryDelays
        self.launchAtLoginStatusProvider = launchAtLoginStatusProvider
        self.updateLaunchAtLogin = updateLaunchAtLogin
        self.now = now
        self.historyStore = historyStore
        self.fetchCodexResetStatus = fetchCodexResetStatus
        quotaHistory = .empty(now: now())
        launchAtLoginStatus = launchAtLoginStatusProvider()
        petSize = PetSize(
            rawValue: defaults.string(forKey: AppConstants.petSizeKey) ?? ""
        ) ?? .large
        absorptionCategoryWeights = absorptionCatalog?.resolvedCategoryWeights(
            from: defaults.object(forKey: AppConstants.absorptionCategoryWeightsKey)
        ) ?? [:]
        tooltipStyle = TooltipStyle(
            rawValue: defaults.string(forKey: AppConstants.tooltipStyleKey) ?? ""
        ) ?? .smooth
        showsQuotaDynamics = defaults.object(forKey: AppConstants.showQuotaDynamicsKey)
            as? Bool ?? true
        showsCodexResetForecast = Self.storedBoolean(
            in: defaults,
            forKey: AppConstants.showCodexResetForecastKey
        )
        isPetPositionLocked = Self.storedBoolean(
            in: defaults,
            forKey: AppConstants.petPositionLockedKey
        )
        passesPointerInputThrough = Self.storedBoolean(
            in: defaults,
            forKey: AppConstants.passesPointerInputThroughKey
        )
        hidesInFullScreenApps = defaults.bool(forKey: AppConstants.hideInFullScreenAppsKey)
        showsOnlyWhenCodexIsActive = Self.storedBoolean(
            in: defaults,
            forKey: AppConstants.showOnlyWhenCodexIsActiveKey
        )
    }

    var launchesAtLogin: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    var codexResetSignal: CodexResetSignal? {
        codexResetSignalStorage?.valid(at: now())
    }

    var absorptionCategories: [AbsorbableObjectManifest.Category] {
        absorptionCatalog?.manifest.categories ?? []
    }

    var absorptionCategoryWeightsSummary: String {
        absorptionCategories.map {
            String(absorptionCategoryWeights[$0.id, default: $0.weight])
        }.joined(separator: ":")
    }

    func start() {
        guard !hasStarted, !isPreparingToTerminate else {
            return
        }

        hasStarted = true
        let loadedAt = now()
        enqueueHistory { [historyStore] in
            await historyStore.load(at: loadedAt)
        }
        connect(isRetry: false)
        refreshCodexResetForecastIfStale()
    }

    func retryNow() {
        guard !isPreparingToTerminate else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        requiresHistoryGap = true

        if hasStarted {
            connect(isRetry: false)
        } else {
            start()
        }
    }

    func stop() {
        connectionGeneration &+= 1
        hasStarted = false
        reconnectTask?.cancel()
        reconnectTask = nil
        appServer.stop()
        cancelCodexResetForecast(clearCache: true)
        resetCreditsAvailableCount = nil
        connectionState = .disconnected
        requiresHistoryGap = true
    }

    func refreshCodexResetForecastIfStale() {
        guard hasStarted,
              !isPreparingToTerminate,
              showsCodexResetForecast,
              codexResetTask == nil else {
            return
        }
        let requestedAt = now()
        if let codexResetFreshUntil, requestedAt < codexResetFreshUntil {
            return
        }

        codexResetGeneration &+= 1
        let generation = codexResetGeneration
        let eTag = codexResetETag
        codexResetTask = Task { @MainActor [weak self, fetchCodexResetStatus] in
            do {
                let result = try await fetchCodexResetStatus(eTag)
                guard !Task.isCancelled,
                      let self,
                      self.codexResetGeneration == generation,
                      self.hasStarted,
                      self.showsCodexResetForecast else {
                    return
                }
                self.applyCodexResetResult(result)
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.codexResetGeneration == generation,
                      self.hasStarted,
                      self.showsCodexResetForecast else {
                    return
                }
                self.codexResetSignalStorage = nil
                self.codexResetETag = nil
                let delay: TimeInterval
                if case let CodexResetRadar.FetchError.retryAfter(retryAfter) = error {
                    delay = retryAfter
                } else {
                    delay = CodexResetRadar.fallbackFreshness
                }
                self.codexResetFreshUntil = self.now().addingTimeInterval(delay)
                self.codexResetTask = nil
            }
        }
    }

    func setShowsCodexResetForecast(_ isEnabled: Bool) {
        guard isEnabled != showsCodexResetForecast else { return }
        showsCodexResetForecast = isEnabled
        defaults.set(isEnabled, forKey: AppConstants.showCodexResetForecastKey)
        if isEnabled {
            codexResetFreshUntil = nil
            refreshCodexResetForecastIfStale()
        } else {
            cancelCodexResetForecast(clearCache: true)
        }
    }

    private func applyCodexResetResult(_ result: CodexResetRadar.FetchResult) {
        let receivedAt = now()
        switch result {
        case let .updated(signal, eTag, maxAge):
            codexResetSignalStorage = signal?.valid(at: receivedAt)
            codexResetETag = eTag
            codexResetFreshUntil = receivedAt.addingTimeInterval(maxAge)
        case let .notModified(maxAge):
            codexResetSignalStorage = codexResetSignalStorage?.valid(at: receivedAt)
            codexResetFreshUntil = receivedAt.addingTimeInterval(maxAge)
        }
        codexResetTask = nil
    }

    private func cancelCodexResetForecast(clearCache: Bool) {
        codexResetGeneration &+= 1
        codexResetTask?.cancel()
        codexResetTask = nil
        codexResetSignalStorage = nil
        guard clearCache else { return }
        codexResetETag = nil
        codexResetFreshUntil = nil
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
        connectionGeneration &+= 1
        let generation = connectionGeneration
        resetCreditsAvailableCount = nil
        connectionState = isRetry ? .reconnecting : .connecting
        errorMessage = nil

        do {
            try appServer.start(
                onSnapshot: { [weak self] snapshot, resetCreditsAvailableCount in
                    Task { @MainActor [weak self] in
                        guard let self, self.connectionGeneration == generation else { return }
                        self.didReceive(
                            snapshot,
                            resetCreditsAvailableCount: resetCreditsAvailableCount
                        )
                    }
                },
                onSpeedMode: { [weak self] speedMode in
                    Task { @MainActor [weak self] in
                        guard let self, self.connectionGeneration == generation else { return }
                        self.speedMode = speedMode
                    }
                },
                onFailure: { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.connectionGeneration == generation else { return }
                        self.didFail(message)
                    }
                }
            )
        } catch {
            didFail(error.localizedDescription)
        }
    }

    private func didReceive(
        _ snapshot: QuotaSnapshot,
        resetCreditsAvailableCount: Int?
    ) {
        let observedAt = now()
        let forceHistoryGap = requiresHistoryGap
        let currentSample = QuotaHistorySample(snapshot: snapshot, observedAt: observedAt)
        let previousSample = previousAcceptedQuotaSample
        let primaryTransition = previousSample.map {
            QuotaHistoryClassifier.transition(
                previousSample: $0,
                currentSample: currentSample,
                previousWindow: $0.primary,
                currentWindow: currentSample.primary,
                forceGap: forceHistoryGap
            )
        } ?? .discontinuity
        requiresHistoryGap = false
        previousAcceptedQuotaSample = currentSample
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        quota = snapshot
        self.resetCreditsAvailableCount = resetCreditsAvailableCount
        quotaUpdatedAt = observedAt
        errorMessage = nil
        connectionState = .connected
        enqueueHistory { [historyStore] in
            await historyStore.record(
                snapshot: snapshot,
                at: observedAt,
                forceGap: forceHistoryGap,
                primaryTransition: primaryTransition
            )
        }
    }

    private func didFail(_ message: String) {
        guard hasStarted, reconnectTask == nil else {
            return
        }

        errorMessage = message
        resetCreditsAvailableCount = nil
        connectionState = .reconnecting
        requiresHistoryGap = true

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
    }

    func requestAbsorption() {
        absorptionRequestID &+= 1
    }

    func resetAbsorptionScene() {
        absorptionResetID &+= 1
    }

    func setPetSize(_ size: PetSize) {
        guard size != petSize else { return }
        petSize = size
        defaults.set(size.rawValue, forKey: AppConstants.petSizeKey)
        resetAbsorptionScene()
    }

    func canSetAbsorptionCategoryWeight(_ weight: Int, for categoryID: String) -> Bool {
        guard 0...3 ~= weight,
              absorptionCategories.contains(where: { $0.id == categoryID }) else {
            return false
        }
        guard weight == 0, absorptionCategoryWeights[categoryID, default: 0] > 0 else {
            return true
        }
        return absorptionCategoryWeights.values.filter { $0 > 0 }.count > 1
    }

    func setAbsorptionCategoryWeight(_ weight: Int, for categoryID: String) {
        guard canSetAbsorptionCategoryWeight(weight, for: categoryID),
              let absorptionCatalog else { return }
        var updated = absorptionCategoryWeights
        updated[categoryID] = weight
        guard let validated = absorptionCatalog.validatedCategoryWeights(updated),
              validated != absorptionCategoryWeights else { return }
        absorptionCategoryWeights = validated
        defaults.set(validated, forKey: AppConstants.absorptionCategoryWeightsKey)
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
    }

    func clearQuotaHistory() {
        guard !isPreparingToTerminate else { return }
        let clearedAt = now()
        enqueueHistory { [historyStore] in
            await historyStore.clear(at: clearedAt)
        }
    }

    func setCanCheckForUpdates(_ value: Bool) {
        canCheckForUpdates = value
    }

    func restoreUpdateVisibility(_ isVisible: Bool) {
        isPetVisible = isVisible
    }

    func beginTermination() {
        guard !isPreparingToTerminate else { return }
        isPreparingToTerminate = true
        stop()
    }

    func drainHistoryForTermination() async -> Bool {
        let previous = historyTask
        let observedAt = now()
        let flush = Task { [historyStore] in
            await previous?.value
            return await historyStore.flush(at: observedAt)
        }
        let tail = Task { [weak self] in
            let update = await flush.value
            self?.applyHistoryUpdate(update)
        }
        historyTask = tail
        await tail.value
        return await flush.value.issue != .notSaved
    }

    func cancelTermination() {
        guard isPreparingToTerminate else { return }
        isPreparingToTerminate = false
        quotaHistoryIssue = .notSaved
        // Resume with a fresh baseline without reloading over pending in-memory writes.
        hasStarted = true
        connect(isRetry: false)
        refreshCodexResetForecastIfStale()
    }

    private func enqueueHistory(
        _ operation: @escaping @Sendable () async -> QuotaHistoryStoreUpdate
    ) {
        let previous = historyTask
        historyTask = Task { [weak self] in
            await previous?.value
            let update = await operation()
            self?.applyHistoryUpdate(update)
        }
    }

    func setHidesInFullScreenApps(_ isEnabled: Bool) {
        hidesInFullScreenApps = isEnabled
        defaults.set(isEnabled, forKey: AppConstants.hideInFullScreenAppsKey)
    }

    func setShowsOnlyWhenCodexIsActive(_ isEnabled: Bool) {
        guard isEnabled != showsOnlyWhenCodexIsActive else { return }
        showsOnlyWhenCodexIsActive = isEnabled
        defaults.set(isEnabled, forKey: AppConstants.showOnlyWhenCodexIsActiveKey)
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
