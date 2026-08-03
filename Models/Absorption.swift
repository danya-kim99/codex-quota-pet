import CoreGraphics
import Foundation

struct AbsorbableObjectManifest: Decodable, Equatable {
    struct Canvas: Decodable, Equatable {
        let width: Int
        let height: Int
    }

    struct Category: Decodable, Equatable {
        let id: String
        let weight: Double
    }

    struct Object: Decodable, Equatable, Identifiable {
        let id: String
        let category: String
        let asset: String
    }

    let canvas: Canvas
    let categories: [Category]
    let objects: [Object]
}

enum AbsorbableObjectCatalogError: Error, Equatable {
    case missingManifest
    case invalidCanvas
    case duplicateCategory(String)
    case invalidCategoryWeight(String)
    case duplicateObject(String)
    case unknownCategory(object: String, category: String)
    case emptyCategory(String)
}

struct AbsorbableObjectCatalog {
    let manifest: AbsorbableObjectManifest

    init(data: Data) throws {
        let manifest = try JSONDecoder().decode(AbsorbableObjectManifest.self, from: data)
        try Self.validate(manifest)
        self.manifest = manifest
    }

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "objects"
        ) else {
            throw AbsorbableObjectCatalogError.missingManifest
        }
        try self.init(data: Data(contentsOf: url))
    }

    func select(
        excluding excludedID: String?,
        categoryRoll: Double,
        objectRoll: Double
    ) -> AbsorbableObjectManifest.Object? {
        let eligibleObjects = manifest.objects.filter { $0.id != excludedID }
        let eligibleCategories = manifest.categories.filter { category in
            eligibleObjects.contains { $0.category == category.id }
        }
        guard let category = Self.weightedCategory(
            from: eligibleCategories,
            roll: categoryRoll
        ) else {
            return nil
        }

        let objects = eligibleObjects.filter { $0.category == category.id }
        guard !objects.isEmpty else { return nil }
        let index = min(
            objects.count - 1,
            Int(Self.unitInterval(objectRoll) * Double(objects.count))
        )
        return objects[index]
    }

    private static func validate(_ manifest: AbsorbableObjectManifest) throws {
        guard manifest.canvas.width == 64, manifest.canvas.height == 64 else {
            throw AbsorbableObjectCatalogError.invalidCanvas
        }

        var categoryIDs = Set<String>()
        for category in manifest.categories {
            guard categoryIDs.insert(category.id).inserted else {
                throw AbsorbableObjectCatalogError.duplicateCategory(category.id)
            }
            guard category.weight > 0 else {
                throw AbsorbableObjectCatalogError.invalidCategoryWeight(category.id)
            }
        }

        var objectIDs = Set<String>()
        for object in manifest.objects {
            guard objectIDs.insert(object.id).inserted else {
                throw AbsorbableObjectCatalogError.duplicateObject(object.id)
            }
            guard categoryIDs.contains(object.category) else {
                throw AbsorbableObjectCatalogError.unknownCategory(
                    object: object.id,
                    category: object.category
                )
            }
        }

        for category in manifest.categories where
            !manifest.objects.contains(where: { $0.category == category.id }) {
            throw AbsorbableObjectCatalogError.emptyCategory(category.id)
        }
    }

    private static func weightedCategory(
        from categories: [AbsorbableObjectManifest.Category],
        roll: Double
    ) -> AbsorbableObjectManifest.Category? {
        let totalWeight = categories.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        let target = unitInterval(roll) * totalWeight
        var cumulativeWeight = 0.0
        for category in categories {
            cumulativeWeight += category.weight
            if target < cumulativeWeight {
                return category
            }
        }
        return categories.last
    }

    private static func unitInterval(_ value: Double) -> Double {
        min(0.999_999_999, max(0, value))
    }
}

enum AbsorptionSpawnSide: CaseIterable, Equatable {
    case left
    case top
    case right
    case bottom
}

