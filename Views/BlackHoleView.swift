import AppKit
import SwiftUI

struct BlackHoleView: View {
    static let size = PetSize.large.sceneSize
    static let hoverDiameter: CGFloat = 128
    static let reactionBrightness: Double = 0.16

    let appState: AppState
    let setTooltipVisible: (Bool) -> Void
    let openContextMenu: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()
    @State private var activePlans: [AbsorptionPlan] = []
    @State private var lastObjectID: String?
    @State private var reactionStart: Date?
    @State private var isTooltipSuppressed = false
    @State private var quotaReactionQueue = QuotaReactionQueue()
    @State private var quotaReactionStartedAt: Date?
    @State private var quotaReactionUsesReducedMotion = false
    @State private var quotaReactionCompletionTask: Task<Void, Never>?
    @State private var isQuotaReactionPreview = false

    private static let objectCatalog = try? AbsorbableObjectCatalog()

    init(
        appState: AppState,
        setTooltipVisible: @escaping (Bool) -> Void = { _ in },
        openContextMenu: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.setTooltipVisible = setTooltipVisible
        self.openContextMenu = openContextMenu
    }

    private var remainingPercent: Int {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["BLACK_HOLE_QUOTA_PREVIEW"],
           let percent = Int(value) {
            return PetVisualState(remainingPercent: percent).remainingPercent
        }
        #endif

        return appState.quota?.primary?.remainingPercent ?? 100
    }

    private var visualState: PetVisualState {
        PetVisualState(remainingPercent: remainingPercent)
    }

