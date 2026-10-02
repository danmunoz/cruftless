import Darwin
import Foundation

extension RootResolver {
    public static func androidSDKPackage(at directory: URL) -> AndroidSDKPackage? {
        let properties = directory.appendingPathComponent("source.properties")
        guard let contents = boundedRegularFile(properties) else { return nil }
        let values = propertyValues(contents)
        guard let description = values["Pkg.Desc"] ?? values["Pkg.Path"], !description.isEmpty else { return nil }
        return AndroidSDKPackage(
            displayName: description,
            packagePath: values["Pkg.Path"],
            revision: values["Pkg.Revision"]
        )
    }

    static func androidSDKPackage(at directory: URL, sdkRoot: URL) -> AndroidSDKPackage? {
        AndroidSDKMetadataReader.read(directory: directory, root: sdkRoot).package
    }

    static func sdkPackagePath(for directory: URL, sdkRoot: URL) -> String? {
        let rootPath = ProtectedPaths.normalize(sdkRoot).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let packagePath = ProtectedPaths.normalize(directory).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = rootPath + "/"
        guard packagePath.hasPrefix(prefix) else { return nil }
        let components = packagePath.dropFirst(prefix.count).split(separator: "/").map(String.init)
        guard isSupportedSDKPackagePath(components) else { return nil }
        return components.joined(separator: ";")
    }

    static func isSupportedSDKPackagePath(_ components: [String]) -> Bool {
        guard let first = components.first else { return false }
        switch first {
        case "platform-tools", "emulator": return components.count == 1
        case "platforms", "build-tools", "sources", "ndk", "cmake", "cmdline-tools": return components.count == 2
        case "system-images": return components.count == 4
        case "extras": return components.count == 3
        default: return false
        }
    }

    static func boundedRegularFile(_ url: URL) -> String? {
        guard let data = boundedSDKMetadata(at: url, maximumBytes: 64 * 1024) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func boundedSDKMetadata(at url: URL, maximumBytes: Int) -> Data? {
        let descriptor = Darwin.open(url.path(percentEncoded: false), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var metadataStat = stat()
        guard Darwin.fstat(descriptor, &metadataStat) == 0,
              (metadataStat.st_mode & S_IFMT) == S_IFREG else { return nil }

        var data = Data()
        while data.count <= maximumBytes {
            let count = min(8 * 1024, maximumBytes + 1 - data.count)
            var buffer = [UInt8](repeating: 0, count: count)
            let bytesRead = Darwin.read(descriptor, &buffer, count)
            if bytesRead < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard bytesRead > 0 else { return data }
            data.append(contentsOf: buffer.prefix(bytesRead))
        }
        return nil
    }

    public static func androidRootSource(locationID: String, root: URL) -> String {
        let environment = ProcessInfo.processInfo.environment
        switch locationID {
        case "androidStudioSystem":
            let parent = homeURL.appendingPathComponent("Library/Caches/Google", isDirectory: true)
            let isDefault = ProtectedPaths.normalize(root.deletingLastPathComponent()) == ProtectedPaths.normalize(parent)
                && isStudioDirectoryName(root.lastPathComponent)
            return isDefault ? "Android Studio system directory" : "Android Studio idea.system.path"
        case "gradleCaches":
            return environment["GRADLE_USER_HOME"] == nil ? "Default Gradle cache" : "GRADLE_USER_HOME/caches"
        case "androidSDK":
            return sdkRootSource(environment)
        case "androidAVDs":
            return avdRootSource(root, environment: environment)
        default:
            return "Discovered root"
        }
    }

    public static func androidRootLayout(locationID: String, root: URL) -> String {
        switch locationID {
        case "androidStudioSystem":
            return isStudioDirectoryName(root.lastPathComponent)
                ? "Recognized Android Studio system-directory name"
                : "Custom Studio layout not verified"
        case "gradleCaches":
            return root.lastPathComponent == "caches"
                ? "Recognized Gradle caches directory"
                : "Gradle cache layout not verified"
        case "androidSDK":
            let expected = Set(["platforms", "build-tools", "platform-tools", "system-images", "ndk", "cmake", "licenses"])
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
            return names.contains(where: expected.contains)
                ? "Recognized Android SDK directory structure"
                : "SDK layout not verified"
        case "androidAVDs":
            let resolvedRoots = androidAVDRoots()
            if resolvedRoots.first.map({ ProtectedPaths.normalize($0) == ProtectedPaths.normalize(root) }) == true {
                return androidAVDInventory(roots: resolvedRoots).isEmpty
                    ? "AVD layout not verified"
                    : "Recognized AVD registry"
            }
            return resolvedRoots.contains { ProtectedPaths.normalize($0) == ProtectedPaths.normalize(root) }
                ? "Registered AVD data directory"
                : "AVD layout not verified"
        default:
            return "Android layout not verified"
        }
    }

    public static func androidAVDInventory(roots: [URL]) -> [AndroidAVDInventoryItem] {
        var items: [String: AndroidAVDInventoryItem] = [:]
        guard let registryRoot = roots.first,
              let names = try? FileManager.default.contentsOfDirectory(atPath: registryRoot.path(percentEncoded: false))
        else { return [] }
        for name in names.filter({ $0.hasSuffix(".ini") }).prefix(256) {
            guard let item = androidAVDItem(named: name, in: registryRoot) else { continue }
            items[ProtectedPaths.normalize(registryRoot.appendingPathComponent(name))] = item
        }
        return items.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func boundedProperties(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024 + 1), data.count <= 64 * 1024 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func propertyValues(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let property = parseProperty(String(line)) else { continue }
            values[property.key] = property.value
        }
        return values
    }

    static func parseProperty(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!"), !trimmed.hasSuffix("\\") else {
            return nil
        }
        guard let delimiter = trimmed.firstIndex(where: { $0 == "=" || $0 == ":" || $0.isWhitespace }) else {
            return nil
        }
        let key = String(trimmed[..<delimiter]).trimmingCharacters(in: .whitespaces)
        var valueStart = delimiter
        while valueStart < trimmed.endIndex, trimmed[valueStart].isWhitespace {
            valueStart = trimmed.index(after: valueStart)
        }
        if valueStart < trimmed.endIndex {
            let character = trimmed[valueStart]
            if character == "=" || character == ":" {
                valueStart = trimmed.index(after: valueStart)
            }
        }
        while valueStart < trimmed.endIndex, trimmed[valueStart].isWhitespace {
            valueStart = trimmed.index(after: valueStart)
        }
        return (key, String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces))
    }

