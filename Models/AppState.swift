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
    private(set) var selectedCompanionID: String?
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
    private(set) var responseNoticesEnabled: Bool
    private(set) var responseNoticeConfigurationBusy = false
    private(set) var responseNoticeIssue: String?
    private(set) var completionNotice: CompletionNotice? {
        didSet { responseNoticeDidChange?() }
    }
    @ObservationIgnored var responseNoticeDidChange: (() -> Void)?
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
    private var codexResetSignalsStorage: [CodexResetSignal]?
    private var codexResetSourceStateStorage: CodexResetSourceState = .loading
    private var codexResetETag: String?
    private var codexResetFreshUntil: Date?
    private var codexResetCacheMaxAge = CodexResetRadar.fallbackFreshness
    private var codexResetNextAttemptAt: Date?
    private var codexResetTask: Task<Void, Never>?
    private var codexResetGeneration: UInt64 = 0
    private var completionObserver: NSObjectProtocol?
    private var completionEpoch = Date()
    private var completionGeneration: UInt64 = 0
    private var completionSeen: [String] = []
    private var completionChecks: [String: Task<Void, Never>] = [:]
    private var completionExpiry: Task<Void, Never>?
    private var completionInteractions = Set<CompletionNoticeInteraction>()
    private var completionAllowed = false
    private var completionNativeMenuOpen = false
    private var completionSleeping = false
    private let companionExperimentToken: String?
    private var companionTracker: CompanionHookTracker
    private var companionHookObserver: NSObjectProtocol?
    private var companionExpiryTask: Task<Void, Never>?
    private var companionGeneration: UInt64 = 0
    private var companionPanelVisible = false
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
        companionExperimentToken: String? = ProcessInfo.processInfo.environment[CompanionActivityHook.environmentKey],
        fetchCodexResetStatus: @escaping @Sendable (String?) async throws -> CodexResetRadar.FetchResult = {
            try await CodexResetRadar().fetch(eTag: $0)
        }
    ) {
        self.defaults = defaults
        self.companionExperimentToken = CompanionActivityHook.token(companionExperimentToken)
        companionTracker = CompanionHookTracker(acceptSince: now())
        responseNoticesEnabled = Self.storedBoolean(in: defaults, forKey: AppConstants.responseNoticesKey)
        self.absorptionCatalog = absorptionCatalog
        selectedCompanionID = absorptionCatalog?.resolvedCompanionID(
            from: defaults.object(forKey: AppConstants.selectedCompanionIDKey)
        )
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

    func setResponseNoticesEnabled(_ enabled: Bool) {
        guard !responseNoticeConfigurationBusy, enabled != responseNoticesEnabled else { return }
        // Disable presentation immediately, even if restoring the user's config fails.
        if !enabled {
            responseNoticesEnabled = false
            defaults.set(false, forKey: AppConstants.responseNoticesKey)
            invalidateCompletionNotices()
        }
        responseNoticeConfigurationBusy = true
        responseNoticeIssue = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.responseNoticeConfigurationBusy = false }
            do {
                guard let executable = Bundle.main.executableURL?.path else { throw CompletionError.configuration }
                let response = try await self.appServer.request(method: "config/read", params: ["includeLayers": true], timeout: 3)
                let storedToken = self.defaults.string(forKey: AppConstants.responseNotifyTokenKey)
                let token = storedToken.flatMap(UUID.init(uuidString:))?.uuidString ?? UUID().uuidString
                let plan = try CompletionConfigPlan.make(response: response, enable: enabled, executable: executable,
                    ownedFingerprint: self.defaults.string(forKey: AppConstants.responseNotifyFingerprintKey), token: token)
                // Store no original argv locally: it remains inside Codex's owned notify command.
                if let wrapper = plan.wrapper, let adapter = CompletionNotifyAdapter.decode(wrapper[2]) {
                    self.defaults.set(CompletionNotifyAdapter.fingerprint(wrapper), forKey: AppConstants.responseNotifyFingerprintKey)
                    self.defaults.set(adapter.token, forKey: AppConstants.responseNotifyTokenKey)
                }
                let result = try await self.appServer.request(method: "config/value/write", params: plan.parameters, timeout: 3)
                guard result["status"] as? String == "ok" else { throw CompletionError.configuration }
                if enabled {
                    self.responseNoticesEnabled = true
                    self.defaults.set(true, forKey: AppConstants.responseNoticesKey)
                    self.invalidateCompletionNotices()
                    self.startCompletionListener()
                }
            } catch {
                self.responseNoticeIssue = "completion.configuration_failed"
            }
        }
    }

    private func startCompletionListener() {
        CompletionTrace.event("listener.start enabled=\(responseNoticesEnabled) existing=\(completionObserver != nil) hasToken=\(defaults.string(forKey: AppConstants.responseNotifyTokenKey) != nil)")
        guard completionObserver == nil, responseNoticesEnabled,
              let token = defaults.string(forKey: AppConstants.responseNotifyTokenKey) else { return }
        completionEpoch = now()
        completionObserver = DistributedNotificationCenter.default().addObserver(
            forName: CompletionNotifyAdapter.notification, object: token, queue: .main
        ) { [weak self] notification in
            CompletionTrace.event("ipc.received")
            // Capture only the bounded IPC metadata, never the raw Codex event.
            guard let fields = notification.userInfo,
                  let threadID = fields["thread"] as? String,
                  let turnID = fields["turn"] as? String,
                  let sentAt = fields["sentAt"] as? Double,
                  sentAt.isFinite,
                  let hint = CompletionHint(threadID: threadID, turnID: turnID) else {
                CompletionTrace.event("ipc.rejected malformed=true")
                return
            }
            CompletionTrace.event("ipc.parsed")
            Task { @MainActor [weak self] in
                self?.receiveCompletionHint(hint, sentAt: Date(timeIntervalSince1970: sentAt))
            }
        }
        CompletionTrace.event("listener.registered")
    }

    func setCompletionPresentationAllowed(_ allowed: Bool) {
        guard completionAllowed != allowed else { return }
        CompletionTrace.event("eligibility.changed allowed=\(allowed)")
        completionAllowed = allowed
        invalidateCompletionNotices()
    }

    func setCompletionNativeMenuOpen(_ open: Bool) {
        guard completionNativeMenuOpen != open else { return }
        CompletionTrace.event("nativeMenu.changed open=\(open)")
        completionNativeMenuOpen = open
        invalidateCompletionNotices()
    }

    func setCompletionSleeping(_ sleeping: Bool) {
        completionSleeping = sleeping
        resetCompanionActivity()
        invalidateCompletionNotices()
    }

    private var canPresentCompletion: Bool {
        hasStarted && !isPreparingToTerminate && responseNoticesEnabled && isPetVisible
            && completionAllowed && !completionSleeping && !completionNativeMenuOpen
            && connectionState == .connected
    }

    func receiveCompletionHint(_ hint: CompletionHint, sentAt: Date) {
        CompletionTrace.event("hint.gates enabled=\(responseNoticesEnabled) started=\(hasStarted) connected=\(connectionState == .connected) visible=\(isPetVisible) allowed=\(completionAllowed) sleeping=\(completionSleeping) nativeMenu=\(completionNativeMenuOpen) terminating=\(isPreparingToTerminate) duplicate=\(completionSeen.contains(hint.key)) age=\(now().timeIntervalSince(sentAt)) epochPassed=\(sentAt >= completionEpoch) inflight=\(completionChecks.count)")
        guard !completionSeen.contains(hint.key) else { return }
        // Remember suppressed/rejected events too: later visibility/reconnect must never replay them.
        completionSeen.append(hint.key)
        // ponytail: 512 recent IDs; raise this bound only above 512 completions per freshness window.
        if completionSeen.count > 512 { completionSeen.removeFirst(completionSeen.count - 512) }
        guard canPresentCompletion, sentAt >= completionEpoch,
              now().timeIntervalSince(sentAt) >= -1, now().timeIntervalSince(sentAt) <= 3,
              completionChecks.count < 8 else { return }
        let generation = completionGeneration
        let epoch = completionEpoch
        completionChecks[hint.key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.completionChecks[hint.key] = nil }
            for (attempt, delay) in [0.0, 0.3, 1.0, 2.0].enumerated() {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, self.completionGeneration == generation, self.canPresentCompletion,
                      self.now().timeIntervalSince(sentAt) <= 12 else {
                    CompletionTrace.event("verification.aborted attempt=\(attempt + 1) cancelled=\(Task.isCancelled) generationCurrent=\(self.completionGeneration == generation) canPresent=\(self.canPresentCompletion)")
                    return
                }
                var stage = "metadata"
                do {
                    CompletionTrace.event("rpc.begin attempt=\(attempt + 1) stage=metadata")
                    let metadata = try await self.appServer.request(method: "thread/read", params: ["threadId": hint.threadID, "includeTurns": false], timeout: 2)
                    CompletionTrace.event("rpc.success attempt=\(attempt + 1) stage=metadata hasThread=\(metadata["thread"] is [String: Any])")
                    guard !Task.isCancelled, self.completionGeneration == generation,
                          let thread = metadata["thread"] as? [String: Any] else {
                        CompletionTrace.event("verification.aborted stage=metadata")
                        return
                    }
                    stage = "turns"
                    CompletionTrace.event("rpc.begin attempt=\(attempt + 1) stage=turns")
                    let turns = try await self.appServer.request(method: "thread/turns/list", params: [
                        "threadId": hint.threadID, "itemsView": "notLoaded", "limit": 8, "sortDirection": "desc"
                    ], timeout: 2)
                    CompletionTrace.event("rpc.success attempt=\(attempt + 1) stage=turns")
                    guard !Task.isCancelled, self.completionGeneration == generation, self.canPresentCompletion else {
                        CompletionTrace.event("verification.aborted stage=turns cancelled=\(Task.isCancelled) generationCurrent=\(self.completionGeneration == generation) canPresent=\(self.canPresentCompletion)")
                        return
                    }
                    switch CompletionVerification.evaluate(hint: hint, thread: thread, turns: turns, since: epoch, now: self.now()) {
                    case .pending:
                        CompletionTrace.event("verification.pending attempt=\(attempt + 1)")
                        continue
                    case .rejected:
                        CompletionTrace.event("verification.rejected attempt=\(attempt + 1)")
                        return
                    case .completed(let title):
                        CompletionTrace.event("verification.completed attempt=\(attempt + 1)")
                        self.presentCompletion(title: title)
                        return
                    }
                } catch {
                    CompletionTrace.event("rpc.error attempt=\(attempt + 1) stage=\(stage)")
                    // A notice lookup failure never changes quota connectivity or its retry loop.
                    continue
                }
            }
            CompletionTrace.event("verification.exhausted")
        }
    }

    private func presentCompletion(title: String) {
        let date = now()
        if var notice = completionNotice, notice.pausedRemaining != nil || notice.deadline > date {
            notice.count += 1
            notice.title = title
            CompletionTrace.event("notice.updated count=\(notice.count) callbackBound=\(responseNoticeDidChange != nil)")
            completionNotice = notice
            return
        }
        completionExpiry?.cancel()
        completionInteractions.removeAll()
        let notice = CompletionNotice(id: UUID(), deadline: date.addingTimeInterval(8), count: 1, title: title)
        CompletionTrace.event("notice.created callbackBound=\(responseNoticeDidChange != nil)")
        completionNotice = notice
        scheduleCompletionExpiry(id: notice.id)
    }

    func dismissCompletionNotice(id: UUID) {
        guard completionNotice?.id == id else { return }
        invalidateCompletionNotices()
    }

    func setCompletionInteraction(_ interaction: CompletionNoticeInteraction, active: Bool, id: UUID) {
        guard var notice = completionNotice, notice.id == id else { return }
        let wasPaused = !completionInteractions.isEmpty
        if active { completionInteractions.insert(interaction) }
        else { completionInteractions.remove(interaction) }
        let isPaused = !completionInteractions.isEmpty
        guard wasPaused != isPaused else { return }
        completionExpiry?.cancel()
        completionExpiry = nil
        if isPaused {
            let remaining = max(0, notice.deadline.timeIntervalSince(now()))
            guard remaining > 0 else { dismissCompletionNotice(id: id); return }
            notice.pausedRemaining = remaining
            completionNotice = notice
        } else {
            notice.deadline = now().addingTimeInterval(notice.pausedRemaining ?? 0)
            notice.pausedRemaining = nil
            completionNotice = notice
            scheduleCompletionExpiry(id: id)
        }
    }

    private func scheduleCompletionExpiry(id: UUID) {
        guard let notice = completionNotice, notice.id == id, notice.pausedRemaining == nil else { return }
        let remaining = max(0, notice.deadline.timeIntervalSince(now()))
        completionExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining), tolerance: .milliseconds(20))
            guard !Task.isCancelled, self?.completionNotice?.id == id else { return }
            self?.completionInteractions.removeAll()
            self?.completionNotice = nil
            self?.completionExpiry = nil
        }
    }

    func invalidateCompletionNotices() {
        completionGeneration &+= 1
        completionEpoch = now()
        completionChecks.values.forEach { $0.cancel() }
        completionChecks.removeAll()
        completionExpiry?.cancel()
        completionExpiry = nil
        completionInteractions.removeAll()
        completionNotice = nil
    }

    var launchesAtLogin: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    var codexResetSignal: CodexResetSignal? {
        codexResetSourceState.signals(at: now()).first
    }

    var codexResetSourceState: CodexResetSourceState {
        guard showsCodexResetForecast else { return .disabled }
        if case .available = codexResetSourceStateStorage,
           let codexResetFreshUntil, now() >= codexResetFreshUntil {
            return codexResetTask == nil ? .unavailable : .loading
        }
        if case let .available(signals, _) = codexResetSourceStateStorage,
           CodexResetSignal.visible(signals, at: now()).isEmpty,
           signals.contains(where: {
               if case let .watch(_, expiry) = $0 { return expiry <= now() }
               return false
           }) {
            return .unavailable
        }
        return codexResetSourceStateStorage
    }

    // Explicitly opted-in, approximate hook hints; ordinary launches remain unavailable.
    var companionActivity: CompanionActivity {
        canReceiveCompanionHooks ? companionTracker.activity : .unavailable
    }

    private var canReceiveCompanionHooks: Bool {
        companionExperimentToken != nil && hasStarted && !isPreparingToTerminate
            && connectionState == .connected && isPetVisible && companionPanelVisible && !completionSleeping
    }

    func setCompanionPanelVisible(_ visible: Bool) {
        guard companionPanelVisible != visible else { return }
        companionPanelVisible = visible
        resetCompanionActivity()
    }

    private func startCompanionHookListener() {
        guard companionHookObserver == nil, let token = companionExperimentToken else { return }
        companionHookObserver = DistributedNotificationCenter.default().addObserver(
            forName: CompanionActivityHook.notification, object: token, queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo, let hint = CompanionHookHint(userInfo: info) else { return }
            Task { @MainActor [weak self] in self?.receiveCompanionHook(hint) }
        }
    }

    func receiveCompanionHook(_ hint: CompanionHookHint) {
        guard canReceiveCompanionHooks else { return }
        companionTracker.receive(hint, now: now())
        scheduleCompanionExpiry()
    }

    func expireCompanionActivity() {
        companionTracker.expire(at: now())
        scheduleCompanionExpiry()
    }

    private func resetCompanionActivity() {
        companionGeneration &+= 1
        companionExpiryTask?.cancel()
        companionExpiryTask = nil
        companionTracker.reset(at: now())
    }

    private func scheduleCompanionExpiry() {
        companionExpiryTask?.cancel()
        companionExpiryTask = nil
        guard canReceiveCompanionHooks, let deadline = companionTracker.nextExpiry else { return }
        let generation = companionGeneration
        let delay = max(0, deadline.timeIntervalSince(now()))
        companionExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.companionGeneration == generation else { return }
            self.expireCompanionActivity()
        }
    }

    var companionObjects: [AbsorbableObjectManifest.Object] {
        absorptionCatalog?.manifest.objects ?? []
    }

    var selectedCompanion: AbsorbableObjectManifest.Object? {
        companionObjects.first { $0.id == selectedCompanionID }
    }

    var companionSelectionName: String {
        selectedCompanion?.companionName ?? NSLocalizedString("companion.none", comment: "No companion")
    }

    func setSelectedCompanionID(_ id: String?) {
        let resolved = absorptionCatalog?.resolvedCompanionID(from: id)
        guard selectedCompanionID != resolved else { return }
        selectedCompanionID = resolved
        if let resolved { defaults.set(resolved, forKey: AppConstants.selectedCompanionIDKey) }
        else { defaults.removeObject(forKey: AppConstants.selectedCompanionIDKey) }
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
        startCompletionListener()
        startCompanionHookListener()
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
        resetCompanionActivity()
        if let companionHookObserver { DistributedNotificationCenter.default().removeObserver(companionHookObserver) }
        companionHookObserver = nil
        invalidateCompletionNotices()
        if let completionObserver { DistributedNotificationCenter.default().removeObserver(completionObserver) }
        completionObserver = nil
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
        if let codexResetNextAttemptAt, requestedAt < codexResetNextAttemptAt {
            return
        }
        if let codexResetFreshUntil, requestedAt < codexResetFreshUntil {
            return
        }

        codexResetNextAttemptAt = requestedAt.addingTimeInterval(
            CodexResetRadar.minimumRefreshInterval
        )
        codexResetSourceStateStorage = .loading
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
                self.codexResetSignalsStorage = nil
                self.codexResetSourceStateStorage = .unavailable
                self.codexResetETag = nil
                let delay: TimeInterval
                if case let CodexResetRadar.FetchError.retryAfter(retryAfter) = error {
                    delay = retryAfter
                } else {
                    delay = CodexResetRadar.fallbackFreshness
                }
                self.codexResetFreshUntil = nil
                self.codexResetNextAttemptAt = self.now().addingTimeInterval(
                    max(CodexResetRadar.minimumRefreshInterval, delay)
                )
                self.codexResetTask = nil
            }
        }
    }

    func setShowsCodexResetForecast(_ isEnabled: Bool) {
        guard isEnabled != showsCodexResetForecast else { return }
        showsCodexResetForecast = isEnabled
        defaults.set(isEnabled, forKey: AppConstants.showCodexResetForecastKey)
        if isEnabled {
            codexResetSourceStateStorage = .loading
            refreshCodexResetForecastIfStale()
        } else {
            cancelCodexResetForecast(clearCache: true)
        }
    }

    private func applyCodexResetResult(_ result: CodexResetRadar.FetchResult) {
        let receivedAt = now()
        switch result {
        case let .updated(signals, eTag, maxAge):
            codexResetSignalsStorage = signals
            codexResetETag = eTag
            codexResetCacheMaxAge = maxAge
            codexResetFreshUntil = receivedAt.addingTimeInterval(max(CodexResetRadar.minimumRefreshInterval, maxAge))
            codexResetNextAttemptAt = receivedAt.addingTimeInterval(
                CodexResetRadar.minimumRefreshInterval
            )
        case let .notModified(updatedMaxAge):
            let maxAge = updatedMaxAge ?? codexResetCacheMaxAge
            codexResetCacheMaxAge = maxAge
            codexResetFreshUntil = receivedAt.addingTimeInterval(max(CodexResetRadar.minimumRefreshInterval, maxAge))
            codexResetNextAttemptAt = receivedAt.addingTimeInterval(
                CodexResetRadar.minimumRefreshInterval
            )
        }
        codexResetSourceStateStorage = codexResetSignalsStorage.map {
            .available(signals: $0, checkedAt: receivedAt)
        } ?? .unavailable
        codexResetTask = nil
    }

    private func cancelCodexResetForecast(clearCache: Bool) {
        codexResetGeneration &+= 1
        codexResetTask?.cancel()
        codexResetTask = nil
        codexResetSignalsStorage = nil
        codexResetSourceStateStorage = .loading
        guard clearCache else { return }
        codexResetETag = nil
        codexResetFreshUntil = nil
        codexResetCacheMaxAge = CodexResetRadar.fallbackFreshness
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
        resetCompanionActivity()
        invalidateCompletionNotices()
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
        if connectionState != .connected { resetCompanionActivity() }
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

        invalidateCompletionNotices()
        resetCompanionActivity()
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
        resetCompanionActivity()
        if !isPetVisible { invalidateCompletionNotices() }
    }

    func requestAbsorption() {
        absorptionRequestID &+= 1
    }

    func resetAbsorptionScene() {
        resetCompanionActivity()
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
        startCompletionListener()
        startCompanionHookListener()
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
