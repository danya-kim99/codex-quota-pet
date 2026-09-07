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
    let setShowsOnlyWhenCodexIsActive: (Bool) -> Void
    let setHidesInFullScreenApps: (Bool) -> Void
    let setLaunchesAtLogin: (Bool) -> Void
    let openLoginItems: () -> Void
    let hidePet: () -> Void
    let quit: () -> Void
}

enum PixelContextMenuItem: Hashable {
    case retry, appearance, objectMix, behavior, hidePet, quit
    case size(PetSize), tooltipStyle(TooltipStyle), quotaDynamics
    case positionLock, pointerClickThrough, onlyWhenCodexActive, hideFullScreen
    case launchAtLogin, openLoginItems
    case objectWeight(categoryID: String, weight: Int)

    var isGroup: Bool {
        self == .appearance || self == .objectMix || self == .behavior
    }
}

struct PixelContextMenuNavigation: Equatable {
    private(set) var selectedRoot: PixelContextMenuItem = .appearance
    private(set) var selectedChild: PixelContextMenuItem?
    private(set) var isSubmenuOpen = false

    static func rootItems(requiresRetry: Bool) -> [PixelContextMenuItem] {
        (requiresRetry ? [.retry] : []) + [.appearance, .objectMix, .behavior, .hidePet, .quit]
    }

    static func childItems(
        for group: PixelContextMenuItem,
        requiresLoginApproval: Bool,
        objectWeights: [PixelContextMenuItem] = []
    ) -> [PixelContextMenuItem] {
        switch group {
        case .appearance:
            PetSize.allCases.map(PixelContextMenuItem.size)
                + TooltipStyle.allCases.map(PixelContextMenuItem.tooltipStyle) + [.quotaDynamics]
        case .behavior:
            [.positionLock, .pointerClickThrough, .onlyWhenCodexActive, .hideFullScreen, .launchAtLogin]
                + (requiresLoginApproval ? [.openLoginItems] : [])
        case .objectMix:
            objectWeights
        default:
            []
        }
    }

    mutating func selectRoot(_ item: PixelContextMenuItem, opensSubmenu: Bool = true) {
        selectedRoot = item
        selectedChild = nil
        isSubmenuOpen = opensSubmenu && item.isGroup
    }

    mutating func selectChild(_ item: PixelContextMenuItem) {
        selectedChild = item
        isSubmenuOpen = true
    }

    mutating func enterSubmenu(children: [PixelContextMenuItem]) {
        guard selectedRoot.isGroup else { return }
        isSubmenuOpen = true
        selectedChild = selectedChild ?? children.first
    }

    mutating func leaveSubmenu() {
        selectedChild = nil
        isSubmenuOpen = false
    }

    mutating func normalize(roots: [PixelContextMenuItem], children: [PixelContextMenuItem]) {
        if !roots.contains(selectedRoot) {
            selectRoot(.appearance, opensSubmenu: false)
        } else if let selectedChild, !children.contains(selectedChild) {
            self.selectedChild = children.first
        }
    }

    mutating func move(by offset: Int, roots: [PixelContextMenuItem], children: [PixelContextMenuItem]) {
        normalize(roots: roots, children: children)
        let items = selectedChild == nil ? roots : children
        guard !items.isEmpty else { return }
        let current = selectedChild ?? selectedRoot
        let index = items.firstIndex(of: current) ?? 0
        let next = items[((index + offset) % items.count + items.count) % items.count]
        if selectedChild != nil {
            selectChild(next)
        } else {
            selectRoot(next)
        }
    }
}

