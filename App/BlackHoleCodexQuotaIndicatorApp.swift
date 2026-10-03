import AppKit
import SwiftUI

@main
struct BlackHoleEntryPoint {
    static func main() {
        if let status = CompanionActivityHook.runIfRequested(arguments: CommandLine.arguments) {
            exit(status)
        }
        if let status = CompletionNotifyAdapter.runIfRequested(arguments: CommandLine.arguments) {
            exit(status)
        }
        BlackHoleCodexQuotaIndicatorApp.main()
    }
}

struct BlackHoleCodexQuotaIndicatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                appState: appDelegate.appState,
                togglePetVisibility: appDelegate.togglePetVisibility,
                setPetSize: appDelegate.setPetSize,
                setPetPositionLocked: appDelegate.setPetPositionLocked,
                setPassesPointerInputThrough: appDelegate.setPassesPointerInputThrough,
                setTooltipStyle: appDelegate.setTooltipStyle,
                setShowsQuotaDynamics: appDelegate.setShowsQuotaDynamics,
                setShowsCodexResetForecast: appDelegate.setShowsCodexResetForecast,
                clearQuotaHistory: appDelegate.clearQuotaHistory,
                setShowsOnlyWhenCodexIsActive: appDelegate.setShowsOnlyWhenCodexIsActive,
                setHidesInFullScreenApps: appDelegate.setHidesInFullScreenApps,
                openCompanionPicker: appDelegate.openCompanionPicker,
                checkForUpdates: appDelegate.checkForUpdates
            )
        } label: {
            Label {
                Text(
                    appDelegate.appState.quota?.primary.map { "\($0.remainingPercent)%" }
                        ?? NSLocalizedString("menu.quota.short", comment: "Menu bar quota label")
                )
            } icon: {
                Image("MenuBarIcon")
                    .renderingMode(.template)
            }
            .accessibilityLabel(
                NSLocalizedString("accessibility.quota", comment: "Menu bar accessibility label")
            )
            .accessibilityValue(menuBarAccessibilityValue)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarAccessibilityValue: String {
        QuotaTooltipView.accessibilitySummary(
            remainingPercent: appDelegate.appState.quota?.primary?.remainingPercent,
            speedMode: appDelegate.appState.speedMode,
            connectionState: appDelegate.appState.connectionState,
            resetDate: appDelegate.appState.quota?.primary?.resetDate,
            history: appDelegate.appState.quotaHistory,
            showsQuotaDynamics: appDelegate.appState.showsQuotaDynamics
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    private var activeCompletionMenus = Set<ObjectIdentifier>()
    private var observesCompletionMenus = false
    private lazy var petPanel = PetPanelController(
        checkForUpdates: { [weak self] in self?.checkForUpdates() },
        clearQuotaHistory: { [weak self] in self?.clearQuotaHistory() },
        openCompanionPicker: { [weak self] in self?.openCompanionPicker() }
    )
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private let terminationGate = UpdateTerminationGate()
    private lazy var appUpdater = AppUpdater(
        appState: appState,
        beforePresentation: { [weak self] in self?.petPanel.dismissTransientUI() },
        prepareTermination: { [weak self] completion in
            guard let self else { completion(false); return }
            self.prepareUpdateTermination(completion: completion)
        },
        didCancel: { [weak self] in self?.cancelUpdateTermination() }
    )

    override init() {
        appState = AppState()
        super.init()
    }

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func startCompletionMenuTracking() {
        guard !observesCompletionMenus else { return }
        observesCompletionMenus = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(completionMenuDidBeginTracking(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(completionMenuDidEndTracking(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
    }

    func stopCompletionMenuTracking() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
        center.removeObserver(self, name: NSMenu.didEndTrackingNotification, object: nil)
        observesCompletionMenus = false
        activeCompletionMenus.removeAll()
        appState.setCompletionNativeMenuOpen(false)
    }

    // AppKit posts these synchronously on the main thread, including nested menus.
    @objc private func completionMenuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        activeCompletionMenus.insert(ObjectIdentifier(menu))
        appState.setCompletionNativeMenuOpen(!activeCompletionMenus.isEmpty)
    }

    @objc private func completionMenuDidEndTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        activeCompletionMenus.remove(ObjectIdentifier(menu))
        appState.setCompletionNativeMenuOpen(!activeCompletionMenus.isEmpty)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startCompletionMenuTracking()
        if let handoff = UpdateHandoff.consume(for: currentBuild) {
            appState.restoreUpdateVisibility(handoff.isPetVisible)
            petPanel.restoreFrameAfterUpdate(handoff.frame)
        }
        appState.start()
        petPanel.startMonitoring(appState: appState)
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.setCompletionSleeping(true)
                self?.petPanel.dismissTransientUI()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.setCompletionSleeping(false)
                self?.appState.noteWakeForQuotaHistory()
                self?.appState.refreshQuotaIfStale(maxAge: 0)
                self?.appState.refreshCodexResetForecastIfStale()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard appUpdater.targetBuild != nil else { return .terminateNow }
        if terminationGate.isPrepared { return .terminateNow }
        prepareUpdateTermination { success in
            sender.reply(toApplicationShouldTerminate: success)
        }
        return .terminateLater
    }

    private var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    private func prepareUpdateTermination(completion: @escaping (Bool) -> Void) {
        petPanel.dismissTransientUI()
        appState.beginTermination()
        terminationGate.prepare(
            operation: { [appState] in await appState.drainHistoryForTermination() },
            commit: { [weak self] in
                guard let self, let target = self.appUpdater.targetBuild else { return false }
                do {
                    try UpdateHandoff(
                        sourceBuild: self.currentBuild, targetBuild: target,
                        frame: self.petPanel.petFrame, isPetVisible: self.appState.isPetVisible
                    ).save()
                    return true
                } catch { return false }
            }
        ) { [weak self] success in
            if !success, let self, self.appState.isPreparingToTerminate {
                self.cancelUpdateTermination()
                self.appUpdater.showError("update.save_failed")
            }
            completion(success)
        }
    }

    private func cancelUpdateTermination() {
        terminationGate.reset()
        if appState.isPreparingToTerminate {
            appState.cancelTermination()
        }
        do {
            try UpdateHandoff.clear()
        } catch {
            appUpdater.showError("update.handoff_clear_failed", detail: error.localizedDescription)
        }
    }

    func openCompanionPicker() {
        petPanel.showCompanionPicker(appState: appState)
    }

    func checkForUpdates() {
        appUpdater.checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopCompletionMenuTracking()
        petPanel.dismissTransientUI()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        appState.stop()
    }

    func togglePetVisibility() {
        appState.togglePetVisibility()

        petPanel.updateVisibility(appState: appState)
    }

    func setHidesInFullScreenApps(_ isEnabled: Bool) {
        appState.setHidesInFullScreenApps(isEnabled)
        petPanel.updateVisibility(appState: appState)
    }

    func setShowsOnlyWhenCodexIsActive(_ isEnabled: Bool) {
        appState.setShowsOnlyWhenCodexIsActive(isEnabled)
        petPanel.updateVisibility(appState: appState)
    }

    func setPetSize(_ size: PetSize) {
        guard size != appState.petSize else { return }
        appState.setPetSize(size)
        petPanel.resize(to: size)
    }

    func setPetPositionLocked(_ isLocked: Bool) {
        guard isLocked != appState.isPetPositionLocked else { return }
        appState.setPetPositionLocked(isLocked)
        petPanel.positionLockDidChange()
    }

    func setPassesPointerInputThrough(_ passesThrough: Bool) {
        guard passesThrough != appState.passesPointerInputThrough else { return }
        appState.setPassesPointerInputThrough(passesThrough)
        petPanel.pointerClickThroughDidChange()
    }

    func setTooltipStyle(_ style: TooltipStyle) {
        guard style != appState.tooltipStyle else { return }
        appState.setTooltipStyle(style)
        petPanel.updateTooltipLayout()
    }

    func setShowsQuotaDynamics(_ isEnabled: Bool) {
        guard isEnabled != appState.showsQuotaDynamics else { return }
        appState.setShowsQuotaDynamics(isEnabled)
        petPanel.updateTooltipLayout()
    }

    func setShowsCodexResetForecast(_ isEnabled: Bool) {
        appState.setShowsCodexResetForecast(isEnabled)
    }

    func clearQuotaHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "history.clear.confirmation.title",
            comment: "Clear local quota history confirmation title"
        )
        alert.informativeText = NSLocalizedString(
            "history.clear.confirmation.message",
            comment: "Clear local quota history confirmation message"
        )
        alert.addButton(withTitle: NSLocalizedString("common.cancel", comment: "Cancel"))
        let clearButton = alert.addButton(
            withTitle: NSLocalizedString("history.clear.action", comment: "Clear history")
        )
        clearButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        appState.clearQuotaHistory()
    }
}
