import SwiftUI

enum ContextMenuPlacement: Equatable {
    case aboveLeft
    case aboveRight
    case belowLeft
    case belowRight

    var opensRight: Bool {
        self == .aboveRight || self == .belowRight
    }

    var opensBelow: Bool {
        self == .belowLeft || self == .belowRight
    }

    var transformAnchor: UnitPoint {
        switch self {
        case .aboveLeft: .bottomTrailing
        case .aboveRight: .bottomLeading
        case .belowLeft: .topTrailing
        case .belowRight: .topLeading
        }
    }
}

enum ContextMenuInteraction {
    static let movementThreshold: CGFloat = 6

    static func acceptsClick(
        mouseDown: CGPoint,
        mouseUp: CGPoint,
        visibleRegion: PetVisibleRegion
    ) -> Bool {
        hypot(mouseUp.x - mouseDown.x, mouseUp.y - mouseDown.y) <= movementThreshold
            && visibleRegion.contains(mouseDown)
            && visibleRegion.contains(mouseUp)
    }
}

@MainActor
final class ContextMenuPresentation: ObservableObject {
    enum Phase: Equatable {
        case opening
        case open
        case closing
        case closed
    }

    let placement: ContextMenuPlacement
    @Published private(set) var phase: Phase = .opening
    @Published private(set) var phaseStartedAt = Date()

    init(placement: ContextMenuPlacement) {
        self.placement = placement
    }

    func finishOpening() {
        guard phase == .opening else { return }
        phase = .open
    }

    func startClosing() {
        guard phase != .closing, phase != .closed else { return }
        phase = .closing
        phaseStartedAt = Date()
    }

    func closeImmediately() {
        phase = .closed
        phaseStartedAt = Date()
    }
}

struct ContextMenuVisualState: Equatable {
    static let appearanceDuration: TimeInterval = 0.28
    static let dismissalDuration: TimeInterval = 0.22
    static let reducedMotionDuration: TimeInterval = 0.14

    let longitudinalScale: CGFloat
    let transverseScale: CGFloat
    let opacity: Double
    let visibleProgress: CGFloat

    static func make(
        phase: ContextMenuPresentation.Phase,
        elapsedTime: TimeInterval,
        reduceMotion: Bool
    ) -> ContextMenuVisualState {
        let duration: TimeInterval
        let rawProgress: CGFloat
        switch phase {
        case .opening:
            duration = reduceMotion ? reducedMotionDuration : appearanceDuration
            rawProgress = CGFloat(min(1, max(0, elapsedTime / duration)))
        case .open:
            return ContextMenuVisualState(
                longitudinalScale: 1,
                transverseScale: 1,
                opacity: 1,
                visibleProgress: 1
            )
        case .closing:
            duration = reduceMotion ? reducedMotionDuration : dismissalDuration
            rawProgress = 1 - CGFloat(min(1, max(0, elapsedTime / duration)))
        case .closed:
            return ContextMenuVisualState(
                longitudinalScale: 1,
                transverseScale: 1,
                opacity: 0,
                visibleProgress: 0
            )
        }

        let stepCount: CGFloat = reduceMotion ? 4 : phase == .opening ? 7 : 6
        let progress = floor(rawProgress * stepCount) / stepCount
        if reduceMotion {
            return ContextMenuVisualState(
                longitudinalScale: 1,
                transverseScale: 1,
                opacity: Double(progress),
                visibleProgress: progress
            )
        }

        let longitudinalProgress = min(1, progress / 0.68)
        let transverseProgress = min(1, max(0, (progress - 0.32) / 0.68))
        return ContextMenuVisualState(
            longitudinalScale: 0.08 + 0.92 * longitudinalProgress,
            transverseScale: 0.035 + 0.965 * transverseProgress,
            opacity: Double(min(1, 0.18 + progress * 1.4)),
            visibleProgress: progress
        )
    }
}

