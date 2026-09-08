import Foundation

struct UpdateHandoff: Codable, Equatable {
    let sourceBuild: String
    let targetBuild: String
    let frame: CGRect?
    let isPetVisible: Bool

    var isValid: Bool {
        guard !sourceBuild.isEmpty, !targetBuild.isEmpty, sourceBuild != targetBuild else {
            return false
        }
        guard let frame else { return true }
        return [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    static var fileURL: URL {
        QuotaHistoryStore.defaultFileURL().deletingLastPathComponent()
            .appendingPathComponent("update-handoff.json")
    }

    func save(to url: URL = Self.fileURL) throws {
        guard isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = url
        try file.setResourceValues(values)
    }

    static func consume(for build: String, at url: URL = fileURL) -> Self? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Removal is part of consumption: a record that cannot be removed must not replay.
        guard (try? FileManager.default.removeItem(at: url)) != nil,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.isValid, value.targetBuild == build else { return nil }
        return value
    }

    static func clear(at url: URL = fileURL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// A deadline for termination preparation, not a second updater state machine.
@MainActor
final class UpdateTerminationGate {
    private(set) var isPrepared = false
    private var attempt = 0
    private var completions: [(Bool) -> Void] = []
    private var deadline: Task<Void, Never>?
    private var commit: () -> Bool = { true }

    func prepare(
        timeout: Duration = .seconds(10),
        operation: @escaping () async -> Bool,
        commit: @escaping () -> Bool = { true },
        completion: @escaping (Bool) -> Void
    ) {
        if isPrepared { completion(true); return }
        completions.append(completion)
        guard completions.count == 1 else { return }
        self.commit = commit
        attempt &+= 1
        let current = attempt
        // Never cancel accepted disk writes. The deadline replies independently of them.
        Task { [weak self] in
            let success = await operation()
            self?.finish(success, attempt: current)
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(false, attempt: current)
        }
    }

    func reset() {
        isPrepared = false
        if !completions.isEmpty { finish(false, attempt: attempt) }
        attempt &+= 1
    }

    private func finish(_ success: Bool, attempt current: Int) {
        guard current == attempt, !completions.isEmpty else { return }
        deadline?.cancel()
        deadline = nil
        let accepted = success && commit()
        isPrepared = accepted
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(accepted) }
    }
}
