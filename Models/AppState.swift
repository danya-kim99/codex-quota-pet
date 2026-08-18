import Foundation
import CoreFoundation
import Observation
import ServiceManagement

enum QuotaConsumptionReactionKind: String, CaseIterable, Codable, Sendable {
    case small
    case medium
    case large
    case lastLight = "last-light"

    var frameCount: Int {
        switch self {
        case .small: 10
        case .medium: 20
        case .large: 30
        case .lastLight: 40
        }
    }

    fileprivate var strength: Int {
        switch self {
        case .small: 0
        case .medium: 1
        case .large: 2
        case .lastLight: 3
        }
    }
}

struct QuotaConsumptionReactionEvent: Equatable, Sendable, Identifiable {
    let id: UInt64
    let kind: QuotaConsumptionReactionKind
    let bucket: Int
}

struct QuotaConsumptionReactionState: Equatable, Sendable {
    private(set) var cadencePosition = 0
    private(set) var active: QuotaConsumptionReactionEvent?
    private(set) var pending: QuotaConsumptionReactionEvent?
    private var nextID: UInt64 = 0

    mutating func acceptConsumption(
        delta: Int,
        remainingPercent: Int,
        isLastLight: Bool,
        isPresentationEligible: Bool,
        reduceMotion: Bool
    ) {
        guard delta > 0 else { return }
        let previousPosition = cadencePosition
        cadencePosition &+= delta
        let kind: QuotaConsumptionReactionKind
        if isLastLight {
            kind = .lastLight
        } else if previousPosition / 10 != cadencePosition / 10 {
            kind = .large
        } else if previousPosition / 5 != cadencePosition / 5 {
            kind = .medium
        } else {
            kind = .small
        }
        guard isPresentationEligible, !(reduceMotion && kind == .lastLight) else {
            return
        }

        nextID &+= 1
        let bucket = ((min(100, max(0, remainingPercent)) + 5) / 10) * 10
        if active == nil {
            active = QuotaConsumptionReactionEvent(id: nextID, kind: kind, bucket: bucket)
        } else {
            let strongest = [pending?.kind, kind]
                .compactMap { $0 }
                .max { $0.strength < $1.strength }!
            pending = QuotaConsumptionReactionEvent(
                id: nextID,
                kind: strongest,
                bucket: bucket
            )
        }
    }

    mutating func complete(eventID: UInt64) {
        guard active?.id == eventID else { return }
        active = pending
        pending = nil
    }

    mutating func cancelPresentation() {
        active = nil
        pending = nil
    }

    mutating func resetContinuity() {
        cadencePosition = 0
        cancelPresentation()
    }

    #if DEBUG
    mutating func preview(kind: QuotaConsumptionReactionKind, bucket: Int) {
        nextID &+= 1
        active = QuotaConsumptionReactionEvent(id: nextID, kind: kind, bucket: bucket)
        pending = nil
    }
    #endif
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
    private(set) var absorptionCategoryWeights: [String: Int]
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
    private(set) var quotaConsumptionReaction = QuotaConsumptionReactionState()

    private let appServer: any CodexAppServerClient
    private let defaults: UserDefaults
    private let absorptionCatalog: AbsorbableObjectCatalog?
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
    private var historyRevision = -1
    private var previousAcceptedQuotaSample: QuotaHistorySample?
    private var isQuotaConsumptionPanelPresented = false
    private var isQuotaConsumptionDragging = false
    private var isQuotaConsumptionResizing = false
    private var isQuotaConsumptionContextMenuPresented = false
    private var isQuotaConsumptionFullScreenSuppressed = false
    private var quotaConsumptionAbsorptionCount = 0
    private var quotaConsumptionReduceMotion = false

    var activeQuotaConsumptionReaction: QuotaConsumptionReactionEvent? {
        quotaConsumptionReaction.active
    }

