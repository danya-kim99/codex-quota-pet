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
                setHidesInFullScreenApps: appDelegate.setHidesInFullScreenApps
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
            resetDate: appDelegate.appState.quota?.primary?.resetDate
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let petPanel = PetPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.start()
        petPanel.startMonitoring(appState: appState)
    }

    func applicationWillTerminate(_ notification: Notification) {
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
}
