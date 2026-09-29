import Darwin
import Foundation

extension RootResolver {
    // MARK: - Android locations

    public static func androidStudioSystemRoots() -> [URL] {
        androidStudioSystemRoots(home: homeURL)
    }

    public static func androidStudioSystemIssue() -> String? {
        androidStudioSystemIssue(home: homeURL)
    }

    public static func gradleCacheRoots() -> [URL] {
        gradleCacheRoots(home: homeURL, environment: ProcessInfo.processInfo.environment)
    }

    public static func androidSDKRoots() -> [URL] {
        androidSDKRoots(home: homeURL, environment: ProcessInfo.processInfo.environment)
    }

    public static func androidAVDRoots() -> [URL] {
        androidAVDRoots(home: homeURL, environment: ProcessInfo.processInfo.environment)
    }

    public static func gradleCacheIssue() -> String? {
        let value = ProcessInfo.processInfo.environment["GRADLE_USER_HOME"]
        if value == nil {
            let defaultCache = homeURL.appendingPathComponent(".gradle/caches", isDirectory: true)
            if FileManager.default.fileExists(atPath: defaultCache.path(percentEncoded: false)),
               usableAndroidRoot(defaultCache, home: homeURL) == nil {
                return "The default Gradle cache is not a readable local directory. Coverage is incomplete."
            }
            return nil
        }
        guard let root = absoluteAndroidPath(value),
              usableAndroidRoot(root.appendingPathComponent("caches", isDirectory: true), home: homeURL) != nil
        else {
            return "GRADLE_USER_HOME is set, but its caches are not a readable local directory."
        }
        return nil
    }