struct PixelContextMenuActions {
    let dismiss: () -> Void
    let retry: () -> Void
    let setPetSize: (PetSize) -> Void
    let setAbsorptionCategoryWeight: (String, Int) -> Void
    let setPetPositionLocked: (Bool) -> Void
    let setPassesPointerInputThrough: (Bool) -> Void
    let setTooltipStyle: (TooltipStyle) -> Void
    let setShowsQuotaDynamics: (Bool) -> Void
    let setHidesInFullScreenApps: (Bool) -> Void
    let setLaunchesAtLogin: (Bool) -> Void
    let openLoginItems: () -> Void
    let hidePet: () -> Void
    let quit: () -> Void
}

struct PixelContextMenuView: View {
    nonisolated static let mainWidth: CGFloat = 232
    nonisolated static let compactSubmenuWidth: CGFloat = 146
    nonisolated static let submenuWidth: CGFloat = 214
    nonisolated static let matrixCategoryWidth: CGFloat = 76
    nonisolated static let matrixCellSize: CGFloat = 31
    nonisolated static let matrixCategoryCount = 3
    nonisolated static let matrixWeights = Array(0...3)
    nonisolated static let menuGap: CGFloat = 8
    nonisolated static let purpleShadowOffset = CGSize(width: 4, height: -4)
    nonisolated static let blackShadowOffset = CGSize(width: 8, height: -8)
    nonisolated static let shadowTopInset = max(
        -purpleShadowOffset.height,
        -blackShadowOffset.height
    )
    nonisolated static let shadowTrailingInset = max(
        purpleShadowOffset.width,
        blackShadowOffset.width
    )
    nonisolated static let panelSize = CGSize(
        width: mainWidth + menuGap + submenuWidth + shadowTrailingInset,
        height: 474
    )

