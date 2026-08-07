import Foundation

enum QuotaHistoryBoundary: String, Codable, Equatable, Sendable {
    case baseline
    case continuous
    case reset
    case gap
}

enum QuotaHistoryIssue: Equatable, Sendable {
    case restarted
    case notSaved

    var localizationKey: String {
        switch self {
        case .restarted: "history.issue.restarted"
        case .notSaved: "history.issue.not_saved"
        }
    }
}

struct QuotaHistoryIdentity: Codable, Equatable, Sendable {
    let limitId: String?
    let limitName: String?
    let planType: String?

    init(snapshot: QuotaSnapshot) {
        limitId = snapshot.limitId
        limitName = snapshot.limitName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        planType = snapshot.planType
    }

    func conflicts(with other: Self) -> Bool {
        Self.conflicts(limitId, other.limitId)
            || Self.conflicts(limitName, other.limitName)
            || Self.conflicts(planType, other.planType)
    }

    private static func conflicts(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs != rhs
    }
}

struct QuotaHistoryWindow: Codable, Equatable, Sendable {
    let remainingPercent: Int
    let windowDurationMinutes: Int64?
    let resetsAt: Int64?

    init(_ window: QuotaWindow) {
        remainingPercent = window.remainingPercent
        windowDurationMinutes = window.windowDurationMins
        resetsAt = window.resetsAt
    }
}

struct QuotaHistorySample: Codable, Equatable, Sendable {
    let observedAt: Date
    let identity: QuotaHistoryIdentity
    let primary: QuotaHistoryWindow?
    let secondary: QuotaHistoryWindow?
    var primaryBoundary: QuotaHistoryBoundary
    var secondaryBoundary: QuotaHistoryBoundary

    init(
        snapshot: QuotaSnapshot,
        observedAt: Date,
        primaryBoundary: QuotaHistoryBoundary = .baseline,
        secondaryBoundary: QuotaHistoryBoundary = .baseline
    ) {
        self.observedAt = observedAt
        identity = QuotaHistoryIdentity(snapshot: snapshot)
        primary = snapshot.primary.map(QuotaHistoryWindow.init)
        secondary = snapshot.secondary.map(QuotaHistoryWindow.init)
        self.primaryBoundary = primaryBoundary
        self.secondaryBoundary = secondaryBoundary
    }

    func hasSamePayload(as other: Self) -> Bool {
        identity == other.identity
            && primary == other.primary
            && secondary == other.secondary
    }
}

enum QuotaHistoryClassifier {
    static let maximumComparableGap: TimeInterval = 90 * 60

    static func boundary(
        previousSample: QuotaHistorySample,
        currentSample: QuotaHistorySample,
        previousWindow: QuotaHistoryWindow?,
        currentWindow: QuotaHistoryWindow?,
        forceGap: Bool
    ) -> QuotaHistoryBoundary {
        guard let previousWindow, let currentWindow else { return .gap }
        let elapsed = currentSample.observedAt.timeIntervalSince(previousSample.observedAt)
        guard !forceGap,
              elapsed > 0,
              elapsed <= maximumComparableGap,
              !previousSample.identity.conflicts(with: currentSample.identity) else {
            return .gap
        }

        if let previousReset = previousWindow.resetsAt,
           let currentReset = currentWindow.resetsAt,
           previousReset != currentReset,
           previousWindow.windowDurationMinutes == currentWindow.windowDurationMinutes {
            let previousResetDate = Date(
                timeIntervalSince1970: TimeInterval(previousReset)
            )
            let currentResetDate = Date(
                timeIntervalSince1970: TimeInterval(currentReset)
            )
            if previousResetDate > previousSample.observedAt,
               previousResetDate <= currentSample.observedAt,
               currentResetDate > currentSample.observedAt {
                return .reset
            }
        }

        guard let previousReset = previousWindow.resetsAt,
              previousReset == currentWindow.resetsAt,
              previousWindow.windowDurationMinutes
                == currentWindow.windowDurationMinutes,
              currentWindow.remainingPercent <= previousWindow.remainingPercent else {
            return .gap
        }
        return .continuous
    }
}