struct AbsorptionPlan: Identifiable, Equatable {
    let id: UUID
    let object: AbsorbableObjectManifest.Object
    let startDate: Date
    let duration: TimeInterval
    let side: AbsorptionSpawnSide
    let seed: UInt64
    let usesReducedMotion: Bool

    init(
        id: UUID = UUID(),
        object: AbsorbableObjectManifest.Object,
        startDate: Date,
        duration: TimeInterval,
        side: AbsorptionSpawnSide,
        seed: UInt64,
        usesReducedMotion: Bool
    ) {
        self.id = id
        self.object = object
        self.startDate = startDate
        self.duration = duration
        self.side = side
        self.seed = seed
        self.usesReducedMotion = usesReducedMotion
    }

    static func spawnSide(
        excluding activeSides: [AbsorptionSpawnSide],
        roll: Double
    ) -> AbsorptionSpawnSide {
        let unused = allSides.filter { !activeSides.contains($0) }
        let choices = unused.isEmpty ? allSides : unused
        let clampedRoll = min(0.999_999_999, max(0, roll))
        return choices[min(choices.count - 1, Int(clampedRoll * Double(choices.count)))]
    }

    private static let allSides = AbsorptionSpawnSide.allCases
}

struct AbsorptionVisualState: Equatable {
    static let objectSize: CGFloat = 48
    static let renderingInset: CGFloat = 2

    let progress: CGFloat
    let position: CGPoint
    let rotation: AngleValue
    let longitudinalScale: CGFloat
    let transverseScale: CGFloat
    let sizeScale: CGFloat
    let opacity: CGFloat
    let breakupProgress: CGFloat

    var renderedFrame: CGRect {
        let halfExtents = Self.transformedHalfExtents(
            rotation: rotation.radians,
            longitudinalScale: longitudinalScale,
            transverseScale: transverseScale,
            sizeScale: sizeScale
        )
        return CGRect(
            x: position.x - halfExtents.width,
            y: position.y - halfExtents.height,
            width: halfExtents.width * 2,
            height: halfExtents.height * 2
        )
    }

    struct AngleValue: Equatable {
        let radians: CGFloat
    }

    static func make(
        plan: AbsorptionPlan,
        at date: Date,
        sceneSize: CGSize
    ) -> AbsorptionVisualState {
        let progress = CGFloat(
            min(1, max(0, date.timeIntervalSince(plan.startDate) / plan.duration))
        )
        if plan.usesReducedMotion {
            return reducedMotionState(plan: plan, progress: progress, sceneSize: sceneSize)
        }

        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        let start = spawnPoint(plan: plan, sceneSize: sceneSize)
        let sceneScale = min(
            sceneSize.width / PetSize.large.sceneSize.width,
            sceneSize.height / PetSize.large.sceneSize.height
        )
        let inward = normalized(CGPoint(x: center.x - start.x, y: center.y - start.y))
        let directionSign: CGFloat = unit(seed: plan.seed, index: 3) < 0.5 ? -1 : 1
        let perpendicular = CGPoint(x: -inward.y * directionSign, y: inward.x * directionSign)
        let firstControl = CGPoint(
            x: start.x + inward.x * (54 + unit(seed: plan.seed, index: 4) * 34) * sceneScale
                + perpendicular.x * (28 + unit(seed: plan.seed, index: 5) * 26) * sceneScale,
            y: start.y + inward.y * (54 + unit(seed: plan.seed, index: 4) * 34) * sceneScale
                + perpendicular.y * (28 + unit(seed: plan.seed, index: 5) * 26) * sceneScale
        )
        let secondControl = CGPoint(
            x: center.x - inward.x * (22 + unit(seed: plan.seed, index: 6) * 18) * sceneScale
                + perpendicular.x * (42 + unit(seed: plan.seed, index: 7) * 24) * sceneScale,
            y: center.y - inward.y * (22 + unit(seed: plan.seed, index: 6) * 18) * sceneScale
                + perpendicular.y * (42 + unit(seed: plan.seed, index: 7) * 24) * sceneScale
        )

        let pathProgress = pow(progress, 1.45)
        let rawPosition = cubicPoint(
            from: start,
            firstControl: firstControl,
            secondControl: secondControl,
            to: center,
            progress: pathProgress
        )
        let tangent = cubicTangent(
            from: start,
            firstControl: firstControl,
            secondControl: secondControl,
            to: center,
            progress: pathProgress
        )
        let rotation = atan2(tangent.y, tangent.x)

        let deformation = stepped(smoothstep((progress - 0.55) / 0.4), steps: 6)
        let shrink = smoothstep((progress - 0.78) / 0.22)
        let fade = stepped(smoothstep((progress - 0.92) / 0.08), steps: 4)
        let longitudinalScale = 1 + 1.5 * deformation
        let transverseScale = 1 - 0.5 * deformation
        let sizeScale = 1 - 0.88 * shrink
        let halfExtents = transformedHalfExtents(
            rotation: rotation,
            longitudinalScale: longitudinalScale,
            transverseScale: transverseScale,
            sizeScale: sizeScale
        )
        let position = fitted(
            snapped(rawPosition),
            halfExtents: halfExtents,
            sceneSize: sceneSize
        )

        return AbsorptionVisualState(
            progress: progress,
            position: position,
            rotation: AngleValue(radians: rotation),
            longitudinalScale: longitudinalScale,
            transverseScale: transverseScale,
            sizeScale: sizeScale,
            opacity: 1 - fade,
            breakupProgress: smoothstep((progress - 0.67) / 0.31)
        )
    }

