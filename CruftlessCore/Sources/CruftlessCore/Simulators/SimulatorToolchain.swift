import Foundation

public struct SimulatorToolchain: Sendable, Hashable, Identifiable {
    public let id: String
    public let appURL: URL
    public let developerDirectory: URL
    public let version: String?

    public init(id: String, appURL: URL, developerDirectory: URL, version: String? = nil) {
        self.id = id
        self.appURL = appURL
        self.developerDirectory = developerDirectory
        self.version = version
    }
}

public enum SimulatorToolchainSource: String, Sendable, Hashable {
    case selected
    case discovered
    case userSelected
}

public enum SimulatorToolchainFailure: Sendable, Equatable, LocalizedError {
    case unavailable
    case ambiguous(candidateCount: Int)
    case invalidSelection
    case probeFailed
    case candidateLimitExceeded

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "No usable Xcode simulator tools were confirmed. Open Xcode to finish setup or accept its license, " +
                "then refresh in Settings."
        case let .ambiguous(count):
            "\(count) usable Xcode installations were found. Choose one in Settings before using simulator actions."
        case .invalidSelection:
            "The selected Xcode installation is no longer usable. Refresh toolchain status or choose another installation."
        case .probeFailed:
            "Xcode simulator tools could not be checked within the time limit. Try again from Settings."
        case .candidateLimitExceeded:
            "More Xcode installations were found than Cruftless can safely check at once. Choose one in Settings."
        }
    }
}

public enum SimulatorToolchainResolution: Sendable, Equatable {
    case ready(SimulatorToolchain, source: SimulatorToolchainSource, generation: UUID)
    case unavailable(SimulatorToolchainFailure)

    public var toolchain: SimulatorToolchain? {
        guard case let .ready(toolchain, _, _) = self else { return nil }
        return toolchain
    }

    public var generation: UUID? {
        guard case let .ready(_, _, generation) = self else { return nil }
        return generation
    }

    public var failure: SimulatorToolchainFailure? {
        guard case let .unavailable(failure) = self else { return nil }
        return failure
    }

    /// Whether dropping Cruftless's own Xcode choice would change this resolution.
    public var systemSelectionWouldChange: Bool {
        switch self {
        case let .ready(_, source, _): source == .userSelected
        case .unavailable: true
        }
    }
}

/// The outcome of checking one Xcode installation.
public enum SimulatorToolchainProbe: Sendable, Equatable {
    case usable(SimulatorToolchain)
    case unusable
    case timedOut

    public var toolchain: SimulatorToolchain? {
        guard case let .usable(toolchain) = self else { return nil }
        return toolchain
    }
}

