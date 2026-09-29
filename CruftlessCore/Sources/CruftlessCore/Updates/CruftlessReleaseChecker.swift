import Foundation

public struct CruftlessRelease: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL

    public init(version: String, releaseURL: URL) {
        self.version = version
        self.releaseURL = releaseURL
    }
}

public enum CruftlessReleaseCheckResult: Equatable, Sendable {
    case upToDate
    case updateAvailable(CruftlessRelease)
}

public enum CruftlessReleaseCheckError: Error {
    case missingInstalledVersion
    case invalidVersion
    case invalidResponse
}

public struct CruftlessReleaseChecker: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func checkForUpdates() async throws -> CruftlessReleaseCheckResult {
        guard let installedVersion = CruftlessVersion.shortVersion() else {
            throw CruftlessReleaseCheckError.missingInstalledVersion
        }
        guard let parsedInstalledVersion = ReleaseVersion(installedVersion) else {
            throw CruftlessReleaseCheckError.invalidVersion
        }

        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cruftless", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let latestRelease = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let parsedReleaseVersion = ReleaseVersion(latestRelease.tagName),
              latestRelease.htmlURL.scheme == "https",
              latestRelease.htmlURL.host == "github.com",
              latestRelease.htmlURL.path.hasPrefix("/danmunoz/cruftless/releases/")
        else {
            throw CruftlessReleaseCheckError.invalidResponse
        }

        guard parsedReleaseVersion > parsedInstalledVersion else {
            return .upToDate
        }

        return .updateAvailable(
            CruftlessRelease(
                version: parsedReleaseVersion.description,
                releaseURL: latestRelease.htmlURL
            )
        )
    }

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/danmunoz/cruftless/releases/latest"
    )!
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private struct ReleaseVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ component in
                  !component.isEmpty && component.utf8.allSatisfy { (48...57).contains($0) }
              }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
