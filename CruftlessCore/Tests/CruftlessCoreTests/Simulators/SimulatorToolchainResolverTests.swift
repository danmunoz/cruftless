@testable import CruftlessCore
import Foundation
import Testing

@Suite("Simulator toolchain resolution and leases")
struct SimulatorToolchainResolverTests {
    private static let first = fixture("Stable")
    private static let second = fixture("Beta")

    private static func fixture(_ name: String) -> SimulatorToolchain {
        let app = URL(fileURLWithPath: "/Applications/Fixture-\(name).app", isDirectory: true)
        return SimulatorToolchain(
            id: app.path,
            appURL: app,
            developerDirectory: app.appendingPathComponent("Contents/Developer", isDirectory: true),
            version: "27.0"
        )
    }

    @Test("Selected full Xcode wins without discovery")
    func selectedWins() async {
        let count = ToolchainProbeCounter()
        let selected = Self.first
        let resolver = SimulatorToolchainResolver(
            candidates: { await count.increment()
                return [Self.second.appURL]
            },
            selectedDirectory: { selected.appURL },
            validator: { $0 == selected.appURL ? selected : Self.second }
        )
        let result = await resolver.resolve()
        #expect(result.toolchain == selected)
        if case let .ready(_, source, _) = result {
            #expect(source == .selected)
        } else { Issue.record("Expected selected toolchain") }
        #expect(await count.value == 0)
    }

    @Test("Command Line Tools selection falls back to one usable Xcode")
    func commandLineToolsFallback() async {
        let valid = Self.first
        let commandLineTools = URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
        let resolver = SimulatorToolchainResolver(
            candidates: { [valid.appURL] },
            selectedDirectory: { commandLineTools },
            validator: { $0 == valid.appURL ? valid : nil }
        )
        let result = await resolver.resolve()
        #expect(result.toolchain == valid)
        if case let .ready(_, source, _) = result {
            #expect(source == .discovered)
        } else { Issue.record("Expected discovered toolchain") }
    }