    let appState: AppState
    @ObservedObject var presentation: ContextMenuPresentation
    let actions: PixelContextMenuActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var hasKeyboardFocus: Bool
    @State private var selectedItem: ItemID = .size
    @State private var selectedSize: PetSize?
    @State private var selectedTooltipStyle: TooltipStyle?
    @State private var showsSizeSubmenu = true
    @State private var showsObjectMixSubmenu = false
    @State private var showsTooltipStyleSubmenu = false

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: presentation.phase == .open || presentation.phase == .closed
            )
        ) { timeline in
            let state = ContextMenuVisualState.make(
                phase: presentation.phase,
                elapsedTime: timeline.date.timeIntervalSince(presentation.phaseStartedAt),
                reduceMotion: reduceMotion
            )

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: actions.dismiss)

                menuLayout
                    .scaleEffect(
                        x: state.longitudinalScale,
                        y: state.transverseScale,
                        anchor: presentation.placement.transformAnchor
                    )
                    .opacity(state.opacity)
                    .allowsHitTesting(presentation.phase == .open)

                if !reduceMotion {
                    detachedPixels(progress: state.visibleProgress)
                }
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onAppear {
            Task { @MainActor in hasKeyboardFocus = true }
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            enterSelectedSubmenu()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            selectedSize = nil
            selectedTooltipStyle = nil
            return .handled
        }
        .onKeyPress(.return) {
            activateSelection()
            return .handled
        }
        .onKeyPress(.space) {
            activateSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            actions.dismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
    }

    private var menuLayout: some View {
        VStack(spacing: 0) {
            if !presentation.placement.opensBelow {
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: Self.menuGap) {
                if !presentation.placement.opensRight {
                    submenuSlot
                }

                mainMenu

                if presentation.placement.opensRight {
                    submenuSlot
                }
            }
            .padding(.top, Self.shadowTopInset)
            .padding(.trailing, Self.shadowTrailingInset)

            if presentation.placement.opensBelow {
                Spacer(minLength: 0)
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
    }

    private var mainMenu: some View {
        VStack(spacing: 0) {
            if appState.connectionState != .connected {
                row(
                    .retry,
                    title: localized("menu.retry"),
                    icon: .retry
                )
            }

            row(
                .size,
                title: localized("menu.size"),
                icon: .size,
                showsDisclosure: true
            )

            row(
                .objectMix,
                title: String.localizedStringWithFormat(
                    localized("menu.object_mix.format"),
                    appState.absorptionCategoryWeightsSummary
                ),
                icon: .mix,
                showsDisclosure: true,
                accessibilityValue: appState.absorptionCategoryWeightsSummary,
                accessibilityHelp: localized("menu.object_mix.hint")
            )

            row(
                .positionLock,
                title: localized("menu.lock_position"),
                icon: .lock,
                isChecked: appState.isPetPositionLocked,
                accessibilityValue: toggleValue(appState.isPetPositionLocked),
                accessibilityHelp: localized("menu.lock_position.help")
            )

            row(
                .pointerClickThrough,
                title: localized("menu.pass_pointer_input_through"),
                icon: .pointerThrough,
                isChecked: appState.passesPointerInputThrough,
                accessibilityValue: toggleValue(appState.passesPointerInputThrough),
                accessibilityHelp: localized("menu.pass_pointer_input_through.help")
            )

            row(
                .tooltipStyle,
                title: localized("menu.tooltip_style"),
                icon: .style,
                showsDisclosure: true
            )

            row(
                .quotaDynamics,
                title: localized("menu.show_quota_dynamics"),
                icon: .history,
                isChecked: appState.showsQuotaDynamics
            )

            row(
                .hideFullScreen,
                title: localized("menu.hide_full_screen"),
                icon: .fullscreen,
                isChecked: appState.hidesInFullScreenApps
            )

            row(
                .launchAtLogin,
                title: localized("menu.launch_at_login"),
                icon: .login,
                isChecked: appState.launchesAtLogin
            )

            if appState.launchAtLoginStatus == .requiresApproval {
                disabledRow(
                    title: localized("menu.approval_required"),
                    icon: .lock
                )
                row(
                    .openLoginItems,
                    title: localized("menu.open_login_items"),
                    icon: .sliders
                )
            }

            if let error = appState.launchAtLoginError {
                disabledRow(title: shortTitle(error), icon: .warning)
            }

            PixelDivider()

            row(
                .hidePet,
                title: localized("menu.hide_pet"),
                icon: .hide
            )
            row(
                .quit,
                title: localized("context_menu.quit"),
                icon: .power,
                isDestructive: true
            )
        }
        .padding(7)
        .frame(width: Self.mainWidth)
        .background(PixelMenuBackground())
    }

    @ViewBuilder
    private var submenuSlot: some View {
        if showsSizeSubmenu {
            compactSubmenu {
                VStack(spacing: 0) {
                    ForEach(PetSize.allCases, id: \.self) { size in
                        PixelMenuRow(
                            title: size.label,
                            icon: size == .small ? .small : size == .medium ? .medium : .large,
                            isSelected: selectedSize == size,
                            isChecked: appState.petSize == size,
                            showsDisclosure: false,
                            isEnabled: true,
                            isDestructive: false
                        ) {
                            actions.setPetSize(size)
                        } onHover: { isHovering in
                            guard isHovering else { return }
                            selectedItem = .size
                            selectedSize = size
                        }
                    }
                }
                .padding(7)
                .frame(width: Self.compactSubmenuWidth)
                .background(PixelMenuBackground())
            }
        } else if showsObjectMixSubmenu {
            objectMixMatrix
                .padding(.top, submenuTopPadding)
        } else if showsTooltipStyleSubmenu {
            compactSubmenu {
                VStack(spacing: 0) {
                    ForEach(TooltipStyle.allCases, id: \.self) { style in
                        PixelMenuRow(
                            title: style.title,
                            icon: style == .smooth ? .smooth : .pixel,
                            isSelected: selectedTooltipStyle == style,
                            isChecked: appState.tooltipStyle == style,
                            showsDisclosure: false,
                            isEnabled: true,
                            isDestructive: false
                        ) {
                            actions.setTooltipStyle(style)
                        } onHover: { isHovering in
                            guard isHovering else { return }
                            selectedItem = .tooltipStyle
                            selectedTooltipStyle = style
                        }
                    }
                }
                .padding(7)
                .frame(width: Self.compactSubmenuWidth)
                .background(PixelMenuBackground())
            }
        } else {
            Color.clear
                .frame(width: Self.submenuWidth, height: 1)
                .allowsHitTesting(false)
        }
    }

    private func compactSubmenu<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(
                width: Self.submenuWidth,
                alignment: presentation.placement.opensRight ? .leading : .trailing
            )
            .padding(.top, submenuTopPadding)
    }

    private var objectMixMatrix: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: Self.matrixCategoryWidth, height: 18)

                ForEach(Self.matrixWeights, id: \.self) { weight in
                    Text(String(weight))
                        .frame(width: Self.matrixCellSize, height: 18)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(PixelPalette.mutedGold)
            .accessibilityHidden(true)

            ForEach(
                Array(appState.absorptionCategories.prefix(Self.matrixCategoryCount)),
                id: \.id
            ) { category in
                let categoryName = localized("absorption.category.\(category.id)")
                let currentWeight = appState.absorptionCategoryWeights[
                    category.id,
                    default: category.weight
                ]

                HStack(spacing: 0) {
                    Text(categoryName)
                        .lineLimit(1)
                        .frame(
                            width: Self.matrixCategoryWidth,
                            height: Self.matrixCellSize,
                            alignment: .leading
                        )
                        .accessibilityHidden(true)

                    ForEach(Self.matrixWeights, id: \.self) { weight in
                        let isEnabled = appState.canSetAbsorptionCategoryWeight(
                            weight,
                            for: category.id
                        )
                        let presentation = PixelObjectMixCellPresentation(
                            weight: weight,
                            currentWeight: currentWeight,
                            isEnabled: isEnabled
                        )
                        PixelObjectMixWeightCell(
                            weight: weight,
                            presentation: presentation,
                            accessibilityLabel: objectMixCellAccessibilityLabel(
                                categoryName: categoryName,
                                weight: weight
                            ),
                            accessibilityHelp: localized(
                                isEnabled
                                    ? "menu.object_mix.hint"
                                    : "menu.object_mix.matrix.last_active.help"
                            )
                        ) {
                            actions.setAbsorptionCategoryWeight(category.id, weight)
                        }
                    }
                }
            }

            PixelDivider()

            Text(localized("menu.object_mix.matrix.hint.zero"))
                .frame(height: 18)
                .accessibilityHidden(true)
            Text(localized("menu.object_mix.matrix.hint.frequency"))
                .frame(height: 18)
                .accessibilityHidden(true)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(PixelPalette.mutedGold)
        .padding(7)
        .frame(width: Self.submenuWidth)
        .background(PixelMenuBackground())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("menu.object_mix.matrix.accessibility.label"))
        .accessibilityValue(appState.absorptionCategoryWeightsSummary)
        .accessibilityHint(localized("menu.object_mix.hint"))
    }

    private func objectMixCellAccessibilityLabel(
        categoryName: String,
        weight: Int
    ) -> String {
        let weightLabel = weight == 0
            ? localized("menu.object_mix.matrix.zero.accessibility")
            : String(weight)
        return String.localizedStringWithFormat(
            localized("menu.object_mix.matrix.cell.accessibility.format"),
            categoryName,
            weightLabel
        )
    }

    private func row(
        _ item: ItemID,
        title: String,
        icon: PixelMenuIcon,
        isChecked: Bool = false,
        showsDisclosure: Bool = false,
        isDestructive: Bool = false,
        accessibilityValue: String? = nil,
        accessibilityHelp: String? = nil
    ) -> some View {
        PixelMenuRow(
            title: title,
            icon: icon,
            isSelected: selectedSize == nil
                && selectedTooltipStyle == nil
                && selectedItem == item,
            isChecked: isChecked,
            showsDisclosure: showsDisclosure,
            isEnabled: true,
            isDestructive: isDestructive,
            accessibilityValue: accessibilityValue,
            accessibilityHelp: accessibilityHelp
        ) {
            activate(item)
        } onHover: { isHovering in
            guard isHovering else { return }
            selectedSize = nil
            selectedTooltipStyle = nil
            selectedItem = item
            showsSizeSubmenu = item == .size
            showsObjectMixSubmenu = item == .objectMix
            showsTooltipStyleSubmenu = item == .tooltipStyle
        }
    }

    private func disabledRow(title: String, icon: PixelMenuIcon) -> some View {
        PixelMenuRow(
            title: title,
            icon: icon,
            isSelected: false,
            isChecked: false,
            showsDisclosure: false,
            isEnabled: false,
            isDestructive: false,
            action: {},
            onHover: { _ in }
        )
    }

    private var interactiveItems: [ItemID] {
        var items: [ItemID] = []
        if appState.connectionState != .connected {
            items.append(.retry)
        }
        items += [
            .size,
            .objectMix,
            .positionLock,
            .pointerClickThrough,
            .tooltipStyle,
            .quotaDynamics,
            .hideFullScreen,
            .launchAtLogin
        ]
        if appState.launchAtLoginStatus == .requiresApproval {
            items.append(.openLoginItems)
        }
        items += [.hidePet, .quit]
        return items
    }

    private func moveSelection(by offset: Int) {
        guard presentation.phase == .open else { return }
        if let selectedSize,
           let index = PetSize.allCases.firstIndex(of: selectedSize) {
            let sizes = PetSize.allCases
            self.selectedSize = sizes[(index + offset + sizes.count) % sizes.count]
            return
        }
        if let selectedTooltipStyle,
           let index = TooltipStyle.allCases.firstIndex(of: selectedTooltipStyle) {
            let styles = TooltipStyle.allCases
            self.selectedTooltipStyle = styles[
                (index + offset + styles.count) % styles.count
            ]
            return
        }

        let items = interactiveItems
        guard !items.isEmpty else { return }
        let index = items.firstIndex(of: selectedItem) ?? 0
        selectedItem = items[(index + offset + items.count) % items.count]
        showsSizeSubmenu = selectedItem == .size
        showsObjectMixSubmenu = selectedItem == .objectMix
        showsTooltipStyleSubmenu = selectedItem == .tooltipStyle
    }

    private func enterSizeSubmenu() {
        guard presentation.phase == .open, selectedItem == .size else { return }
        showsSizeSubmenu = true
        showsObjectMixSubmenu = false
        showsTooltipStyleSubmenu = false
        selectedTooltipStyle = nil
        selectedSize = appState.petSize
    }

    private func enterTooltipStyleSubmenu() {
        guard presentation.phase == .open, selectedItem == .tooltipStyle else { return }
        showsSizeSubmenu = false
        showsObjectMixSubmenu = false
        showsTooltipStyleSubmenu = true
        selectedSize = nil
        selectedTooltipStyle = appState.tooltipStyle
    }

    private func enterSelectedSubmenu() {
        if selectedItem == .size {
            enterSizeSubmenu()
        } else if selectedItem == .objectMix {
            showsSizeSubmenu = false
            showsObjectMixSubmenu = true
            showsTooltipStyleSubmenu = false
        } else if selectedItem == .tooltipStyle {
            enterTooltipStyleSubmenu()
        }
    }

    private func activateSelection() {
        guard presentation.phase == .open else { return }
        if let selectedSize {
            actions.setPetSize(selectedSize)
        } else if let selectedTooltipStyle {
            actions.setTooltipStyle(selectedTooltipStyle)
        } else {
            activate(selectedItem)
        }
    }

    private func activate(_ item: ItemID) {
        guard presentation.phase == .open else { return }
        switch item {
        case .retry:
            actions.retry()
        case .size:
            enterSizeSubmenu()
        case .objectMix:
            showsSizeSubmenu = false
            showsObjectMixSubmenu = true
            showsTooltipStyleSubmenu = false
        case .positionLock:
            actions.setPetPositionLocked(!appState.isPetPositionLocked)
        case .pointerClickThrough:
            actions.setPassesPointerInputThrough(!appState.passesPointerInputThrough)
        case .tooltipStyle:
            enterTooltipStyleSubmenu()
        case .quotaDynamics:
            actions.setShowsQuotaDynamics(!appState.showsQuotaDynamics)
        case .hideFullScreen:
            actions.setHidesInFullScreenApps(!appState.hidesInFullScreenApps)
        case .launchAtLogin:
            actions.setLaunchesAtLogin(!appState.launchesAtLogin)
        case .openLoginItems:
            actions.openLoginItems()
        case .hidePet:
            actions.hidePet()
        case .quit:
            actions.quit()
        }
    }

    @ViewBuilder
    private func detachedPixels(progress: CGFloat) -> some View {
        if presentation.phase == .opening || presentation.phase == .closing {
            let direction: CGFloat = presentation.placement.opensRight ? 1 : -1
            let verticalDirection: CGFloat = presentation.placement.opensBelow ? 1 : -1
            let anchorX = presentation.placement.opensRight ? 0 : Self.panelSize.width
            let anchorY = presentation.placement.opensBelow ? 0 : Self.panelSize.height

            ForEach(0..<4, id: \.self) { index in
                let distance = CGFloat(24 + index * 14) * progress
                Rectangle()
                    .fill(pixelColor(for: index))
                    .frame(width: 3 + CGFloat(index % 2), height: 3 + CGFloat(index % 2))
                    .position(
                        x: anchorX + direction * distance,
                        y: anchorY + verticalDirection
                            * (distance * 0.18 + CGFloat(index - 1) * 5)
                    )
                    .opacity(Double(sin(progress * .pi)))
                    .allowsHitTesting(false)
            }
        }
    }

    private func pixelColor(for index: Int) -> Color {
        switch index {
        case 0: PixelPalette.brightGold
        case 1: PixelPalette.orange
        case 2: PixelPalette.purple
        default: PixelPalette.mutedGold
        }
    }

    private func shortTitle(_ title: String) -> String {
        title.count <= 30 ? title : String(title.prefix(29)) + "…"
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "Black-hole context menu item")
    }

    private func toggleValue(_ isOn: Bool) -> String {
        localized(isOn ? "accessibility.toggle.on" : "accessibility.toggle.off")
    }

    private var submenuTopPadding: CGFloat {
        let firstRowOffset: CGFloat = appState.connectionState == .connected ? 7 : 38
        if showsObjectMixSubmenu {
            return firstRowOffset + 31
        }
        return firstRowOffset + (showsTooltipStyleSubmenu ? 124 : 0)
    }

    private enum ItemID: Equatable {
        case retry
        case size
        case objectMix
        case positionLock
        case pointerClickThrough
        case tooltipStyle
        case quotaDynamics
        case hideFullScreen
        case launchAtLogin
        case openLoginItems
        case hidePet
        case quit
    }
}

