import CoreGraphics
import Foundation

/// Presentation state; only an explicit experiment may supply approximate hook activity.
enum CompanionActivity: Equatable {
    case unavailable, idle, working, waiting
}

struct CompanionOrbitVisualState: Equatable {
    static let period: TimeInterval = 5
    static let appearanceDuration: TimeInterval = 0.35
    static let disappearanceDuration: TimeInterval = 0.25

    let position: CGPoint
    let canvasSize: CGFloat
    let scale: CGFloat
    let tiltDegrees: Double
    let opacity: Double
    let isBehindHole: Bool

    static func make(
        elapsed: TimeInterval,
        sceneSize: CGSize,
        reduceMotion: Bool,
        waiting: Bool = false,
        disappearanceElapsed: TimeInterval? = nil
    ) -> Self {
        let age = max(0, elapsed)
        let sceneScale = min(sceneSize.width / 400, sceneSize.height / 220)
        let theta = -0.35 + age * 2 * .pi / period
        let isStatic = reduceMotion || waiting
        let depth = isStatic ? 0 : sin(theta)
        // A terminal transition fades from the opacity already reached, even during entry.
        let entryAge = max(0, age - max(0, disappearanceElapsed ?? 0))
        let enter = reduceMotion ? 1 : ease(entryAge / appearanceDuration)
        let leave = disappearanceElapsed.map { reduceMotion ? 1 : ease($0 / disappearanceDuration) } ?? 0
        return Self(
            position: CGPoint(x: sceneSize.width / 2 + (isStatic ? 130 : 130 * cos(theta)) * sceneScale,
                              y: sceneSize.height / 2 + (isStatic ? -12 : 62 * depth) * sceneScale),
            canvasSize: 80 * sceneScale,
            scale: isStatic ? 1 : (0.94 + 0.06 * depth) * (0.9 + 0.1 * enter),
            tiltDegrees: isStatic ? 0 : 5 * depth,
            opacity: enter * (1 - leave),
            isBehindHole: !isStatic && depth < 0
        )
    }

    private static func ease(_ progress: Double) -> Double {
        let progress = min(1, max(0, progress))
        return progress * progress * (3 - 2 * progress)
    }
}

/// View-local, finite presentation state; it has no transport, task queue or timers.
struct CompanionOrbitPresentation: Equatable {
    private(set) var object: AbsorbableObjectManifest.Object?
    private(set) var activity: CompanionActivity = .unavailable
    private(set) var appearedAt: Date?
    private(set) var disappearedAt: Date?
    private(set) var isAppearing = false

    mutating func update(
        selection: AbsorbableObjectManifest.Object?,
        activity: CompanionActivity,
        at date: Date,
        reduceMotion: Bool
    ) {
        guard let selection, activity != .unavailable else { reset(); return }
        if activity == .idle {
            guard object != nil else { return }
            if reduceMotion { reset(); return }
            if disappearedAt == nil { disappearedAt = date }
            return
        }
        // A wait may retain a verified presentation; it is not evidence that work started.
        guard activity != .waiting || object != nil else { return }
        if object?.id != selection.id || disappearedAt != nil {
            object = selection
            appearedAt = date
            isAppearing = !reduceMotion
        }
        if reduceMotion { isAppearing = false }
        self.activity = activity
        disappearedAt = nil
    }

    mutating func advance(at date: Date) {
        if isAppearing, let appearedAt,
           date.timeIntervalSince(appearedAt) >= CompanionOrbitVisualState.appearanceDuration {
            isAppearing = false
        }
        guard let disappearedAt,
              date.timeIntervalSince(disappearedAt) >= CompanionOrbitVisualState.disappearanceDuration else { return }
        reset()
    }

    mutating func reset() {
        self = Self()
    }

    func needsAnimation(reduceMotion: Bool) -> Bool {
        object != nil && !reduceMotion && (activity == .working || isAppearing || disappearedAt != nil)
    }

    func visualState(at date: Date, sceneSize: CGSize, reduceMotion: Bool) -> CompanionOrbitVisualState? {
        guard object != nil, let appearedAt else { return nil }
        return .make(elapsed: date.timeIntervalSince(appearedAt), sceneSize: sceneSize,
                     reduceMotion: reduceMotion, waiting: activity == .waiting,
                     disappearanceElapsed: disappearedAt.map { date.timeIntervalSince($0) })
    }
}
