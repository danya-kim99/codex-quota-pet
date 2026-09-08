import AppKit
import SwiftUI

@main
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
                clearQuotaHistory: appDelegate.clearQuotaHistory,
                setShowsOnlyWhenCodexIsActive: appDelegate.setShowsOnlyWhenCodexIsActive,
                setHidesInFullScreenApps: appDelegate.setHidesInFullScreenApps,
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
    let appState = AppState()
    private let petPanel = PetPanelController()
    private var wakeObserver: NSObjectProtocol?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let handoff = UpdateHandoff.consume(for: currentBuild) {
            appState.restoreUpdateVisibility(handoff.isPetVisible)
            petPanel.restoreFrameAfterUpdate(handoff.frame)
        }
        appState.start()
        petPanel.startMonitoring(appState: appState)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appState.noteWakeForQuotaHistory()
                self?.appState.refreshQuotaIfStale(maxAge: 0)
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

    func checkForUpdates() {
        appUpdater.checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
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
        petPanel.updateTooltipStyle()
    }

    func setShowsQuotaDynamics(_ isEnabled: Bool) {
        guard isEnabled != appState.showsQuotaDynamics else { return }
        appState.setShowsQuotaDynamics(isEnabled)
        petPanel.updateTooltipLayout()
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