struct QuotaHistoryPoint: Equatable, Sendable {
    let observedAt: Date
    let remainingPercent: Int
    let boundaryBefore: QuotaHistoryBoundary
}

struct QuotaHistoryPresentation: Equatable, Sendable {
    static let rangeDuration: TimeInterval = 24 * 60 * 60
    static let maximumRenderPoints = 240

    let points: [QuotaHistoryPoint]
    let rangeStart: Date
    let rangeEnd: Date
    let startPercent: Int?
    let endPercent: Int?
    let observedDuration: TimeInterval?
    let currentUnavailable: Bool
    let containsReset: Bool
    let containsGap: Bool

    static func empty(now: Date = Date()) -> Self {
        Self(
            points: [],
            rangeStart: now.addingTimeInterval(-rangeDuration),
            rangeEnd: now,
            startPercent: nil,
            endPercent: nil,
            observedDuration: nil,
            currentUnavailable: false,
            containsReset: false,
            containsGap: false
        )
    }

    static func make(samples: [QuotaHistorySample], now: Date) -> Self {
        let rangeStart = now.addingTimeInterval(-rangeDuration)
        let recent = samples.filter {
            $0.observedAt >= rangeStart && $0.observedAt <= now
        }
        let currentUnavailable = samples.last.map { $0.primary == nil } ?? false

        var allPoints = recent.compactMap { sample -> QuotaHistoryPoint? in
            guard let primary = sample.primary else { return nil }
            return QuotaHistoryPoint(
                observedAt: sample.observedAt,
                remainingPercent: primary.remainingPercent,
                boundaryBefore: sample.primaryBoundary
            )
        }
        if !allPoints.isEmpty {
            allPoints[0] = QuotaHistoryPoint(
                observedAt: allPoints[0].observedAt,
                remainingPercent: allPoints[0].remainingPercent,
                boundaryBefore: .baseline
            )
        }

        let comparable = comparablePrimarySegment(in: recent, currentUnavailable: currentUnavailable)
        return Self(
            points: decimated(allPoints),
            rangeStart: rangeStart,
            rangeEnd: now,
            startPercent: comparable.first?.primary?.remainingPercent,
            endPercent: comparable.last?.primary?.remainingPercent,
            observedDuration: comparable.count >= 2
                ? comparable.last!.observedAt.timeIntervalSince(comparable.first!.observedAt)
                : nil,
            currentUnavailable: currentUnavailable,
            containsReset: allPoints.contains { $0.boundaryBefore == .reset },
            containsGap: allPoints.contains { $0.boundaryBefore == .gap }
        )
    }

    var hasComparableChange: Bool {
        startPercent != nil && endPercent != nil && observedDuration != nil
    }

    func endpointText(locale: Locale) -> String {
        if currentUnavailable {
            return NSLocalizedString(
                "history.current_unavailable",
                comment: "Current quota unavailable in local history"
            )
        }
        guard let startPercent, let endPercent, observedDuration != nil else {
            return NSLocalizedString(
                "history.collecting",
                comment: "Local quota history is collecting"
            )
        }
        if startPercent == endPercent {
            return String(
                format: NSLocalizedString(
                    "history.unchanged.format",
                    comment: "Unchanged observed quota percentage"
                ),
                locale: locale,
                endPercent
            )
        }
        return String(
            format: NSLocalizedString(
                "history.endpoint.format",
                comment: "Observed quota start and end percentages"
            ),
            locale: locale,
            startPercent,
            endPercent
        )
    }

