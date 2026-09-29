import Foundation

public struct BloatSubPath: Sendable, Hashable, Identifiable {
    public var id: String {
        relativePath
    }

    public let relativePath: String
    public let title: String
    public let allocatedBytes: Int64
    public let url: URL

    public init(relativePath: String, title: String, allocatedBytes: Int64, url: URL) {
        self.relativePath = relativePath
        self.title = title
        self.allocatedBytes = allocatedBytes
        self.url = url
    }
}

public enum KnownBloat: Sendable {
    public static let candidatePaths: [(relative: String, title: String)] = [
        ("Library/Application Support/PRBPosterExtensionDataStore", "Poster extension data store"),
        ("Library/Caches", "Caches"),
        ("tmp", "Temporary files")
    ]

    /// Scans a simulator device's `data/` directory for the `candidatePaths`.
    public static func scanBloat(for device: SimDevice, inodeSet: InodeSet) -> [BloatSubPath] {
        let dataDir = device.dataDirectory
        var results: [BloatSubPath] = []

        for candidate in candidatePaths {
            let targetURL = dataDir.appendingPathComponent(candidate.relative)
            let path = ProtectedPaths.normalize(targetURL)

            if FileManager.default.fileExists(atPath: path) {
                let sizeResult = DirectoryWalker.walk(url: targetURL, inodeSet: inodeSet)
                guard sizeResult.allocatedBytes > 0 else { continue }
                results.append(
                    BloatSubPath(
                        relativePath: candidate.relative,
                        title: candidate.title,
                        allocatedBytes: sizeResult.allocatedBytes,
                        url: targetURL
                    )
                )
            }
        }

        return results
    }

    /// Creates a deletion plan for known bloat inside a device.
    public static func createBloatDeletionPlan(
        for device: SimDevice,
        protectedPaths: ProtectedPaths = .default,
        policyGeneration: UInt64 = 0
    ) throws -> DeletionPlan {
        guard device.state.isShutdown else {
            throw DeletionPlanningError.simulatorNotShutdown(name: device.name)
        }

        let dataDir = device.dataDirectory
        guard FileManager.default.fileExists(atPath: dataDir.path(percentEncoded: false)) else {
            throw DeletionPlanningError.missingOnDisk(name: device.name)
        }

        let targets = try deletionTargets(for: device, protectedPaths: protectedPaths, dataDirectory: dataDir)

        // Nothing to clear is a refusal, not a "Clear Zero KB" plan.
        guard !targets.isEmpty else {
            throw DeletionPlanningError.nothingToPlan(title: device.name)
        }

        let totalSize = targets.reduce(0) { $0 + $1.reclaimableBytes }
        return DeletionPlan.plannedBatch(
            targets,
            confirmLabel: "Clear \(ByteFormatter.format(totalSize))",
            affectedLocationIds: [LocationCatalog.simulatorDevices.id],
            policyGeneration: policyGeneration
        )
    }

    private static func deletionTargets(
        for device: SimDevice,
        protectedPaths: ProtectedPaths,
        dataDirectory: URL
    ) throws -> [DeletionTarget] {
        let guardInstance = PathGuard(roots: [dataDirectory], protectedPaths: protectedPaths)
        let inodeSet = InodeSet()
        var targets: [DeletionTarget] = []
        for candidate in candidatePaths {
            let targetURL = dataDirectory.appendingPathComponent(candidate.relative)
            guard FileManager.default.fileExists(atPath: ProtectedPaths.normalize(targetURL)) else { continue }
            let name = "\(device.name) · \(candidate.title)"
            let validatedPath: ValidatedPath
            do {
                validatedPath = try guardInstance.validate(targetURL)
            } catch let error as PathGuardError {
                throw DeletionPlanningError.refused(name: name, error: error)
            }
            guard let fingerprint = Fingerprint.capture(at: targetURL) else {
                throw DeletionPlanningError.missingOnDisk(name: name)
            }
            let size = DirectoryWalker.walk(url: targetURL, inodeSet: inodeSet).allocatedBytes
            targets.append(.path(
                id: "bloat-\(device.udid)-\(candidate.relative)",
                name: name,
                validatedPath: validatedPath,
                fingerprint: fingerprint,
                tier: .regen,
                consequence: "Removes cached simulator system data. The simulator regenerates it when needed.",
                reclaimableBytes: size,
                precondition: .simulatorShutdown(
                    devicePlist: device.deviceDirectory.appendingPathComponent("device.plist"),
                    deviceName: device.name
                )
            ))
        }
        return targets
    }
}
