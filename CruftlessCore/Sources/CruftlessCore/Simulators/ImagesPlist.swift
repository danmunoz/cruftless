import Foundation

/// Decodes installed runtime images from `/Library/Developer/CoreSimulator/Images/images.plist`.
public enum ImagesPlist: Sendable {
    public static let defaultPath = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Images/images.plist")

    public static func load(from url: URL = defaultPath) -> [SimRuntime]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data, imagesDirectory: url.deletingLastPathComponent())
    }

    /// - Parameter imagesDirectory: the directory `images.plist` lives in.
    public static func parse(
        data: Data,
        imagesDirectory: URL = defaultPath.deletingLastPathComponent()
    ) -> [SimRuntime]? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]]
        else {
            return nil
        }

        var runtimes: [SimRuntime] = []

        for image in images {
            guard let runtimeInfo = image["runtimeInfo"] as? [String: Any],
                  let bundleId = runtimeInfo["bundleIdentifier"] as? String
            else {
                continue
            }

            let build = runtimeInfo["build"] as? String ?? ""

            var size: Int64 = 0
            if let pathDict = image["path"] as? [String: Any],
               let relStr = pathDict["relative"] as? String {
                size = imageFileSize(of: relStr, relativeTo: imagesDirectory)
            }

            let friendlyName = Naming.runtime(identifier: bundleId, build: build)

            runtimes.append(
                SimRuntime(
                    identifier: bundleId,
                    runtimeIdentifier: bundleId,
                    name: friendlyName,
                    build: build,
                    sizeBytes: size,
                    isDeletable: true
                )
            )
        }

        return runtimes
    }

    /// Resolves a `path.relative` value to a filesystem `URL`.
    private static func resolveImagePath(_ relative: String, relativeTo imagesDirectory: URL) -> URL? {
        if relative.hasPrefix("file://") {
            // `.path` percent-decodes, so `iOS%2027.0.simruntime` lands as the spaced name that is actually on disk.
            return URL(string: relative)
        }
        if relative.hasPrefix("/") {
            return URL(fileURLWithPath: relative)
        }
        return URL(fileURLWithPath: relative, relativeTo: imagesDirectory)
    }

    /// Sizes the image the plist names, in APFS allocated bytes.
    private static func imageFileSize(of relative: String, relativeTo imagesDirectory: URL) -> Int64 {
        guard let fileURL = resolveImagePath(relative, relativeTo: imagesDirectory) else { return 0 }
        var statBuf = stat()
        guard lstat(fileURL.path, &statBuf) == 0 else { return 0 }
        return Int64(statBuf.st_blocks) * 512
    }
}
