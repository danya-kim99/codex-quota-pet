import AppKit
import CoreGraphics
import SwiftUI

struct PetPanelInputPolicy: Equatable {
    let allowsPointer: Bool
    let allowsDrag: Bool
}

struct PetDisplayGeometry: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

@MainActor
final class PetPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var tooltipPanel: NSPanel?
    private var tooltipHostingView: NSHostingView<QuotaTooltipView>?
    private var contextMenuPanel: ContextMenuPanel?
    private var contextMenuPresentation: ContextMenuPresentation?
    private var tooltipPlacement: QuotaTooltipView.Placement = .below
    private var isTooltipPresentedToSwiftUI = false
    private var isDraggingPet = false
    private var restoreTooltipAfterDrag = false
    private var dragCompletionTask: Task<Void, Never>?
    private var contextMenuAnimationTask: Task<Void, Never>?
    private var resetCountdownTask: Task<Void, Never>?
    private var contextMenuDismissCompletion: (() -> Void)?
    private var pointerMonitor: Any?
    private var outsidePointerMonitor: Any?
    private var absorptionPointerStart: (window: CGPoint, screen: CGPoint)?
    private var contextPointerStart: (
        window: CGPoint,
        screen: CGPoint,
        kind: ContextPointerKind
    )?
    private var hoverRequiresExitBeforeReentry = false
    private weak var appState: AppState?
    private var observationTokens: [NSObjectProtocol] = []
    private var displayObservationToken: NSObjectProtocol?
    private let isFrontmostApplicationFullScreen: () -> Bool
    private let frameName: String

    init(
        isFrontmostApplicationFullScreen: (() -> Bool)? = nil,
        frameName: String = AppConstants.petPanelFrameName
    ) {
        self.isFrontmostApplicationFullScreen = isFrontmostApplicationFullScreen
            ?? Self.detectFrontmostApplicationFullScreen
        self.frameName = frameName
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var isTooltipVisible: Bool {
        tooltipPanel?.isVisible == true
    }

    var isTooltipPresentationActive: Bool {
        isTooltipPresentedToSwiftUI
    }

    var tooltipHostingViewIdentity: ObjectIdentifier? {
        tooltipHostingView.map(ObjectIdentifier.init)
    }

    var isResetCountdownUpdateActive: Bool {
        resetCountdownTask != nil
    }

    var tooltipFrame: CGRect? {
        tooltipPanel?.frame
    }

    var tooltipAnimationBehavior: NSWindow.AnimationBehavior? {
        tooltipPanel?.animationBehavior
    }

    var isContextMenuVisible: Bool {
        contextMenuPanel?.isVisible == true
    }

    var petFrame: CGRect? {
        panel?.frame
    }

    var contextMenuFrame: CGRect? {
        contextMenuPanel?.frame
    }

    var isPanelIgnoringMouseEvents: Bool {
        panel?.ignoresMouseEvents == true
    }

    var isPanelMovableByWindowBackground: Bool {
        panel?.isMovableByWindowBackground == true
    }

    var isDragTrackingActive: Bool {
        isDraggingPet
    }

    static func inputPolicy(
        isPositionLocked: Bool,
        passesPointerInputThrough: Bool,
        hasContextMenu: Bool
    ) -> PetPanelInputPolicy {
        let allowsPointer = !passesPointerInputThrough
        return PetPanelInputPolicy(
            allowsPointer: allowsPointer,
            allowsDrag: allowsPointer && !isPositionLocked && !hasContextMenu
        )
    }

    static func shouldClearHoverRearm(
        passesPointerInputThrough: Bool,
        cursorIsInsideHoverTarget: Bool
    ) -> Bool {
        !passesPointerInputThrough && !cursorIsInsideHoverTarget
    }

    static func hoverRearmRequired(
        currentlyRequired: Bool,
        passesPointerInputThrough: Bool,
        cursorIsInsideHoverTarget: Bool
    ) -> Bool {
        currentlyRequired && !shouldClearHoverRearm(
            passesPointerInputThrough: passesPointerInputThrough,
            cursorIsInsideHoverTarget: cursorIsInsideHoverTarget
        )
    }

    func startMonitoring(appState: AppState) {
        self.appState = appState

        if observationTokens.isEmpty {
            let notificationCenter = NSWorkspace.shared.notificationCenter
            let names: [Notification.Name] = [
                NSWorkspace.activeSpaceDidChangeNotification,
                NSWorkspace.didActivateApplicationNotification
            ]

            observationTokens = names.map { name in
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, let appState = self.appState else {
                            return
                        }

                        self.updateVisibility(appState: appState)
                    }
                }
            }
        }

        if displayObservationToken == nil {
            displayObservationToken = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.displayParametersDidChange()
                }
            }
        }

        updateVisibility(appState: appState)
    }

    func updateVisibility(appState: AppState) {
        let isSuppressedByFullScreen = appState.hidesInFullScreenApps
            && isFrontmostApplicationFullScreen()

        if appState.isPetVisible && !isSuppressedByFullScreen {
            show(appState: appState)
        } else {
            hide()
        }
    }

    func show(appState: AppState) {
        self.appState = appState

        if let panel {
            correctPanelFrameIfNeeded(saveIfLocked: true)
            repositionTooltip()
            applyInputPolicy()
            updateHoverRearmForPanelShow()
            panel.orderFrontRegardless()
            return
        }

        let size = appState.petSize.sceneSize
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Codex quota pet"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = PetHostingView(
            rootView: BlackHoleView(
                appState: appState,
                setTooltipVisible: { [weak self] isVisible in
                    self?.handleTooltipVisibilityRequest(isVisible)
                },
                openContextMenu: { [weak self] in
                    self?.showContextMenuFromAccessibility()
                }
            )
        )

        positionPanelForInitialShow(panel, size: size, isLocked: appState.isPetPositionLocked)

        self.panel = panel
        applyInputPolicy()
        let tooltipPanel = makeTooltipPanel(appState: appState, relativeTo: panel)
        self.tooltipPanel = tooltipPanel
        installPointerMonitorIfNeeded()
        panel.addChildWindow(tooltipPanel, ordered: .above)
        tooltipPanel.orderOut(nil)
        repositionTooltip()
        if appState.isPetPositionLocked {
            panel.saveFrame(usingName: frameName)
        }

        panel.orderFrontRegardless()
    }

    func hide() {
        dismissContextMenu(animated: false)
        cancelDragTracking()
        absorptionPointerStart = nil
        contextPointerStart = nil
        appState?.resetAbsorptionScene()
        hideTooltip()
        panel?.orderOut(nil)
    }

    func resize(to size: PetSize) {
        dismissContextMenu(animated: true)
        hideTooltip()
        guard let panel else { return }

        let frame = Self.resizedPetFrame(
            currentFrame: panel.frame,
            to: size.sceneSize,
            visibleFrame: Self.visibleFrame(for: panel.frame)
        )
        panel.setFrame(frame, display: true)
        if appState?.isPetPositionLocked == true {
            panel.saveFrame(usingName: frameName)
        }
        repositionTooltip()
    }

    func positionLockDidChange() {
        absorptionPointerStart = nil
        contextPointerStart = nil
        applyInputPolicy()
        if appState?.isPetPositionLocked == true {
            panel?.saveFrame(usingName: frameName)
        }
    }

    func pointerClickThroughDidChange() {
        guard let appState else { return }
        if appState.passesPointerInputThrough {
            absorptionPointerStart = nil
            contextPointerStart = nil
            cancelDragTracking()
            hideTooltip()
            dismissContextMenu(animated: false, applyMouseEvents: false)
            applyInputPolicy(applyMouseEvents: false)
            panel?.ignoresMouseEvents = true
        } else {
            panel?.ignoresMouseEvents = false
            applyInputPolicy(applyMouseEvents: false)
            hoverRequiresExitBeforeReentry = cursorIsInsideHoverTarget()
        }
    }

    func updateTooltipStyle() {
        updateTooltipLayout()
    }

    func updateTooltipLayout() {
        let wasVisible = tooltipPanel?.isVisible == true
        repositionTooltip(preferredPlacement: tooltipPlacement, refreshContent: true)
        if wasVisible {
            tooltipPanel?.orderFrontRegardless()
        }
    }

    func setTooltipVisible(_ isVisible: Bool) {
        handleTooltipVisibilityRequest(isVisible)
    }

    private func handleTooltipVisibilityRequest(_ isVisible: Bool) {
        if isVisible {
            guard inputPolicy.allowsPointer, !hoverRequiresExitBeforeReentry else { return }
            showTooltip()
        } else {
            if hoverRequiresExitBeforeReentry {
                guard Self.shouldClearHoverRearm(
                    passesPointerInputThrough: appState?.passesPointerInputThrough == true,
                    cursorIsInsideHoverTarget: cursorIsInsideHoverTarget()
                ) else { return }
            }
            hoverRequiresExitBeforeReentry = false
            hideTooltip()
        }
    }

    private func showTooltip() {
        guard let tooltipPanel, !isDraggingPet, contextMenuPanel == nil else { return }
        let wasVisible = tooltipPanel.isVisible
        repositionTooltip(refreshContent: !wasVisible)
        setTooltipPresentedToSwiftUI(true)
        if !tooltipPanel.isVisible {
            tooltipPanel.orderFrontRegardless()
        }
        if resetCountdownTask == nil {
            startResetCountdownUpdates()
        }
    }

    private func hideTooltip() {
        stopResetCountdownUpdates()
        setTooltipPresentedToSwiftUI(false)
        tooltipPanel?.orderOut(nil)
    }

    func windowWillMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel,
              NSEvent.pressedMouseButtons & 1 != 0,
              !isDraggingPet,
              inputPolicy.allowsDrag else {
            return
        }

        beginDragTracking()
    }

    func beginDragTracking() {
        guard !isDraggingPet else { return }
        isDraggingPet = true
        restoreTooltipAfterDrag = tooltipPanel?.isVisible == true
        dragCompletionTask?.cancel()
        stopResetCountdownUpdates()
        setTooltipPresentedToSwiftUI(false)
        tooltipPanel?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        repositionTooltip()
        waitForDragToEnd()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        repositionTooltip()
    }

    static func contextMenuLayout(
        anchor: CGPoint,
        visibleFrame: CGRect,
        size: CGSize = PixelContextMenuView.panelSize
    ) -> (frame: CGRect, placement: ContextMenuPlacement) {
        let spacing: CGFloat = 8
        let rightSpace = visibleFrame.maxX - anchor.x
        let leftSpace = anchor.x - visibleFrame.minX
        let aboveSpace = visibleFrame.maxY - anchor.y
        let belowSpace = anchor.y - visibleFrame.minY
        let opensRight = rightSpace >= size.width + spacing || rightSpace >= leftSpace
        let opensAbove = aboveSpace >= size.height + spacing || aboveSpace >= belowSpace

        let unclampedOrigin = CGPoint(
            x: opensRight ? anchor.x + spacing : anchor.x - size.width - spacing,
            y: opensAbove ? anchor.y + spacing : anchor.y - size.height - spacing
        )
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        let origin = CGPoint(
            x: min(max(unclampedOrigin.x, visibleFrame.minX), maximumX),
            y: min(max(unclampedOrigin.y, visibleFrame.minY), maximumY)
        )
        let placement: ContextMenuPlacement = switch (opensAbove, opensRight) {
        case (true, true): .aboveRight
        case (true, false): .aboveLeft
        case (false, true): .belowRight
        case (false, false): .belowLeft
        }
        return (CGRect(origin: origin, size: size), placement)
    }

    func showContextMenu(at screenPoint: CGPoint) {
        guard contextMenuPanel == nil,
              let panel,
              panel.isVisible,
              let appState else {
            return
        }

        cancelDragTracking()
        absorptionPointerStart = nil
        hideTooltip()
        appState.refreshLaunchAtLoginStatus()

        let layout = Self.contextMenuLayout(
            anchor: screenPoint,
            visibleFrame: Self.visibleFrame(containing: screenPoint, fallback: panel.frame)
        )
        let presentation = ContextMenuPresentation(placement: layout.placement)
        let contextMenuPanel = ContextMenuPanel(
            contentRect: CGRect(origin: .zero, size: layout.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        contextMenuPanel.title = "Black-hole context menu"
        contextMenuPanel.level = .popUpMenu
        contextMenuPanel.isFloatingPanel = true
        contextMenuPanel.isOpaque = false
        contextMenuPanel.backgroundColor = .clear
        contextMenuPanel.hasShadow = false
        contextMenuPanel.hidesOnDeactivate = false
        contextMenuPanel.becomesKeyOnlyIfNeeded = false
        contextMenuPanel.collectionBehavior = panel.collectionBehavior
        contextMenuPanel.animationBehavior = .none
        contextMenuPanel.setFrame(layout.frame, display: false)
        contextMenuPanel.contentView = NSHostingView(
            rootView: PixelContextMenuView(
                appState: appState,
                presentation: presentation,
                actions: contextMenuActions(appState: appState)
            )
        )

        self.contextMenuPanel = contextMenuPanel
        contextMenuPresentation = presentation
        applyInputPolicy()
        installOutsidePointerMonitor()
        contextMenuPanel.makeKeyAndOrderFront(nil)

        contextMenuAnimationTask?.cancel()
        contextMenuAnimationTask = Task { @MainActor [weak self, weak presentation] in
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? ContextMenuVisualState.reducedMotionDuration
                : ContextMenuVisualState.appearanceDuration
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            presentation?.finishOpening()
            self?.contextMenuAnimationTask = nil
        }
    }

    private func showContextMenuFromAccessibility() {
        guard let panel else { return }
        showContextMenu(at: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
    }

    func contextMenuActions(appState: AppState) -> PixelContextMenuActions {
        PixelContextMenuActions(
            dismiss: { [weak self] in
                self?.dismissContextMenu(animated: true)
            },
            retry: { [weak self, weak appState] in
                appState?.retryNow()
                self?.dismissContextMenu(animated: true)
            },
            setPetSize: { [weak self, weak appState] size in
                guard let self, let appState, size != appState.petSize else {
                    self?.dismissContextMenu(animated: true)
                    return
                }
                appState.setPetSize(size)
                self.resize(to: size)
            },
            setPetPositionLocked: { [weak self, weak appState] isLocked in
                guard let self, let appState else { return }
                appState.setPetPositionLocked(isLocked)
                self.positionLockDidChange()
            },
            setPassesPointerInputThrough: { [weak self, weak appState] passesThrough in
                guard let self, let appState else { return }
                appState.setPassesPointerInputThrough(passesThrough)
                self.pointerClickThroughDidChange()
            },
            setTooltipStyle: { [weak self, weak appState] style in
                guard let self, let appState else { return }
                if style != appState.tooltipStyle {
                    appState.setTooltipStyle(style)
                    self.updateTooltipStyle()
                }
                self.dismissContextMenu(animated: true)
            },
            setShowsQuotaDynamics: { [weak self, weak appState] isEnabled in
                guard let self, let appState else { return }
                appState.setShowsQuotaDynamics(isEnabled)
                self.updateTooltipLayout()
            },
            setHidesInFullScreenApps: { [weak self, weak appState] isEnabled in
                guard let self, let appState else { return }
                appState.setHidesInFullScreenApps(isEnabled)
                self.updateVisibility(appState: appState)
            },
            setLaunchesAtLogin: { [weak appState] isEnabled in
                appState?.setLaunchesAtLogin(isEnabled)
            },
            openLoginItems: { [weak self, weak appState] in
                self?.dismissContextMenu(animated: true)
                appState?.openLoginItemsSettings()
            },
            hidePet: { [weak self, weak appState] in
                self?.dismissContextMenu(animated: true) { [weak self, weak appState] in
                    guard let self, let appState else { return }
                    appState.togglePetVisibility()
                    self.updateVisibility(appState: appState)
                }
            },
            quit: { [weak self] in
                self?.dismissContextMenu(animated: true) {
                    NSApp.terminate(nil)
                }
            }
        )
    }

    private func dismissContextMenu(
        animated: Bool,
        applyMouseEvents: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        guard let contextMenuPanel, let presentation = contextMenuPresentation else {
            completion?()
            return
        }

        appendContextMenuDismissCompletion(completion)
        guard animated else {
            contextMenuAnimationTask?.cancel()
            contextMenuAnimationTask = nil
            presentation.closeImmediately()
            finishContextMenuDismissal(applyMouseEvents: applyMouseEvents)
            return
        }

        guard presentation.phase != .closing else { return }
        contextMenuAnimationTask?.cancel()
        contextMenuAnimationTask = nil
        contextMenuPanel.ignoresMouseEvents = true

        presentation.startClosing()
        contextMenuAnimationTask = Task { @MainActor [weak self] in
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? ContextMenuVisualState.reducedMotionDuration
                : ContextMenuVisualState.dismissalDuration
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.finishContextMenuDismissal(applyMouseEvents: applyMouseEvents)
        }
    }

    private func appendContextMenuDismissCompletion(_ completion: (() -> Void)?) {
        guard let completion else { return }
        if let existing = contextMenuDismissCompletion {
            contextMenuDismissCompletion = {
                existing()
                completion()
            }
        } else {
            contextMenuDismissCompletion = completion
        }
    }

    private func finishContextMenuDismissal(applyMouseEvents: Bool = true) {
        contextMenuAnimationTask?.cancel()
        contextMenuAnimationTask = nil
        contextMenuPanel?.orderOut(nil)
        contextMenuPanel = nil
        contextMenuPresentation = nil
        removeOutsidePointerMonitor()
        applyInputPolicy(applyMouseEvents: applyMouseEvents)

        let completion = contextMenuDismissCompletion
        contextMenuDismissCompletion = nil
        completion?()
    }

    static func tooltipLayout(
        petFrame: CGRect,
        visibleFrame: CGRect,
        tooltipStyle: TooltipStyle = .smooth,
        showsHistory: Bool = false,
        preferredPlacement: QuotaTooltipView.Placement? = nil,
        tooltipSize: CGSize? = nil
    ) -> (
        origin: CGPoint,
        placement: QuotaTooltipView.Placement,
        size: CGSize
    ) {
        let center = CGPoint(x: petFrame.midX, y: petFrame.midY)
        let petScale = min(
            petFrame.width / PetSize.large.sceneSize.width,
            petFrame.height / PetSize.large.sceneSize.height
        )
        let size = tooltipSize
            ?? QuotaTooltipView.panelSize(
                forScale: petScale,
                style: tooltipStyle,
                showsHistory: showsHistory
            )
        let halfHole = CGSize(
            width: QuotaTooltipView.petAnchorHalfSize.width * petScale,
            height: QuotaTooltipView.petAnchorHalfSize.height * petScale
        )

        func clamp(_ value: CGFloat, from minimum: CGFloat, to maximum: CGFloat) -> CGFloat {
            guard maximum >= minimum else { return minimum }
            return min(maximum, max(minimum, value))
        }

        let centeredX = clamp(
            center.x - size.width / 2,
            from: visibleFrame.minX,
            to: visibleFrame.maxX - size.width
        )
        let centeredY = clamp(
            center.y - size.height / 2,
            from: visibleFrame.minY,
            to: visibleFrame.maxY - size.height
        )

        let candidates: [(
            placement: QuotaTooltipView.Placement,
            frame: CGRect,
            score: CGFloat
        )] = [
            (
                .below,
                CGRect(
                    origin: CGPoint(x: centeredX, y: center.y - halfHole.height - size.height),
                    size: size
                ),
                (center.y - halfHole.height - visibleFrame.minY) / visibleFrame.height + 0.0004
            ),
            (
                .above,
                CGRect(
                    origin: CGPoint(x: centeredX, y: center.y + halfHole.height),
                    size: size
                ),
                (visibleFrame.maxY - center.y - halfHole.height) / visibleFrame.height + 0.0003
            ),
            (
                .right,
                CGRect(
                    origin: CGPoint(x: center.x + halfHole.width, y: centeredY),
                    size: size
                ),
                (visibleFrame.maxX - center.x - halfHole.width) / visibleFrame.width + 0.0002
            ),
            (
                .left,
                CGRect(
                    origin: CGPoint(x: center.x - halfHole.width - size.width, y: centeredY),
                    size: size
                ),
                (center.x - halfHole.width - visibleFrame.minX) / visibleFrame.width + 0.0001
            )
        ]

        let fitting = candidates.filter { visibleFrame.contains($0.frame) }
        let preferred = preferredPlacement.flatMap { placement in
            fitting.first(where: { $0.placement == placement })
        }
        let selected = preferred
            ?? fitting.max { $0.score < $1.score }
            ?? candidates.min {
                overflow(of: $0.frame, outside: visibleFrame)
                    < overflow(of: $1.frame, outside: visibleFrame)
            }!

        return (
            CGPoint(
                x: clamp(
                    selected.frame.minX,
                    from: visibleFrame.minX,
                    to: visibleFrame.maxX - size.width
                ),
                y: clamp(
                    selected.frame.minY,
                    from: visibleFrame.minY,
                    to: visibleFrame.maxY - size.height
                )
            ),
            selected.placement,
            size
        )
    }

    static func shouldRestoreTooltipAfterDrag(
        wasVisible: Bool,
        cursorLocation: CGPoint,
        petFrame: CGRect
    ) -> Bool {
        wasVisible && petFrame.contains(cursorLocation)
    }

    static func resizedPetFrame(
        currentFrame: CGRect,
        to size: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let centeredOrigin = CGPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.midY - size.height / 2
        )
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return CGRect(
            origin: CGPoint(
                x: min(max(centeredOrigin.x, visibleFrame.minX), maximumX),
                y: min(max(centeredOrigin.y, visibleFrame.minY), maximumY)
            ),
            size: size
        )
    }

    static func resolvedPetFrame(
        candidate: CGRect,
        size: CGSize,
        displays: [PetDisplayGeometry],
        fallbackVisibleFrame: CGRect
    ) -> CGRect? {
        guard isFinite(candidate), candidate.width > 0, candidate.height > 0,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              isFinite(fallbackVisibleFrame),
              fallbackVisibleFrame.width > 0, fallbackVisibleFrame.height > 0 else {
            return nil
        }

        let resized = CGRect(
            x: candidate.midX - size.width / 2,
            y: candidate.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let visibleFrame = displays
            .map { ($0, intersectionArea($0.frame, resized)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0.visibleFrame ?? fallbackVisibleFrame
        return resizedPetFrame(
            currentFrame: resized,
            to: size,
            visibleFrame: visibleFrame
        )
    }

    private func makeTooltipPanel(appState: AppState, relativeTo panel: NSPanel) -> NSPanel {
        let visibleFrame = Self.visibleFrame(for: panel.frame)
        let hostingView = NSHostingView(
            rootView: QuotaTooltipView(
                appState: appState,
                placement: tooltipPlacement,
                isTooltipPresented: false
            )
        )
        let layout = Self.tooltipLayout(
            petFrame: panel.frame,
            visibleFrame: visibleFrame,
            tooltipStyle: appState.tooltipStyle,
            showsHistory: appState.showsQuotaDynamics,
            tooltipSize: hostingView.fittingSize
        )
        let tooltipPanel = NSPanel(
            contentRect: CGRect(origin: .zero, size: layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        tooltipPanel.title = "Codex quota details"
        tooltipPanel.level = .floating
        tooltipPanel.isFloatingPanel = true
        tooltipPanel.isOpaque = false
        tooltipPanel.backgroundColor = .clear
        tooltipPanel.hasShadow = false
        tooltipPanel.hidesOnDeactivate = false
        tooltipPanel.ignoresMouseEvents = true
        tooltipPanel.collectionBehavior = panel.collectionBehavior
        tooltipPlacement = layout.placement
        hostingView.rootView = QuotaTooltipView(
            appState: appState,
            placement: layout.placement,
            isTooltipPresented: false
        )
        tooltipHostingView = hostingView
        tooltipPanel.contentView = hostingView
        tooltipPanel.setFrameOrigin(layout.origin)
        return tooltipPanel
    }

    private func repositionTooltip(
        preferredPlacement: QuotaTooltipView.Placement? = nil,
        refreshContent: Bool = false
    ) {
        guard let panel, let tooltipPanel, let appState else { return }
        tooltipPanel.animationBehavior = appState.tooltipStyle == .pixel ? .none : .default

        if refreshContent {
            refreshTooltipRoot()
        }
        let measuredSize = tooltipHostingView?.fittingSize
            ?? tooltipPanel.contentView?.fittingSize

        let layout = Self.tooltipLayout(
            petFrame: panel.frame,
            visibleFrame: Self.visibleFrame(for: panel.frame),
            tooltipStyle: appState.tooltipStyle,
            showsHistory: appState.showsQuotaDynamics,
            preferredPlacement: preferredPlacement,
            tooltipSize: measuredSize
        )
        tooltipPanel.setFrame(
            CGRect(origin: layout.origin, size: layout.size),
            display: true
        )

        guard refreshContent || layout.placement != tooltipPlacement else { return }
        tooltipPlacement = layout.placement
        refreshTooltipRoot()
    }

    private func startResetCountdownUpdates() {
        resetCountdownTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let delay = QuotaTooltipView.resetCountdownUpdateDelay(
                    resetDate: self.appState?.quota?.primary?.resetDate,
                    now: Date()
                )
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(delay * 1_000_000_000)
                    )
                } catch {
                    return
                }
                guard self.tooltipPanel?.isVisible == true else { return }
                self.refreshTooltipCountdown()
            }
        }
    }

    private func stopResetCountdownUpdates() {
        resetCountdownTask?.cancel()
        resetCountdownTask = nil
    }

    private func refreshTooltipCountdown() {
        refreshTooltipRoot()
    }

    private func setTooltipPresentedToSwiftUI(_ isPresented: Bool) {
        guard isTooltipPresentedToSwiftUI != isPresented else { return }
        isTooltipPresentedToSwiftUI = isPresented
        refreshTooltipRoot()
    }

    private func refreshTooltipRoot() {
        guard let appState, let tooltipHostingView else { return }
        tooltipHostingView.rootView = QuotaTooltipView(
            appState: appState,
            placement: tooltipPlacement,
            isTooltipPresented: isTooltipPresentedToSwiftUI
        )
        tooltipHostingView.invalidateIntrinsicContentSize()
        tooltipHostingView.layoutSubtreeIfNeeded()
    }

    private func waitForDragToEnd() {
        guard isDraggingPet else { return }

        dragCompletionTask?.cancel()
        dragCompletionTask = Task { @MainActor [weak self] in
            while CGEventSource.buttonState(.combinedSessionState, button: .left) {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
            }
            self?.finishDragging()
        }
    }

    private func finishDragging() {
        guard isDraggingPet, let panel else { return }

        isDraggingPet = false
        dragCompletionTask = nil
        let shouldRestore = Self.shouldRestoreTooltipAfterDrag(
            wasVisible: restoreTooltipAfterDrag,
            cursorLocation: NSEvent.mouseLocation,
            petFrame: panel.frame
        )
        restoreTooltipAfterDrag = false

        if appState?.isPetPositionLocked == true {
            panel.saveFrame(usingName: frameName)
        }

        if shouldRestore {
            setTooltipVisible(true)
        }
    }

    private func cancelDragTracking() {
        dragCompletionTask?.cancel()
        dragCompletionTask = nil
        isDraggingPet = false
        restoreTooltipAfterDrag = false
    }

    private var inputPolicy: PetPanelInputPolicy {
        Self.inputPolicy(
            isPositionLocked: appState?.isPetPositionLocked ?? false,
            passesPointerInputThrough: appState?.passesPointerInputThrough ?? false,
            hasContextMenu: contextMenuPanel != nil
        )
    }

    private func applyInputPolicy(applyMouseEvents: Bool = true) {
        guard let panel else { return }
        let policy = inputPolicy
        panel.isMovableByWindowBackground = policy.allowsDrag
        if applyMouseEvents {
            panel.ignoresMouseEvents = !policy.allowsPointer
        }
    }

    private func installPointerMonitorIfNeeded() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            self?.handlePointerEvent(event) ?? event
        }
    }

    private func installOutsidePointerMonitor() {
        guard outsidePointerMonitor == nil else { return }
        outsidePointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissContextMenu(animated: true)
            }
        }
    }

    private func removeOutsidePointerMonitor() {
        guard let outsidePointerMonitor else { return }
        NSEvent.removeMonitor(outsidePointerMonitor)
        self.outsidePointerMonitor = nil
    }

    private func handlePointerEvent(_ event: NSEvent) -> NSEvent? {
        guard let panel, inputPolicy.allowsPointer else { return event }

        if contextMenuPanel != nil {
            if event.window === contextMenuPanel {
                return event
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                dismissContextMenu(animated: true)
                absorptionPointerStart = nil
                contextPointerStart = nil
            }

            return event.window === panel ? nil : event
        }

        switch event.type {
        case .leftMouseDown:
            guard event.window === panel else {
                absorptionPointerStart = nil
                contextPointerStart = nil
                return event
            }

            if event.modifierFlags.contains(.control) {
                absorptionPointerStart = nil
                if ContextMenuInteraction.containsVisiblePet(
                    event.locationInWindow,
                    sceneSize: appState?.petSize.sceneSize ?? BlackHoleView.size
                ) {
                    contextPointerStart = (
                        window: event.locationInWindow,
                        screen: NSEvent.mouseLocation,
                        kind: .controlClick
                    )
                }
                return nil
            }

            contextPointerStart = nil
            absorptionPointerStart = (
                window: event.locationInWindow,
                screen: NSEvent.mouseLocation
            )
        case .leftMouseUp:
            if let start = contextPointerStart, start.kind == .controlClick {
                contextPointerStart = nil
                showContextMenuIfAccepted(start: start)
                return nil
            }

            guard let start = absorptionPointerStart else { return event }
            absorptionPointerStart = nil
            let screenEnd = NSEvent.mouseLocation
            let virtualWindowEnd = CGPoint(
                x: start.window.x + screenEnd.x - start.screen.x,
                y: start.window.y + screenEnd.y - start.screen.y
            )
            if AbsorptionInteraction.acceptsClick(
                mouseDown: start.window,
                mouseUp: virtualWindowEnd,
                sceneSize: appState?.petSize.sceneSize ?? BlackHoleView.size
            ) {
                appState?.requestAbsorption()
            }
        case .rightMouseDown:
            guard event.window === panel,
                  ContextMenuInteraction.containsVisiblePet(
                    event.locationInWindow,
                    sceneSize: appState?.petSize.sceneSize ?? BlackHoleView.size
                  ) else {
                contextPointerStart = nil
                return event
            }
            absorptionPointerStart = nil
            contextPointerStart = (
                window: event.locationInWindow,
                screen: NSEvent.mouseLocation,
                kind: .rightClick
            )
            return nil
        case .rightMouseUp:
            guard let start = contextPointerStart, start.kind == .rightClick else {
                return event
            }
            contextPointerStart = nil
            showContextMenuIfAccepted(start: start)
            return nil
        default:
            break
        }

        return event
    }

    private func showContextMenuIfAccepted(
        start: (window: CGPoint, screen: CGPoint, kind: ContextPointerKind)
    ) {
        let screenEnd = NSEvent.mouseLocation
        let virtualWindowEnd = CGPoint(
            x: start.window.x + screenEnd.x - start.screen.x,
            y: start.window.y + screenEnd.y - start.screen.y
        )
        guard ContextMenuInteraction.acceptsClick(
            mouseDown: start.window,
            mouseUp: virtualWindowEnd,
            sceneSize: appState?.petSize.sceneSize ?? BlackHoleView.size
        ) else {
            return
        }
        showContextMenu(at: screenEnd)
    }

    private func positionPanelForInitialShow(
        _ panel: NSPanel,
        size: CGSize,
        isLocked: Bool
    ) {
        let fallbackVisibleFrame = Self.mainVisibleFrame(fallbackSize: size)
        var candidate = Self.defaultPetFrame(size: size, visibleFrame: fallbackVisibleFrame)
        if isLocked, panel.setFrameUsingName(frameName, force: true) {
            candidate = panel.frame
        }
        let frame = Self.resolvedPetFrame(
            candidate: candidate,
            size: size,
            displays: Self.currentDisplays,
            fallbackVisibleFrame: fallbackVisibleFrame
        ) ?? Self.defaultPetFrame(size: size, visibleFrame: fallbackVisibleFrame)
        panel.setFrame(frame, display: false)
    }

    private func correctPanelFrameIfNeeded(saveIfLocked: Bool) {
        guard let panel, let appState else { return }
        let size = appState.petSize.sceneSize
        let fallbackVisibleFrame = Self.mainVisibleFrame(fallbackSize: size)
        let corrected = Self.resolvedPetFrame(
            candidate: panel.frame,
            size: size,
            displays: Self.currentDisplays,
            fallbackVisibleFrame: fallbackVisibleFrame
        ) ?? Self.defaultPetFrame(size: size, visibleFrame: fallbackVisibleFrame)
        guard panel.frame != corrected else { return }
        panel.setFrame(corrected, display: true)
        if saveIfLocked, appState.isPetPositionLocked {
            panel.saveFrame(usingName: frameName)
        }
    }

    private func displayParametersDidChange() {
        dismissContextMenu(animated: false)
        correctPanelFrameIfNeeded(saveIfLocked: true)
        repositionTooltip()
        applyInputPolicy()
    }

    private func cursorIsInsideHoverTarget() -> Bool {
        guard let panel, let appState else { return false }
        let radius = BlackHoleView.hoverDiameter * appState.petSize.scale / 2
        let cursor = NSEvent.mouseLocation
        let deltaX = cursor.x - panel.frame.midX
        let deltaY = cursor.y - panel.frame.midY
        return hypot(deltaX, deltaY) <= radius
    }

    private func updateHoverRearmForPanelShow() {
        hoverRequiresExitBeforeReentry = Self.hoverRearmRequired(
            currentlyRequired: hoverRequiresExitBeforeReentry,
            passesPointerInputThrough: appState?.passesPointerInputThrough == true,
            cursorIsInsideHoverTarget: cursorIsInsideHoverTarget()
        )
    }

    private static var currentDisplays: [PetDisplayGeometry] {
        NSScreen.screens.map { PetDisplayGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    private static func mainVisibleFrame(fallbackSize: CGSize) -> CGRect {
        NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(origin: .zero, size: fallbackSize)
    }

    private static func defaultPetFrame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        resizedPetFrame(
            currentFrame: CGRect(
                x: visibleFrame.maxX - size.width - 24,
                y: visibleFrame.maxY - size.height - 24,
                width: size.width,
                height: size.height
            ),
            to: size,
            visibleFrame: visibleFrame
        )
    }

    private static func visibleFrame(for petFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens
            .map { ($0, intersectionArea($0.frame, petFrame)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
        return screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? petFrame
    }

    private static func visibleFrame(containing point: CGPoint, fallback: CGRect) -> CGRect {
        NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? visibleFrame(for: fallback)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func isFinite(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
    }

    private static func overflow(of frame: CGRect, outside bounds: CGRect) -> CGFloat {
        max(0, bounds.minX - frame.minX)
            + max(0, frame.maxX - bounds.maxX)
            + max(0, bounds.minY - frame.minY)
            + max(0, frame.maxY - bounds.maxY)
    }

    private static func detectFrontmostApplicationFullScreen() -> Bool {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return false
        }

        let screenSizes = NSScreen.screens.map(\.frame.size)
        return windows.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontmostApplication.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"],
                  let height = bounds["Height"] else {
                return false
            }

            return screenSizes.contains { screenSize in
                abs(width - screenSize.width) <= 2
                    && abs(height - screenSize.height) <= 2
            }
        }
    }
}

private enum ContextPointerKind {
    case rightClick
    case controlClick
}

private final class ContextMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class PetHostingView: NSHostingView<BlackHoleView> {
    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityLabel() -> String? {
        NSLocalizedString("accessibility.quota", comment: "Pet accessibility label")
    }

    override func accessibilityValue() -> Any? {
        QuotaTooltipView.accessibilitySummary(
            remainingPercent: rootView.appState.quota?.primary?.remainingPercent,
            speedMode: rootView.appState.speedMode,
            connectionState: rootView.appState.connectionState,
            resetDate: rootView.appState.quota?.primary?.resetDate,
            history: rootView.appState.quotaHistory,
            showsQuotaDynamics: rootView.appState.showsQuotaDynamics
        )
    }

    override func accessibilityChildren() -> [Any]? {
        nil
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(
                name: NSLocalizedString(
                    "accessibility.absorb_object",
                    comment: "Absorb object accessibility action"
                )
            ) { [weak self] in
                self?.rootView.appState.requestAbsorption()
                return self != nil
            },
            NSAccessibilityCustomAction(
                name: NSLocalizedString(
                    "accessibility.open_context_menu",
                    comment: "Open black-hole context menu accessibility action"
                )
            ) { [weak self] in
                self?.rootView.openContextMenu()
                return self != nil
            }
        ]
    }
}
