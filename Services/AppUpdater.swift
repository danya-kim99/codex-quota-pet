import AppKit
import CoreFoundation
import Sparkle

enum AppUpdateConfiguration {
    static let feedURL = "https://github.com/danya-kim99/codex-quota-pet/releases/latest/download/appcast.xml"

    static func isValid(_ info: [String: Any]) -> Bool {
        guard info["SUFeedURL"] as? String == feedURL,
              let key = info["SUPublicEDKey"] as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32,
              bytes.contains(where: { $0 != 0 }),
              let expiry = info["SUSignedFeedFailureExpirationInterval"] as? NSNumber,
              CFGetTypeID(expiry) != CFBooleanGetTypeID(),
              expiry.doubleValue.isFinite, expiry.doubleValue == 0 else {
            return false
        }
        let disabled = ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
                        "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling", "SUEnableJavaScript"]
        let enabled = ["SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"]
        return (disabled + enabled).allSatisfy { key in
            guard let value = info[key] as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
            return value.boolValue == enabled.contains(key)
        }
    }
}

@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private weak var appState: AppState?
    private var controller: SPUStandardUpdaterController?
    private var availabilityObservation: NSKeyValueObservation?
    private var allowsRelaunch = true
    private let beforePresentation: () -> Void
    private let prepareTermination: (@escaping (Bool) -> Void) -> Void
    private let didCancel: () -> Void
    private(set) var targetBuild: String?

    init(
        appState: AppState,
        beforePresentation: @escaping () -> Void,
        prepareTermination: @escaping (@escaping (Bool) -> Void) -> Void,
        didCancel: @escaping () -> Void
    ) {
        self.appState = appState
        self.beforePresentation = beforePresentation
        self.prepareTermination = prepareTermination
        self.didCancel = didCancel
        super.init()
    }

    func checkForUpdates() {
        guard appState?.canCheckForUpdates == true else { return }
        beforePresentation()
        guard AppUpdateConfiguration.isValid(Bundle.main.infoDictionary ?? [:]) else {
            showError("update.unconfigured")
            return
        }
        if controller == nil {
            let controller = SPUStandardUpdaterController(
                startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
            )
            do {
                try controller.updater.start()
            } catch {
                showError("update.start_failed", detail: error.localizedDescription)
                return
            }
            self.controller = controller
            // This product has no automatic-update preference, including inherited defaults.
            controller.updater.automaticallyChecksForUpdates = false
            controller.updater.automaticallyDownloadsUpdates = false
            controller.updater.sendsSystemProfile = false
            availabilityObservation = controller.updater.observe(
                \.canCheckForUpdates, options: [.initial, .new]
            ) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.appState?.setCanCheckForUpdates(
                        self.controller?.updater.canCheckForUpdates ?? true
                    )
                }
            }
        }
        appState?.setCanCheckForUpdates(false)
        controller?.checkForUpdates(nil)
    }

    func updater(
        _ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
        forUpdate item: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if choice == .install {
            targetBuild = item.versionString
            allowsRelaunch = true
        } else if choice == .skip {
            cancelPendingUpdate()
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        AppUpdateConfiguration.feedURL
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        targetBuild = item.versionString
        allowsRelaunch = true
    }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        targetBuild = item.versionString
        prepareTermination { [weak self] success in
            self?.allowsRelaunch = success
            // Sparkle 2.9.6 rechecks the veto after this continuation, including failure.
            installHandler()
        }
        return true
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        allowsRelaunch
    }

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        targetBuild = item.versionString
        return false
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        cancelPendingUpdate()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        cancelPendingUpdate()
    }

    func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        // A successful cycle can leave an installation waiting for ordinary Quit.
        if error != nil { cancelPendingUpdate() }
    }

    func cancelPendingUpdate() {
        targetBuild = nil
        didCancel()
    }

    func showError(_ key: String, detail: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("update.error.title", comment: "Update error")
        alert.informativeText = NSLocalizedString(key, comment: "Update recovery")
            + (detail.map { "\n\n" + $0 } ?? "")
        alert.addButton(withTitle: NSLocalizedString("common.ok", comment: "OK"))
        alert.runModal()
    }
}
