import Foundation

/// Validates the identifiers handed to `simctl` before a process is spawned.
public enum SimctlIdentifier {
    private static let sentinels: Set<String> = ["all", "booted", "available", "unavailable"]

    /// A device UDID is a UUID, exactly.
    public static func validatedUDID(_ udid: String) throws -> String {
        guard let uuid = UUID(uuidString: udid) else {
            throw SimctlError.invalidIdentifier(udid)
        }
        return uuid.uuidString
    }

    /// A runtime is addressed by its UUID or by an identifier such as `com.apple.CoreSimulator.SimRuntime.iOS-26-0`.
    public static func validatedRuntime(_ identifier: String) throws -> String {
        if let uuid = UUID(uuidString: identifier) {
            return uuid.uuidString
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard !identifier.isEmpty,
              let first = identifier.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first),
              identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !sentinels.contains(identifier.lowercased())
        else {
            throw SimctlError.invalidIdentifier(identifier)
        }
        return identifier
    }
}
