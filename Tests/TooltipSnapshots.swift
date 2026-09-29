// Standalone offscreen tool, deliberately not a member of the hosted XCTest target.
// Run through script/tooltip_snapshots.sh. No AppDelegate or NSApplication entrypoint.
import AppKit
import CryptoKit
import SwiftUI
@testable import Black_Hole_Codex_Quota_Indicator

private struct SnapshotError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private final class SnapshotServer: CodexAppServerClient {
    var snapshot: ((QuotaSnapshot, Int?) -> Void)?
    var mode: ((SpeedMode) -> Void)?
    var failure: ((String) -> Void)?
    func start(onSnapshot: @escaping (QuotaSnapshot, Int?) -> Void,
               onSpeedMode: @escaping (SpeedMode) -> Void,
               onFailure: @escaping (String) -> Void) throws {
        snapshot = onSnapshot; mode = onSpeedMode; failure = onFailure
    }
    func refreshRateLimits() {}
    func stop() { snapshot = nil; mode = nil; failure = nil }
}

private struct Fixture {
    let id: String
    let source: CodexResetSourceState
    let credits: Int?
    var remaining: Int? = 77
    var mode: SpeedMode = .standard
    var disconnected = false
    var resetOffset: TimeInterval? = 345_600
}

private struct Card: Codable {
    let file: String
    let fixture: String
    let width: Int
    let height: Int
    let pixelSHA256: String
    let personalTitle: String
    let announcementTitles: [String]
    let announcementDetails: [String]
    let accessibility: String
}

private struct Manifest: Codable {
    let environment: [String: String]
    let cards: [Card]
}

@main
private struct TooltipSnapshots {
    static let fileManager = FileManager.default
    static let now = Date(timeIntervalSince1970: 1_790_676_000) // 2026-09-29 10:00 UTC
    static let scale: CGFloat = 2