struct PixelObjectMixCellPresentation: Equatable {
    let isSelected: Bool
    let isEnabled: Bool

    init(weight: Int, currentWeight: Int, isEnabled: Bool) {
        isSelected = weight == currentWeight
        self.isEnabled = isEnabled
    }

    var acceptsAction: Bool {
        isEnabled && !isSelected
    }
}

private struct PixelObjectMixWeightCell: View {
    let weight: Int
    let presentation: PixelObjectMixCellPresentation
    let accessibilityLabel: String
    let accessibilityHelp: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            guard presentation.acceptsAction else { return }
            action()
        } label: {
            Text(String(weight))
        }
        .buttonStyle(
            PixelObjectMixCellButtonStyle(
                isSelected: presentation.isSelected,
                isHovering: isHovering,
                isEnabled: presentation.isEnabled
            )
        )
        .disabled(!presentation.isEnabled)
        .onHover { isHovering in
            self.isHovering = presentation.isEnabled && isHovering
        }
        .onChange(of: presentation.isEnabled) { _, isEnabled in
            if !isEnabled {
                isHovering = false
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHelp)
        .accessibilityAddTraits(presentation.isSelected ? .isSelected : [])
    }
}

private struct PixelObjectMixCellButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovering: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .frame(
                width: PixelContextMenuView.matrixCellSize,
                height: PixelContextMenuView.matrixCellSize
            )
            .contentShape(Rectangle())
            .background(fillColor(isPressed: configuration.isPressed))
            .overlay {
                Rectangle()
                    .stroke(
                        borderColor,
                        lineWidth: isHovering && isEnabled && !isSelected ? 2 : 1
                    )
            }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return PixelPalette.disabled
        }
        if isSelected {
            return PixelPalette.darkText
        }
        return isHovering ? PixelPalette.highlightText : PixelPalette.mutedGold
    }

    private func fillColor(isPressed: Bool) -> Color {
        guard isEnabled else { return PixelPalette.disabledBackground }
        if isPressed {
            return isSelected
                ? PixelPalette.brightGold.opacity(0.72)
                : PixelPalette.orange.opacity(0.42)
        }
        if isSelected {
            return PixelPalette.brightGold
        }
        return isHovering ? PixelPalette.hoverBackground : PixelPalette.cellBackground
    }

    private var borderColor: Color {
        guard isEnabled else { return PixelPalette.innerBorder.opacity(0.35) }
        return isHovering && !isSelected ? PixelPalette.brightGold : PixelPalette.innerBorder
    }
}