    private static func reducedMotionState(
        plan: AbsorptionPlan,
        progress: CGFloat,
        sceneSize: CGSize
    ) -> AbsorptionVisualState {
        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        let angle = unit(seed: plan.seed, index: 8) * .pi * 2
        let position = snapped(
            CGPoint(x: center.x + cos(angle) * 34, y: center.y + sin(angle) * 24)
        )
        return AbsorptionVisualState(
            progress: progress,
            position: position,
            rotation: AngleValue(radians: 0),
            longitudinalScale: 1,
            transverseScale: 1,
            sizeScale: 1 - 0.25 * stepped(progress, steps: 4),
            opacity: 1 - stepped(progress, steps: 4),
            breakupProgress: 0
        )
    }

    private static func spawnPoint(plan: AbsorptionPlan, sceneSize: CGSize) -> CGPoint {
        let minimumCenterInset = ceil(objectSize / sqrt(2)) + renderingInset
        let edgeOffset = minimumCenterInset + unit(seed: plan.seed, index: 0) * 8
        let horizontalRange = sceneSize.width * 0.42
        let verticalRange = sceneSize.height * 0.30
        let horizontal = sceneSize.width / 2
            + (unit(seed: plan.seed, index: 1) - 0.5) * horizontalRange * 2
        let vertical = sceneSize.height / 2
            + (unit(seed: plan.seed, index: 2) - 0.5) * verticalRange * 2
        let minimumCenter = minimumCenterInset
        let boundedHorizontal = min(
            max(horizontal, minimumCenter),
            sceneSize.width - minimumCenter
        )
        let boundedVertical = min(
            max(vertical, minimumCenter),
            sceneSize.height - minimumCenter
        )

        return switch plan.side {
        case .left:
            CGPoint(x: edgeOffset, y: boundedVertical)
        case .top:
            CGPoint(x: boundedHorizontal, y: edgeOffset)
        case .right:
            CGPoint(x: sceneSize.width - edgeOffset, y: boundedVertical)
        case .bottom:
            CGPoint(x: boundedHorizontal, y: sceneSize.height - edgeOffset)
        }
    }