    private var effectiveReduceMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BLACK_HOLE_REDUCE_MOTION_PREVIEW"] == "1" {
            return true
        }
        #endif
        return reduceMotion
    }

    private var effectiveSpeedMode: SpeedMode {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BLACK_HOLE_SPEED_PREVIEW"] == "turbo" {
            return .turbo
        }
        #endif
        return appState.speedMode
    }

    private var sceneSize: CGSize {
        appState.petSize.sceneSize
    }

    var body: some View {
        ZStack {
            scene

            Color.clear
                .frame(
                    width: Self.hoverDiameter * appState.petSize.scale,
                    height: Self.hoverDiameter * appState.petSize.scale
                )
                .contentShape(Circle())
                .onHover(perform: updateHover)
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
        .opacity(appState.connectionState == .connected ? 1 : 0.35)
        .onChange(of: appState.absorptionRequestID) { _, _ in
            startAbsorption()
        }
        .onChange(of: appState.absorptionResetID) { _, _ in
            resetAbsorptionScene()
        }
        .onChange(of: appState.quotaConsumptionEvent?.id) { _, _ in
            receiveQuotaConsumptionEvent()
        }
        .onChange(of: appState.quotaReactionResetID) { _, _ in
            if !isQuotaReactionPreview {
                resetQuotaReactionPlayback()
            }
        }
        .onChange(of: effectiveReduceMotion) { _, _ in
            if !isQuotaReactionPreview {
                resetQuotaReactionPlayback()
            }
        }
        .onAppear {
            startQuotaReactionPreviewIfNeeded()
        }
        .onDisappear {
            resetAbsorptionScene()
            resetQuotaReactionPlayback()
            setTooltipVisible(false)
        }
    }

    private var scene: some View {
        TimelineView(
            .animation(
                minimumInterval: timelineInterval,
                paused: shouldPauseTimeline
            )
        ) { timeline in
            ZStack {
                quotaSprite(at: timeline.date)

                ForEach(activePlans) { plan in
                    if let sprite = AbsorbableSprites.sprite(named: plan.object.asset) {
                        AbsorptionObjectView(
                            plan: plan,
                            sprite: sprite,
                            date: timeline.date,
                            sceneSize: sceneSize
                        )
                    }
                }

                quotaReactionOverlay(at: timeline.date)
                reactionOverlay(at: timeline.date)
            }
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
    }

    @ViewBuilder
    private func reactionOverlay(at date: Date) -> some View {
        let intensity = reactionIntensity(at: date)
        if intensity > 0 {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.55 * intensity), lineWidth: 2)
                    .frame(width: 118, height: 118)
                Circle()
                    .stroke(Color.yellow.opacity(0.38 * intensity), lineWidth: 2)
                    .frame(width: 126, height: 126)
                Rectangle()
                    .fill(Color.white.opacity(0.58 * intensity))
                    .frame(width: 132, height: 2)
            }
            .scaleEffect(appState.petSize.scale)
            .allowsHitTesting(false)
        }
    }

    private var shouldTurboPulse: Bool {
        !effectiveReduceMotion
            && visualState.shouldPulse(in: effectiveSpeedMode)
    }

    private var shouldPauseTimeline: Bool {
        let hasNoOtherAnimation = activePlans.isEmpty
            && reactionStart == nil
            && quotaReactionQueue.active == nil
        return effectiveReduceMotion && hasNoOtherAnimation
    }

    private var timelineInterval: TimeInterval {
        let activeReaction = quotaReactionQueue.active.map {
            QuotaReactionVisualState(
                kind: $0.kind,
                elapsed: 0,
                usesReducedMotion: quotaReactionUsesReducedMotion
            )
        }
        return QuotaReactionVisualState.timelineInterval(
            hasManualAnimation: !activePlans.isEmpty || reactionStart != nil,
            activeReaction: activeReaction,
            turboPulse: shouldTurboPulse,
            idleInterval: visualState.frameInterval(for: effectiveSpeedMode)
        )
    }

    private func animationTime(at date: Date) -> TimeInterval {
        guard !effectiveReduceMotion else { return 0 }
        return max(0, date.timeIntervalSince(animationStart))
    }

    private func pulseScale(at date: Date) -> CGFloat {
        let turboPulse: CGFloat
        if shouldTurboPulse {
            turboPulse = CGFloat(0.01 + sin(animationTime(at: date) * 5) * 0.01)
        } else {
            turboPulse = 0
        }
        return 1 + turboPulse + 0.022 * reactionIntensity(at: date)
    }

    private func pulseBrightness(at date: Date) -> Double {
        let turboBrightness: Double
        if shouldTurboPulse {
            turboBrightness = 0.025 + sin(animationTime(at: date) * 5) * 0.025
        } else {
            turboBrightness = 0
        }
        return turboBrightness
            + Self.reactionBrightness * Double(reactionIntensity(at: date))
    }

    private func reactionIntensity(at date: Date) -> CGFloat {
        guard !effectiveReduceMotion, let reactionStart else { return 0 }
        let progress = min(1, max(0, date.timeIntervalSince(reactionStart) / 0.15))
        return CGFloat(sin(progress * .pi))
    }

    private func updateHover(_ isHovering: Bool) {
        if isHovering {
            appState.refreshQuotaIfStale()
            if !isTooltipSuppressed {
                setTooltipVisible(true)
            }
        } else {
            isTooltipSuppressed = false
            setTooltipVisible(false)
        }
    }

    @ViewBuilder
    private func quotaSprite(at date: Date) -> some View {
        if let sprite = SpriteFrames.image(
            named: visualState.spriteName(
                elapsedTime: animationTime(at: date),
                speedMode: effectiveSpeedMode
            )
        ) {
            Image(nsImage: sprite)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .scaleEffect(pulseScale(at: date))
                .brightness(pulseBrightness(at: date))
        }
    }

    @ViewBuilder
    private func quotaReactionOverlay(at date: Date) -> some View {
        if let event = quotaReactionQueue.active,
           quotaReactionStartedAt != nil {
            QuotaReactionCanvas(
                state: QuotaReactionVisualState(
                    kind: event.kind,
                    elapsed: quotaReactionElapsed(at: date),
                    usesReducedMotion: quotaReactionUsesReducedMotion
                )
            )
            .frame(width: sceneSize.width, height: sceneSize.height)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func receiveQuotaConsumptionEvent() {
        guard !isQuotaReactionPreview,
              appState.quotaReactionPresentationAllowed,
              let event = appState.quotaConsumptionEvent else {
            return
        }
        if let eventToStart = quotaReactionQueue.receive(
            event,
            deferPlayback: hasManualReaction
        ) {
            startQuotaReaction(eventToStart)
        }
    }

    private var hasManualReaction: Bool {
        !activePlans.isEmpty || reactionStart != nil
    }

    private func startQuotaReaction(
        _ event: QuotaConsumptionEvent,
        holdForPreview: Bool = false
    ) {
        quotaReactionCompletionTask?.cancel()
        quotaReactionStartedAt = Date()
        quotaReactionUsesReducedMotion = effectiveReduceMotion
        guard !holdForPreview else { return }

        let duration = quotaReactionUsesReducedMotion
            ? event.kind.reducedMotionDuration
            : event.kind.normalDuration
        quotaReactionCompletionTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            guard !Task.isCancelled,
                  quotaReactionQueue.active?.id == event.id else {
                return
            }

            let next = quotaReactionQueue.completeActive(
                id: event.id,
                startPending: !hasManualReaction
                    && appState.quotaReactionPresentationAllowed
            )
            quotaReactionStartedAt = nil
            quotaReactionCompletionTask = nil
            if let next {
                startQuotaReaction(next)
            }
        }
    }

    private func cancelActiveQuotaReaction() {
        quotaReactionCompletionTask?.cancel()
        quotaReactionCompletionTask = nil
        quotaReactionQueue.cancelActive()
        quotaReactionStartedAt = nil
    }

    private func resumePendingQuotaReactionIfPossible() {
        guard !hasManualReaction,
              appState.quotaReactionPresentationAllowed,
              let next = quotaReactionQueue.resumePending() else {
            return
        }
        startQuotaReaction(next)
    }

    private func resetQuotaReactionPlayback() {
        quotaReactionCompletionTask?.cancel()
        quotaReactionCompletionTask = nil
        quotaReactionQueue.reset()
        quotaReactionStartedAt = nil
        isQuotaReactionPreview = false
    }

    private func quotaReactionElapsed(at date: Date) -> TimeInterval {
        guard let event = quotaReactionQueue.active,
              let quotaReactionStartedAt else {
            return 0
        }
        #if DEBUG
        if isQuotaReactionPreview,
           let rawProgress = ProcessInfo.processInfo.environment[
                "BLACK_HOLE_QUOTA_REACTION_PREVIEW_PROGRESS"
           ],
           let progress = Double(rawProgress) {
            let duration = quotaReactionUsesReducedMotion
                ? event.kind.reducedMotionDuration
                : event.kind.normalDuration
            return min(1, max(0, progress)) * duration
        }
        #endif
        return max(0, date.timeIntervalSince(quotaReactionStartedAt))
    }

    private func startQuotaReactionPreviewIfNeeded() {
        #if DEBUG
        guard quotaReactionQueue.active == nil,
              let rawKind = ProcessInfo.processInfo.environment[
                "BLACK_HOLE_QUOTA_REACTION_PREVIEW"
              ] else {
            return
        }
        let kind: QuotaConsumptionReactionKind? = switch rawKind {
        case "small": .small
        case "medium": .medium
        case "large": .large
        case "last-light": .lastLight
        default: nil
        }
        guard let kind else { return }
        isQuotaReactionPreview = true
        let event = QuotaConsumptionEvent(id: -1, kind: kind)
        if let eventToStart = quotaReactionQueue.receive(event, deferPlayback: false) {
            startQuotaReaction(
                eventToStart,
                holdForPreview: ProcessInfo.processInfo.environment[
                    "BLACK_HOLE_QUOTA_REACTION_PREVIEW_PROGRESS"
                ] != nil
            )
        }
        #endif
    }

    private func startAbsorption() {
        guard activePlans.count < 3,
              let object = Self.objectCatalog?.select(
                excluding: lastObjectID,
                categoryRoll: Double.random(in: 0..<1),
                objectRoll: Double.random(in: 0..<1)
              ) else {
            return
        }

        let plan = AbsorptionPlan(
            object: object,
            startDate: Date(),
            duration: effectiveReduceMotion ? 0.225 : Double.random(in: 0.9...1.05),
            side: AbsorptionPlan.spawnSide(
                excluding: activePlans.map(\.side),
                roll: Double.random(in: 0..<1)
            ),
            seed: UInt64.random(in: UInt64.min...UInt64.max),
            usesReducedMotion: effectiveReduceMotion
        )
        cancelActiveQuotaReaction()
        activePlans.append(plan)
        lastObjectID = object.id
        isTooltipSuppressed = true
        setTooltipVisible(false)

        Task { @MainActor in
            let nanoseconds = UInt64(plan.duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard activePlans.contains(where: { $0.id == plan.id }) else { return }
            activePlans.removeAll { $0.id == plan.id }
            guard !plan.usesReducedMotion else {
                resumePendingQuotaReactionIfPossible()
                return
            }

            let startedAt = Date()
            reactionStart = startedAt
            try? await Task.sleep(nanoseconds: 180_000_000)
            if reactionStart == startedAt {
                reactionStart = nil
                resumePendingQuotaReactionIfPossible()
            }
        }
    }

    private func resetAbsorptionScene() {
        activePlans.removeAll()
        reactionStart = nil
        isTooltipSuppressed = false
    }
}

enum QuotaReactionVisualPhase: Equatable {
    case packets
    case lensingRing
    case photonRing
    case drain
    case afterglow
    case reducedStep(Int)
    case complete
}

struct QuotaReactionVisualState: Equatable {
    static let largeRingStart: TimeInterval = 0.64

    let kind: QuotaConsumptionReactionKind
    let elapsed: TimeInterval
    let usesReducedMotion: Bool

    var duration: TimeInterval {
        usesReducedMotion ? kind.reducedMotionDuration : kind.normalDuration
    }

    var progress: CGFloat {
        CGFloat(min(1, max(0, elapsed / duration)))
    }

    var phase: QuotaReactionVisualPhase {
        guard elapsed < duration else { return .complete }
        if usesReducedMotion {
            return .reducedStep(min(3, Int(progress * 4)))
        }
        switch kind {
        case .small, .medium:
            return .packets
        case .large:
            return elapsed < Self.largeRingStart ? .packets : .lensingRing
        case .lastLight:
            if elapsed < 0.48 { return .packets }
            if elapsed < 0.78 { return .photonRing }
            if elapsed < 0.96 { return .drain }
            return .afterglow
        }
    }

    var timelineInterval: TimeInterval {
        usesReducedMotion ? duration / 4 : 1.0 / 30.0
    }

    static func timelineInterval(
        hasManualAnimation: Bool,
        activeReaction: QuotaReactionVisualState?,
        turboPulse: Bool,
        idleInterval: TimeInterval
    ) -> TimeInterval {
        if hasManualAnimation { return 1.0 / 30.0 }
        if let activeReaction { return activeReaction.timelineInterval }
        return turboPulse ? 1.0 / 30.0 : idleInterval
    }

    func packetProgress(index: Int) -> CGFloat {
        guard !usesReducedMotion else { return 0 }
        let (travelDuration, stagger): (TimeInterval, TimeInterval) = switch kind {
        case .small: (0.46, 0)
        case .medium: (0.58, 0.045)
        case .large: (0.50, 0.035)
        case .lastLight: (0.42, 0.035)
        }
        let localElapsed = elapsed - Double(index) * stagger
        return CGFloat(min(1, max(0, localElapsed / travelDuration)))
    }
}

struct QuotaReactionRoute: Equatable {
    static let packetRoutes = [
        QuotaReactionRoute(
            start: CGPoint(x: 0.08, y: 0.24),
            firstControl: CGPoint(x: 0.31, y: 0.07),
            secondControl: CGPoint(x: 0.66, y: 0.22)
        ),
        QuotaReactionRoute(
            start: CGPoint(x: 0.91, y: 0.18),
            firstControl: CGPoint(x: 0.69, y: 0.05),
            secondControl: CGPoint(x: 0.54, y: 0.34)
        ),
        QuotaReactionRoute(
            start: CGPoint(x: 0.07, y: 0.78),
            firstControl: CGPoint(x: 0.27, y: 0.96),
            secondControl: CGPoint(x: 0.62, y: 0.76)
        ),
        QuotaReactionRoute(
            start: CGPoint(x: 0.93, y: 0.76),
            firstControl: CGPoint(x: 0.72, y: 0.96),
            secondControl: CGPoint(x: 0.48, y: 0.69)
        ),
        QuotaReactionRoute(
            start: CGPoint(x: 0.50, y: 0.06),
            firstControl: CGPoint(x: 0.24, y: 0.13),
            secondControl: CGPoint(x: 0.34, y: 0.44)
        )
    ]

    let start: CGPoint
    let firstControl: CGPoint
    let secondControl: CGPoint

    func point(progress: CGFloat, in size: CGSize, end: CGPoint) -> CGPoint {
        let t = min(1, max(0, progress))
        let inverse = 1 - t
        let p0 = scaled(start, to: size)
        let p1 = scaled(firstControl, to: size)
        let p2 = scaled(secondControl, to: size)
        return CGPoint(
            x: inverse * inverse * inverse * p0.x
                + 3 * inverse * inverse * t * p1.x
                + 3 * inverse * t * t * p2.x
                + t * t * t * end.x,
            y: inverse * inverse * inverse * p0.y
                + 3 * inverse * inverse * t * p1.y
                + 3 * inverse * t * t * p2.y
                + t * t * t * end.y
        )
    }

    private func scaled(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

private struct QuotaReactionCanvas: View {
    let state: QuotaReactionVisualState

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            if state.usesReducedMotion {
                drawReducedMotion(context: &context, size: size)
            } else {
                drawMovingReaction(context: &context, size: size)
            }
        }
    }

    private func drawMovingReaction(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for index in 0..<state.kind.packetCount {
            let progress = state.packetProgress(index: index)
            guard progress > 0, progress < 1 else { continue }
            drawPacket(
                context: &context,
                size: size,
                index: index,
                progress: progress
            )
        }

        switch state.kind {
        case .large:
            drawLargeRing(context: &context, size: size)
        case .lastLight:
            drawLastLight(context: &context, size: size)
        case .small, .medium:
            break
        }
    }

    private func drawPacket(
        context: inout GraphicsContext,
        size: CGSize,
        index: Int,
        progress: CGFloat
    ) {
        let eased = progress * progress * (3 - 2 * progress)
        let end = packetEnd(index: index, size: size)
        let route = QuotaReactionRoute.packetRoutes[index]
        let head = route.point(progress: eased, in: size, end: end)
        let tailStart = route.point(
            progress: max(0, eased - 0.12),
            in: size,
            end: end
        )
        let scale = sceneScale(size)
        let fadeIn = min(1, progress / 0.08)
        let fadeOut = min(1, (1 - progress) / 0.18)
        let opacity = fadeIn * fadeOut
        let color = state.kind == .lastLight
            ? Color(red: 1, green: 0.73, blue: 0.22)
            : Color(red: 0.42, green: 0.91, blue: 1)

        var tail = Path()
        tail.move(to: snapped(tailStart))
        for step in 1...5 {
            let sample = max(0, eased - 0.12 + 0.12 * CGFloat(step) / 5)
            tail.addLine(to: snapped(route.point(progress: sample, in: size, end: end)))
        }
        context.stroke(
            tail,
            with: .color(color.opacity(0.18 * opacity)),
            style: StrokeStyle(
                lineWidth: max(3, 7 * scale),
                lineCap: .square,
                lineJoin: .round
            )
        )
        context.stroke(
            tail,
            with: .color(color.opacity(0.82 * opacity)),
            style: StrokeStyle(
                lineWidth: max(1.5, 2.4 * scale),
                lineCap: .square,
                lineJoin: .round
            )
        )

        let outerSize = CGSize(width: max(6, 9 * scale), height: max(3, 4 * scale))
        context.fill(
            Path(rectCentered(at: snapped(head), size: outerSize)),
            with: .color(color.opacity(0.72 * opacity))
        )
        let core = max(2, 3 * scale)
        context.fill(
            Path(rectCentered(at: snapped(head), size: CGSize(width: core, height: core))),
            with: .color(.white.opacity(0.95 * opacity))
        )
    }

    private func drawLargeRing(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard state.elapsed >= QuotaReactionVisualState.largeRingStart else { return }
        let phase = clamped(
            (state.elapsed - QuotaReactionVisualState.largeRingStart)
                / (state.duration - QuotaReactionVisualState.largeRingStart)
        )
        let formed = smoothstep(min(1, phase / 0.28))
        let collapse = smoothstep(max(0, (phase - 0.38) / 0.62))
        let scale = sceneScale(size)
        let radii = CGSize(
            width: 62 * scale * (1 - 0.48 * collapse),
            height: 34 * scale * (1 - 0.48 * collapse)
        )
        drawSegmentedRing(
            context: &context,
            size: size,
            radii: radii,
            segmentCount: 16,
            visibleFraction: 1,
            color: Color(red: 0.55, green: 0.92, blue: 1),
            opacity: formed * (1 - collapse),
            lineWidth: max(1.5, 2.4 * scale)
        )
    }

    private func drawLastLight(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard state.elapsed >= 0.36 else { return }
        let scale = sceneScale(size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radii = CGSize(width: 63 * scale, height: 35 * scale)
        let formed = smoothstep(clamped((state.elapsed - 0.36) / 0.14))
        let color: Color
        if state.elapsed < 0.60 {
            color = Color(red: 1, green: 0.77, blue: 0.20)
        } else if state.elapsed < 0.72 {
            color = Color(red: 1, green: 0.39, blue: 0.08)
        } else {
            color = Color(red: 0.64, green: 0.35, blue: 1)
        }

        if state.elapsed < 0.78 {
            context.stroke(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - radii.width,
                        y: center.y - radii.height,
                        width: radii.width * 2,
                        height: radii.height * 2
                    )
                ),
                with: .color(color.opacity(0.92 * formed)),
                style: StrokeStyle(lineWidth: max(2, 3 * scale), lineCap: .square)
            )
        } else if state.elapsed < 0.96 {
            let drain = clamped((state.elapsed - 0.78) / 0.18)
            drawSegmentedRing(
                context: &context,
                size: size,
                radii: radii,
                segmentCount: 18,
                visibleFraction: 1 - drain,
                color: color,
                opacity: 1 - 0.6 * drain,
                lineWidth: max(1.5, 2.6 * scale)
            )
            drawDrainThreads(
                context: &context,
                center: center,
                radii: radii,
                progress: drain,
                color: color,
                lineWidth: max(1.5, 2.2 * scale)
            )
        }

        if state.elapsed >= 0.90 {
            let afterglow = 1 - clamped((state.elapsed - 0.90) / 0.25)
            context.stroke(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - radii.width,
                        y: center.y - radii.height,
                        width: radii.width * 2,
                        height: radii.height * 2
                    )
                ),
                with: .color(Color(red: 0.58, green: 0.28, blue: 1).opacity(0.36 * afterglow)),
                style: StrokeStyle(lineWidth: max(2, 5 * scale))
            )
        }
    }

    private func drawReducedMotion(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard case let .reducedStep(step) = state.phase, step < 3 else { return }
        let opacity: CGFloat = [1, 0.72, 0.42][step]
        let scale = sceneScale(size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radii = CGSize(width: 60 * scale, height: 33 * scale)

        if state.kind == .lastLight {
            let colors = [
                Color(red: 1, green: 0.77, blue: 0.20),
                Color(red: 1, green: 0.39, blue: 0.08),
                Color(red: 0.64, green: 0.35, blue: 1)
            ]
            context.stroke(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - radii.width,
                        y: center.y - radii.height,
                        width: radii.width * 2,
                        height: radii.height * 2
                    )
                ),
                with: .color(colors[step]),
                style: StrokeStyle(lineWidth: max(2, 3 * scale), lineCap: .square)
            )
            return
        }

        for index in 0..<state.kind.packetCount {
            let angle = fixedGlintAngle(index: index)
            let point = CGPoint(
                x: center.x + cos(angle) * radii.width,
                y: center.y + sin(angle) * radii.height
            )
            drawFixedGlint(
                context: &context,
                at: snapped(point),
                scale: scale,
                opacity: opacity
            )
        }

        if state.kind == .large {
            drawSegmentedRing(
                context: &context,
                size: size,
                radii: radii,
                segmentCount: 16,
                visibleFraction: 1,
                color: Color(red: 0.55, green: 0.92, blue: 1),
                opacity: opacity * 0.72,
                lineWidth: max(1.5, 2.2 * scale)
            )
        }
    }

    private func drawFixedGlint(
        context: inout GraphicsContext,
        at point: CGPoint,
        scale: CGFloat,
        opacity: CGFloat
    ) {
        let color = Color(red: 0.52, green: 0.93, blue: 1)
        context.fill(
            Path(
                rectCentered(
                    at: point,
                    size: CGSize(width: max(7, 10 * scale), height: max(2, 3 * scale))
                )
            ),
            with: .color(color.opacity(0.72 * opacity))
        )
        context.fill(
            Path(
                rectCentered(
                    at: point,
                    size: CGSize(width: max(2, 3 * scale), height: max(7, 10 * scale))
                )
            ),
            with: .color(.white.opacity(0.9 * opacity))
        )
    }

    private func drawSegmentedRing(
        context: inout GraphicsContext,
        size: CGSize,
        radii: CGSize,
        segmentCount: Int,
        visibleFraction: CGFloat,
        color: Color,
        opacity: CGFloat,
        lineWidth: CGFloat
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let visibleSegments = Int(ceil(CGFloat(segmentCount) * max(0, visibleFraction)))
        for index in 0..<visibleSegments {
            let start = CGFloat(index) * 2 * .pi / CGFloat(segmentCount) + 0.035
            let end = CGFloat(index + 1) * 2 * .pi / CGFloat(segmentCount) - 0.035
            context.stroke(
                ringSegment(
                    center: center,
                    radii: radii,
                    startAngle: start,
                    endAngle: end
                ),
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square)
            )
        }
    }

    private func drawDrainThreads(
        context: inout GraphicsContext,
        center: CGPoint,
        radii: CGSize,
        progress: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        for angle: CGFloat in [-2.55, 0.52] {
            let start = CGPoint(
                x: center.x + cos(angle) * radii.width,
                y: center.y + sin(angle) * radii.height
            )
            let end = CGPoint(
                x: start.x + (center.x - start.x) * progress,
                y: start.y + (center.y - start.y) * progress
            )
            let bend = CGPoint(
                x: (start.x + end.x) / 2 - sin(angle) * 12,
                y: (start.y + end.y) / 2 + cos(angle) * 12
            )
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: bend)
            context.stroke(
                path,
                with: .color(color.opacity(0.85 * (1 - 0.45 * progress))),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square)
            )
        }
    }

    private func packetEnd(index: Int, size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard state.kind == .lastLight else { return center }
        let scale = sceneScale(size)
        let angles: [CGFloat] = [-2.70, -1.48, -0.22, 0.92, 2.20]
        return CGPoint(
            x: center.x + cos(angles[index]) * 63 * scale,
            y: center.y + sin(angles[index]) * 35 * scale
        )
    }

    private func fixedGlintAngle(index: Int) -> CGFloat {
        let angles: [CGFloat] = [-2.70, -1.48, -0.22, 0.92, 2.20]
        if state.kind == .small { return angles[0] }
        if state.kind == .medium { return angles[[0, 2, 4][index]] }
        return angles[index]
    }

    private func ringSegment(
        center: CGPoint,
        radii: CGSize,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) -> Path {
        var path = Path()
        for step in 0...5 {
            let angle = startAngle + (endAngle - startAngle) * CGFloat(step) / 5
            let point = CGPoint(
                x: center.x + cos(angle) * radii.width,
                y: center.y + sin(angle) * radii.height
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func sceneScale(_ size: CGSize) -> CGFloat {
        min(
            size.width / PetSize.large.sceneSize.width,
            size.height / PetSize.large.sceneSize.height
        )
    }

    private func rectCentered(at point: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func snapped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x.rounded(), y: point.y.rounded())
    }

    private func clamped(_ value: TimeInterval) -> CGFloat {
        CGFloat(min(1, max(0, value)))
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
    }
}

private struct AbsorptionObjectView: View {
    let plan: AbsorptionPlan
    let sprite: AbsorbableSprite
    let date: Date
    let sceneSize: CGSize

    var body: some View {
        let state = AbsorptionVisualState.make(plan: plan, at: date, sceneSize: sceneSize)
        let fragments = sprite.fragmentTiles(seed: plan.seed)
        let removedTiles = Set(
            fragments.enumerated().compactMap { index, tile in
                state.breakupProgress >= threshold(for: index, count: fragments.count)
                    ? tile
                    : nil
            }
        )

        ZStack {
            Image(nsImage: sprite.image)
                .resizable()
                .interpolation(.none)
                .frame(
                    width: state.renderFieldSize,
                    height: state.renderFieldSize
                )
                .mask(PixelTileMask(removedTiles: removedTiles))
                .scaleEffect(
                    x: state.sizeScale * state.longitudinalScale,
                    y: state.sizeScale * state.transverseScale
                )
                .rotationEffect(.radians(state.rotation.radians))
                .position(state.position)
                .opacity(state.opacity)

            ForEach(Array(fragments.enumerated()), id: \.offset) { index, tile in
                fragment(
                    tile: tile,
                    index: index,
                    count: fragments.count,
                    state: state
                )
            }
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func fragment(
        tile: PixelTile,
        index: Int,
        count: Int,
        state: AbsorptionVisualState
    ) -> some View {
        let threshold = threshold(for: index, count: count)
        if state.breakupProgress >= threshold {
            let phase = min(
                1,
                (state.breakupProgress - threshold) / max(0.01, 1 - threshold)
            )
            let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
            let toCore = CGPoint(
                x: center.x - state.position.x,
                y: center.y - state.position.y
            )
            let length = max(1, hypot(toCore.x, toCore.y))
            let perpendicular = CGPoint(x: -toCore.y / length, y: toCore.x / length)
            let alternatingDirection: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let drift = sin(phase * .pi) * CGFloat(5 + index % 4) * alternatingDirection
            let fragmentPosition = CGPoint(
                x: state.position.x + toCore.x * pow(phase, 0.78) + perpendicular.x * drift,
                y: state.position.y + toCore.y * pow(phase, 0.78) + perpendicular.y * drift
            )

            Image(nsImage: sprite.image)
                .resizable()
                .interpolation(.none)
                .frame(
                    width: state.renderFieldSize,
                    height: state.renderFieldSize
                )
                .mask(SinglePixelTileMask(tile: tile))
                .scaleEffect(
                    x: state.sizeScale * state.longitudinalScale * (1 - 0.75 * phase),
                    y: state.sizeScale * state.transverseScale * (1 - 0.75 * phase)
                )
                .rotationEffect(.radians(state.rotation.radians))
                .position(fragmentPosition)
                .opacity(1 - phase)
        }
    }

    private func threshold(for index: Int, count: Int) -> CGFloat {
        CGFloat(index + 1) / CGFloat(max(1, count + 2))
    }
}

private struct PixelTile: Hashable {
    static let gridSize = 10

    let column: Int
    let row: Int
}

private struct PixelTileMask: View {
    let removedTiles: Set<PixelTile>

    var body: some View {
        Canvas { context, size in
            let tileWidth = size.width / CGFloat(PixelTile.gridSize)
            let tileHeight = size.height / CGFloat(PixelTile.gridSize)
            for row in 0..<PixelTile.gridSize {
                for column in 0..<PixelTile.gridSize {
                    let tile = PixelTile(column: column, row: row)
                    guard !removedTiles.contains(tile) else { continue }
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * tileWidth,
                                y: CGFloat(row) * tileHeight,
                                width: tileWidth,
                                height: tileHeight
                            )
                        ),
                        with: .color(.white)
                    )
                }
            }
        }
    }
}

