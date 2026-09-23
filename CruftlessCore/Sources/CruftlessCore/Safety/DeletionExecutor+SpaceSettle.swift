import Darwin
import Foundation

extension DeletionExecutor {
    /// Maximum polling attempts for mutation confirmation.
    static let mutationConfirmationAttempts = 15
    /// Maximum allocated bytes that confirm a simulator erase.
    static let eraseConfirmationThresholdBytes: Int64 = 64_000_000

    /// Reports deletion progress.
    func report(_ progress: DeletionProgress) {
        onProgress?(progress)
    }

    private func deviceDirectory(for udid: String) -> URL? {
        deviceDirectoryProvider(udid)
    }

    private static func pathExists(_ url: URL) -> Bool {
        var statBuffer = stat()
        return lstat(PathNormalizer.normalize(url.path(percentEncoded: false)), &statBuffer) == 0
    }

    /// Confirms an erase when the device directory falls below the threshold.
    func confirmEraseLanded(udid: String) async -> Bool {
        guard let directory = deviceDirectory(for: udid) else { return false }
        for _ in 0 ..< Self.mutationConfirmationAttempts {
            let bytes = await Self.offCooperativePool {
                DirectoryWalker.walk(url: directory, inodeSet: InodeSet()).allocatedBytes
            }
            if bytes <= Self.eraseConfirmationThresholdBytes {
                return true
            }
            try? await settleSleep()
        }
        return false
    }

    /// Confirms deletion when the device directory disappears.
    func confirmDeviceGone(udid: String) async -> Bool {
        guard let directory = deviceDirectory(for: udid) else { return false }
        for _ in 0 ..< Self.mutationConfirmationAttempts {
            let gone = await Self.offCooperativePool { !Self.pathExists(directory) }
            if gone {
                return true
            }
            try? await settleSleep()
        }
        return false
    }

    /// Waits until free space settles or the detector caps.
    func waitForSpaceToSettle(
        verb: DeletionProgress.Verb,
        targetName: String,
        expectedBytes: Int64,
        baselineFreeBytes: Int64
    ) async -> SpaceSettleOutcome {
        report(DeletionProgress(verb: verb, targetName: targetName, phase: .waitingForSpace))
        var detector = SpaceSettleDetector(
            expectedBytes: expectedBytes,
            baselineFreeBytes: baselineFreeBytes
        )
        while true {
            let freeBytes = await capacitySampler()
            switch detector.observe(freeBytes: freeBytes) {
            case .settled: return .settled
            case .capped: return .capped
            case .keepWaiting: break
            }
            do {
                try await settleSleep()
            } catch {
                // Treats interruption as a capped wait.
                return .capped
            }
        }
    }
}