    private static func cubicPoint(
        from start: CGPoint,
        firstControl: CGPoint,
        secondControl: CGPoint,
        to end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        let inverse = 1 - progress
        return CGPoint(
            x: inverse * inverse * inverse * start.x
                + 3 * inverse * inverse * progress * firstControl.x
                + 3 * inverse * progress * progress * secondControl.x
                + progress * progress * progress * end.x,
            y: inverse * inverse * inverse * start.y
                + 3 * inverse * inverse * progress * firstControl.y
                + 3 * inverse * progress * progress * secondControl.y
                + progress * progress * progress * end.y
        )
    }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        let length = max(0.001, hypot(point.x, point.y))
        return CGPoint(x: point.x / length, y: point.y / length)
    }

    private static func cubicTangent(
        from start: CGPoint,
        firstControl: CGPoint,
        secondControl: CGPoint,
        to end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        let inverse = 1 - progress
        return CGPoint(
            x: 3 * inverse * inverse * (firstControl.x - start.x)
                + 6 * inverse * progress * (secondControl.x - firstControl.x)
                + 3 * progress * progress * (end.x - secondControl.x),
            y: 3 * inverse * inverse * (firstControl.y - start.y)
                + 6 * inverse * progress * (secondControl.y - firstControl.y)
                + 3 * progress * progress * (end.y - secondControl.y)
        )
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
    }

    private static func stepped(_ value: CGFloat, steps: CGFloat) -> CGFloat {
        floor(min(1, max(0, value)) * steps) / steps
    }

    private static func snapped(_ point: CGPoint) -> CGPoint {
        let step: CGFloat = 0.5
        return CGPoint(
            x: (point.x / step).rounded() * step,
            y: (point.y / step).rounded() * step
        )
    }

    private static func transformedHalfExtents(
        rotation: CGFloat,
        longitudinalScale: CGFloat,
        transverseScale: CGFloat,
        sizeScale: CGFloat
    ) -> CGSize {
        let width = objectSize * longitudinalScale * sizeScale
        let height = objectSize * transverseScale * sizeScale
        let cosine = abs(cos(rotation))
        let sine = abs(sin(rotation))
        return CGSize(
            width: (cosine * width + sine * height) / 2,
            height: (sine * width + cosine * height) / 2
        )
    }

    private static func fitted(
        _ point: CGPoint,
        halfExtents: CGSize,
        sceneSize: CGSize
    ) -> CGPoint {
        let step: CGFloat = 0.5
        let minimumX = ceil((halfExtents.width + renderingInset) / step) * step
        let maximumX = floor((sceneSize.width - halfExtents.width - renderingInset) / step) * step
        let minimumY = ceil((halfExtents.height + renderingInset) / step) * step
        let maximumY = floor((sceneSize.height - halfExtents.height - renderingInset) / step) * step

        return CGPoint(
            x: minimumX <= maximumX
                ? min(maximumX, max(minimumX, point.x))
                : sceneSize.width / 2,
            y: minimumY <= maximumY
                ? min(maximumY, max(minimumY, point.y))
                : sceneSize.height / 2
        )
    }

    private static func unit(seed: UInt64, index: UInt64) -> CGFloat {
        var value = seed &+ index &* 0x9E37_79B9_7F4A_7C15
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return CGFloat(value % 10_000) / 9_999
    }
}

enum AbsorptionInteraction {
    static let maximumClickMovement: CGFloat = 6
    static let coreDiameter: CGFloat = 112

    static func acceptsClick(
        mouseDown: CGPoint,
        mouseUp: CGPoint,
        sceneSize: CGSize
    ) -> Bool {
        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        let scale = min(
            sceneSize.width / PetSize.large.sceneSize.width,
            sceneSize.height / PetSize.large.sceneSize.height
        )
        let isInsideCore = hypot(mouseDown.x - center.x, mouseDown.y - center.y)
            <= coreDiameter * scale / 2
        let movement = hypot(mouseUp.x - mouseDown.x, mouseUp.y - mouseDown.y)
        return isInsideCore && movement <= maximumClickMovement
    }
}
