import Foundation

struct PetVisualState: Equatable, Sendable {
    static let spriteFrameCount = 6
    static let spriteFrameDuration: TimeInterval = 0.14

    let remainingPercent: Int

    init(remainingPercent: Int) {
        self.remainingPercent = min(100, max(0, remainingPercent))
    }

    var spriteStatePercent: Int {
        ((remainingPercent + 5) / 10) * 10
    }

    func spriteFrameIndex(elapsedTime: TimeInterval, speedMode: SpeedMode) -> Int {
        guard elapsedTime.isFinite, elapsedTime > 0 else {
            return 0
        }

        let progress = elapsedTime
            * rotationSpeed(for: speedMode)
            / Self.spriteFrameDuration
        return Int(progress.truncatingRemainder(dividingBy: Double(Self.spriteFrameCount)))
    }

    func spriteName(elapsedTime: TimeInterval, speedMode: SpeedMode) -> String {
        let frame = spriteFrameIndex(elapsedTime: elapsedTime, speedMode: speedMode)
        return "quota-\(spriteStatePercent)-frame-\(frame)"
    }

    func rotationSpeed(for speedMode: SpeedMode) -> Double {
        let quotaFactor = 0.1 + Double(remainingPercent) / 100 * 0.9
        return quotaFactor * (speedMode == .turbo ? 1.5 : 1)
    }

    func frameInterval(for speedMode: SpeedMode) -> TimeInterval {
        Self.spriteFrameDuration / rotationSpeed(for: speedMode)
    }

    func shouldPulse(in speedMode: SpeedMode) -> Bool {
        speedMode == .turbo && remainingPercent > 0
    }
}