private struct SinglePixelTileMask: View {
    let tile: PixelTile

    var body: some View {
        GeometryReader { geometry in
            let tileWidth = geometry.size.width / CGFloat(PixelTile.gridSize)
            let tileHeight = geometry.size.height / CGFloat(PixelTile.gridSize)
            Rectangle()
                .fill(.white)
                .frame(width: tileWidth, height: tileHeight)
                .position(
                    x: (CGFloat(tile.column) + 0.5) * tileWidth,
                    y: (CGFloat(tile.row) + 0.5) * tileHeight
                )
        }
    }
}

private final class AbsorbableSprite: NSObject {
    let image: NSImage
    private let occupiedTiles: [PixelTile]

    init(image: NSImage) {
        self.image = image
        occupiedTiles = Self.findOccupiedTiles(in: image)
    }

    func fragmentTiles(seed: UInt64) -> [PixelTile] {
        let count = min(occupiedTiles.count, 8 + Int(seed % 7))
        return occupiedTiles
            .sorted { tileHash($0, seed: seed) < tileHash($1, seed: seed) }
            .prefix(count)
            .map { $0 }
    }

    private func tileHash(_ tile: PixelTile, seed: UInt64) -> UInt64 {
        var value = seed
            &+ UInt64(tile.row * PixelTile.gridSize + tile.column)
            &* 0x9E37_79B9_7F4A_7C15
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        return value
    }

