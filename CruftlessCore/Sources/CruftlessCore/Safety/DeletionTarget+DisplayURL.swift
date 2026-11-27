import Foundation

public extension DeletionTarget {
    /// The folder this target removes or mutates, shown in Review; `nil` for a runtime in the root-owned store.
    var displayURL: URL? {
        displayURL(simulatorDevicesRoot: RootResolver.simulatorDevicesRoot().first)
    }

    /// Resolves simulator device folders against `simulatorDevicesRoot`.
    func displayURL(simulatorDevicesRoot: URL?) -> URL? {
        switch self {
        case let .path(_, _, validatedPath, _, _, _, _, _):
            validatedPath.url
        case let .simulatorErase(udid, _, _, _, _), let .simulatorDelete(udid, _, _, _, _):
            simulatorDevicesRoot?.appendingPathComponent(udid, isDirectory: true)
        case let .xctestSimulatorDelete(_, _, deviceDirectory, _, _, _, _, _):
            deviceDirectory
        case let .androidSDKPackageDelete(request):
            request.identity.directory
        case let .androidAVDDelete(request):
            request.identity.directory
        case .runtimeDelete:
            nil
        }
    }
}
