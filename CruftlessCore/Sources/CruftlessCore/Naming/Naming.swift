import Foundation

/// Transforms raw machine identifiers and build numbers into human-readable labels.
public enum Naming: Sendable {
    /// Formats a Device Support folder name like `iPhone18,1 27.0 (24A5418b)` into `"iPhone 17 Pro · iOS 27.0 beta"`.
    public static func deviceSupportFolder(_ folderName: String) -> String {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse build inside parentheses: "(24A5418b)".
        var build: String?
        var mainPart = trimmed
        if let openParen = trimmed.lastIndex(of: "("),
           let closeParen = trimmed.lastIndex(of: ")"),
           openParen < closeParen {
            let buildRange = trimmed.index(after: openParen) ..< closeParen
            build = String(trimmed[buildRange])
            mainPart = String(trimmed[..<openParen]).trimmingCharacters(in: .whitespaces)
        }

        // Split mainPart into model identifier and OS version.
        let tokens = mainPart.split(separator: " ", maxSplits: 1).map(String.init)
        guard !tokens.isEmpty else { return folderName }

        let modelIdentifier = tokens[0]
        let osVersion = tokens.count > 1 ? tokens[1] : ""

        let deviceName = DeviceIdentifierTable.lookup(modelIdentifier) ?? modelIdentifier
        let platformPrefix = detectPlatform(for: modelIdentifier)

        var osClause = ""
        if !osVersion.isEmpty {
            osClause = platformPrefix.isEmpty ? osVersion : "\(platformPrefix) \(osVersion)"
        }

        if let build, BuildNumberParser.isBeta(build) {
            osClause = osClause.isEmpty ? "beta" : "\(osClause) beta"
        }

        if osClause.isEmpty {
            return deviceName
        }
        return "\(deviceName) · \(osClause)"
    }

    /// Formats a CoreSimulator runtime identifier like `com.apple.CoreSimulator.SimRuntime.iOS-18-6` into `"iOS 18.6"`.
    public static func runtime(identifier: String, build: String? = nil) -> String {
        let prefix = "com.apple.CoreSimulator.SimRuntime."
        let stripped = identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : identifier

        // Replace hyphens in version: iOS-18-6 -> iOS 18.6.
        var parts = stripped.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return identifier }

        let platformRaw = parts.removeFirst()
        let platformName = platformRaw == "xrOS" ? "visionOS" : platformRaw

        let version = parts.joined(separator: ".")
        var result = version.isEmpty ? platformName : "\(platformName) \(version)"

        if let build, BuildNumberParser.isBeta(build) {
            result += " beta"
        }

        return result
    }

    /// Known Xcode Derived Data system folder names, mapped to plain words.
    private static let derivedDataSystemFolders: [String: String] = [
        "ModuleCache.noindex": "Module cache",
        "SDKStatCaches.noindex": "SDK stat caches",
        "SymbolCache.noindex": "Symbol cache",
        "CompilationCache.noindex": "Compilation cache",
        "SDKExplicitPrecompiledModules": "SDK precompiled modules",
        "Index.noindex": "Index"
    ]

    private static let derivedDataHashLength = 28

    /// Formats a Derived Data child folder name for display.
    public static func derivedDataFolder(_ name: String) -> String {
        if let systemFolder = derivedDataSystemFolders[name] {
            return systemFolder
        }
        return strippingProjectHash(from: name)
    }

    private static func strippingProjectHash(from name: String) -> String {
        guard name.count > derivedDataHashLength + 1 else { return name }

        let hashStart = name.index(name.endIndex, offsetBy: -derivedDataHashLength)
        let separatorIndex = name.index(before: hashStart)
        guard name[separatorIndex] == "-" else { return name }

        let hashCandidate = name[hashStart...]
        guard hashCandidate.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) else {
            return name
        }

        return String(name[name.startIndex ..< separatorIndex])
    }

    private static func detectPlatform(for identifier: String) -> String {
        let lower = identifier.lowercased()
        if lower.hasPrefix("iphone") {
            return "iOS"
        } else if lower.hasPrefix("ipad") {
            return "iPadOS"
        } else if lower.hasPrefix("watch") {
            return "watchOS"
        } else if lower.hasPrefix("appletv") {
            return "tvOS"
        } else if lower.hasPrefix("reality") || lower.hasPrefix("vision") {
            return "visionOS"
        }
        return ""
    }
}