    private static func findOccupiedTiles(in image: NSImage) -> [PixelTile] {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            return []
        }

        let tileWidth = max(1, bitmap.pixelsWide / PixelTile.gridSize)
        let tileHeight = max(1, bitmap.pixelsHigh / PixelTile.gridSize)
        var tiles: [PixelTile] = []
        for row in 0..<PixelTile.gridSize {
            for column in 0..<PixelTile.gridSize {
                let xRange = (column * tileWidth)..<min(
                    bitmap.pixelsWide,
                    (column + 1) * tileWidth
                )
                let yRange = (row * tileHeight)..<min(
                    bitmap.pixelsHigh,
                    (row + 1) * tileHeight
                )
                let isOccupied = yRange.contains { y in
                    xRange.contains { x in
                        (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
                    }
                }
                if isOccupied {
                    tiles.append(PixelTile(column: column, row: row))
                }
            }
        }
        return tiles
    }
}

private enum AbsorbableSprites {
    private static let cache = NSCache<NSString, AbsorbableSprite>()

    static func sprite(named name: String) -> AbsorbableSprite? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "objects"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        let sprite = AbsorbableSprite(image: image)
        cache.setObject(sprite, forKey: key)
        return sprite
    }
}

private enum SpriteFrames {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String) -> NSImage? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "frames"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }
}
