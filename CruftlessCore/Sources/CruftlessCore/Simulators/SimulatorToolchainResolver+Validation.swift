import Darwin
import Foundation

extension SimulatorToolchainResolver {
    struct CandidateMetadata: Sendable {
        let appURL: URL
        let developerDirectory: URL
        let version: String?
    }

    static func validate(candidate: URL) async -> SimulatorToolchain? {
        guard let metadata = await inspect(candidate: candidate) else { return nil }
        let app = metadata.appURL
        let developer = metadata.developerDirectory

        var environment = BoundedProcess.minimalEnvironment()
        environment["DEVELOPER_DIR"] = developer.path
        do {
            let result = try await BoundedProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["--find", "simctl"],
                environment: environment,
                timeout: probeTimeout
            )
            guard result.status == 0,
                  canonicalPath(URL(fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))) ==
                    canonicalPath(developer.appendingPathComponent("usr/bin/simctl"))
            else { return nil }

            let runtimeList = try await BoundedProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["simctl", "runtime", "list", "-j"],
                environment: environment,
                timeout: probeTimeout
            )
            guard runtimeList.status == 0,
                  let data = runtimeList.stdout.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) is [String: [String: Any]]
            else { return nil }

            return SimulatorToolchain(
                id: canonicalPath(app),
                appURL: app,
                developerDirectory: developer,
                version: metadata.version
            )
        } catch {
            return nil
        }
    }

    static func inspect(candidate: URL) async -> CandidateMetadata? {
        await withCheckedContinuation { continuation in
            validationQueue.async {
                let app = candidate.standardizedFileURL
                let developer = app.appendingPathComponent("Contents/Developer", isDirectory: true)
                let info = app.appendingPathComponent("Contents/Info.plist")
                guard let dictionary = readInfoDictionary(at: info),
                      dictionary["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode",
                      FileManager.default.isExecutableFile(atPath: developer.appendingPathComponent("usr/bin/simctl").path)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: CandidateMetadata(
                    appURL: app,
                    developerDirectory: developer,
                    version: dictionary["CFBundleShortVersionString"] as? String
                ))
            }
        }
    }

    static func readSelectedDirectory() async -> URL? {
        do {
            let output = try await BoundedProcess.run(
                executable: URL(fileURLWithPath: "/usr/bin/xcode-select"),
                arguments: ["--print-path"],
                environment: BoundedProcess.minimalEnvironment(),
                timeout: probeTimeout
            )
            guard output.status == 0 else { return nil }
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasSuffix("/Contents/Developer") else { return nil }
            return URL(fileURLWithPath: String(path.dropLast("/Contents/Developer".count)), isDirectory: true)
        } catch {
            return nil
        }
    }

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    package static func readInfoDictionary(at url: URL) -> [String: Any]? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= 65_536
        else { return nil }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard count > 0 else { break }
            guard data.count + count <= 65_536 else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}