/// Resolves only validated Xcode installations and coalesces concurrent probes.
///
/// A ready resolution is cached; a failed one is kept for display but probed again on the next `resolve()`.
public actor SimulatorToolchainResolver {
    public static let shared = SimulatorToolchainResolver(persistsSelection: true)
    public static let candidateLimit = 8
    static let probeTimeout: Duration = .seconds(2)
    static let runtimeListProbeTimeout: Duration = .seconds(6)
    private static let preferenceKey = "selectedSimulatorXcodePath"
    static let validationQueue = DispatchQueue(label: "com.danmunoz.cruftless.xcode-validation", qos: .utility)

    public typealias CandidateProvider = @Sendable () async -> [URL]
    public typealias SelectionProvider = @Sendable () async -> URL?
    public typealias CandidateValidator = @Sendable (URL) async -> SimulatorToolchain?
    public typealias CandidateProber = @Sendable (URL) async -> SimulatorToolchainProbe

    let candidates: CandidateProvider
    let refreshCandidates: CandidateProvider
    let selectedDirectory: SelectionProvider
    let prober: CandidateProber
    private var cached: SimulatorToolchainResolution?
    private var refreshTask: Task<SimulatorToolchainResolution, Never>?
    private var activeOperationGeneration: UUID?
    private var activeOperationCount = 0
    private var acquiringOperationGeneration: UUID?
    private var resolutionRevision: UInt64 = 0
    private var explicitChoice: URL?
    private let persistsSelection: Bool

    public init(
        candidates: CandidateProvider? = nil,
        refreshCandidates: CandidateProvider? = nil,
        selectedDirectory: SelectionProvider? = nil,
        validator: CandidateValidator? = nil,
        prober: CandidateProber? = nil,
        persistsSelection: Bool = false
    ) {
        let candidateProvider = candidates ?? { await XcodeInstallDiscovery.discover(refresh: false) }
        self.candidates = candidateProvider
        if let refreshCandidates {
            self.refreshCandidates = refreshCandidates
        } else if candidates != nil {
            self.refreshCandidates = candidateProvider
        } else {
            self.refreshCandidates = { await XcodeInstallDiscovery.discover(refresh: true) }
        }
        self.selectedDirectory = selectedDirectory ?? { await Self.readSelectedDirectory() }
        if let prober {
            self.prober = prober
        } else if let validator {
            self.prober = { await validator($0).map(SimulatorToolchainProbe.usable) ?? .unusable }
        } else {
            self.prober = { await Self.probe(candidate: $0) }
        }
        self.persistsSelection = persistsSelection
        explicitChoice = persistsSelection
            ? UserDefaults.standard.string(forKey: Self.preferenceKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            : nil
    }

    public func resolve(refresh: Bool = false) async -> SimulatorToolchainResolution {
        if acquiringOperationGeneration != nil, let cached { return cached }
        if activeOperationCount > 0, let cached { return cached }
        if !refresh, let cached, cached.toolchain != nil { return cached }
        if !refresh, let refreshTask { return await refreshTask.value }
        if refresh {
            refreshTask?.cancel()
            refreshTask = nil
            resolutionRevision &+= 1
        }
        let revision = resolutionRevision
        let task = Task { await self.performResolution(refresh: refresh) }
        refreshTask = task
        let result = await task.value
        guard revision == resolutionRevision,
              activeOperationCount == 0,
              acquiringOperationGeneration == nil
        else { return cached ?? result }
        cached = result
        refreshTask = nil
        return result
    }

    public func invalidate() {
        guard activeOperationCount == 0 else { return }
        cached = nil
    }

    public func cachedResolution() -> SimulatorToolchainResolution? {
        cached
    }

    public func discoverUsableCandidates(refresh: Bool = false) async -> [SimulatorToolchain] {
        let installations = await (refresh ? refreshCandidates : candidates)()
        let unique = Dictionary(grouping: installations, by: Self.canonicalPath).values
            .compactMap(\.first)
            .sorted { Self.canonicalPath($0) < Self.canonicalPath($1) }
        return await withTaskGroup(of: SimulatorToolchain?.self, returning: [SimulatorToolchain].self) { group in
            for installation in unique.prefix(Self.candidateLimit) {
                let prober = self.prober
                group.addTask { await prober(installation).toolchain }
            }
            var results: [SimulatorToolchain] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results.sorted { $0.id < $1.id }
        }
    }

    public func select(_ appURL: URL) async -> SimulatorToolchainResolution {
        guard activeOperationCount == 0, acquiringOperationGeneration == nil else {
            return cached ?? .unavailable(.invalidSelection)
        }
        resolutionRevision &+= 1
        let revision = resolutionRevision
        refreshTask?.cancel()
        refreshTask = nil
        guard let toolchain = await prober(appURL).toolchain,
              revision == resolutionRevision,
              activeOperationCount == 0,
              acquiringOperationGeneration == nil
        else {
            let result = SimulatorToolchainResolution.unavailable(.invalidSelection)
            if revision == resolutionRevision, activeOperationCount == 0, acquiringOperationGeneration == nil {
                cached = result
            }
            return result
        }
        explicitChoice = toolchain.appURL
        if persistsSelection {
            UserDefaults.standard.set(toolchain.appURL.path, forKey: Self.preferenceKey)
        }
        let result = SimulatorToolchainResolution.ready(toolchain, source: .userSelected, generation: UUID())
        cached = result
        return result
    }

    public func useSystemSelection() {
        guard activeOperationCount == 0, acquiringOperationGeneration == nil else { return }
        explicitChoice = nil
        if persistsSelection { UserDefaults.standard.removeObject(forKey: Self.preferenceKey) }
        resolutionRevision &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        cached = nil
    }

    public func beginOperation(generation: UUID) async -> Bool {
        if activeOperationCount > 0 {
            guard activeOperationGeneration == generation else { return false }
            activeOperationCount += 1
            return true
        }
        guard case let .ready(toolchain, _, currentGeneration) = cached,
              currentGeneration == generation
        else { return false }
        resolutionRevision &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        acquiringOperationGeneration = generation
        let validated = await prober(toolchain.appURL).toolchain
        guard acquiringOperationGeneration == generation,
              case let .ready(currentToolchain, _, stillCurrentGeneration) = cached,
              stillCurrentGeneration == generation,
              validated == currentToolchain
        else {
            acquiringOperationGeneration = nil
            return false
        }
        acquiringOperationGeneration = nil
        activeOperationGeneration = generation
        activeOperationCount = 1
        return true
    }

    public func endOperation(generation: UUID) {
        guard activeOperationGeneration == generation, activeOperationCount > 0 else { return }
        activeOperationCount -= 1
        if activeOperationCount == 0 { activeOperationGeneration = nil }
    }

    func performResolution(refresh: Bool) async -> SimulatorToolchainResolution {
        if let explicitChoice {
            switch await prober(explicitChoice) {
            case let .usable(selected): return .ready(selected, source: .userSelected, generation: UUID())
            case .timedOut: return .unavailable(.probeFailed)
            case .unusable: return .unavailable(.invalidSelection)
            }
        }
        var timedOut = false
        if let selected = await selectedDirectory() {
            switch await prober(selected) {
            case let .usable(toolchain): return .ready(toolchain, source: .selected, generation: UUID())
            case .timedOut: timedOut = true
            case .unusable: break
            }
        }
        return await resolveDiscovered(refresh: refresh, selectionTimedOut: timedOut)
    }

    private func resolveDiscovered(refresh: Bool, selectionTimedOut: Bool) async -> SimulatorToolchainResolution {
        let installations = await (refresh ? refreshCandidates : candidates)()
        var unique = Dictionary(grouping: installations, by: Self.canonicalPath).values.compactMap(\.first)
        unique.sort { Self.canonicalPath($0) < Self.canonicalPath($1) }
        guard unique.count <= Self.candidateLimit else {
            return .unavailable(.candidateLimitExceeded)
        }

        let probes = await withTaskGroup(of: SimulatorToolchainProbe.self, returning: [SimulatorToolchainProbe].self) { group in
            for candidate in unique {
                let prober = self.prober
                group.addTask { await prober(candidate) }
            }
            var values: [SimulatorToolchainProbe] = []
            for await value in group {
                values.append(value)
            }
            return values
        }
        let usable = probes.compactMap(\.toolchain).sorted { $0.id < $1.id }
        guard !usable.isEmpty else {
            return .unavailable(selectionTimedOut || probes.contains(.timedOut) ? .probeFailed : .unavailable)
        }
        guard usable.count == 1, let toolchain = usable.first else {
            return .unavailable(.ambiguous(candidateCount: usable.count))
        }
        return .ready(toolchain, source: .discovered, generation: UUID())
    }
}
