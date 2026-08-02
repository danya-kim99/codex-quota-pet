import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class PetPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var tooltipPanel: NSPanel?
    private var tooltipPlacement: QuotaTooltipView.Placement = .below
    private var isDraggingPet = false
    private var restoreTooltipAfterDrag = false
    private var dragCompletionTask: Task<Void, Never>?
    private var pointerMonitor: Any?
    private var absorptionPointerStart: (window: CGPoint, screen: CGPoint)?
    private weak var appState: AppState?
    private var observationTokens: [NSObjectProtocol] = []
    private let isFrontmostApplicationFullScreen: () -> Bool

    init(isFrontmostApplicationFullScreen: (() -> Bool)? = nil) {
        self.isFrontmostApplicationFullScreen = isFrontmostApplicationFullScreen
            ?? Self.detectFrontmostApplicationFullScreen
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var isTooltipVisible: Bool {
        tooltipPanel?.isVisible == true
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
        if let panel {
            repositionTooltip()
            panel.orderFrontRegardless()
            return
        }

        let size = BlackHoleView.size
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
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = PetHostingView(
            rootView: BlackHoleView(appState: appState) { [weak self] isVisible in
                self?.setTooltipVisible(isVisible)
            }
        )

        if let visibleFrame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(
                CGPoint(
                    x: visibleFrame.maxX - size.width - 24,
                    y: visibleFrame.maxY - size.height - 24
                )
            )
        }

        let tooltipPanel = makeTooltipPanel(appState: appState, relativeTo: panel)
        self.panel = panel
        self.tooltipPanel = tooltipPanel
        installPointerMonitorIfNeeded()
        panel.addChildWindow(tooltipPanel, ordered: .above)
        tooltipPanel.orderOut(nil)
        repositionTooltip()

        panel.orderFrontRegardless()
    }

    func hide() {
        cancelDragTracking()
        absorptionPointerStart = nil
        appState?.resetAbsorptionScene()
        setTooltipVisible(false)
        panel?.orderOut(nil)
    }

    func setTooltipVisible(_ isVisible: Bool) {
        guard let tooltipPanel, !isDraggingPet else { return }

        if isVisible {
            repositionTooltip()
            if !tooltipPanel.isVisible {
                tooltipPanel.orderFrontRegardless()
            }
        } else if tooltipPanel.isVisible {
            tooltipPanel.orderOut(nil)
        }
    }

    func windowWillMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel,
              NSEvent.pressedMouseButtons & 1 != 0,
              !isDraggingPet else {
            return
        }

        isDraggingPet = true
        restoreTooltipAfterDrag = tooltipPanel?.isVisible == true
        dragCompletionTask?.cancel()
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

    static func tooltipLayout(
        petFrame: CGRect,
        visibleFrame: CGRect
    ) -> (origin: CGPoint, placement: QuotaTooltipView.Placement) {
        let size = QuotaTooltipView.panelSize
        let center = CGPoint(x: petFrame.midX, y: petFrame.midY)
        let halfHole = QuotaTooltipView.petAnchorHalfSize

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
        let selected = fitting.max { $0.score < $1.score }
            ?? candidates.min { overflow(of: $0.frame, outside: visibleFrame) < overflow(of: $1.frame, outside: visibleFrame) }!

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
            selected.placement
        )
    }

    static func shouldRestoreTooltipAfterDrag(
        wasVisible: Bool,
        cursorLocation: CGPoint,
        petFrame: CGRect
    ) -> Bool {
        wasVisible && petFrame.contains(cursorLocation)
    }

    private func makeTooltipPanel(appState: AppState, relativeTo panel: NSPanel) -> NSPanel {
        let tooltipPanel = NSPanel(
            contentRect: CGRect(origin: .zero, size: QuotaTooltipView.panelSize),
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
        let visibleFrame = Self.visibleFrame(for: panel.frame)
        let layout = Self.tooltipLayout(petFrame: panel.frame, visibleFrame: visibleFrame)
        tooltipPlacement = layout.placement
        tooltipPanel.contentView = NSHostingView(
            rootView: QuotaTooltipView(appState: appState, placement: layout.placement)
        )
        tooltipPanel.setFrameOrigin(layout.origin)
        return tooltipPanel
    }

    private func repositionTooltip() {
        guard let panel, let tooltipPanel, let appState else { return }

        let layout = Self.tooltipLayout(
            petFrame: panel.frame,
            visibleFrame: Self.visibleFrame(for: panel.frame)
        )
        tooltipPanel.setFrameOrigin(layout.origin)

        guard layout.placement != tooltipPlacement else { return }
        tooltipPlacement = layout.placement
        tooltipPanel.contentView = NSHostingView(
            rootView: QuotaTooltipView(appState: appState, placement: layout.placement)
        )
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

    private func installPointerMonitorIfNeeded() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.handlePointerEvent(event)
            return event
        }
    }

    private func handlePointerEvent(_ event: NSEvent) {
        guard let panel else { return }

        switch event.type {
        case .leftMouseDown:
            guard event.window === panel else {
                absorptionPointerStart = nil
                return
            }
            absorptionPointerStart = (
                window: event.locationInWindow,
                screen: NSEvent.mouseLocation
            )
        case .leftMouseUp:
            guard let start = absorptionPointerStart else { return }
            absorptionPointerStart = nil
            let screenEnd = NSEvent.mouseLocation
            let virtualWindowEnd = CGPoint(
                x: start.window.x + screenEnd.x - start.screen.x,
                y: start.window.y + screenEnd.y - start.screen.y
            )
            if AbsorptionInteraction.acceptsClick(
                mouseDown: start.window,
                mouseUp: virtualWindowEnd,
                sceneSize: BlackHoleView.size
            ) {
                appState?.requestAbsorption()
            }
        default:
            break
        }
    }

    private static func visibleFrame(for petFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, petFrame) < intersectionArea(rhs.frame, petFrame)
        }
        return screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? petFrame
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
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
            resetDate: rootView.appState.quota?.primary?.resetDate
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
            }
        ]
    }
}