    func durationText(locale: Locale, compact: Bool) -> String? {
        guard let observedDuration else { return nil }
        let duration = max(60, observedDuration)
        if compact {
            let usesHours = duration >= 3_600
            let value = usesHours
                ? max(1, Int(duration / 3_600))
                : max(1, Int(duration / 60))
            return String(
                format: NSLocalizedString(
                    usesHours
                        ? "history.duration.hours.compact"
                        : "history.duration.minutes.compact",
                    comment: "Compact observed history duration"
                ),
                locale: locale,
                value
            )
        }

        let formatter = DateComponentsFormatter()
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = duration >= 3_600 ? [.hour] : [.minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        guard let localizedDuration = formatter.string(from: duration) else { return nil }
        return String(
            format: NSLocalizedString(
                "history.duration.observed",
                comment: "Duration covered by observed local history"
            ),
            locale: locale,
            localizedDuration
        )
    }

    func compactSummary(locale: Locale) -> String {
        let endpoint = endpointText(locale: locale)
        guard let duration = durationText(locale: locale, compact: true),
              hasComparableChange else {
            return endpoint
        }
        return String(
            format: NSLocalizedString(
                "history.compact.format",
                comment: "Compact endpoint and duration history summary"
            ),
            locale: locale,
            endpoint,
            duration
        )
    }

    func accessibilitySummary(locale: Locale) -> String {
        var details = [endpointText(locale: locale)]
        if let duration = durationText(locale: locale, compact: false), hasComparableChange {
            details.append(duration)
        }
        if containsReset {
            details.append(
                NSLocalizedString(
                    "history.accessibility.reset",
                    comment: "Accessible observed reset boundary"
                )
            )
        }
        if containsGap {
            details.append(
                NSLocalizedString(
                    "history.accessibility.gap",
                    comment: "Accessible observed continuity gap"
                )
            )
        }
        return details.joined(separator: ", ")
    }

    private static func comparablePrimarySegment(
        in samples: [QuotaHistorySample],
        currentUnavailable: Bool
    ) -> [QuotaHistorySample] {
        guard !currentUnavailable,
              let lastIndex = samples.lastIndex(where: { $0.primary != nil }) else {
            return []
        }

        var firstIndex = lastIndex
        while firstIndex > samples.startIndex {
            guard samples[firstIndex].primaryBoundary == .continuous,
                  samples[samples.index(before: firstIndex)].primary != nil else {
                break
            }
            firstIndex = samples.index(before: firstIndex)
        }
        return Array(samples[firstIndex...lastIndex])
    }

    private static func decimated(_ points: [QuotaHistoryPoint]) -> [QuotaHistoryPoint] {
        guard points.count > maximumRenderPoints else { return points }

        var important = Set([0, points.count - 1])
        for index in points.indices where points[index].boundaryBefore != .continuous {
            important.insert(index)
            if index > 0 { important.insert(index - 1) }
        }

        if important.count < maximumRenderPoints {
            let remainingCapacity = maximumRenderPoints - important.count
            let candidates = points.indices.filter { !important.contains($0) }
            let step = max(1, Int(ceil(Double(candidates.count) / Double(remainingCapacity))))
            for index in candidates.enumerated() where index.offset % step == 0 {
                important.insert(index.element)
                if important.count == maximumRenderPoints { break }
            }
        }

        let sorted = important.sorted()
        if sorted.count <= maximumRenderPoints {
            return sorted.map { points[$0] }
        }

        let step = Double(sorted.count - 1) / Double(maximumRenderPoints - 1)
        return (0..<maximumRenderPoints).map { offset in
            points[sorted[Int((Double(offset) * step).rounded())]]
        }
    }
}

struct QuotaHistoryStoreUpdate: Sendable {
    let presentation: QuotaHistoryPresentation
    let issue: QuotaHistoryIssue?
    let sampleCount: Int
    let revision: Int
}

actor QuotaHistoryStore {
    static let formatVersion = 1
    static let retention: TimeInterval = 30 * 24 * 60 * 60
    static let heartbeatInterval: TimeInterval = 60 * 60
    static let maximumSampleCount = 2_000

    private struct Document: Codable {
        let formatVersion: Int
        var samples: [QuotaHistorySample]
    }

    private let fileURL: URL?
    private var samples: [QuotaHistorySample] = []
    private var isLoaded = false
    private var writesDisabled = false
    private var issue: QuotaHistoryIssue?
    private var revision = 0
    private var cachedPresentation: QuotaHistoryPresentation?

    init(fileURL: URL? = QuotaHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directoryName = Bundle.main.bundleIdentifier ?? AppConstants.displayName
        return root
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("quota-history-v1.json")
    }

    func load(at now: Date) -> QuotaHistoryStoreUpdate {
        ensureLoaded(at: now)
        return update(at: now)
    }

    func record(
        snapshot: QuotaSnapshot,
        at observedAt: Date,
        forceGap: Bool
    ) -> QuotaHistoryStoreUpdate {
        ensureLoaded(at: observedAt)
        var current = QuotaHistorySample(snapshot: snapshot, observedAt: observedAt)

        if let previous = samples.last {
            let elapsed = observedAt.timeIntervalSince(previous.observedAt)
            let needsHeartbeat = elapsed >= Self.heartbeatInterval
            let clockMovedBackward = elapsed <= 0
            guard !current.hasSamePayload(as: previous)
                    || forceGap
                    || needsHeartbeat
                    || clockMovedBackward else {
                return update(at: observedAt)
            }

            current.primaryBoundary = QuotaHistoryClassifier.boundary(
                previousSample: previous,
                currentSample: current,
                previousWindow: previous.primary,
                currentWindow: current.primary,
                forceGap: forceGap
            )
            current.secondaryBoundary = QuotaHistoryClassifier.boundary(
                previousSample: previous,
                currentSample: current,
                previousWindow: previous.secondary,
                currentWindow: current.secondary,
                forceGap: forceGap
            )
        }

        samples.append(current)
        prune(at: observedAt)
        revision &+= 1
        cachedPresentation = nil
        persist()
        return update(at: observedAt)
    }

    func clear(at now: Date) -> QuotaHistoryStoreUpdate {
        ensureLoaded(at: now)
        do {
            if let fileURL {
                let directory = fileURL.deletingLastPathComponent()
                if FileManager.default.fileExists(atPath: directory.path) {
                    let quarantinePrefix = fileURL.deletingPathExtension().lastPathComponent
                        + ".corrupt-"
                    let candidates = try FileManager.default.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: nil
                    ).filter {
                        $0 == fileURL || $0.lastPathComponent.hasPrefix(quarantinePrefix)
                    }
                    for candidate in candidates {
                        try FileManager.default.removeItem(at: candidate)
                    }
                }
            }
            samples = []
            issue = nil
            writesDisabled = false
            revision &+= 1
            cachedPresentation = nil
        } catch {
            issue = .notSaved
        }
        return update(at: now)
    }