struct PixelContextMenuView: View {
    nonisolated static let mainWidth: CGFloat = 232
    nonisolated static let groupedSubmenuWidth: CGFloat = 232
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
        width: mainWidth + menuGap + groupedSubmenuWidth + shadowTrailingInset,
        height: 505
    )

    let appState: AppState
    @ObservedObject var presentation: ContextMenuPresentation
    let actions: PixelContextMenuActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var hasKeyboardFocus: Bool
    @State private var navigation = PixelContextMenuNavigation()

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
            navigation.leaveSubmenu()
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
        .onChange(of: rootItems) { _, _ in normalizeSelection() }
        .onChange(of: childItems) { _, _ in normalizeSelection() }
        .accessibilityElement(children: .contain)
    }

    static func menuFrames(
        placement: ContextMenuPlacement,
        requiresRetry: Bool,
        openGroup: PixelContextMenuItem?,
        requiresLoginApproval: Bool,
        hasLoginError: Bool
    ) -> (root: CGRect, submenu: CGRect?) {
        let roots = PixelContextMenuNavigation.rootItems(requiresRetry: requiresRetry)
        let rootHeight = CGFloat(roots.count) * 31 + 10 + 14
        let root = CGRect(
            x: placement.opensRight ? 0 : groupedSubmenuWidth + menuGap,
            y: placement.opensBelow ? shadowTopInset : panelSize.height - rootHeight,
            width: mainWidth,
            height: rootHeight
        )
        guard let group = openGroup, group.isGroup, let row = roots.firstIndex(of: group) else {
            return (root, nil)
        }
        let submenuHeight: CGFloat = switch group {
        case .appearance: 256
        case .objectMix: 171
        default: 189 + (requiresLoginApproval ? 62 : 0) + (hasLoginError ? 31 : 0)
        }
        let width = group == .objectMix ? submenuWidth : groupedSubmenuWidth
        return (
            root,
            CGRect(
                x: placement.opensRight ? mainWidth + menuGap : groupedSubmenuWidth - width,
                y: min(panelSize.height - submenuHeight, root.minY + 7 + CGFloat(row) * 31),
                width: width,
                height: submenuHeight
            )
        )
    }

    private var menuLayout: some View {
        let frames = Self.menuFrames(
            placement: presentation.placement,
            requiresRetry: appState.connectionState != .connected,
            openGroup: navigation.isSubmenuOpen ? navigation.selectedRoot : nil,
            requiresLoginApproval: appState.launchAtLoginStatus == .requiresApproval,
            hasLoginError: appState.launchAtLoginError != nil
        )
        return ZStack(alignment: .topLeading) {
            mainMenu
                .position(x: frames.root.midX, y: frames.root.midY)
            if let submenu = frames.submenu {
                submenuContent
                    .position(x: submenu.midX, y: submenu.midY)
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
    }

    private var mainMenu: some View {
        VStack(spacing: 0) {
            if appState.connectionState != .connected {
                row(.retry, title: localized("menu.retry"), icon: .retry)
            }
            row(
                .appearance,
                title: localized("context_menu.appearance"),
                icon: .style,
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
                .behavior,
                title: localized("context_menu.behavior"),
                icon: .sliders,
                showsDisclosure: true
            )
            PixelDivider()
            row(.hidePet, title: localized("menu.hide_pet"), icon: .hide)
            row(.quit, title: localized("context_menu.quit"), icon: .power, isDestructive: true)
        }
        .padding(7)
        .frame(width: Self.mainWidth)
        .background(PixelMenuBackground())
    }

    @ViewBuilder
    private var submenuContent: some View {
        switch navigation.selectedRoot {
        case .appearance: appearanceSubmenu
        case .objectMix: objectMixMatrix
        case .behavior: behaviorSubmenu
        default: EmptyView()
        }
    }

    private var appearanceSubmenu: some View {
        VStack(spacing: 0) {
            sectionTitle("menu.size")
            ForEach(PetSize.allCases, id: \.self) { size in
                row(
                    .size(size),
                    title: size.label,
                    icon: size == .small ? .small : size == .medium ? .medium : .large,
                    isChecked: appState.petSize == size
                )
            }
            PixelDivider()
            sectionTitle("menu.tooltip_style")
            ForEach(TooltipStyle.allCases, id: \.self) { style in
                row(
                    .tooltipStyle(style),
                    title: style.title,
                    icon: style == .smooth ? .smooth : .pixel,
                    isChecked: appState.tooltipStyle == style
                )
            }
            PixelDivider()
            row(
                .quotaDynamics,
                title: localized("menu.show_quota_dynamics"),
                icon: .history,
                isChecked: appState.showsQuotaDynamics
            )
        }
        .padding(7)
        .frame(width: Self.groupedSubmenuWidth)
        .background(PixelMenuBackground())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("context_menu.appearance"))
    }

    private var behaviorSubmenu: some View {
        VStack(spacing: 0) {
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
            PixelDivider()
            row(
                .onlyWhenCodexActive,
                title: localized("menu.only_when_codex_active"),
                icon: .fullscreen,
                isChecked: appState.showsOnlyWhenCodexIsActive,
                accessibilityValue: toggleValue(appState.showsOnlyWhenCodexIsActive),
                accessibilityHelp: localized("menu.only_when_codex_active.help")
            )
            row(
                .hideFullScreen,
                title: localized("menu.hide_full_screen"),
                icon: .fullscreen,
                isChecked: appState.hidesInFullScreenApps
            )
            PixelDivider()
            row(
                .launchAtLogin,
                title: localized("menu.launch_at_login"),
                icon: .login,
                isChecked: appState.launchesAtLogin
            )
            if appState.launchAtLoginStatus == .requiresApproval {
                disabledRow(title: localized("menu.approval_required"), icon: .lock)
                row(.openLoginItems, title: localized("menu.open_login_items"), icon: .sliders)
            }
            if let error = appState.launchAtLoginError {
                disabledRow(title: shortTitle(error), icon: .warning)
            }
        }
        .padding(7)
        .frame(width: Self.groupedSubmenuWidth)
        .background(PixelMenuBackground())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("context_menu.behavior"))
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(localized(key))
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(PixelPalette.mutedGold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 18)
            .accessibilityAddTraits(.isHeader)
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
                            isKeyboardSelected: navigation.selectedChild == .objectWeight(
                                categoryID: category.id,
                                weight: weight
                            ),
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
                            navigation.selectChild(.objectWeight(categoryID: category.id, weight: weight))
                            actions.setAbsorptionCategoryWeight(category.id, weight)
                        }
                        .onHover { isHovering in
                            guard isHovering, isEnabled else { return }
                            navigation.selectChild(.objectWeight(categoryID: category.id, weight: weight))
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
        _ item: PixelContextMenuItem,
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
            isSelected: item == (navigation.selectedChild ?? navigation.selectedRoot),
            isChecked: isChecked,
            showsDisclosure: showsDisclosure,
            isEnabled: true,
            isDestructive: isDestructive,
            accessibilityValue: accessibilityValue,
            accessibilityHelp: accessibilityHelp
        ) {
            if rootItems.contains(item) {
                navigation.selectRoot(item)
            } else {
                navigation.selectChild(item)
            }
            activate(item)
        } onHover: { isHovering in
            guard isHovering else { return }
            if rootItems.contains(item) {
                navigation.selectRoot(item)
            } else {
                navigation.selectChild(item)
            }
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

    private var rootItems: [PixelContextMenuItem] {
        PixelContextMenuNavigation.rootItems(requiresRetry: appState.connectionState != .connected)
    }

    private var childItems: [PixelContextMenuItem] {
        PixelContextMenuNavigation.childItems(
            for: navigation.selectedRoot,
            requiresLoginApproval: appState.launchAtLoginStatus == .requiresApproval,
            objectWeights: appState.absorptionCategories.prefix(Self.matrixCategoryCount).flatMap { category in
                Self.matrixWeights.compactMap { weight in
                    appState.canSetAbsorptionCategoryWeight(weight, for: category.id)
                        ? .objectWeight(categoryID: category.id, weight: weight) : nil
                }
            }
        )
    }

    private func normalizeSelection() {
        navigation.normalize(roots: rootItems, children: childItems)
    }

    private func moveSelection(by offset: Int) {
        guard presentation.phase == .open else { return }
        navigation.move(by: offset, roots: rootItems, children: childItems)
    }

    private func enterSelectedSubmenu() {
        guard presentation.phase == .open else { return }
        navigation.enterSubmenu(children: childItems)
    }

    private func activateSelection() {
        normalizeSelection()
        activate(navigation.selectedChild ?? navigation.selectedRoot)
    }

    private func activate(_ item: PixelContextMenuItem) {
        guard presentation.phase == .open else { return }
        switch item {
        case .retry: actions.retry()
        case .appearance, .objectMix, .behavior: enterSelectedSubmenu()
        case .size(let size): actions.setPetSize(size)
        case .tooltipStyle(let style): actions.setTooltipStyle(style)
        case .objectWeight(let categoryID, let weight):
            guard appState.canSetAbsorptionCategoryWeight(weight, for: categoryID) else { return }
            actions.setAbsorptionCategoryWeight(categoryID, weight)
        case .positionLock:
            actions.setPetPositionLocked(!appState.isPetPositionLocked)
        case .pointerClickThrough:
            actions.setPassesPointerInputThrough(!appState.passesPointerInputThrough)
        case .quotaDynamics:
            actions.setShowsQuotaDynamics(!appState.showsQuotaDynamics)
        case .onlyWhenCodexActive:
            actions.setShowsOnlyWhenCodexIsActive(!appState.showsOnlyWhenCodexIsActive)
        case .hideFullScreen:
            actions.setHidesInFullScreenApps(!appState.hidesInFullScreenApps)
        case .launchAtLogin:
            actions.setLaunchesAtLogin(!appState.launchesAtLogin)
        case .openLoginItems: actions.openLoginItems()
        case .hidePet: actions.hidePet()
        case .quit: actions.quit()
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
    let isKeyboardSelected: Bool
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
                isHovering: isHovering || isKeyboardSelected,
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
