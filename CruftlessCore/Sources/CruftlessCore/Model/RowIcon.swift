import Foundation

/// Represents an icon for a tracked location row: an SF Symbol name or a bundled asset image name.
public enum RowIcon: Sendable, Hashable, Codable {
    case symbol(String)
    case image(String)

    public var symbolName: String? {
        if case let .symbol(name) = self { return name }
        return nil
    }

    public var imageName: String? {
        if case let .image(name) = self { return name }
        return nil
    }
}