private struct PixelMenuRow: View {
    let title: String
    let icon: PixelMenuIcon
    let isSelected: Bool
    let isChecked: Bool
    let showsDisclosure: Bool
    let isEnabled: Bool
    let isDestructive: Bool
    var accessibilityValue: String? = nil
    var accessibilityHelp: String? = nil
    let action: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                PixelMenuIconView(icon: icon)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsDisclosure {
                    Text("›")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(PixelPalette.orange)
                        .accessibilityHidden(true)
                } else if isChecked {
                    PixelMenuIconView(icon: .check)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(PixelPalette.brightGold)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 31)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    Rectangle()
                        .fill(PixelPalette.hoverBackground)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(PixelPalette.brightGold)
                                .frame(width: 3)
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(PixelPalette.orange)
                                .frame(width: 2)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(foregroundColor)
        .disabled(!isEnabled)
        .onHover(perform: onHover)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityHint(accessibilityHelp ?? "")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return PixelPalette.disabled
        }
        if isDestructive {
            return PixelPalette.orange
        }
        return isSelected ? PixelPalette.highlightText : PixelPalette.mutedGold
    }
}

private struct PixelDivider: View {
    var body: some View {
        Rectangle()
            .fill(PixelPalette.innerBorder)
            .frame(height: 2)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}

private struct PixelMenuBackground: View {
    var body: some View {
        ZStack {
            PixelPanelShape()
                .fill(.black.opacity(0.55))
                .offset(
                    x: PixelContextMenuView.blackShadowOffset.width,
                    y: PixelContextMenuView.blackShadowOffset.height
                )

            PixelPanelShape()
                .fill(PixelPalette.purple.opacity(0.58))
                .offset(
                    x: PixelContextMenuView.purpleShadowOffset.width,
                    y: PixelContextMenuView.purpleShadowOffset.height
                )

            PixelPanelShape()
                .fill(PixelPalette.background)
                .overlay {
                    PixelPanelShape()
                        .stroke(PixelPalette.border, lineWidth: 2)
                }
                .overlay {
                    PixelPanelShape(inset: 4)
                        .stroke(PixelPalette.innerBorder, lineWidth: 1)
                }
        }
    }
}

private struct PixelPanelShape: Shape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let notch: CGFloat = 7
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + notch, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + notch))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notch))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + notch))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.minY + notch))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.minY + 3))
        path.closeSubpath()
        return path
    }
}