    var pendingQuotaConsumptionReaction: QuotaConsumptionReactionEvent? {
        quotaConsumptionReaction.pending
    }

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
        absorptionCatalog: AbsorbableObjectCatalog? = try? AbsorbableObjectCatalog()
    ) {
        self.defaults = defaults
        self.absorptionCatalog = absorptionCatalog
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
        absorptionCategoryWeights = absorptionCatalog?.resolvedCategoryWeights(
            from: defaults.object(forKey: AppConstants.absorptionCategoryWeightsKey)
        ) ?? [:]
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

    var absorptionCategories: [AbsorbableObjectManifest.Category] {
        absorptionCatalog?.manifest.categories ?? []
    }

    var absorptionCategoryWeightsSummary: String {
        absorptionCategories.map {
            String(absorptionCategoryWeights[$0.id, default: $0.weight])
        }.joined(separator: ":")
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
        acceptQuotaTransition(
            primaryTransition,
            previousRemainingPercent: previousSample?.primary?.remainingPercent,
            currentRemainingPercent: currentSample.primary?.remainingPercent
        )
        quota = snapshot
        quotaUpdatedAt = observedAt
        errorMessage = nil
        connectionState = .connected
        Task { [weak self, historyStore] in
            let update = await historyStore.record(
                snapshot: snapshot,
                at: observedAt,
                forceGap: forceHistoryGap,
                primaryTransition: primaryTransition
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
        if !isPetVisible { cancelQuotaConsumptionPresentation() }
    }

    func requestAbsorption() {
        absorptionRequestID &+= 1
    }

    func resetAbsorptionScene() {
        absorptionResetID &+= 1
    }

    func setPetSize(_ size: PetSize) {
        guard size != petSize else { return }
        cancelQuotaConsumptionPresentation()
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
        resetQuotaConsumptionContinuity()
    }

    func clearQuotaHistory() {
        let clearedAt = now()
        Task { [weak self, historyStore] in
            let update = await historyStore.clear(at: clearedAt)
            self?.applyHistoryUpdate(update)
        }
    }

    func setQuotaConsumptionPanelPresented(_ isPresented: Bool) {
        isQuotaConsumptionPanelPresented = isPresented
        if !isPresented { cancelQuotaConsumptionPresentation() }
    }

    func setQuotaConsumptionDragging(_ isDragging: Bool) {
        isQuotaConsumptionDragging = isDragging
        if isDragging { cancelQuotaConsumptionPresentation() }
    }

    func setQuotaConsumptionResizing(_ isResizing: Bool) {
        isQuotaConsumptionResizing = isResizing
        if isResizing { cancelQuotaConsumptionPresentation() }
    }

    func setQuotaConsumptionContextMenuPresented(_ isPresented: Bool) {
        isQuotaConsumptionContextMenuPresented = isPresented
        if isPresented { cancelQuotaConsumptionPresentation() }
    }

    func setQuotaConsumptionFullScreenSuppressed(_ isSuppressed: Bool) {
        isQuotaConsumptionFullScreenSuppressed = isSuppressed
        if isSuppressed { cancelQuotaConsumptionPresentation() }
    }

    func quotaConsumptionAbsorptionDidStart() {
        quotaConsumptionAbsorptionCount &+= 1
        cancelQuotaConsumptionPresentation()
    }

    func quotaConsumptionAbsorptionDidFinish() {
        quotaConsumptionAbsorptionCount = max(0, quotaConsumptionAbsorptionCount - 1)
    }

    func resetQuotaConsumptionAbsorptions() {
        quotaConsumptionAbsorptionCount = 0
    }

    func setQuotaConsumptionReduceMotion(_ reduceMotion: Bool) {
        guard quotaConsumptionReduceMotion != reduceMotion else { return }
        quotaConsumptionReduceMotion = reduceMotion
        cancelQuotaConsumptionPresentation()
    }

    func completeQuotaConsumptionReaction(eventID: UInt64) {
        quotaConsumptionReaction.complete(eventID: eventID)
    }

    func failQuotaConsumptionReaction(eventID: UInt64) {
        guard quotaConsumptionReaction.active?.id == eventID else { return }
        quotaConsumptionReaction.cancelPresentation()
    }

    func cancelQuotaConsumptionPresentation() {
        quotaConsumptionReaction.cancelPresentation()
    }

    #if DEBUG
    func previewQuotaConsumptionReaction(
        kind: QuotaConsumptionReactionKind,
        remainingPercent: Int
    ) {
        let bucket = ((min(100, max(0, remainingPercent)) + 5) / 10) * 10
        quotaConsumptionReaction.preview(kind: kind, bucket: bucket)
    }

    #endif

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

    private var isQuotaConsumptionPresentationEligible: Bool {
        isPetVisible
            && isQuotaConsumptionPanelPresented
            && connectionState == .connected
            && !isQuotaConsumptionDragging
            && !isQuotaConsumptionResizing
            && !isQuotaConsumptionContextMenuPresented
            && !isQuotaConsumptionFullScreenSuppressed
            && quotaConsumptionAbsorptionCount == 0
    }

    private func acceptQuotaTransition(
        _ transition: QuotaSnapshotTransition,
        previousRemainingPercent: Int?,
        currentRemainingPercent: Int?
    ) {
        switch transition {
        case let .consumption(delta):
            guard let currentRemainingPercent else { return }
            let isLastLight = (previousRemainingPercent ?? 0) > 0
                && currentRemainingPercent == 0
            quotaConsumptionReaction.acceptConsumption(
                delta: delta,
                remainingPercent: isLastLight
                    ? previousRemainingPercent!
                    : currentRemainingPercent,
                isLastLight: isLastLight,
                isPresentationEligible: isQuotaConsumptionPresentationEligible,
                reduceMotion: quotaConsumptionReduceMotion
            )
        case .reset:
            quotaConsumptionReaction.resetContinuity()
        case .correction, .discontinuity:
            resetQuotaConsumptionContinuity()
        case .duplicate:
            break
        }
    }

    private func resetQuotaConsumptionContinuity() {
        quotaConsumptionReaction.resetContinuity()
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