    @MainActor
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 4 else { throw SnapshotError("Expected mode output language-or-baseline") }
            let output = URL(fileURLWithPath: arguments[2]).standardizedFileURL
            switch arguments[1] {
            case "render": try await render(language: arguments[3], output: output)
            case "check", "record":
                try compareOrRecord(mode: arguments[1], output: output,
                                    baseline: URL(fileURLWithPath: arguments[3]).standardizedFileURL)
            default: throw SnapshotError("Unknown mode")
            }
        } catch {
            FileHandle.standardError.write(Data("Snapshot failure: \(error)\n".utf8))
            exit(1)
        }
    }

    static var fixtures: [Fixture] {
        func available(_ signals: [CodexResetSignal]) -> CodexResetSourceState {
            .available(signals: signals, checkedAt: now)
        }
        let today = CodexResetSignal.scheduled(resetType: .regular, scheduledFor: now.addingTimeInterval(3_600), id: "next")
        let tomorrow = CodexResetSignal.scheduled(resetType: .regular, scheduledFor: now.addingTimeInterval(86_400), id: "next")
        let past = CodexResetSignal.scheduled(resetType: .regular, scheduledFor: now.addingTimeInterval(-3_600), id: "next")
        let latest = CodexResetSignal.completed(resetType: .banked, announcedAt: now.addingTimeInterval(-600), id: "last")
        let watch = CodexResetSignal.watch(chancePercent: 60, expiresAt: now.addingTimeInterval(3_600))
        return [
            Fixture(id: "01-disabled-unknown", source: .disabled, credits: nil),
            Fixture(id: "02-disabled-one", source: .disabled, credits: 1),
            Fixture(id: "03-loading-zero", source: .loading, credits: 0),
            Fixture(id: "04-empty-several", source: available([]), credits: 3),
            Fixture(id: "05-error-several", source: .unavailable, credits: 3),
            Fixture(id: "06-watch-60-zero", source: available([watch]), credits: 0),
            Fixture(id: "07-watch-unknown-turbo", source: available([.watch(chancePercent: nil, expiresAt: now.addingTimeInterval(3_600))]), credits: nil, mode: .turbo),
            Fixture(id: "08-scheduled-today-turbo", source: available([today]), credits: 3, mode: .turbo),
            Fixture(id: "09-scheduled-tomorrow", source: available([tomorrow]), credits: 3),
            Fixture(id: "10-scheduled-undated-zero", source: available([.scheduled(resetType: .regular, scheduledFor: nil, id: "next")]), credits: 0),
            Fixture(id: "11-scheduled-past", source: available([past]), credits: 3),
            Fixture(id: "12-banked-future-one", source: available([.scheduled(resetType: .banked, scheduledFor: now.addingTimeInterval(3_600), id: "next")]), credits: 1),
            Fixture(id: "13-banked-undated-99", source: available([.scheduled(resetType: .banked, scheduledFor: nil, id: "next")]), credits: 99),
            Fixture(id: "14-completed-regular", source: available([.completed(resetType: .regular, announcedAt: now.addingTimeInterval(-600), id: "last")]), credits: 1),
            Fixture(id: "15-completed-banked", source: available([latest]), credits: 3),
            Fixture(id: "16-scheduled-and-latest", source: available([tomorrow, latest]), credits: 3),
            Fixture(id: "17-watch-and-latest-zero", source: available([watch, latest]), credits: 0),
            Fixture(id: "18-deduplicated", source: available([.scheduled(resetType: .banked, scheduledFor: nil, id: "last"), latest]), credits: 3),
            Fixture(id: "19-latest-expired", source: available([.completed(resetType: .banked, announcedAt: now.addingTimeInterval(-86_400), id: "old")]), credits: 0),
            Fixture(id: "20-watch-expired", source: available([.watch(chancePercent: 60, expiresAt: now)]), credits: 1),
            Fixture(id: "21-count-100-turbo", source: .disabled, credits: 100, mode: .turbo),
            Fixture(id: "22-count-maximum", source: .disabled, credits: .max),
            Fixture(id: "23-disconnected-cached", source: available([tomorrow, latest]), credits: 3, mode: .turbo, disconnected: true),
            Fixture(id: "24-quota-unavailable", source: .unavailable, credits: nil, remaining: nil),
            Fixture(id: "25-zero-quota-turbo", source: available([]), credits: 3, remaining: 0, mode: .turbo),
            Fixture(id: "26-critical-quota", source: .disabled, credits: 1, remaining: 5),
            Fixture(id: "27-warning-quota", source: available([today]), credits: 3, remaining: 23),
            Fixture(id: "28-reset-date-unavailable", source: .disabled, credits: 3, resetOffset: nil),
            Fixture(id: "29-past-and-completed-banked", source: available([past, latest]), credits: 3),
            Fixture(id: "30-next-year", source: available([.scheduled(resetType: .regular, scheduledFor: now.addingTimeInterval(380 * 86_400), id: "next-year")]), credits: 3, resetOffset: 380 * 86_400),
            Fixture(id: "31-completion-in-future", source: available([.completed(resetType: .regular, announcedAt: now.addingTimeInterval(600), id: "future")]), credits: 0),
            Fixture(id: "32-unknown-personal-turbo", source: .disabled, credits: nil, mode: .turbo)
        ]
    }

    @MainActor
    static func waitFor(_ label: String, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw SnapshotError("Fixture timeout: \(label)") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor
    static func render(language: String, output: URL) async throws {
        guard ["en", "ru"].contains(language) else { throw SnapshotError("Language must be en or ru") }
        let locale = Locale(identifier: language == "en" ? "en_US" : "ru_RU")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let expectedSource = language == "en" ? "ANNOUNCEMENTS · CODEX RESETS" : "ОБЪЯВЛЕНИЯ · CODEX RESETS"
        guard NSLocalizedString("reset_info.source", comment: "") == expectedSource else {
            throw SnapshotError("Main bundle is not localized to \(language); use the wrapper's per-process language flags")
        }
        var cards: [Card] = []
        for style in [TooltipStyle.smooth, .pixel] {
            for size in [PetSize.small, .medium, .large] {
                for history in [false, true] {
                    let group = "\(language)-\(style.rawValue)-\(size.label.lowercased())-history-\(history ? "on" : "off")"
                    var tiles: [(String, CGImage)] = []
                    for fixture in fixtures {
                        let (card, image) = try await renderCard(fixture, group: group, size: size, style: style,
                                                               history: history, locale: locale, calendar: calendar, output: output)
                        cards.append(card)
                        tiles.append((fixture.id, image))
                    }
                    try writePNG(contactSheet(title: group, tiles: tiles), to: output.appendingPathComponent("overview/\(group).png"))
                    print("Rendered \(group): \(tiles.count) cards")
                }
            }
        }
        let manifest = Manifest(environment: environment(), cards: cards)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: output.appendingPathComponent("manifest-\(language).json"), options: .atomic)
        print("\(language): \(cards.count) card PNGs; references unchanged")
    }

    @MainActor
    static func renderCard(_ fixture: Fixture, group: String, size: PetSize, style: TooltipStyle,
                           history: Bool, locale: Locale, calendar: Calendar, output: URL) async throws -> (Card, CGImage) {
        let defaults = UserDefaults(suiteName: "local.black-hole.snapshots.\(UUID().uuidString)")!
        defaults.register(defaults: [AppConstants.petSizeKey: size.rawValue,
                                    AppConstants.tooltipStyleKey: style.rawValue,
                                    AppConstants.showQuotaDynamicsKey: history,
                                    AppConstants.showCodexResetForecastKey: fixture.source != .disabled])
        let server = SnapshotServer()
        var observed = now
        let state = AppState(defaults: defaults, appServer: server, retryDelays: [3_600],
                             launchAtLoginStatusProvider: { .notRegistered }, updateLaunchAtLogin: { _ in },
                             now: { observed }, historyStore: QuotaHistoryStore(fileURL: nil), absorptionCatalog: nil,
                             fetchCodexResetStatus: { _ in
            switch fixture.source {
            case .disabled: throw SnapshotError("Unexpected request from disabled fixture")
            case .loading: try await Task.sleep(for: .seconds(3_600)); throw CancellationError()
            case .unavailable: throw URLError(.timedOut)
            case let .available(signals, _): return .updated(signals: signals, eTag: nil, maxAge: 86_400)
            }
        })
        state.start()
        defer { state.stop() }
        let expectedSource: CodexResetSourceState = fixture.id == "20-watch-expired" ? .unavailable : fixture.source
        try await waitFor(fixture.id + " source") { state.codexResetSourceState == expectedSource }
        server.mode?(fixture.mode)
        for (index, remaining) in [Int?(91), Int?(84), fixture.remaining].enumerated() {
            observed = now.addingTimeInterval(TimeInterval(index - 2) * 3_600)
            server.snapshot?(QuotaSnapshot(limitId: "codex", limitName: nil, planType: "pro",
                                          primary: remaining.map { QuotaWindow(usedPercent: 100 - $0, windowDurationMins: 10_080,
                                                                              resetsAt: fixture.resetOffset.map { Int64(now.addingTimeInterval($0).timeIntervalSince1970) }) },
                                          secondary: nil), fixture.credits)
            try await waitFor(fixture.id + " quota") { state.connectionState == .connected && state.quota?.primary?.remainingPercent == remaining }
            guard await state.drainHistoryForTermination() else { throw SnapshotError("In-memory history did not drain") }
        }
        try await waitFor(fixture.id + " mode") { state.speedMode == fixture.mode }
        if fixture.disconnected {
            server.failure?("Fixture disconnect")
            try await waitFor(fixture.id + " disconnect") { state.connectionState == .reconnecting && state.resetCreditsAvailableCount == nil }
        }
        guard state.resetCreditsAvailableCount == (fixture.disconnected ? nil : fixture.credits) else {
            throw SnapshotError("Personal count mismatch")
        }
        let content = QuotaTooltipContent(remainingPercent: state.quota?.primary?.remainingPercent, speedMode: state.speedMode,
                                         connectionState: state.connectionState, resetDate: state.quota?.primary?.resetDate,
                                         windowDurationMinutes: state.quota?.primary?.windowDurationMins, now: now,
                                         locale: locale, calendar: calendar, history: state.quotaHistory,
                                         showsQuotaDynamics: history, codexResetSourceState: state.codexResetSourceState,
                                         resetCreditsAvailableCount: state.resetCreditsAvailableCount)
        let view = QuotaTooltipView(appState: state, placement: .below, isTooltipPresented: false, now: { now })
            .environment(\.locale, locale).environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true }
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.colorMode = .nonLinear
        // Pin the raster target instead of accepting cgImage's implicit format.
        // Its early renders can differ by one quantization step between processes.
        var rendered: CGImage?
        renderer.render(rasterizationScale: scale) { size, draw in
            guard let context = CGContext(data: nil, width: Int(ceil(size.width * scale)),
                                          height: Int(ceil(size.height * scale)), bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: scale, y: scale)
            draw(context)
            rendered = context.makeImage()
        }
        guard let image = rendered else { throw SnapshotError("ImageRenderer produced no image") }
        let file = "cards/\(group)/\(fixture.id).png"
        try writePNG(image, to: output.appendingPathComponent(file))
        return (Card(file: file, fixture: fixture.id, width: image.width, height: image.height,
                     pixelSHA256: try pixelHash(Self.image(at: output.appendingPathComponent(file))), personalTitle: content.personalResetHeader?.text ?? "",
                     announcementTitles: content.resetAnnouncements.map(\.title),
                     announcementDetails: content.resetAnnouncements.map(\.detail), accessibility: content.accessibilitySummary), image)
    }

    static func pixelHash(_ image: CGImage) throws -> String {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw SnapshotError("Could not normalize image pixels")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw SnapshotError("Could not encode PNG")
        }
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    static func contactSheet(title: String, tiles: [(String, CGImage)]) throws -> CGImage {
        let columns = 4
        let cellWidth = Int(ceil(CGFloat(tiles.map { $0.1.width }.max()!) / scale)) + 24
        let cellHeight = Int(ceil(CGFloat(tiles.map { $0.1.height }.max()!) / scale)) + 42
        let width = columns * cellWidth
        let height = 42 + ((tiles.count + columns - 1) / columns) * cellHeight
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw SnapshotError("Contact sheet context failed") }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        (title as NSString).draw(at: NSPoint(x: 12, y: CGFloat(height - 28)), withAttributes: attributes)
        for (index, tile) in tiles.enumerated() {
            let x = 12 + (index % columns) * cellWidth
            let top = height - 42 - (index / columns) * cellHeight
            (tile.0 as NSString).draw(at: NSPoint(x: CGFloat(x), y: CGFloat(top - 16)), withAttributes: attributes)
            let size = NSSize(width: CGFloat(tile.1.width) / scale, height: CGFloat(tile.1.height) / scale)
            NSImage(cgImage: tile.1, size: size).draw(in: NSRect(x: CGFloat(x), y: CGFloat(top - 24) - size.height,
                                                              width: size.width, height: size.height))
        }
        guard let image = bitmap.cgImage else { throw SnapshotError("Contact sheet image failed") }
        return image
    }

    @MainActor
    static func environment() -> [String: String] {
        ["format": "2", "os": ProcessInfo.processInfo.operatingSystemVersionString,
         "swift": ProcessInfo.processInfo.environment["BH_SNAPSHOT_SWIFT_VERSION"] ?? "unknown",
         "sdk": ProcessInfo.processInfo.environment["BH_SNAPSHOT_SDK_VERSION"] ?? "unknown",
         "architecture": MemoryLayout<Int>.size == 8 ? architecture : "unsupported",
         "scale": "2", "rasterTarget": "ImageRenderer.render; sRGB RGBA8",
         "timezone": "UTC", "calendar": "gregorian", "appearance": "dark",
         "dynamicType": "large", "clock": String(now.timeIntervalSince1970),
         "animations": "hidden-tooltip; transaction-disablesAnimations",
         "systemFont": NSFont.systemFont(ofSize: 12).fontName,
         "monospaceFont": NSFont.monospacedSystemFont(ofSize: 11, weight: .medium).fontName]
    }

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    static func image(at url: URL) throws -> CGImage {
        guard let representation = NSBitmapImageRep(data: try Data(contentsOf: url)), let image = representation.cgImage else {
            throw SnapshotError("Missing/invalid PNG: \(url.path)")
        }
        return image
    }

    static func validate(_ card: Card, in directory: URL) throws {
        guard card.file.hasPrefix("cards/"), !card.file.contains("..") else { throw SnapshotError("Unsafe manifest path") }
        let value = try image(at: directory.appendingPathComponent(card.file))
        guard value.width == card.width, value.height == card.height, try pixelHash(value) == card.pixelSHA256 else {
            throw SnapshotError("PNG does not match its manifest: \(card.file)")
        }
    }

    static func compareOrRecord(mode: String, output: URL, baseline: URL) throws {
        guard output != baseline, !output.path.hasPrefix(baseline.path + "/"), !baseline.path.hasPrefix(output.path + "/") else {
            throw SnapshotError("Output and reference directories must be disjoint")
        }
        var total = 0
        var differences: [String] = []
        var reviewed: [(String, Data, Manifest)] = []
        for language in ["en", "ru"] {
            let name = "manifest-\(language).json"
            let data = try Data(contentsOf: output.appendingPathComponent(name))
            let current = try JSONDecoder().decode(Manifest.self, from: data)
            guard current.cards.count == fixtures.count * 12, Set(current.cards.map(\.file)).count == current.cards.count else {
                throw SnapshotError("Incomplete or duplicate card matrix")
            }
            try current.cards.forEach { try validate($0, in: output) }
            if mode == "record" {
                reviewed.append((name, data, current))
            } else {
                let reference = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: baseline.appendingPathComponent(name)))
                guard Set(reference.cards.map(\.file)).count == reference.cards.count else { throw SnapshotError("Duplicate reference card paths") }
                guard current.environment == reference.environment else {
                    throw SnapshotError("Render environment differs from reference (OS/SDK/Swift/fonts/settings). Review explicitly; nothing was recorded")
                }
                let expected = Dictionary(uniqueKeysWithValues: reference.cards.map { ($0.file, $0) })
                guard Set(expected.keys) == Set(current.cards.map(\.file)) else { throw SnapshotError("Reference card set differs; no files were changed") }
                for card in current.cards {
                    let old = expected[card.file]!
                    try validate(old, in: baseline)
                    if card.width != old.width || card.height != old.height || card.pixelSHA256 != old.pixelSHA256 {
                        differences.append(card.file)
                    }
                }
            }
            total += current.cards.count
        }
        guard differences.isEmpty else { throw SnapshotError("\(differences.count) changed cards:\n" + differences.joined(separator: "\n")) }
        // Validate the entire reviewed matrix before changing any references.
        // Only record reaches this branch; check never writes into the baseline.
        for (name, data, current) in reviewed {
            for card in current.cards {
                let destination = baseline.appendingPathComponent(card.file)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: output.appendingPathComponent(card.file)).write(to: destination, options: .atomic)
            }
            try data.write(to: baseline.appendingPathComponent(name), options: .atomic)
        }
        print(mode == "record" ? "Recorded \(total) explicitly reviewed references at \(baseline.path)" : "PASS: \(total) cards match decoded RGBA pixels; references unchanged")
    }
}
