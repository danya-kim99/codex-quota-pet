import AppKit
import SwiftUI

struct BlackHoleView: View {
    static let size = CGSize(width: 400, height: 220)
    static let hoverDiameter: CGFloat = 128

    let appState: AppState
    let setTooltipVisible: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()

    init(
        appState: AppState,
        setTooltipVisible: @escaping (Bool) -> Void = { _ in }
    ) {
        self.appState = appState
        self.setTooltipVisible = setTooltipVisible
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

    var body: some View {
        ZStack {
            pet

            Color.clear
                .frame(width: Self.hoverDiameter, height: Self.hoverDiameter)
                .contentShape(Circle())
                .onHover { isHovering in
                    if isHovering {
                        appState.refreshQuotaIfStale()
                    }
                    setTooltipVisible(isHovering)
                }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onDisappear {
            setTooltipVisible(false)
        }
    }

    private var pet: some View {
        TimelineView(.animation(minimumInterval: timelineInterval, paused: reduceMotion)) { timeline in
            if let sprite = SpriteFrames.image(
                named: visualState.spriteName(
                    elapsedTime: animationTime(at: timeline.date),
                    speedMode: appState.speedMode
                )
            ) {
                Image(nsImage: sprite)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(pulseScale(at: timeline.date))
                    .brightness(pulseBrightness(at: timeline.date))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .opacity(appState.connectionState == .connected ? 1 : 0.35)
    }

    private var shouldPulse: Bool {
        !reduceMotion && visualState.shouldPulse(in: appState.speedMode)
    }

    private var timelineInterval: TimeInterval {
        shouldPulse ? 1.0 / 30.0 : visualState.frameInterval(for: appState.speedMode)
    }

    private func animationTime(at date: Date) -> TimeInterval {
        guard !reduceMotion else {
            return 0
        }

        return max(0, date.timeIntervalSince(animationStart))
    }

    private func pulseScale(at date: Date) -> CGFloat {
        guard shouldPulse else {
            return 1
        }

        return 1 + CGFloat(0.01 + sin(animationTime(at: date) * 5) * 0.01)
    }

    private func pulseBrightness(at date: Date) -> Double {
        guard shouldPulse else {
            return 0
        }

        return 0.025 + sin(animationTime(at: date) * 5) * 0.025
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
