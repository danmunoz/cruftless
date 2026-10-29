import Darwin
import Foundation

public struct AndroidAVDRemovalIdentity: Sendable, Hashable {
    public let name: String
    public let directory: URL
    public let registry: URL
    public let registryRoot: URL
    let directoryFingerprint: Fingerprint
    let registryFingerprint: Fingerprint
    let configFingerprint: Fingerprint

    public static func capture(
        child: ChildEntry,
        registryRoot: URL,
        protectedPaths: ProtectedPaths
    ) throws -> Self {
        let name = child.url.deletingPathExtension().lastPathComponent
        guard name.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$"#, options: .regularExpression) != nil,
              registryRoot.lastPathComponent == "avd",
              child.url.lastPathComponent == name + ".avd",
              ProtectedPaths.standardize(child.url.deletingLastPathComponent()) == ProtectedPaths.standardize(registryRoot),
              ProtectedPaths.standardize(registryRoot) == ProtectedPaths.normalize(registryRoot),
              protectedPaths.allowsAndroidAVD(child.url, under: registryRoot)
        else { throw AndroidAVDRemovalError.refused("This device's storage layout is unsupported or protected.") }
        let registry = registryRoot.appendingPathComponent(name + ".ini")
        let configURL = child.url.appendingPathComponent("config.ini")
        try verifyFiles([(registryRoot, true), (child.url, true), (registry, false), (configURL, false)])
        guard !protectedPaths.intersectsCustomProtection(registry),
              let registryText = RootResolver.boundedProperties(at: registry),
              let configText = RootResolver.boundedProperties(at: configURL)
        else { throw AndroidAVDRemovalError.refused("The device's configuration is unreadable or protected.") }
        let registryValues = try properties(registryText)
        let config = try properties(configText)
        try rejectAliases(of: child.url, registry: registry, root: registryRoot)
        guard let absolute = registryValues["path"], absolute.hasPrefix("/"),
              ProtectedPaths.standardize(URL(fileURLWithPath: absolute)) == ProtectedPaths.standardize(child.url)
        else { throw AndroidAVDRemovalError.refused("The device registration points to different storage. Rescan and try again.") }
        if let relative = registryValues["path.rel"] {
            guard !relative.hasPrefix("/"), !relative.contains("\0") else {
                throw AndroidAVDRemovalError.refused("The device registration has an unsupported relative path.")
            }
            let cliRelative = registryRoot.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: cliRelative.path(percentEncoded: false)),
               ProtectedPaths.normalize(cliRelative) != ProtectedPaths.normalize(child.url) {
                throw AndroidAVDRemovalError.refused("Android tools resolve this registration to different storage.")
            }
        }
        guard config["AvdId"] == name,
              !config.keys.contains(where: { key in
                  key == "sdcard.path" || key.hasPrefix("disk.") && (key.hasSuffix(".path") || key.hasSuffix(".initPath"))
              }),
              let directoryFingerprint = Fingerprint.capture(at: child.url),
              let registryFingerprint = Fingerprint.capture(at: registry),
              let configFingerprint = Fingerprint.capture(at: configURL)
        else { throw AndroidAVDRemovalError.refused("This device has custom storage paths or an unverified identity.") }
        return Self(name: name, directory: child.url, registry: registry, registryRoot: registryRoot,
                    directoryFingerprint: directoryFingerprint, registryFingerprint: registryFingerprint,
                    configFingerprint: configFingerprint)
    }

    func revalidate(protectedPaths: ProtectedPaths) throws {
        let child = ChildEntry(id: name, name: name, url: directory, reclaimableBytes: 0,
                               staleness: StalenessInfo(lastUsedDate: nil), tier: .info, consequence: "")
        let current = try Self.capture(child: child, registryRoot: registryRoot, protectedPaths: protectedPaths)
        guard current.name == name,
              directoryFingerprint.verify(at: directory) == .valid,
              registryFingerprint.verify(at: registry) == .valid,
              configFingerprint.verify(at: directory.appendingPathComponent("config.ini")) == .valid
        else { throw AndroidAVDRemovalError.refused("The device changed after Review. Rescan and review it again.") }
    }

    private static func verifyFiles(_ files: [(URL, Bool)]) throws {
        var rootDevice: dev_t?
        for (url, directory) in files {
            var metadata = stat()
            guard lstat(url.path(percentEncoded: false), &metadata) == 0,
                  metadata.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
                  metadata.st_uid == getuid(),
                  ProtectedPaths.standardize(url) == ProtectedPaths.normalize(url)
            else { throw AndroidAVDRemovalError.refused("The device's files could not be verified. Rescan and try again.") }
            if let rootDevice, metadata.st_dev != rootDevice {
                throw AndroidAVDRemovalError.refused("This device crosses a mounted filesystem and remains read-only.")
            }
            rootDevice = metadata.st_dev
        }
    }

    private static func rejectAliases(of directory: URL, registry: URL, root: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
        guard names.count <= 256 else { throw AndroidAVDRemovalError.refused("Too many device registrations to verify this device.") }
        let target = ProtectedPaths.normalize(directory)
        for name in names where name.hasSuffix(".ini") && name != registry.lastPathComponent {
            guard let text = RootResolver.boundedProperties(at: root.appendingPathComponent(name)) else {
                throw AndroidAVDRemovalError.refused("Another device registration is unreadable. Rescan and try again.")
            }
            let values = try properties(text)
            let paths = [values["path"].flatMap(RootResolver.absoluteAndroidPath), values["path.rel"].map {
                root.deletingLastPathComponent().appendingPathComponent($0)
            }, values["path.rel"].map { root.appendingPathComponent($0) }].compactMap(\.self)
            if paths.contains(where: {
                let other = ProtectedPaths.normalize($0)
                return other == target || other.hasPrefix(target + "/") || target.hasPrefix(other + "/")
            }) {
                throw AndroidAVDRemovalError.refused("Multiple device registrations share this storage. This device remains read-only.")
            }
        }
    }

    private static func properties(_ text: String) throws -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("!") { continue }
            guard raw == trimmed, !raw.contains("\\"), let delimiter = raw.firstIndex(of: "=") else {
                throw AndroidAVDRemovalError.refused("The device configuration uses unsupported property syntax.")
            }
            let key = String(raw[..<delimiter])
            let value = String(raw[raw.index(after: delimiter)...])
            guard !key.isEmpty, key.trimmingCharacters(in: .whitespaces) == key,
                  values.updateValue(value, forKey: key) == nil else {
                throw AndroidAVDRemovalError.refused("The device configuration contains ambiguous or duplicate entries.")
            }
        }
        return values
    }
}

public enum AndroidAVDRemovalError: Error, LocalizedError, Sendable {
    case refused(String)
    case toolsRequired

    public var errorDescription: String? {
        switch self {
        case let .refused(reason): reason
        case .toolsRequired: "Android tools need to be set up before this device can be deleted."
        }
    }
}