    static func isStudioDirectoryName(_ name: String) -> Bool {
        let prefix = name.hasPrefix("AndroidStudioPreview") ? "AndroidStudioPreview" : "AndroidStudio"
        return name.hasPrefix(prefix) && isIDEVersion(String(name.dropFirst(prefix.count)))
    }

    private static func sdkRootSource(_ environment: [String: String]) -> String {
        if environment["ANDROID_HOME"] != nil { return "ANDROID_HOME" }
        if environment["ANDROID_SDK_ROOT"] != nil { return "ANDROID_SDK_ROOT" }
        return "Default Android SDK"
    }

    private static func avdRootSource(_ root: URL, environment: [String: String]) -> String {
        guard let base = androidAVDBaseRoot(home: homeURL, environment: environment) else {
            return "AVD registry redirect"
        }
        if ProtectedPaths.normalize(base) != ProtectedPaths.normalize(root) {
            return "AVD path / path.rel data directory"
        }
        if environment["ANDROID_AVD_HOME"] != nil { return "ANDROID_AVD_HOME" }
        if environment["ANDROID_EMULATOR_HOME"] != nil { return "ANDROID_EMULATOR_HOME/avd" }
        if environment["ANDROID_USER_HOME"] != nil { return "ANDROID_USER_HOME/avd" }
        return "Default AVD home"
    }

    private static func androidAVDItem(named name: String, in root: URL) -> AndroidAVDInventoryItem? {
        guard let contents = boundedProperties(at: root.appendingPathComponent(name)) else { return nil }
        let values = propertyValues(contents)
        let absolute = values["path"].flatMap(absoluteAndroidPath)
        let relative = values["path.rel"].flatMap { value -> URL? in
            guard !value.hasPrefix("/"), !value.contains("\0") else { return nil }
            return root.deletingLastPathComponent().appendingPathComponent(value).standardizedFileURL
        }
        if let absolute, let relative,
           ProtectedPaths.normalize(absolute) != ProtectedPaths.normalize(relative) { return nil }
        guard let directory = absolute ?? relative,
              usableAndroidRoot(directory, home: homeURL) != nil
        else { return nil }
        let config = boundedProperties(at: directory.appendingPathComponent("config.ini")).map(propertyValues) ?? [:]
        let fallback = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let displayName = values["avd.ini.displayname"] ?? config["hw.device.name"] ?? fallback
        return AndroidAVDInventoryItem(
            directory: directory,
            registryPath: ProtectedPaths.normalize(root.appendingPathComponent(name)),
            registryName: name,
            displayName: displayName,
            systemImage: values["target"] ?? config["image.sysdir.1"]
        )
    }
}
