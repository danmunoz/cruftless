import Darwin
import Foundation

/// Names Gradle documents for caches directly below its user-home `caches` directory.
public enum GradleCacheEntryPolicy {
    public static func isRecognizedCacheEntryName(_ name: String) -> Bool {
        if name == "modules-2" || name == "build-cache-1" {
            return true
        }
        if hasPositiveNumericSuffix(name, prefix: "jars-") || hasPositiveNumericSuffix(name, prefix: "transforms-") {
            return true
        }
        return isGradleVersionDirectory(name)
    }

    /// A removable row is one recognized, real directory directly inside the resolved cache root.
    public static func isEligible(_ child: ChildEntry, cacheRoots: [URL]) -> Bool {
        let path = ProtectedPaths.normalize(child.url)
        guard child.id == "\(LocationCatalog.gradleCaches.id)-\(path)",
              child.name == child.url.lastPathComponent,
              isRecognizedCacheEntryName(child.name),
              let root = cacheRoots.first(where: {
                  ProtectedPaths.normalize(child.url.deletingLastPathComponent())
                      == ProtectedPaths.normalize($0)
              })
        else { return false }

        let rootPath = ProtectedPaths.normalize(root)
        guard path.hasPrefix(rootPath + "/"),
              !path.dropFirst(rootPath.count + 1).contains("/")
        else { return false }

        var info = stat()
        guard lstat(path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR
        else { return false }
        return true
    }

    private static func hasPositiveNumericSuffix(_ name: String, prefix: String) -> Bool {
        guard name.hasPrefix(prefix) else { return false }
        let suffix = name.dropFirst(prefix.count)
        let digits = suffix.unicodeScalars
        return !digits.isEmpty && digits.allSatisfy(isASCIIDigit) && digits.contains(where: { $0.value != 48 })
    }

    private static func isGradleVersionDirectory(_ name: String) -> Bool {
        let buildParts = name.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2,
              buildParts.count == 1 || isIdentifierList(String(buildParts[1]))
        else { return false }

        let prereleaseParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard prereleaseParts.count <= 2,
              isNumericVersion(String(prereleaseParts[0])),
              prereleaseParts.count == 1 || isIdentifierList(String(prereleaseParts[1]))
        else { return false }
        return true
    }

    private static func isNumericVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return components.count >= 2
            && components.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(isASCIIDigit) }
    }

    private static func isIdentifierList(_ value: String) -> Bool {
        let identifiers = value.split(omittingEmptySubsequences: false) {
            $0 == "." || $0 == "-"
        }
        return !identifiers.isEmpty && identifiers.allSatisfy { identifier in
            !identifier.isEmpty && identifier.unicodeScalars.allSatisfy(isASCIIAlphaNumeric)
        }
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (48 ... 57).contains(scalar.value)
    }

    private static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIDigit(scalar)
            || (65 ... 90).contains(scalar.value)
            || (97 ... 122).contains(scalar.value)
    }
}
