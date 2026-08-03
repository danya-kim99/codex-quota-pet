import AppKit
import SwiftUI

struct MenuBarContent: View {
    let appState: AppState
    let togglePetVisibility: () -> Void
    let setPetSize: (PetSize) -> Void
    let setHidesInFullScreenApps: (Bool) -> Void

    var body: some View {
        Group {
            if let quota = appState.quota, let primary = quota.primary {
                Text(
                    String.localizedStringWithFormat(
                        localized("quota.percent.remaining"),
                        primary.remainingPercent
                    )
                )
                    .font(.headline)

                if let resetDate = primary.resetDate {
                    Text(
                        String.localizedStringWithFormat(
                            localized("menu.reset"),
                            resetDate.formatted(date: .abbreviated, time: .shortened)
                        )
                    )
                }

                if let secondary = quota.secondary {
                    Text(
                        String.localizedStringWithFormat(
                            localized("menu.secondary.remaining"),
                            secondary.remainingPercent
                        )
                    )
                }

                Text(
                    String.localizedStringWithFormat(
                        localized("menu.mode"),
                        appState.speedMode.title
                    )
                )
            } else {
                Text(appState.connectionState.title)
            }

            if appState.connectionState != .connected {
                if appState.quota != nil {
                    Text(appState.connectionState.title)
                }

                if let errorMessage = appState.errorMessage {
                    Text(shortMenuTitle(errorMessage))
                }

                Button(localized("menu.retry")) {
                    appState.retryNow()
                }
            }

            Divider()

            Button(
                localized(appState.isPetVisible ? "menu.hide_pet" : "menu.show_pet")
            ) {
                togglePetVisibility()
            }

            Picker(
                localized("menu.size"),
                selection: Binding(
                    get: { appState.petSize },
                    set: setPetSize
                )
            ) {
                ForEach(PetSize.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }

            Toggle(
                localized("menu.hide_full_screen"),
                isOn: Binding(
                    get: { appState.hidesInFullScreenApps },
                    set: setHidesInFullScreenApps
                )
            )

            Toggle(
                localized("menu.launch_at_login"),
                isOn: Binding(
                    get: { appState.launchesAtLogin },
                    set: appState.setLaunchesAtLogin
                )
            )

            if appState.launchAtLoginStatus == .requiresApproval {
                Text(localized("menu.approval_required"))
                Button(localized("menu.open_login_items")) {
                    appState.openLoginItemsSettings()
                }
            }

            if let error = appState.launchAtLoginError {
                Text(shortMenuTitle(error))
            }

            Divider()

            Button(
                String.localizedStringWithFormat(
                    localized("menu.quit"),
                    AppConstants.displayName
                )
            ) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear(perform: appState.refreshLaunchAtLoginStatus)
    }

    private func shortMenuTitle(_ title: String) -> String {
        title.count <= 30 ? title : String(title.prefix(29)) + "…"
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "Menu bar item")
    }
}
