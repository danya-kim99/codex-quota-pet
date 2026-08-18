import AppKit
import SwiftUI

struct MenuBarContent: View {
    let appState: AppState
    let togglePetVisibility: () -> Void
    let setPetSize: (PetSize) -> Void
    let setPetPositionLocked: (Bool) -> Void
    let setPassesPointerInputThrough: (Bool) -> Void
    let setTooltipStyle: (TooltipStyle) -> Void
    let setShowsQuotaDynamics: (Bool) -> Void
    let clearQuotaHistory: () -> Void
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

            Menu(
                String.localizedStringWithFormat(
                    localized("menu.object_mix.format"),
                    appState.absorptionCategoryWeightsSummary
                )
            ) {
                Text(localized("menu.object_mix.hint.frequency"))
                Text(localized("menu.object_mix.hint.zero"))

                ForEach(appState.absorptionCategories, id: \.id) { category in
                    let currentWeight = appState.absorptionCategoryWeights[
                        category.id,
                        default: category.weight
                    ]
                    Picker(
                        String.localizedStringWithFormat(
                            localized("menu.object_mix.category.format"),
                            localized("absorption.category.\(category.id)"),
                            currentWeight
                        ),
                        selection: Binding(
                            get: { currentWeight },
                            set: {
                                appState.setAbsorptionCategoryWeight(
                                    $0,
                                    for: category.id
                                )
                            }
                        )
                    ) {
                        ForEach(0...3, id: \.self) { weight in
                            Text(weight == 0 ? localized("menu.object_mix.off") : String(weight))
                                .tag(weight)
                                .disabled(
                                    !appState.canSetAbsorptionCategoryWeight(
                                        weight,
                                        for: category.id
                                    )
                                )
                        }
                    }
                    .help(localized("menu.object_mix.hint"))
                    .accessibilityValue(
                        currentWeight == 0
                            ? localized("menu.object_mix.off")
                            : String(currentWeight)
                    )
                    .accessibilityHint(localized("menu.object_mix.hint"))
                }
            }
            .help(localized("menu.object_mix.hint"))
            .accessibilityHint(localized("menu.object_mix.hint"))

            Toggle(
                localized("menu.lock_position"),
                isOn: Binding(
                    get: { appState.isPetPositionLocked },
                    set: setPetPositionLocked
                )
            )
            .help(localized("menu.lock_position.help"))
            .accessibilityHint(localized("menu.lock_position.help"))

            Toggle(
                localized("menu.pass_pointer_input_through"),
                isOn: Binding(
                    get: { appState.passesPointerInputThrough },
                    set: setPassesPointerInputThrough
                )
            )
            .help(localized("menu.pass_pointer_input_through.help"))
            .accessibilityHint(localized("menu.pass_pointer_input_through.help"))

            Picker(
                localized("menu.tooltip_style"),
                selection: Binding(
                    get: { appState.tooltipStyle },
                    set: setTooltipStyle
                )
            ) {
                ForEach(TooltipStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }

            Toggle(
                localized("menu.show_quota_dynamics"),
                isOn: Binding(
                    get: { appState.showsQuotaDynamics },
                    set: setShowsQuotaDynamics
                )
            )

            Button(localized("menu.clear_quota_history")) {
                clearQuotaHistory()
            }

            if let issue = appState.quotaHistoryIssue {
                Text(localized(issue.localizationKey))
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
