import Foundation
import Synchronization

/// Finds installed `Xcode.app` bundles.
public enum XcodeInstallDiscovery: Sendable {
    /// How long Spotlight gets before the child is terminated and the fallback is used instead.
    static let spotlightTimeout: Duration = .seconds(15)

    private static let mdfind = URL(fileURLWithPath: "/usr/bin/mdfind")
    private static let query = "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'"
    private static let defaultInstall = URL(fileURLWithPath: "/Applications/Xcode.app", isDirectory: true)

    private struct State {
        var cached: [URL]?
        var inFlight: Task<[URL], Never>?
    }

    private static let state = Mutex(State())

    /// The installs discovered so far.
    public static func knownInstalls() -> [URL] {
        state.withLock { $0.cached } ?? filesystemFallback()
    }

    /// Runs Spotlight discovery once and caches the result for the life of the process.
    @discardableResult
    public static func discover() async -> [URL] {
        let task: Task<[URL], Never> = state.withLock { current in
            if let cached = current.cached {
                return Task { cached }
            }
            if let inFlight = current.inFlight {
                return inFlight
            }
            let started = Task { await runSpotlight() }
            current.inFlight = started
            return started
        }
        let found = await task.value
        state.withLock { current in
            current.cached = found
            current.inFlight = nil
        }
        return found
    }

    private static func runSpotlight() async -> [URL] {
        var found: [URL] = []
        do {
            let output = try await BoundedProcess.run(
                executable: mdfind,
                arguments: [query],
                environment: BoundedProcess.minimalEnvironment(),
                timeout: spotlightTimeout
            )
            if output.status == 0 {
                found = parse(output.stdout)
            }
        } catch {
            // Spotlight is disabled, wedged, or absent.
        }
        return found.isEmpty ? filesystemFallback() : found
    }

    /// One absolute `.app` path per line; anything else Spotlight prints (warnings, blank lines, relative noise) is dropped.
    static func parse(_ output: String) -> [URL] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("/"), trimmed.hasSuffix(".app") else { return nil }
            return URL(fileURLWithPath: trimmed, isDirectory: true)
        }
    }

    static func filesystemFallback() -> [URL] {
        FileManager.default.fileExists(atPath: defaultInstall.path(percentEncoded: false)) ? [defaultInstall] : []
    }
}