    public static func androidSDKIssue() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let current = environment["ANDROID_HOME"]
        let deprecated = environment["ANDROID_SDK_ROOT"]
        if let current, absoluteAndroidPath(current) == nil {
            return "ANDROID_HOME is set to an unsupported path. SDK coverage is incomplete."
        }
        if let deprecated, absoluteAndroidPath(deprecated) == nil {
            return "ANDROID_SDK_ROOT is set to an unsupported path. SDK coverage is incomplete."
        }
        if let current, let deprecated,
           let currentPath = absoluteAndroidPath(current),
           let deprecatedPath = absoluteAndroidPath(deprecated),
           ProtectedPaths.normalize(currentPath) != ProtectedPaths.normalize(deprecatedPath) {
            return "ANDROID_HOME and ANDROID_SDK_ROOT point to different locations. SDK coverage is incomplete."
        }
        if current != nil || deprecated != nil,
           androidSDKRoots(home: homeURL, environment: environment).isEmpty {
            return "The configured Android SDK location is not a readable local directory. SDK coverage is incomplete."
        }
        if current == nil, deprecated == nil {
            let defaultRoot = homeURL.appendingPathComponent("Library/Android/sdk", isDirectory: true)
            if FileManager.default.fileExists(atPath: defaultRoot.path(percentEncoded: false)),
               usableAndroidRoot(defaultRoot, home: homeURL) == nil {
                return "The default Android SDK is not a readable local directory. Coverage is incomplete."
            }
        }
        return nil
    }

    public static func androidAVDIssue() -> String? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["ANDROID_AVD_HOME", "ANDROID_EMULATOR_HOME", "ANDROID_USER_HOME"] {
            guard let value = environment[key] else { continue }
            guard let path = absoluteAndroidPath(value) else {
                return "\(key) is set to an unsupported path. AVD coverage is incomplete."
            }
            let root = key == "ANDROID_AVD_HOME" ? path : path.appendingPathComponent("avd", isDirectory: true)
            if usableAndroidRoot(root, home: homeURL) == nil {
                return "The configured AVD location is not a readable local directory. AVD coverage is incomplete."
            }
            return androidAVDMetadataIssue(
                root: androidAVDBaseRoot(home: homeURL, environment: environment),
                home: homeURL
            )
        }
        let defaultRoot = homeURL.appendingPathComponent(".android/avd", isDirectory: true)
        if FileManager.default.fileExists(atPath: defaultRoot.path(percentEncoded: false)),
           usableAndroidRoot(defaultRoot, home: homeURL) == nil {
            return "The default AVD directory is not a readable local directory. Coverage is incomplete."
        }
        return androidAVDMetadataIssue(
            root: androidAVDBaseRoot(home: homeURL, environment: environment),
            home: homeURL
        )
    }

    static func androidStudioSystemRoots(home: URL, fileManager: FileManager = .default) -> [URL] {
        let parent = home.appendingPathComponent("Library/Caches/Google", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: parent.path(percentEncoded: false)) else {
            return []
        }
        let recognized = names.filter(isStudioDirectoryName).sorted()
        let defaults: [URL] = recognized.prefix(32).compactMap { name in
            return usableAndroidRoot(parent.appendingPathComponent(name, isDirectory: true), home: home)
        }
        let configured = androidStudioConfiguredSystemPaths(home: home, fileManager: fileManager)
            .compactMap { usableAndroidRoot($0, home: home) }
        return Array(Set(defaults + configured)).sorted { $0.path < $1.path }
    }

    static func androidStudioSystemIssue(home: URL, fileManager: FileManager = .default) -> String? {
        let cacheRoot = home.appendingPathComponent("Library/Caches/Google", isDirectory: true)
        if fileManager.fileExists(atPath: cacheRoot.path(percentEncoded: false)),
           (try? fileManager.contentsOfDirectory(atPath: cacheRoot.path(percentEncoded: false))) == nil {
            return "Android Studio system files could not be listed. Its inventory may be incomplete."
        }
        if let names = try? fileManager.contentsOfDirectory(atPath: cacheRoot.path(percentEncoded: false)),
           names.filter(isStudioDirectoryName).count > 32 {
            return "Too many Android Studio system directories to inspect completely. Its inventory may be incomplete."
        }
        let configRoot = home.appendingPathComponent("Library/Application Support/Google", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: configRoot.path(percentEncoded: false)) else {
            if fileManager.fileExists(atPath: configRoot.path(percentEncoded: false)) {
                return "Android Studio configuration could not be listed. Its inventory may be incomplete."
            }
            return nil
        }
        guard names.count <= 32 else {
            return "Too many Android Studio configurations to inspect completely. Its inventory may be incomplete."
        }
        for name in names.sorted() where isStudioDirectoryName(name) {
            if let issue = studioPropertiesIssue(name: name, configRoot: configRoot, cacheRoot: cacheRoot, fileManager: fileManager) {
                return issue
            }
        }
        return nil
    }

    private static func studioPropertiesIssue(
        name: String,
        configRoot: URL,
        cacheRoot: URL,
        fileManager: FileManager
    ) -> String? {
        let properties = configRoot.appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("idea.properties")
        guard fileManager.fileExists(atPath: properties.path(percentEncoded: false)) else { return nil }
        guard let contents = boundedProperties(at: properties) else {
            return "Android Studio properties could not be read. Its inventory may be incomplete."
        }
        for line in contents.split(whereSeparator: \.isNewline) {
            let value = line.trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("idea.system.path") else { continue }
            guard let property = parseProperty(value), property.key == "idea.system.path" else {
                return "Android Studio system path metadata is malformed. Its inventory may be incomplete."
            }
            let configured = property.value
            let defaultPath = cacheRoot.appendingPathComponent(name, isDirectory: true)
            guard let path = absoluteAndroidPath(configured),
                  ProtectedPaths.normalize(path) == ProtectedPaths.normalize(defaultPath)
            else {
                return "Android Studio has a custom or unsupported system path. Its inventory may be incomplete."
            }
        }
        return nil
    }

    static func androidStudioConfiguredSystemPaths(home: URL, fileManager: FileManager = .default) -> [URL] {
        let configRoot = home.appendingPathComponent("Library/Application Support/Google", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: configRoot.path(percentEncoded: false)) else {
            return []
        }
        return names.filter(isStudioDirectoryName).sorted().prefix(32).flatMap { name in
            let properties = configRoot.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("idea.properties")
            guard let contents = boundedProperties(at: properties) else { return [URL]() }
            return contents.split(whereSeparator: \.isNewline).compactMap { line in
                guard let property = parseProperty(String(line)), property.key == "idea.system.path",
                      let path = absoluteAndroidPath(property.value)
                else { return nil }
                return path
            }
        }
    }

    static func gradleCacheRoots(home: URL, environment: [String: String]) -> [URL] {
        let gradleHome: URL
        if let value = environment["GRADLE_USER_HOME"] {
            guard let resolved = absoluteAndroidPath(value) else { return [] }
            gradleHome = resolved
        } else {
            gradleHome = home.appendingPathComponent(".gradle", isDirectory: true)
        }
        return usableAndroidRoot(gradleHome.appendingPathComponent("caches", isDirectory: true), home: home).map { [$0] } ?? []
    }

    static func androidSDKRoots(home: URL, environment: [String: String]) -> [URL] {
        let current: URL?
        if let value = environment["ANDROID_HOME"] {
            guard let resolved = absoluteAndroidPath(value) else { return [] }
            current = resolved
        } else {
            current = nil
        }
        let deprecated: URL?
        if let value = environment["ANDROID_SDK_ROOT"] {
            guard let resolved = absoluteAndroidPath(value) else { return [] }
            deprecated = resolved
        } else {
            deprecated = nil
        }
        if let current, let deprecated, ProtectedPaths.normalize(current) != ProtectedPaths.normalize(deprecated) {
            return []
        }
        let root = current ?? deprecated ?? home.appendingPathComponent("Library/Android/sdk", isDirectory: true)
        return usableAndroidRoot(root, home: home).map { [$0] } ?? []
    }

    static func androidAVDRoots(home: URL, environment: [String: String]) -> [URL] {
        guard let avdRoot = androidAVDBaseRoot(home: home, environment: environment) else { return [] }
        let avdRootPath = ProtectedPaths.normalize(avdRoot)
        let redirected = androidAVDRedirectPaths(home: home, environment: environment)
            .compactMap { usableAndroidRoot($0, home: home) }
            .filter {
                let path = ProtectedPaths.normalize($0)
                return !path.hasPrefix(avdRootPath + "/") && path != avdRootPath
            }
        return [avdRoot] + Array(Set(redirected))
    }

    static func androidAVDBaseRoot(home: URL, environment: [String: String]) -> URL? {
        let root: URL
        if let value = environment["ANDROID_AVD_HOME"] {
            guard let path = absoluteAndroidPath(value) else { return nil }
            root = path
        } else if let value = environment["ANDROID_EMULATOR_HOME"] {
            guard let path = absoluteAndroidPath(value) else { return nil }
            root = path.appendingPathComponent("avd", isDirectory: true)
        } else if let value = environment["ANDROID_USER_HOME"] {
            guard let path = absoluteAndroidPath(value) else { return nil }
            root = path.appendingPathComponent("avd", isDirectory: true)
        } else {
            root = home.appendingPathComponent(".android/avd", isDirectory: true)
        }
        return usableAndroidRoot(root, home: home)
    }

    static func androidAVDRedirectPaths(
        home: URL,
        environment: [String: String],
        fileManager: FileManager = .default
    ) -> [URL] {
        guard let root = androidAVDBaseRoot(home: home, environment: environment),
              let names = try? fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false))
        else { return [] }
        let homeRoot = root.deletingLastPathComponent()
        let paths = names.filter { $0.hasSuffix(".ini") }.prefix(256).flatMap { name -> [URL] in
            guard let contents = boundedProperties(at: root.appendingPathComponent(name)) else { return [URL]() }
            let values = propertyValues(contents)
            var paths: [URL] = []
            if let path = values["path"], let absolute = absoluteAndroidPath(path) { paths.append(absolute) }
            if let relative = values["path.rel"], !relative.hasPrefix("/"), !relative.contains("\0") {
                paths.append(homeRoot.appendingPathComponent(relative).standardizedFileURL)
            }
            return paths
        }
        return Array(Set(paths))
    }

    static func androidAVDMetadataIssue(
        root: URL?,
        home: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        guard let root else { return nil }
        let path = root.path(percentEncoded: false)
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else {
            return "The AVD directory could not be listed. Device coverage is incomplete."
        }
        if names.count > 256 {
            return "The AVD directory contains too many entries to inspect completely. Device coverage is incomplete."
        }
        var registryPaths: [String: String] = [:]
        for name in names.filter({ $0.hasSuffix(".ini") }) {
            guard let contents = boundedProperties(at: root.appendingPathComponent(name)) else {
                return "An AVD metadata file could not be read. Device coverage is incomplete."
            }
            let values = propertyValues(contents)
            let absolutePath = values["path"].flatMap(absoluteAndroidPath)
            let relativePath = values["path.rel"].flatMap { path in
                path.hasPrefix("/") || path.contains("\0")
                    ? nil
                    : root.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
            }
            if let absolutePath, let relativePath,
               ProtectedPaths.normalize(absolutePath) != ProtectedPaths.normalize(relativePath) {
                return "An AVD has conflicting path metadata. Device coverage is incomplete."
            }
            let dataPath = absolutePath ?? relativePath
            let home = home ?? root.deletingLastPathComponent().deletingLastPathComponent()
            guard let dataPath, usableAndroidRoot(dataPath, home: home) != nil else {
                return "An AVD has unsupported or missing path metadata. Device coverage is incomplete."
            }
            let normalized = ProtectedPaths.normalize(dataPath)
            if let previous = registryPaths[normalized], previous != name {
                return "Multiple AVD registry entries resolve to the same data directory. "
                    + "Device identity is ambiguous and coverage is incomplete."
            }
            if registryPaths.keys.contains(where: { androidPathsOverlap(normalized, $0) }) {
                return "AVD registry entries resolve to overlapping data directories. "
                    + "Device identity is ambiguous and coverage is incomplete."
            }
            registryPaths[normalized] = name
        }
        return nil
    }

    static func hasUnresolvedAndroidRedirectMetadata(
        home: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        hasUnresolvedStudioRedirect(home: home, fileManager: fileManager)
            || hasUnsupportedAndroidHomes(environment)
            || hasUnresolvedAVDRedirect(home: home, environment: environment, fileManager: fileManager)
    }

    private static func hasUnresolvedStudioRedirect(home: URL, fileManager: FileManager) -> Bool {
        let configRoot = home.appendingPathComponent("Library/Application Support/Google", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: configRoot.path(percentEncoded: false)) else {
            return fileManager.fileExists(atPath: configRoot.path(percentEncoded: false))
        }
        guard names.count <= 32 else { return true }
        return names.filter(isStudioDirectoryName).contains { name in
            let properties = configRoot.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("idea.properties")
            guard fileManager.fileExists(atPath: properties.path(percentEncoded: false)) else { return false }
            guard let contents = boundedProperties(at: properties) else { return true }
            return contents.split(whereSeparator: \.isNewline).contains { line in
                let value = line.trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix("idea.system.path") else { return false }
                guard let property = parseProperty(value), property.key == "idea.system.path" else { return true }
                return absoluteAndroidPath(property.value) == nil
            }
        }
    }

    private static func hasUnsupportedAndroidHomes(_ environment: [String: String]) -> Bool {
        for key in ["ANDROID_AVD_HOME", "ANDROID_EMULATOR_HOME", "ANDROID_USER_HOME"] {
            if let value = environment[key], absoluteAndroidPath(value) == nil { return true }
        }
        return false
    }

    private static func hasUnresolvedAVDRedirect(
        home: URL,
        environment: [String: String],
        fileManager: FileManager
    ) -> Bool {
        guard let root = androidAVDBaseRoot(home: home, environment: environment) else { return false }
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false)),
              names.count <= 256
        else { return true }
        return names.filter { $0.hasSuffix(".ini") }.contains { name in
            guard let contents = boundedProperties(at: root.appendingPathComponent(name)) else { return true }
            let values = propertyValues(contents)
            let hasAbsolute = values["path"].flatMap(absoluteAndroidPath) != nil
            let hasRelative = values["path.rel"].map { !$0.hasPrefix("/") && !$0.contains("\0") } == true
            return !hasAbsolute && !hasRelative
        }
    }

    static func absoluteAndroidPath(_ value: String?) -> URL? {
        guard let value, value.hasPrefix("/"), !value.contains("\0") else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }

    static func usableAndroidRoot(_ root: URL, home: URL) -> URL? {
        guard root.isFileURL else { return nil }
        let path = PathNormalizer.lexical(root.path(percentEncoded: false))
        let homePath = PathNormalizer.normalize(home.path(percentEncoded: false))
        let resolved = PathNormalizer.normalize(path)
        guard path.hasPrefix("/"), !path.contains("\0"),
              resolved != homePath, resolved.hasPrefix(homePath + "/"),
              resolved == path,
              FileManager.default.fileExists(atPath: path),
              FileManager.default.isReadableFile(atPath: path)
        else { return nil }
        var info = stat()
        var homeInfo = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              stat(homePath, &homeInfo) == 0, info.st_dev == homeInfo.st_dev
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func isIDEVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy(\.isNumber)
        }
    }

    private static func androidPathsOverlap(_ first: String, _ second: String) -> Bool {
        first == second || first.hasPrefix(second + "/") || second.hasPrefix(first + "/")
    }
}
