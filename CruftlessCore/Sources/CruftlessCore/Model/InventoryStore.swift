import Foundation

/// Where the last scan's rows are kept between launches.
public struct InventoryStore: Sendable {
    private let fileURL: URL?

    /// - Parameter directory: where `inventory.json` lives.
    public init(directory: URL? = nil) {
        let resolved = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Cruftless", isDirectory: true)
        fileURL = resolved?.appendingPathComponent("inventory.json", isDirectory: false)
    }

    public func load() -> InventorySnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(InventorySnapshot.self, from: data)
    }

    public func save(_ snapshot: InventorySnapshot) {
        guard let fileURL, let data = try? Self.encoder.encode(snapshot) else { return }

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