enum PixelPalette {
    static let background = Color(red: 0.063, green: 0.043, blue: 0.094)
    static let cellBackground = Color(red: 0.071, green: 0.051, blue: 0.098)
    static let disabledBackground = Color(red: 0.129, green: 0.090, blue: 0.157)
    static let darkText = Color(red: 0.090, green: 0.063, blue: 0.118)
    static let border = Color(red: 0.557, green: 0.431, blue: 0.125)
    static let innerBorder = Color(red: 0.294, green: 0.204, blue: 0.118)
    static let hoverBackground = Color(red: 0.290, green: 0.196, blue: 0.106)
    static let mutedGold = Color(red: 0.780, green: 0.659, blue: 0.302)
    static let brightGold = Color(red: 1.000, green: 0.890, blue: 0.282)
    static let highlightText = Color(red: 1.000, green: 0.953, blue: 0.651)
    static let orange = Color(red: 1.000, green: 0.608, blue: 0.125)
    static let purple = Color(red: 0.357, green: 0.129, blue: 0.310)
    static let disabled = Color(red: 0.455, green: 0.376, blue: 0.475)
}

private enum PixelMenuIcon {
    case retry
    case size
    case mix
    case style
    case history
    case smooth
    case pixel
    case fullscreen
    case pointerThrough
    case login
    case lock
    case sliders
    case warning
    case hide
    case power
    case check
    case small
    case medium
    case large

