import Foundation

public struct SimulatorRuntimeCatalog: Sendable, Equatable {
    public struct Runtime: Sendable, Equatable, Identifiable {
        public let identifier: String
        public let version: String
        public let build: String
        public let isAvailable: Bool
        public let availabilityError: String?
        public var id: String { "\(identifier)#\(build)" }

        public init(identifier: String, version: String, build: String, isAvailable: Bool, availabilityError: String? = nil) {
            self.identifier = identifier
            self.version = version
            self.build = build
            self.isAvailable = isAvailable
            self.availabilityError = availabilityError
        }
    }

    public let runtimes: [Runtime]
    public let toolchainID: String?
    public let toolchainGeneration: UUID?

    public init(runtimes: [Runtime], toolchainID: String? = nil, toolchainGeneration: UUID? = nil) {
        self.runtimes = runtimes
        self.toolchainID = toolchainID
        self.toolchainGeneration = toolchainGeneration
    }

    public init(jsonData: Data, toolchainID: String? = nil, toolchainGeneration: UUID? = nil) throws {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let values = root["runtimes"] as? [[String: Any]] else {
            throw SimctlError.invalidJSON("Expected runtimes array")
        }
        guard values.count <= 128 else { throw SimctlError.invalidJSON("Runtime catalog exceeds the supported entry limit") }
        var parsed: [Runtime] = []
        for value in values {
            guard let identifier = value["identifier"] as? String, !identifier.isEmpty,
                  let version = value["version"] as? String, !version.isEmpty,
                  let build = value["buildversion"] as? String, !build.isEmpty,
                  let available = value["isAvailable"] as? Bool else {
                throw SimctlError.invalidJSON("Runtime catalog contains an incomplete runtime")
            }
            parsed.append(Runtime(
                identifier: identifier,
                version: version,
                build: build,
                isAvailable: available,
                availabilityError: value["availabilityError"] as? String
            ))
        }
        self.runtimes = parsed
        self.toolchainID = toolchainID
        self.toolchainGeneration = toolchainGeneration
    }
}
