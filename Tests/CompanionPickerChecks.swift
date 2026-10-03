// No NSApplication, window, app launch, or real preference/network writes.
import AppKit
import ImageIO
import CryptoKit
import SwiftUI
@testable import Black_Hole_Codex_Quota_Indicator

private final class CompanionCheckServer: CodexAppServerClient {
    func start(onSnapshot: @escaping (QuotaSnapshot, Int?) -> Void, onSpeedMode: @escaping (SpeedMode) -> Void,
               onFailure: @escaping (String) -> Void) throws { fatalError("Checks must not connect") }
    func stop() {}
    func refreshRateLimits() { fatalError("Checks must not connect") }
}

@main
struct CompanionPickerChecks {
    @MainActor static func main() throws {
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--orbit-preview" {
            try renderOrbitPreview(path: CommandLine.arguments[2]); return
        }
        if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--preview" {
            try renderPreview(path: CommandLine.arguments[2]); return
        }
        try orbitChecks()
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--source-root" {
            try frozenAssetChecks(root: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
        let catalog = try AbsorbableObjectCatalog()
        let objects = catalog.manifest.objects
        assert(objects.count == 34 && Set(objects.map(\.id)).count == 34)
        assert(catalog.manifest.categories.map(\.id) == ["space", "animals", "characters"])
        let characters = objects.filter { $0.category == "characters" }
        assert(characters.map(\.companionName) == ["Даня", "Женя", "Расул", "Мила", "Настя", "Лиза К.", "Лёша Р.", "Денис", "Лиза П.", "Паша"])
        for invalid: Any in [32, true, [], ["id": "astronaut"], "", "removed-companion"] {
            assert(catalog.resolvedCompanionID(from: invalid) == nil)
            try withState(stored: invalid) { state, _ in assert(state.selectedCompanionID == nil) }
        }
        try withState { state, defaults in
            assert(state.selectedCompanionID == nil)
            let weights = state.absorptionCategoryWeights
            for object in objects {
                state.setSelectedCompanionID(object.id)
                assert(state.selectedCompanion?.id == object.id)
                assert(defaults.string(forKey: AppConstants.selectedCompanionIDKey) == object.id)
            }
            assert(state.absorptionCategoryWeights == weights)
            state.setSelectedCompanionID("character-glasses")
            let reloaded = makeState(defaults: defaults, catalog: catalog)
            assert(reloaded.selectedCompanionID == "character-glasses")
            state.setAbsorptionCategoryWeight(0, for: "characters")
            assert(state.selectedCompanionID == "character-glasses")
            var navigation = CompanionPickerNavigation(objects: objects, selectedID: state.selectedCompanionID)
            assert(navigation.categoryID == "characters" && navigation.columns == 3)
            assert(navigation.previewID == "character-glasses" && navigation.previewSize == 160)
            navigation.preview("character-botanical-shirt", objects: objects)
            assert(navigation.previewID == "character-botanical-shirt")
            assert(state.selectedCompanionID == "character-glasses")
            navigation.preview("unknown", objects: objects)
            assert(navigation.previewID == "character-botanical-shirt")
            for zoom in 0...2 {
                navigation.zoom = zoom
                assert(navigation.previewSize == [80, 120, 160][zoom])
                assert(state.selectedCompanionID == "character-glasses")
            }
            assert(navigation.movedID(from: characters[3].id, by: 3, objects: objects) == characters[6].id)
            assert(navigation.movedID(from: characters[3].id, by: -3, objects: objects) == characters[0].id)
            assert(navigation.movedID(from: characters[0].id, by: -1, objects: objects) == characters[0].id)
            assert(navigation.movedID(from: characters[8].id, by: 1, objects: objects) == characters[9].id)
            assert(navigation.movedID(from: characters[9].id, by: 1, objects: objects) == characters[9].id)
            assert(navigation.movedID(from: characters[6].id, by: 3, objects: objects) == characters[9].id)
            assert(navigation.movedID(from: characters[9].id, by: -3, objects: objects) == characters[6].id)
            for category in catalog.manifest.categories {
                navigation.showCategory(category.id, objects: objects, selectedID: state.selectedCompanionID)
                assert(navigation.categoryID == category.id)
                assert(navigation.columns == (category.id == "characters" ? 3 : 6))
                assert(state.selectedCompanionID == "character-glasses")
            }
            assert(navigation.previewID == "character-glasses")
            for style in TooltipStyle.allCases {
                state.setTooltipStyle(style)
                assert(state.selectedCompanionID == "character-glasses" && navigation.zoom == 2)
            }
            state.setSelectedCompanionID("character-charcoal-blazer")
            assert(makeState(defaults: defaults, catalog: catalog).selectedCompanion?.companionName == "Паша")
            navigation = CompanionPickerNavigation(objects: objects, selectedID: state.selectedCompanionID)
            navigation.zoom = 1
            for category in catalog.manifest.categories {
                navigation.showCategory(category.id, objects: objects, selectedID: state.selectedCompanionID)
                assert(state.selectedCompanionID == "character-charcoal-blazer" && navigation.zoom == 1)
            }
            assert(navigation.previewID == "character-charcoal-blazer" && navigation.columns == 3)
            state.setSelectedCompanionID(nil)
            assert(state.selectedCompanionID == nil && defaults.object(forKey: AppConstants.selectedCompanionIDKey) == nil)
            state.setSelectedCompanionID("unknown")
            assert(state.selectedCompanionID == nil)
        }
        let previews = CompanionPreview.load()
        assert(previews.count == objects.count && Set(previews.map(\.id)) == Set(objects.map(\.id)))
        for entry in previews {
            let url = Bundle.main.url(forResource: entry.source, withExtension: "webp", subdirectory: "CompanionPreviews")!
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            assert(CGFloat(image.width) == entry.sourceSize[0] && CGFloat(image.height) == entry.sourceSize[1])
            assert(entry.isValid)
            for size: CGFloat in [80, 120, 160] {
                assert(abs(max(entry.crop[2], entry.crop[3]) * entry.scale(for: size) - size) < 0.0001)
            }
        }
        for object in objects {
            let url = Bundle.main.url(forResource: object.asset, withExtension: "png", subdirectory: "objects")!
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            assert(image.width == 80 && image.height == 80)
            assert(!object.companionName.hasPrefix("companion."))
            if object.category == "characters" { assert(!object.companionDescription.hasPrefix("companion.")) }
        }
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -400, y: 20, width: 400, height: 420)] {
            for point in [CGPoint(x: screen.minX, y: screen.minY), CGPoint(x: screen.maxX, y: screen.maxY), CGPoint(x: screen.midX, y: screen.midY)] {
                let frame = PetPanelController.companionPickerFrame(anchor: point, visibleFrame: screen)
                assert(screen.contains(frame))
            }
        }
        for retry in [false, true] {
            let roots = PixelContextMenuNavigation.rootItems(requiresRetry: retry)
            let companion = roots.firstIndex(of: .companion)!
            assert(roots[companion - 1] == .objectMix && roots[companion + 1] == .behavior)
            assert(!PixelContextMenuItem.companion.isGroup)
        }
        print("PASS: 34 companions, ten names, invalid/default/reloaded preferences, independent weights, preview/category/zoom, fourth-row arrow boundaries, seven source sheets/crops, sprites, screen clamping and shared menu order")
    }

    @MainActor static func orbitChecks() throws {
        let size = PetSize.large.sceneSize
        let make: (Double) -> CompanionOrbitVisualState = {
            .make(elapsed: $0, sceneSize: size, reduceMotion: false)
        }
        assert(make(0).opacity == 0 && abs(make(0.175).opacity - 0.5) < 0.0001 && make(0.35).opacity == 1)
        assert(make(0).isBehindHole && !make(1).isBehindHole && make(3).isBehindHole)
        assert(make(0.6).position.y > make(0.5).position.y) // clockwise in the native downward-positive scene
        let full = make(1)
        let cycle = make(6)
        assert(abs(full.position.x - cycle.position.x) < 0.0001 && abs(full.position.y - cycle.position.y) < 0.0001)
        for petSize in PetSize.allCases {
            let scale = petSize.scale
            let bounds = CGRect(origin: .zero, size: petSize.sceneSize)
            for sample in 0...700 {
                let pose = CompanionOrbitVisualState.make(elapsed: Double(sample) / 70, sceneSize: petSize.sceneSize, reduceMotion: false)
                let radians = pose.tiltDegrees * .pi / 180
                let half = pose.canvasSize * pose.scale / 2 * (abs(cos(radians)) + abs(sin(radians)))
                let frame = CGRect(x: pose.position.x - half, y: pose.position.y - half, width: half * 2, height: half * 2)
                assert(bounds.contains(frame))
                assert(pose.canvasSize == 80 * scale && abs(pose.tiltDegrees) <= 5)
                if sample >= 25 { assert(pose.scale >= 0.88 && pose.scale <= 1) }
            }
            let still = CompanionOrbitVisualState.make(elapsed: 0, sceneSize: petSize.sceneSize, reduceMotion: true)
            let later = CompanionOrbitVisualState.make(elapsed: 999, sceneSize: petSize.sceneSize, reduceMotion: true)
            assert(still == later && still.opacity == 1 && still.tiltDegrees == 0 && !still.isBehindHole)
            assert(still.position == CGPoint(x: petSize.sceneSize.width / 2 + 130 * scale,
                                            y: petSize.sceneSize.height / 2 - 12 * scale))
        }
        for terminalAge in [0.0, 0.05, 0.1, 0.2, 0.34] {
            var previousOpacity = make(terminalAge).opacity
            for tick in 0...25 {
                let exitAge = Double(tick) / 100
                let pose = CompanionOrbitVisualState.make(elapsed: terminalAge + exitAge, sceneSize: size,
                    reduceMotion: false, disappearanceElapsed: exitAge)
                assert(pose.opacity <= previousOpacity + 0.000001, "Early exit must never brighten")
                previousOpacity = pose.opacity
            }
            assert(previousOpacity == 0)
        }
        let objects = try AbsorbableObjectCatalog().manifest.objects
        let first = objects.first { $0.id == "character-glasses" }!
        let second = objects.first { $0.id == "character-white-shirt" }!
        let start = Date(timeIntervalSince1970: 100)
        var presentation = CompanionOrbitPresentation()
        presentation.update(selection: first, activity: .unavailable, at: start, reduceMotion: false)
        assert(presentation.object == nil && !presentation.needsAnimation(reduceMotion: false))
        presentation.update(selection: first, activity: .waiting, at: start, reduceMotion: false)
        assert(presentation.object == nil) // an unobserved wait never invents work
        presentation.update(selection: nil, activity: .working, at: start, reduceMotion: false)
        assert(presentation.object == nil)
        presentation.update(selection: first, activity: .working, at: start, reduceMotion: false)
        assert(presentation.object == first && presentation.needsAnimation(reduceMotion: false))
        presentation.update(selection: first, activity: .working, at: start.addingTimeInterval(1), reduceMotion: false)
        assert(presentation.appearedAt == start) // unchanged aggregate work does not restart the orbit
        presentation.update(selection: first, activity: .waiting, at: start.addingTimeInterval(0.1), reduceMotion: false)
        assert(presentation.isAppearing && presentation.needsAnimation(reduceMotion: false))
        presentation.advance(at: start.addingTimeInterval(0.35))
        assert(!presentation.needsAnimation(reduceMotion: false))
        presentation.advance(at: start.addingTimeInterval(1))
        presentation.update(selection: first, activity: .waiting, at: start.addingTimeInterval(1), reduceMotion: false)
        assert(!presentation.needsAnimation(reduceMotion: false))
        let wait = presentation.visualState(at: start.addingTimeInterval(2), sceneSize: size, reduceMotion: false)
        assert(wait == presentation.visualState(at: start.addingTimeInterval(20), sceneSize: size, reduceMotion: false))
        presentation.update(selection: first, activity: .idle, at: start.addingTimeInterval(2), reduceMotion: false)
        assert(presentation.visualState(at: start.addingTimeInterval(2), sceneSize: size, reduceMotion: false)?.position == wait?.position)
        assert(abs(presentation.visualState(at: start.addingTimeInterval(2.125), sceneSize: size, reduceMotion: false)!.opacity - 0.5) < 0.0001)
        presentation.update(selection: first, activity: .idle, at: start.addingTimeInterval(2.2), reduceMotion: false)
        assert(presentation.disappearedAt == start.addingTimeInterval(2))
        presentation.advance(at: start.addingTimeInterval(2.25))
        assert(presentation.object == nil && !presentation.needsAnimation(reduceMotion: false))
        presentation.update(selection: first, activity: .working, at: start, reduceMotion: false)
        presentation.update(selection: second, activity: .working, at: start.addingTimeInterval(1), reduceMotion: false)
        assert(presentation.object == second && presentation.appearedAt == start.addingTimeInterval(1))
        presentation.update(selection: nil, activity: .working, at: start.addingTimeInterval(2), reduceMotion: false)
        assert(presentation.object == nil)
        presentation.update(selection: first, activity: .working, at: start, reduceMotion: true)
        assert(!presentation.needsAnimation(reduceMotion: true))
        presentation.update(selection: first, activity: .idle, at: start, reduceMotion: true)
        assert(presentation.object == nil)
        presentation.update(selection: first, activity: .working, at: start, reduceMotion: false)
        presentation.update(selection: first, activity: .unavailable, at: start, reduceMotion: false)
        assert(presentation.object == nil) // disconnect/unknown invalidates immediately; nothing is queued
        presentation.update(selection: first, activity: .working, at: start, reduceMotion: false)
        presentation.reset() // hide/sleep/disappear use the same local reset
        assert(presentation == CompanionOrbitPresentation())
        try withState { state, _ in
            state.setSelectedCompanionID(first.id)
            assert(state.companionActivity == .unavailable) // production is honestly unconnected
        }
        // Compare the inactive extracted scene with the original native aspect-fit image.
        let url = Bundle.main.url(forResource: "quota-50-frame-0", withExtension: "png", subdirectory: "frames")!
        let original = Image(nsImage: NSImage(contentsOf: url)!).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
        let extracted = PetSpriteScene(quotaSpriteName: "quota-50-frame-0", sceneSize: size)
        let originalPixels = try bitmapData(original)
        let extractedPixels = try bitmapData(extracted)
        assert(originalPixels == extractedPixels, "Inactive quota rendering changed")
        print("PASS: native orbit 5s/350ms/250ms, 2103 S/M/L bounds samples, clockwise/depth/layers, selection/clear, static wait/Reduce Motion, finite reset/expiry, inactive source, unchanged inactive quota pixels")
    }

    @MainActor static func renderOrbitPreview(path: String) throws {
        let object = try AbsorbableObjectCatalog().manifest.objects.first { $0.id == "character-glasses" }!
        let size = PetSize.large.sceneSize
        let samples: [(String, CompanionOrbitVisualState?)] = [
            ("Inactive", nil),
            ("Enter · 175 ms", .make(elapsed: 0.175, sceneSize: size, reduceMotion: false)),
            ("Near · 1.50 s", .make(elapsed: 1.5, sceneSize: size, reduceMotion: false)),
            ("Far · 4.03 s", .make(elapsed: 4.03, sceneSize: size, reduceMotion: false)),
            ("Exit · 125 ms", .make(elapsed: 5.6, sceneSize: size, reduceMotion: false, disappearanceElapsed: 0.125)),
            ("Exit · 250 ms", .make(elapsed: 5.75, sceneSize: size, reduceMotion: false, disappearanceElapsed: 0.25)),
            ("Waiting · static", .make(elapsed: 2, sceneSize: size, reduceMotion: false, waiting: true)),
            ("Reduce Motion · static", .make(elapsed: 2, sceneSize: size, reduceMotion: true))
        ]
        let view = VStack(spacing: 16) {
            ForEach(0..<4) { row in
                HStack(spacing: 16) {
                    ForEach(0..<2) { column in
                        let sample = samples[row * 2 + column]
                        VStack(spacing: 4) {
                            Text(sample.0).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                            PetSpriteScene(quotaSpriteName: "quota-50-frame-0", sceneSize: size,
                                           companion: object, companionState: sample.1)
                        }
                    }
                }
            }
        }.padding(20).background(Color(red: 0.035, green: 0.04, blue: 0.06))
        try bitmapData(view).write(to: URL(fileURLWithPath: path))
        print("Native orbit preview: \(path)")
    }

    @MainActor static func bitmapData<V: View>(_ view: V) throws -> Data {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func frozenAssetChecks(root: URL) throws {
        let html = try String(contentsOf: root.appendingPathComponent("docs/concepts/companion-picker-approved.html"), encoding: .utf8)
        let start = html.range(of: "<script type=\"application/json\" id=\"bh-companion-hq-data\">")!.upperBound
        let end = html.range(of: "</script>", range: start..<html.endIndex)!.lowerBound
        let frozen = try JSONSerialization.jsonObject(with: Data(html[start..<end].utf8)) as! [String: Any]
        let items = frozen["items"] as! [[String: Any]]
        let catalog = try AbsorbableObjectCatalog()
        assert(items.count == 33 && catalog.manifest.objects.count == 34)
        assert(items.compactMap { $0["id"] as? String } == catalog.manifest.objects.prefix(33).map(\.id))
        let metadataURL = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "CompanionPreviews")!
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [[String: Any]]
        assert(metadata.count == 34)
        for (index, object) in catalog.manifest.objects.prefix(33).enumerated() {
            let frozenItem = items[index]
            assert(frozenItem["category"] as? String == object.category)
            if object.category == "characters" { assert(frozenItem["name"] as? String == object.companionName) }
            let png = frozenItem["image"] as! String
            let original = Data(base64Encoded: String(png.split(separator: ",", maxSplits: 1)[1]))!
            let url = Bundle.main.url(forResource: object.asset, withExtension: "png", subdirectory: "objects")!
            let bundled = try Data(contentsOf: url)
            assert(original == bundled, "Game thumbnail pixels changed: \(object.id)")
            var expected = frozenItem["preview"] as! [String: Any]
            expected["id"] = object.id
            assert(NSDictionary(dictionary: expected).isEqual(to: metadata[index]))
        }
        let frozenSources = frozen["sources"] as! [String: String]
        assert(frozenSources.count == 6)
        for (name, encoded) in frozenSources {
            let original = Data(base64Encoded: String(encoded.split(separator: ",", maxSplits: 1)[1]))!
            let url = Bundle.main.url(forResource: name, withExtension: "webp", subdirectory: "CompanionPreviews")!
            let bundled = try Data(contentsOf: url)
            assert(original == bundled, "Original source sheet changed: \(name)")
        }
        let pasha = catalog.manifest.objects.last!
        assert(pasha.id == "character-charcoal-blazer" && pasha.category == "characters" && pasha.companionName == "Паша")
        func sha(_ url: URL) throws -> String {
            SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        let runtimeHash = try sha(Bundle.main.url(forResource: pasha.asset, withExtension: "png", subdirectory: "objects")!)
        let sourceHash = try sha(root.appendingPathComponent("docs/concepts/absorbable-person-10-v1.png"))
        let previewHash = try sha(Bundle.main.url(forResource: "person-10", withExtension: "webp", subdirectory: "CompanionPreviews")!)
        assert(runtimeHash == "132fbbdd9961b7623caeb5ca56a91f8c66250cfbac60851a64d425a724e1b8e6")
        assert(sourceHash == "277e48731972b13cd6e213ac95d288fb7bd407801a5d3a38c946a33b2a61cb11")
        assert(previewHash == "6c3a798e9becf10a201c228c17da54c285ed781d149f0e00535bd3be3b08ed1f")
        let added = metadata.last!
        assert(added["id"] as? String == pasha.id && added["source"] as? String == "person-10")
        assert(added["sourceSize"] as? [Int] == [1122, 1402])
        let crop = added["crop"] as! [Double]
        assert(zip(crop, [255.24, 182.485, 573.52, 994.03]).allSatisfy { abs($0.0 - $0.1) < 0.000_001 })
        print("PASS: frozen 33-item prefix/PNG bytes/crops and six HQ sheets unchanged; exactly one restored Паша with verified runtime/source/HQ hashes and crop")
    }

    @MainActor static func makeState(defaults: UserDefaults, catalog: AbsorbableObjectCatalog) -> AppState {
        AppState(defaults: defaults, appServer: CompanionCheckServer(), launchAtLoginStatusProvider: { .notRegistered },
                 updateLaunchAtLogin: { _ in fatalError("No real settings") }, absorptionCatalog: catalog)
    }

    @MainActor static func withState(stored: Any? = nil, _ body: (AppState, UserDefaults) throws -> Void) throws {
        let name = "local.black-hole.companion-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        if let stored { defaults.set(stored, forKey: AppConstants.selectedCompanionIDKey) }
        try body(makeState(defaults: defaults, catalog: AbsorbableObjectCatalog()), defaults)
    }

    @MainActor static func renderPreview(path: String) throws {
        var states: [AppState] = []
        var suites: [String] = []
        defer { for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) } }
        for id in ["character-glasses", "character-botanical-shirt", "character-charcoal-blazer"] {
            for style in [TooltipStyle.smooth, .pixel] {
                let suite = "local.black-hole.companion-preview.\(UUID().uuidString)"
                suites.append(suite)
                let state = makeState(defaults: UserDefaults(suiteName: suite)!, catalog: try AbsorbableObjectCatalog())
                state.setSelectedCompanionID(id)
                state.setTooltipStyle(style)
                states.append(state)
            }
        }
        let view = VStack(spacing: 16) {
            ForEach(0..<3) { row in
                HStack(spacing: 16) {
                    ForEach(0..<2) { column in
                        CompanionPickerView(appState: states[row * 2 + column])
                            .frame(width: CompanionPickerView.panelSize.width, height: CompanionPickerView.panelSize.height)
                    }
                }
            }
        }.padding(18).background(Color(white: 0.15))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        print("Preview: \(path)")
    }
}
