import Foundation

/// A release of Google's Android CLI, as printed by `android --version`.
public struct AndroidCLIVersion: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let components: [Int]

    /// The oldest release whose `sdk remove` behaviour Cruftless has verified.
    public static let minimumForSDKRemoval = AndroidCLIVersion(components: [1, 1, 16_919_734])

    public init(components: [Int]) {
        self.components = components
    }

    /// Parses the first line of `--version` output, ignoring the update notice that may follow it.
    public init?(versionOutput: String) {
        guard let line = versionOutput.split(whereSeparator: \.isNewline).first?
            .trimmingCharacters(in: .whitespaces),
            line.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
        else { return nil }
        let parts = line.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        components = parts
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
