import AppKit
import ImageIO
import SwiftUI

struct BlackHoleView: View {
    static let size = PetSize.large.sceneSize
    static let reactionBrightness: Double = 0.16

    let appState: AppState
    let setTooltipVisible: (Bool) -> Void
    let openContextMenu: () -> Void
    let visibleRegionDidChange: (Int) -> Void
    let absorptionDidStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()
    @State private var activePlans: [AbsorptionPlan] = []
    @State private var lastObjectID: String?
    @State private var reactionStart: Date?
    private static let objectCatalog = try? AbsorbableObjectCatalog()

    init(
        appState: AppState,
        setTooltipVisible: @escaping (Bool) -> Void = { _ in },
        openContextMenu: @escaping () -> Void = {},
        visibleRegionDidChange: @escaping (Int) -> Void = { _ in },
        absorptionDidStart: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.setTooltipVisible = setTooltipVisible
        self.openContextMenu = openContextMenu
        self.visibleRegionDidChange = visibleRegionDidChange
        self.absorptionDidStart = absorptionDidStart
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

    private var sceneSize: CGSize {
        appState.petSize.sceneSize
    }

    var body: some View {
        scene
        .frame(width: sceneSize.width, height: sceneSize.height)
        .opacity(appState.connectionState == .connected ? 1 : 0.35)
        .onAppear {
            visibleRegionDidChange(visualState.spriteStatePercent)
        }
        .onChange(of: visualState.spriteStatePercent) { _, bucket in
            visibleRegionDidChange(bucket)
        }
        .onChange(of: appState.petSize) { _, _ in
            visibleRegionDidChange(visualState.spriteStatePercent)
        }
        .onChange(of: appState.absorptionRequestID) { _, _ in
            startAbsorption()
        }
        .onChange(of: appState.absorptionResetID) { _, _ in
            resetAbsorptionScene()
        }
        .onDisappear {
            resetAbsorptionScene()
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
                idleQuotaSprite(at: timeline.date)

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
        !reduceMotion
            && visualState.shouldPulse(in: appState.speedMode)
    }

    private var shouldPauseTimeline: Bool {
        reduceMotion && activePlans.isEmpty
    }

    private var timelineInterval: TimeInterval {
        if !activePlans.isEmpty || reactionStart != nil || shouldTurboPulse {
            return 1.0 / 30.0
        }
        return visualState.frameInterval(for: appState.speedMode)
    }

    private func animationTime(at date: Date) -> TimeInterval {
        guard !reduceMotion else { return 0 }
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
        guard !reduceMotion, let reactionStart else { return 0 }
        let progress = min(1, max(0, date.timeIntervalSince(reactionStart) / 0.15))
        return CGFloat(sin(progress * .pi))
    }

    @ViewBuilder
    private func idleQuotaSprite(at date: Date) -> some View {
        if let sprite = SpriteFrames.image(named: visualState.spriteName(
            elapsedTime: animationTime(at: date),
            speedMode: appState.speedMode
        )) {
            Image(nsImage: sprite)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .scaleEffect(pulseScale(at: date))
                .brightness(pulseBrightness(at: date))
        }
    }

    private func startAbsorption() {
        guard activePlans.count < 3,
              let object = Self.objectCatalog?.select(
                excluding: lastObjectID,
                categoryWeights: appState.absorptionCategoryWeights,
                categoryRoll: Double.random(in: 0..<1),
                objectRoll: Double.random(in: 0..<1)
              ) else {
            return
        }

        let plan = AbsorptionPlan(
            object: object,
            startDate: Date(),
            duration: reduceMotion ? 0.225 : Double.random(in: 0.9...1.05),
            side: AbsorptionPlan.spawnSide(
                excluding: activePlans.map(\.side),
                roll: Double.random(in: 0..<1)
            ),
            seed: UInt64.random(in: UInt64.min...UInt64.max),
            usesReducedMotion: reduceMotion
        )
        activePlans.append(plan)
        lastObjectID = object.id
        absorptionDidStart()
        setTooltipVisible(false)

        Task { @MainActor in
            let nanoseconds = UInt64(plan.duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard activePlans.contains(where: { $0.id == plan.id }) else { return }
            activePlans.removeAll { $0.id == plan.id }
            if plan.usesReducedMotion {
                return
            }

            let startedAt = Date()
            reactionStart = startedAt
            try? await Task.sleep(nanoseconds: 180_000_000)
            if reactionStart == startedAt {
                reactionStart = nil
            }
        }
    }

    private func resetAbsorptionScene() {
        activePlans.removeAll()
        reactionStart = nil
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

struct PetVisibleRegion {
    static let maximumVisualScale: CGFloat = 1.042

    let bucket: Int
    let sceneSize: CGSize
    private let alphaUnion: SpriteAlphaUnion?
    private let spriteFrame: CGRect
    private let coreRadius: CGFloat
    private let bounds: CGRect

    init(bucket: Int, sceneSize: CGSize, bundle: Bundle = .main) {
        self.bucket = bucket
        self.sceneSize = sceneSize
        let union = SpriteFrames.alphaUnion(bucket: bucket, bundle: bundle)
        alphaUnion = union

        let sourceSize = union.map {
            CGSize(width: $0.width, height: $0.height)
        } ?? CGSize(width: 384, height: 272)
        let fitScale = min(
            sceneSize.width / sourceSize.width,
            sceneSize.height / sourceSize.height
        )
        let renderedScale = fitScale * Self.maximumVisualScale
        let renderedSize = CGSize(
            width: sourceSize.width * renderedScale,
            height: sourceSize.height * renderedScale
        )
        let frame = CGRect(
            x: (sceneSize.width - renderedSize.width) / 2,
            y: (sceneSize.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
        spriteFrame = frame
        let radius = AbsorptionInteraction.coreDiameter
            * sceneSize.width / PetSize.large.sceneSize.width / 2
        coreRadius = radius

        let coreBounds = CGRect(
            x: sceneSize.width / 2 - radius,
            y: sceneSize.height / 2 - radius,
            width: radius * 2,
            height: radius * 2
        )
        let opaqueBounds = union.map { union in
            CGRect(
                x: frame.minX
                    + union.opaqueBounds.minX / CGFloat(union.width) * frame.width,
                y: frame.minY
                    + union.opaqueBounds.minY / CGFloat(union.height) * frame.height,
                width: union.opaqueBounds.width / CGFloat(union.width) * frame.width,
                height: union.opaqueBounds.height / CGFloat(union.height) * frame.height
            )
        } ?? .null
        bounds = coreBounds.union(opaqueBounds)
            .intersection(CGRect(origin: .zero, size: sceneSize))
    }

    func contains(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else { return false }

        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        if hypot(point.x - center.x, point.y - center.y) <= coreRadius {
            return true
        }

        guard let alphaUnion, spriteFrame.contains(point) else { return false }
        let x = Int(
            (point.x - spriteFrame.minX) / spriteFrame.width
                * CGFloat(alphaUnion.width)
        )
        let y = Int(
            (point.y - spriteFrame.minY) / spriteFrame.height
                * CGFloat(alphaUnion.height)
        )
        return alphaUnion.contains(x: x, y: y)
    }
}

private final class SpriteAlphaUnion: NSObject {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let opaqueBounds: CGRect

    init(width: Int, height: Int, pixels: [UInt8], opaqueBounds: CGRect) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.opaqueBounds = opaqueBounds
    }

    func contains(x: Int, y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
            && pixels[y * width + x] != 0
    }
}

private enum SpriteFrames {
    private static let cache = NSCache<NSString, NSImage>()
    private static let alphaUnionCache = NSCache<NSString, SpriteAlphaUnion>()

    static func image(named name: String, bundle: Bundle = .main) -> NSImage? {
        let key = "\(bundle.bundleURL.path)|\(name)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let url = bundle.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "frames"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    static func alphaUnion(bucket: Int, bundle: Bundle) -> SpriteAlphaUnion? {
        let key = "\(bundle.bundleURL.path)|\(bucket)" as NSString
        if let cached = alphaUnionCache.object(forKey: key) {
            return cached
        }

        let images = (0..<PetVisualState.spriteFrameCount).compactMap {
            image(named: "quota-\(bucket)-frame-\($0)", bundle: bundle)
        }
        guard images.count == PetVisualState.spriteFrameCount,
              let first = cgImage(from: images[0]) else { return nil }

        let width = first.width
        let height = first.height
        var union = [UInt8](repeating: 0, count: width * height)
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1

        for image in images {
            guard let cgImage = cgImage(from: image),
                  cgImage.width == width, cgImage.height == height,
                  let alpha = alphaPixels(in: cgImage) else { return nil }
            for index in alpha.indices where alpha[index] > 0 {
                union[index] = 1
                let x = index % width
                let y = index / width
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        let alphaUnion = SpriteAlphaUnion(
            width: width,
            height: height,
            pixels: union,
            opaqueBounds: CGRect(
                x: minimumX,
                y: minimumY,
                width: maximumX - minimumX + 1,
                height: maximumY - minimumY + 1
            )
        )
        alphaUnionCache.setObject(alphaUnion, forKey: key)
        return alphaUnion
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func alphaPixels(in image: CGImage) -> [UInt8]? {
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let didDraw = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        guard didDraw else { return nil }
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }
}
