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
        sceneSize: CGSize
    ) -> Bool {
        hypot(mouseUp.x - mouseDown.x, mouseUp.y - mouseDown.y) <= movementThreshold
            && containsVisiblePet(mouseDown, sceneSize: sceneSize)
            && containsVisiblePet(mouseUp, sceneSize: sceneSize)
    }

    static func containsVisiblePet(_ point: CGPoint, sceneSize: CGSize) -> Bool {
        guard sceneSize.width > 0, sceneSize.height > 0 else { return false }
        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        let radiusX = sceneSize.width * 0.48
        let radiusY = sceneSize.height * 0.40
        let normalizedX = (point.x - center.x) / radiusX
        let normalizedY = (point.y - center.y) / radiusY
        return normalizedX * normalizedX + normalizedY * normalizedY <= 1
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
    let setHidesInFullScreenApps: (Bool) -> Void
    let setLaunchesAtLogin: (Bool) -> Void
    let openLoginItems: () -> Void
    let hidePet: () -> Void
    let quit: () -> Void
}

struct PixelContextMenuView: View {
    nonisolated static let panelSize = CGSize(width: 386, height: 318)
    nonisolated static let mainWidth: CGFloat = 286
    nonisolated static let submenuWidth: CGFloat = 92
    nonisolated static let menuGap: CGFloat = 8

    let appState: AppState
    @ObservedObject var presentation: ContextMenuPresentation
    let actions: PixelContextMenuActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var hasKeyboardFocus: Bool
    @State private var selectedItem: ItemID = .size
    @State private var selectedSize: PetSize?
    @State private var showsSizeSubmenu = true

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
            enterSizeSubmenu()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            selectedSize = nil
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
                    sizeSubmenuSlot
                }

                mainMenu

                if presentation.placement.opensRight {
                    sizeSubmenuSlot
                }
            }

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
    private var sizeSubmenuSlot: some View {
        if showsSizeSubmenu {
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
            .frame(width: Self.submenuWidth)
            .background(PixelMenuBackground())
            .padding(.top, 38)
        } else {
            Color.clear
                .frame(width: Self.submenuWidth, height: 1)
                .allowsHitTesting(false)
        }
    }

    private func row(
        _ item: ItemID,
        title: String,
        icon: PixelMenuIcon,
        isChecked: Bool = false,
        showsDisclosure: Bool = false,
        isDestructive: Bool = false
    ) -> some View {
        PixelMenuRow(
            title: title,
            icon: icon,
            isSelected: selectedSize == nil && selectedItem == item,
            isChecked: isChecked,
            showsDisclosure: showsDisclosure,
            isEnabled: true,
            isDestructive: isDestructive
        ) {
            activate(item)
        } onHover: { isHovering in
            guard isHovering else { return }
            selectedSize = nil
            selectedItem = item
            showsSizeSubmenu = item == .size
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
        items += [.size, .hideFullScreen, .launchAtLogin]
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

        let items = interactiveItems
        guard !items.isEmpty else { return }
        let index = items.firstIndex(of: selectedItem) ?? 0
        selectedItem = items[(index + offset + items.count) % items.count]
        showsSizeSubmenu = selectedItem == .size
    }

    private func enterSizeSubmenu() {
        guard presentation.phase == .open, selectedItem == .size else { return }
        showsSizeSubmenu = true
        selectedSize = appState.petSize
    }

    private func activateSelection() {
        guard presentation.phase == .open else { return }
        if let selectedSize {
            actions.setPetSize(selectedSize)
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

    private enum ItemID: Equatable {
        case retry
        case size
        case hideFullScreen
        case launchAtLogin
        case openLoginItems
        case hidePet
        case quit
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
            .shadow(color: PixelPalette.purple.opacity(0.58), radius: 0, x: 4, y: -4)
            .shadow(color: .black.opacity(0.55), radius: 0, x: 8, y: -8)
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

private enum PixelPalette {
    static let background = Color(red: 0.063, green: 0.043, blue: 0.094)
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
    case fullscreen
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
        case .fullscreen:
            [
                ".##########.", ".#........#.", ".#........#.", ".#....#####.",
                ".#....#...#.", ".######...#.", "......#####.", "............"
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
