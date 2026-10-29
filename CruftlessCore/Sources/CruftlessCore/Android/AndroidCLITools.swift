import Darwin
import Foundation

public typealias AndroidCLIProcess = @Sendable (URL, [String], [String: String], Duration) async throws -> BoundedProcess.Output

public struct AndroidCLITool: Sendable, Hashable {
    public let executable: URL
    public let fingerprint: Fingerprint
}

public enum AndroidCLIToolAvailability: Sendable {
    case ready(AndroidCLITool)
    case setupRequired
}

public actor AndroidCLITools {
    public let home: URL
    public let androidUserHome: URL
    public let sdk: URL
    private let installDirectory: URL
    private let candidates: [URL]
    private let run: AndroidCLIProcess
    private let download: @Sendable (URL, URL) async throws -> Void
    private var prepared: AndroidCLITool?
    private var isPreparing = false

    public init(
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        androidUserHome: URL? = nil,
        sdk: URL? = nil,
        installDirectory: URL? = nil,
        candidates: [URL]? = nil,
        run: @escaping AndroidCLIProcess = { executable, arguments, environment, timeout in
            try await BoundedProcess.run(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
        },
        download: @escaping @Sendable (URL, URL) async throws -> Void = AndroidCLITools.downloadOfficialTool
    ) {
        self.home = home
        self.androidUserHome = androidUserHome ?? RootResolver.androidAVDRoots().first?.deletingLastPathComponent()
            ?? home.appendingPathComponent(".android", isDirectory: true)
        self.sdk = sdk ?? RootResolver.androidSDKRoots().first ?? home.appendingPathComponent("Library/Android/sdk", isDirectory: true)
        let directory = installDirectory ?? home.appendingPathComponent(
            "Library/Application Support/Cruftless/Android Tools",
            isDirectory: true
        )
        self.installDirectory = directory
        self.candidates = candidates ?? [directory.appendingPathComponent("android-cli"),
                                         home.appendingPathComponent(".local/bin/android"),
                                         home.appendingPathComponent(".android/bin/android-cli")]
        self.run = run
        self.download = download
    }

    public func availability() -> AndroidCLIToolAvailability {
        if let prepared, prepared.fingerprint.verify(at: prepared.executable) == .valid {
            return .ready(prepared)
        }
        guard let record = try? Data(contentsOf: markerURL),
              let receipt = try? JSONDecoder().decode(PreparationReceipt.self, from: record),
              receipt.userHome == ProtectedPaths.normalize(androidUserHome),
              let executable = candidates.first(where: { $0.path(percentEncoded: false) == receipt.path }),
              let tool = tool(at: executable), receipt.matches(tool.fingerprint)
        else { return .setupRequired }
        prepared = tool
        return .ready(tool)
    }

    /// Runs only after the user accepts tool installation and first-run setup.
    public func setUp() async throws -> AndroidCLITool {
        guard !isPreparing else { throw AndroidAVDRemovalError.refused("Android tools are already being prepared.") }
        isPreparing = true
        defer { isPreparing = false }
        try validateInstallDirectory()
        var executable = candidates.first(where: { tool(at: $0) != nil })
        if executable == nil {
            let destination = installDirectory.appendingPathComponent("android-cli")
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
                throw AndroidAVDRemovalError.refused("The Android tools installation path is occupied by an unsupported file.")
            }
            try await download(Self.downloadURL, destination)
            executable = destination
        }
        guard let executable, let candidate = tool(at: executable) else {
            throw AndroidAVDRemovalError.refused("The Android CLI executable could not be verified.")
        }
        let output = try await run(executable, ["--no-metrics", "--version"], environment(), .seconds(180))
        guard output.status == 0, output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil,
            candidate.fingerprint.verify(at: executable) == .valid
        else { throw AndroidAVDRemovalError.refused("Android tools could not complete setup. Try again before deleting the device.") }
        let receipt = PreparationReceipt(tool: candidate, userHome: ProtectedPaths.normalize(androidUserHome))
        try JSONEncoder().encode(receipt).write(to: markerURL, options: .atomic)
        prepared = candidate
        return candidate
    }

    public func verify(_ selected: AndroidCLITool) throws {
        guard case let .ready(current) = availability(), current == selected else { throw AndroidAVDRemovalError.toolsRequired }
    }

    public func invoke(_ tool: AndroidCLITool, arguments: [String], timeout: Duration) async throws -> BoundedProcess.Output {
        try verify(tool)
        return try await run(tool.executable, ["--no-metrics", "--sdk=" + sdk.path(percentEncoded: false)] + arguments,
                             environment(), timeout)
    }

    public func environment() -> [String: String] {
        var environment = BoundedProcess.minimalEnvironment()
        environment["HOME"] = home.path(percentEncoded: false)
        environment["ANDROID_USER_HOME"] = androidUserHome.path(percentEncoded: false)
        environment["ANDROID_HOME"] = sdk.path(percentEncoded: false)
        environment["ANDROID_SDK_ROOT"] = sdk.path(percentEncoded: false)
        return environment
    }

    public static var downloadURL: URL {
        #if arch(arm64)
            URL(string: "https://dl.google.com/android/cli/latest/darwin_arm64/android-cli")!
        #else
            URL(string: "https://dl.google.com/android/cli/latest/darwin_x86_64/android-cli")!
        #endif
    }

    private var markerURL: URL {
        installDirectory.appendingPathComponent("prepared.json")
    }

    private func tool(at executable: URL) -> AndroidCLITool? {
        var metadata = stat()
        guard executable.isFileURL, executable.path(percentEncoded: false).hasPrefix("/"),
              lstat(executable.path(percentEncoded: false), &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_uid == getuid(),
              metadata.st_mode & 0o022 == 0,
              FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false)),
              let fingerprint = Fingerprint.capture(at: executable)
        else { return nil }
        return AndroidCLITool(executable: executable, fingerprint: fingerprint)
    }

    private func validateInstallDirectory() throws {
        let path = installDirectory.path(percentEncoded: false)
        guard installDirectory.isFileURL, path.hasPrefix("/"),
              ProtectedPaths.standardize(installDirectory) == ProtectedPaths.normalize(installDirectory) else {
            throw AndroidAVDRemovalError.refused("The Android tools installation directory contains a symbolic link.")
        }
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var metadata = stat()
        guard lstat(path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == getuid(), metadata.st_mode & 0o022 == 0 else {
            throw AndroidAVDRemovalError.refused("The Android tools installation directory is not private to your account.")
        }
    }

    public static func downloadOfficialTool(from source: URL, to destination: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: source)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == "dl.google.com", response.url?.scheme == "https",
              !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw AndroidAVDRemovalError.refused("Android tools could not be downloaded from Google.")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path(percentEncoded: false))
    }
}

private struct PreparationReceipt: Codable {
    let path: String
    let userHome: String
    let inode: UInt64
    let device: Int32
    let modified: Date

    init(tool: AndroidCLITool, userHome: String) {
        path = tool.executable.path(percentEncoded: false)
        self.userHome = userHome
        inode = tool.fingerprint.inode
        device = tool.fingerprint.device
        modified = tool.fingerprint.modificationDate
    }

    func matches(_ fingerprint: Fingerprint) -> Bool {
        fingerprint.inode == inode && fingerprint.device == device && fingerprint.modificationDate == modified
    }
}
