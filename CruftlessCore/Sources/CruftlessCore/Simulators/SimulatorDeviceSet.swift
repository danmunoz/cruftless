import Darwin
import Foundation

public enum SimulatorDeviceSetKind: String, Sendable, Hashable, Codable {
    case ordinary
    case xctest
}

public struct SimulatorDeviceSet: Sendable, Hashable, Identifiable {
    public let kind: SimulatorDeviceSetKind
    public let root: URL
    public let locationID: String
    public var id: String {
        kind.rawValue
    }

    package init(kind: SimulatorDeviceSetKind, root: URL) {
        self.kind = kind
        self.root = root.standardizedFileURL
        locationID = kind == .ordinary ? LocationCatalog.simulatorDevices.id : LocationCatalog.xctestDevices.id
    }

    public static func ordinary() -> Self {
        Self(
            kind: .ordinary,
            root: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(
                "Library/Developer/CoreSimulator/Devices",
                isDirectory: true
            )
        )
    }

    public static func xctest() -> Self {
        Self(
            kind: .xctest,
            root: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(
                "Library/Developer/XCTestDevices",
                isDirectory: true
            )
        )
    }

    public var isProductionRoot: Bool {
        let expected = kind == .ordinary ? Self.ordinary().root : Self.xctest().root
        guard root.standardizedFileURL == expected.standardizedFileURL else { return false }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in root.pathComponents.dropFirst() {
            current.appendPathComponent(component, isDirectory: true)
            var metadata = stat()
            guard lstat(current.path(percentEncoded: false), &metadata) == 0,
                  (metadata.st_mode & S_IFMT) != S_IFLNK else { return false }
        }
        return true
    }

    public var commandArguments: [String] {
        ["--set", root.path(percentEncoded: false)]
    }
}