    var pattern: [String] {
        switch self {
        case .retry:
            [
                "..####......", ".##..##.....", "##..........", "##..###.....",
                "##....##....", "......##....", ".....##.....", "..####......"
            ]
        case .size:
            [
                "###......###", "#..........#", "#..........#", "............",
                "............", "#..........#", "#..........#", "###......###"
            ]
        case .mix:
            [
                ".##########.", ".#.#.#.#.##.", ".##########.", ".#.#.#.#.##.",
                ".##########.", ".#.#.#.#.##.", ".##########.", "............"
            ]
        case .style:
            [
                ".######.....", ".#....#.....", ".#.##.#.###.", ".#.##.#.#.#.",
                ".#....#.###.", ".######.....", "........###.", "........#.#."
            ]
        case .history:
            [
                "............", "..........##", ".......####.", ".....###....",
                "...###......", ".###........", "##..........", "............"
            ]
        case .smooth:
            [
                "...######...", ".##......##.", "##........##", "##........##",
                "##........##", "##........##", ".##......##.", "...######..."
            ]
        case .pixel:
            [
                "..########..", ".##......##.", "##........##", "##..####..##",
                "##..####..##", "##........##", ".##......##.", "..########.."
            ]
        case .fullscreen:
            [
                ".##########.", ".#........#.", ".#........#.", ".#....#####.",
                ".#....#...#.", ".######...#.", "......#####.", "............"
            ]
        case .pointerThrough:
            [
                ".##.........", ".####.......", ".######.....", ".########...",
                ".#####......", ".##.##......", "....##..##..", "........##.."
            ]
        case .login:
            [
                ".######.....", ".#....#.....", ".#....#.##..", ".#...#####..",
                ".#....#.##..", ".#....#.....", ".######.....", "............"
            ]
        case .lock:
            [
                "...####.....", "..##..##....", "..##..##....", ".########...",
                ".##....##...", ".##.##.##...", ".##....##...", ".########..."
            ]
        case .sliders:
            [
                ".####..####.", "....####....", ".####..####.", "............",
                ".##..######.", "..####......", ".##..######.", "............"
            ]
        case .warning:
            [
                ".....##.....", "....####....", "...######...", "..###..###..",
                ".####..####.", "#####..#####", ".....##.....", ".....##....."
            ]
        case .hide:
            [
                "..........##", ".########.##", "##..##..###.", "##..######..",
                ".########...", "...##..##...", "..##........", ".##........."
            ]
        case .power:
            [
                ".....##.....", ".....##.....", "..##.##.##..", ".##..##..##.",
                ".##......##.", "..##....##..", "...######...", "............"
            ]
        case .check:
            [
                "............", "..........##", ".........##.", "..##....##..",
                "...##..##...", "....####....", ".....##.....", "............"
            ]
        case .small:
            [
                "............", "............", "....####....", "....#..#....",
                "....#..#....", "....####....", "............", "............"
            ]
        case .medium:
            [
                "............", "...######...", "...#....#...", "...#....#...",
                "...#....#...", "...#....#...", "...######...", "............"
            ]
        case .large:
            [
                "..########..", "..#......#..", "..#......#..", "..#......#..",
                "..#......#..", "..#......#..", "..#......#..", "..########.."
            ]
        }
    }
}

private struct PixelMenuIconView: View {
    let icon: PixelMenuIcon

    var body: some View {
        Canvas { context, size in
            let patterns = icon.pattern
            let columns = CGFloat(patterns.map(\.count).max() ?? 12)
            let rows = CGFloat(patterns.count)
            let pixelSize = min(size.width / columns, size.height / rows)
            let origin = CGPoint(
                x: (size.width - columns * pixelSize) / 2,
                y: (size.height - rows * pixelSize) / 2
            )

            for (row, pattern) in patterns.enumerated() {
                for (column, character) in pattern.enumerated() where character == "#" {
                    context.fill(
                        Path(
                            CGRect(
                                x: origin.x + CGFloat(column) * pixelSize,
                                y: origin.y + CGFloat(row) * pixelSize,
                                width: pixelSize,
                                height: pixelSize
                            )
                        ),
                        with: .foreground
                    )
                }
            }
        }
    }
}