    @Test("Unavailable installations do not become usable candidates")
    func unavailableCandidates() async {
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.first.appURL] }, selectedDirectory: { nil }, validator: { _ in nil }
        )
        #expect(await resolver.resolve().failure == .unavailable)
    }

    @Test("Multiple usable installations require explicit selection")
    func ambiguousSelection() async {
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.first.appURL, Self.second.appURL] },
            selectedDirectory: { nil },
            validator: { $0 == Self.first.appURL ? Self.first : Self.second }
        )
        #expect(await resolver.resolve().failure == .ambiguous(candidateCount: 2))
        let selected = await resolver.select(Self.second.appURL)
        #expect(selected.toolchain == Self.second)
        #expect(await resolver.resolve(refresh: true).toolchain == Self.second)
    }

    @Test("Duplicate discovery results do not produce ambiguity")
    func duplicateCandidates() async {
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.first.appURL, Self.first.appURL] },
            selectedDirectory: { nil }, validator: { _ in Self.first }
        )
        #expect(await resolver.resolve().toolchain == Self.first)
    }

    @Test("Truncated candidate discovery fails closed")
    func excessiveCandidates() async {
        let count = ToolchainProbeCounter()
        let urls = (0 ... SimulatorToolchainResolver.candidateLimit).map { Self.fixture("\($0)").appURL }
        let resolver = SimulatorToolchainResolver(
            candidates: { urls }, selectedDirectory: { nil },
            validator: { _ in await count.increment()
                return Self.first
            }
        )
        #expect(await resolver.resolve().failure == .candidateLimitExceeded)
        #expect(await count.value == 0)
    }

    @Test("Concurrent callers share the same resolution generation")
    func concurrentResolution() async {
        let count = ToolchainProbeCounter()
        let gate = ToolchainValidationGate()
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.first.appURL] }, selectedDirectory: { nil },
            validator: { _ in await count.increment()
                await gate.wait()
                return Self.first
            }
        )
        async let first = resolver.resolve()
        await gate.waitUntilEntered()
        async let second = resolver.resolve()
        await gate.release()
        let results = await (first, second)
        #expect(results.0.generation == results.1.generation)
        #expect(await count.value == 1)
    }

    @Test("A refreshed listing invalidates an older review")
    func staleGeneration() async throws {
        let resolver = Self.simpleResolver()
        let first = try #require(await resolver.resolve().generation)
        let refreshed = try #require(await resolver.resolve(refresh: true).generation)
        #expect(first != refreshed)
        #expect(await resolver.beginOperation(generation: first) == false)
        #expect(await resolver.beginOperation(generation: refreshed))
        await resolver.endOperation(generation: refreshed)
    }

    @Test("Removed tooling prevents the operation from starting")
    func removedToolchain() async throws {
        let registry = ToolchainValidationRegistry(toolchain: Self.first)
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.first.appURL] }, selectedDirectory: { nil },
            validator: { _ in await registry.current }
        )
        let generation = try #require(await resolver.resolve().generation)
        await registry.remove()
        #expect(await resolver.beginOperation(generation: generation) == false)
    }

    @Test("Refresh and selection cannot redirect an acquired operation")
    func operationPinsSelection() async throws {
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.first.appURL] }, selectedDirectory: { nil },
            validator: { $0 == Self.first.appURL ? Self.first : Self.second }
        )
        let resolution = await resolver.resolve()
        let generation = try #require(resolution.generation)
        #expect(await resolver.beginOperation(generation: generation))
        #expect(await resolver.select(Self.second.appURL).toolchain == Self.first)
        #expect(await resolver.resolve(refresh: true).generation == generation)
        await resolver.endOperation(generation: generation)
        #expect(await resolver.select(Self.second.appURL).toolchain == Self.second)
    }

    @Test("A selection already validating cannot replace an acquired operation")
    func inFlightSelectionCannotRedirectOperation() async throws {
        let gate = ToolchainValidationGate()
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.first.appURL] }, selectedDirectory: { nil },
            validator: { candidate in
                if candidate == Self.second.appURL { await gate.wait()
                    return Self.second
                }
                return Self.first
            }
        )
        let generation = try #require(await resolver.resolve().generation)
        async let selection = resolver.select(Self.second.appURL)
        await gate.waitUntilEntered()
        #expect(await resolver.beginOperation(generation: generation))
        await gate.release()
        _ = await selection
        #expect(await resolver.resolve().toolchain == Self.first)
        #expect(await resolver.resolve().generation == generation)
        await resolver.endOperation(generation: generation)
    }

    @Test("Explicit invalid selection is refused instead of falling back silently")
    func invalidExplicitSelection() async {
        let resolver = Self.simpleResolver()
        #expect(await resolver.resolve().toolchain == Self.first)
        #expect(await resolver.select(Self.second.appURL).failure == .invalidSelection)
    }

    @Test("Only the validated developer directory enters child environments")
    func validatedEnvironment() {
        let environment = DefaultSimctlExecutor.childEnvironment(
            from: ["DEVELOPER_DIR": "/private/attacker", "TOOLCHAINS": "private-toolchain", "SECRET_TOKEN": "private-token"],
            developerDirectory: Self.first.developerDirectory
        )
        #expect(environment["DEVELOPER_DIR"] == Self.first.developerDirectory.path)
        #expect(environment["TOOLCHAINS"] == nil)
        #expect(environment["SECRET_TOKEN"] == nil)
    }

    @Test("Resolved identity and generation accompany actual subprocess results")
    func executorCarriesAuthority() async throws {
        let resolver = Self.simpleResolver()
        let resolution = await resolver.resolve()
        let executor = DefaultSimctlExecutor(
            timeout: .seconds(2), executableURL: URL(fileURLWithPath: "/usr/bin/printenv"),
            argumentPrefix: [], toolchainResolver: resolver
        )
        let output = try await executor.run(arguments: ["DEVELOPER_DIR"])
        #expect(output.status == 0)
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == Self.first.developerDirectory.path)
        #expect(output.toolchainID == Self.first.id)
        #expect(output.toolchainGeneration == resolution.generation)
    }

    @Test("Bundle inspection rejects spoofed identity and missing simulator executable")
    func invalidBundleMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toolchain-inspect-\(UUID().uuidString).app")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let info = contents.appendingPathComponent("Info.plist")
        let invalid = ["CFBundleIdentifier": "private.spoofed.Xcode"]
        let invalidData = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
        try invalidData.write(to: info)
        #expect(await SimulatorToolchainResolver.inspect(candidate: root)?.appURL == nil)
        let valid = ["CFBundleIdentifier": "com.apple.dt.Xcode"]
        let validData = try PropertyListSerialization.data(fromPropertyList: valid, format: .xml, options: 0)
        try validData.write(to: info)
        #expect(await SimulatorToolchainResolver.inspect(candidate: root)?.appURL == nil)
    }

    @Test("Installed Xcode resolves when Command Line Tools are selected", .enabled(
        if: ProcessInfo.processInfo.environment["CRUFTLESS_LIVE_TOOLCHAIN_CHECK"] == "1"
    ))
    func installedXcodeReadOnlyProbe() async throws {
        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app", isDirectory: true)
        let resolver = SimulatorToolchainResolver(
            candidates: { [xcode] },
            selectedDirectory: { URL(fileURLWithPath: "/Library/Developer/CommandLineTools", isDirectory: true) }
        )
        let result = await resolver.resolve()
        #expect(result.toolchain?.appURL == xcode)
        let executor = DefaultSimctlExecutor(
            timeout: .seconds(10),
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            argumentPrefix: ["simctl"],
            toolchainResolver: resolver
        )
        let output = try await executor.run(arguments: ["runtime", "list", "-j"])
        #expect(output.status == 0)
        #expect(output.toolchainGeneration == result.generation)
    }

    private static func simpleResolver() -> SimulatorToolchainResolver {
        SimulatorToolchainResolver(
            candidates: { [first.appURL] }, selectedDirectory: { nil },
            validator: { $0 == first.appURL ? first : nil }
        )
    }
}

extension SimulatorToolchainResolverTests {
    @Test("An unusable explicit choice can be cleared to recover the system selection")
    func resetUnavailableExplicitChoice() async throws {
        let registry = ToolchainValidationRegistry(toolchain: Self.first)
        let resolver = SimulatorToolchainResolver(
            candidates: { [Self.second.appURL] }, selectedDirectory: { Self.second.appURL },
            validator: { candidate in
                if candidate == Self.first.appURL { return await registry.current }
                return candidate == Self.second.appURL ? Self.second : nil
            }
        )
        let chosen = try #require(await resolver.select(Self.first.appURL).generation)
        await registry.remove()
        #expect(await resolver.resolve(refresh: true).failure == .invalidSelection)
        #expect(await resolver.beginOperation(generation: chosen) == false)
        await resolver.useSystemSelection()
        let recovered = await resolver.resolve()
        #expect(recovered.toolchain == Self.second)
        #expect(recovered.generation != chosen)
    }
}

private actor ToolchainProbeCounter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}

private actor ToolchainValidationRegistry {
    private(set) var current: SimulatorToolchain?
    init(toolchain: SimulatorToolchain) {
        current = toolchain
    }

    func remove() {
        current = nil
    }
}

private actor ToolchainValidationGate {
    private var entered = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        observer?.resume()
        observer = nil
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