    func storedSamples() -> [QuotaHistorySample] {
        samples
    }

    private func ensureLoaded(at now: Date) {
        guard !isLoaded else { return }
        isLoaded = true
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return }
            let document = try Self.decoder.decode(Document.self, from: data)
            guard document.formatVersion == Self.formatVersion else {
                throw HistoryFileError.unsupportedVersion
            }
            samples = document.samples
            let oldCount = samples.count
            prune(at: now)
            if samples.count != oldCount { persist() }
        } catch {
            quarantine(fileURL, at: now)
        }
    }

    private func quarantine(_ source: URL, at now: Date) {
        let destination = source.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(now.timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            samples = []
            issue = .restarted
        } catch {
            samples = []
            issue = .notSaved
            writesDisabled = true
        }
    }

    private func prune(at now: Date) {
        samples.removeAll { now.timeIntervalSince($0.observedAt) > Self.retention }
        if samples.count > Self.maximumSampleCount {
            samples.removeFirst(samples.count - Self.maximumSampleCount)
        }
        if !samples.isEmpty {
            samples[0].primaryBoundary = .baseline
            samples[0].secondaryBoundary = .baseline
        }
    }

    private func persist() {
        guard let fileURL, !writesDisabled else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )

            let data = try Self.encoder.encode(
                Document(formatVersion: Self.formatVersion, samples: samples)
            )
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(directoryValues)
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try mutableFileURL.setResourceValues(fileValues)
            if issue == .notSaved { issue = nil }
        } catch {
            issue = .notSaved
        }
    }

    private func update(at now: Date) -> QuotaHistoryStoreUpdate {
        if cachedPresentation == nil {
            cachedPresentation = QuotaHistoryPresentation.make(samples: samples, now: now)
        }
        return QuotaHistoryStoreUpdate(
            presentation: cachedPresentation!,
            issue: issue,
            sampleCount: samples.count,
            revision: revision
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private enum HistoryFileError: Error {
        case unsupportedVersion
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
