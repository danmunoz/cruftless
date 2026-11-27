import Darwin
import Foundation

/// An installed SDK package whose folder, metadata and layout agree, captured for `android sdk remove`.
public struct AndroidSDKPackageRemovalIdentity: Sendable, Hashable {
    /// The `Pkg.Path` identity, in the semicolon form `package.xml` uses.
    public let packagePath: String
    public let directory: URL
    public let sdkRoot: URL
    let directoryFingerprint: Fingerprint
    let packageXMLFingerprint: Fingerprint

    /// The slash form the CLI's `sdk remove` and `sdk list` print.
    public var cliName: String {
        packagePath.replacingOccurrences(of: ";", with: "/")
    }

    public var category: String {
        String(packagePath.prefix { $0 != ";" })
    }

    public static func capture(child: ChildEntry, sdkRoot: URL, protectedPaths: ProtectedPaths) throws -> Self {
        let directory = child.url
        guard child.id.hasPrefix(LocationCatalog.androidSDK.id + "-"),
              child.id == LocationCatalog.androidSDK.id + "-" + ProtectedPaths.normalize(directory),
              ProtectedPaths.standardize(sdkRoot) == ProtectedPaths.normalize(sdkRoot),
              ProtectedPaths.standardize(directory) == ProtectedPaths.normalize(directory),
              let packagePath = RootResolver.sdkPackagePath(for: directory, sdkRoot: sdkRoot),
              protectedPaths.allowsAndroidSDKPackage(directory, under: sdkRoot)
        else { throw AndroidAVDRemovalError.refused("This package's location is unsupported or protected.") }
        let packageXML = directory.appendingPathComponent("package.xml")
        try verifyOwnedSameVolume([(sdkRoot, true), (directory, true), (packageXML, false)])
        let metadata = AndroidSDKMetadataReader.read(directory: directory, root: sdkRoot)
        guard metadata.diagnostic == nil, metadata.package?.packagePath == packagePath else {
            throw AndroidAVDRemovalError.refused(
                "This package's metadata does not match its folder, so Android tools could remove a different one."
            )
        }
        guard let directoryFingerprint = Fingerprint.capture(at: directory),
              let packageXMLFingerprint = Fingerprint.capture(at: packageXML)
        else { throw AndroidAVDRemovalError.refused("This package's files could not be verified. Rescan and try again.") }
        return Self(packagePath: packagePath, directory: directory, sdkRoot: sdkRoot,
                    directoryFingerprint: directoryFingerprint, packageXMLFingerprint: packageXMLFingerprint)
    }

    func revalidate(protectedPaths: ProtectedPaths) throws {
        let child = ChildEntry(id: LocationCatalog.androidSDK.id + "-" + ProtectedPaths.normalize(directory),
                               name: packagePath, url: directory, reclaimableBytes: 0,
                               staleness: StalenessInfo(lastUsedDate: nil), tier: .info, consequence: "")
        let current = try Self.capture(child: child, sdkRoot: sdkRoot, protectedPaths: protectedPaths)
        guard current.packagePath == packagePath,
              directoryFingerprint.verify(at: directory) == .valid,
              packageXMLFingerprint.verify(at: directory.appendingPathComponent("package.xml")) == .valid
        else { throw AndroidAVDRemovalError.refused("The package changed after Review. Rescan and review it again.") }
    }

    /// What losing this package costs, written for Review.
    public var consequence: String {
        let version = packagePath.split(separator: ";").last.map(String.init) ?? packagePath
        let index = " Android tools also keep a small package index in the SDK's .sdk folder."
        let text = switch category {
        case "platform-tools":
            "adb and fastboot. Android Studio and Gradle cannot install or debug apps until you reinstall it."
        case "emulator":
            "The Android Emulator. No virtual device can start until you reinstall it."
        case "cmdline-tools":
            "sdkmanager and avdmanager. Scripts and CI jobs that call them stop working."
        case "build-tools":
            "Build tools \(version). A project pinned to this version downloads it again on its next build."
        case "platforms":
            "The \(version) platform. Projects that compile against it download it again on their next build."
        case "system-images":
            "A system image no virtual device uses. A new device on this image downloads it again."
        case "ndk", "cmake":
            "\(category.uppercased()) \(version). Native builds pinned to this version download it again."
        case "sources":
            "Framework sources for \(version). Android Studio stops showing them while you debug."
        default:
            "An installed SDK add-on. Projects that depend on it download it again."
        }
        return text + index
    }

    private static func verifyOwnedSameVolume(_ files: [(URL, Bool)]) throws {
        var rootDevice: dev_t?
        for (url, isDirectory) in files {
            var metadata = stat()
            guard lstat(url.path(percentEncoded: false), &metadata) == 0,
                  metadata.st_mode & S_IFMT == (isDirectory ? S_IFDIR : S_IFREG),
                  metadata.st_uid == getuid()
            else { throw AndroidAVDRemovalError.refused("This package's files could not be verified. Rescan and try again.") }
            if let rootDevice, metadata.st_dev != rootDevice {
                throw AndroidAVDRemovalError.refused("This package crosses a mounted filesystem and remains read-only.")
            }
            rootDevice = metadata.st_dev
        }
    }
}
