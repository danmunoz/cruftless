import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("SimulatorService.runtimes() source reconciliation")
struct SimulatorServiceRuntimesTests {
    private func writePlist(runtimes: [(bundleId: String, build: String)], in directory: URL) throws -> URL {
        let images = runtimes.map { runtime in
            [
                "runtimeInfo": [
                    "bundleIdentifier": runtime.bundleId,
                    "build": runtime.build
                ]
            ] as [String: Any]
        }
        let dict: [String: Any] = ["images": images]
        let url = directory.appendingPathComponent("images.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func simctlListRuntimesOutput(bundleId: String, uuid: String = UUID().uuidString) -> SimctlOutput {
        let json = """
        {"\(uuid)": {"runtimeIdentifier": "\(bundleId)", "build": "1A", "sizeBytes": 100, "deletable": true}}
        """
        return SimctlOutput(status: 0, stdout: json, stderr: "")
    }

    @Test("Both sources succeed: results are unioned, plist owns the naming fields on overlap")
    func bothSucceedUnionsPreferringPlistNaming() async throws {
        let dir = try tempDirectory()
        defer { TestFileSystem.removeDirectoryRecursively(at: dir) }
        let plistURL = try writePlist(
            runtimes: [(bundleId: "com.apple.CoreSimulator.SimRuntime.iOS-18-6", build: "PLIST-BUILD")],
            in: dir
        )

        let uuid1 = UUID().uuidString
        let uuid2 = UUID().uuidString
        let json = """
        {
            "\(uuid1)": {
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
                "build": "SIMCTL-BUILD", "sizeBytes": 1, "deletable": true
            },
            "\(uuid2)": {
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-0",
                "build": "2B", "sizeBytes": 2, "deletable": true
            }
        }
        """
        let executor = SimctlDouble(result: .success(SimctlOutput(status: 0, stdout: json, stderr: "")))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: plistURL)

        let runtimes = try await service.runtimes()
        let byID = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.runtimeIdentifier, $0) })

        #expect(runtimes.count == 2)
        #expect(byID["com.apple.CoreSimulator.SimRuntime.iOS-18-6"]?.build == "PLIST-BUILD")
        #expect(byID["com.apple.CoreSimulator.SimRuntime.iOS-17-0"]?.build == "2B")
    }

    @Test("Plist has entries, simctl fails: plist entries are returned, not an error")
    func plistSucceedsSimctlFailsReturnsPlist() async throws {
        let dir = try tempDirectory()
        defer { TestFileSystem.removeDirectoryRecursively(at: dir) }
        let plistURL = try writePlist(
            runtimes: [(bundleId: "com.apple.CoreSimulator.SimRuntime.iOS-18-6", build: "PLIST-BUILD")],
            in: dir
        )

        let executor = SimctlDouble(result: .failure(SimctlError.nonZeroExit(exitCode: 1, message: "boom")))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: plistURL)

        let runtimes = try await service.runtimes()
        #expect(runtimes.count == 1)
        #expect(runtimes.first?.build == "PLIST-BUILD")
    }

    @Test("Plist is missing, simctl succeeds: simctl's list is authoritative, including empty")
    func plistMissingSimctlSucceedsReturnsSimctl() async throws {
        let missingPlistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("images.plist")

        let output = simctlListRuntimesOutput(bundleId: "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
        let executor = SimctlDouble(result: .success(output))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: missingPlistURL)

        let runtimes = try await service.runtimes()
        #expect(runtimes.count == 1)
        #expect(runtimes.first?.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-0")

        let emptyExecutor = SimctlDouble(result: .success(SimctlOutput(status: 0, stdout: "{}", stderr: "")))
        let emptyService = SimulatorService(simctlRunner: SimctlRunner(executor: emptyExecutor), imagesPlistURL: missingPlistURL)
        let emptyRuntimes = try await emptyService.runtimes()
        #expect(emptyRuntimes.isEmpty)
    }

    @Test("Plist is missing and simctl fails: throws runtimesUnavailable instead of returning []")
    func bothFailThrows() async throws {
        let missingPlistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("images.plist")

        let executor = SimctlDouble(result: .failure(SimctlError.executionError("xcrun not found")))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: missingPlistURL)

        await #expect(throws: SimulatorServiceError.self) {
            _ = try await service.runtimes()
        }
    }

    @Test("Overlapping runtime keeps simctl's size, not the plist's zero")
    func overlapTakesSimctlSize() async throws {
        let dir = try tempDirectory()
        defer { TestFileSystem.removeDirectoryRecursively(at: dir) }
        let bundleId = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
        let plistURL = try writePlist(runtimes: [(bundleId: bundleId, build: "24A5423a")], in: dir)

        let uuid = UUID().uuidString
        let json = """
        {"\(uuid)": {"runtimeIdentifier": "\(bundleId)", "build": "24A5423a", "sizeBytes": 8014997345, "deletable": true}}
        """
        let executor = SimctlDouble(result: .success(SimctlOutput(status: 0, stdout: json, stderr: "")))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: plistURL)

        let runtime = try #require(try await service.runtimes().first)
        #expect(runtime.sizeBytes == 8_014_997_345)
    }

    @Test("Overlapping runtime keeps simctl's UUID identifier for the delete call")
    func overlapTakesSimctlIdentifier() async throws {
        let dir = try tempDirectory()
        defer { TestFileSystem.removeDirectoryRecursively(at: dir) }
        let bundleId = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
        let plistURL = try writePlist(runtimes: [(bundleId: bundleId, build: "24A5423a")], in: dir)

        let uuid = UUID().uuidString
        let executor = SimctlDouble(result: .success(simctlListRuntimesOutput(bundleId: bundleId, uuid: uuid)))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: plistURL)

        let runtime = try #require(try await service.runtimes().first)
        #expect(runtime.identifier == uuid)
        #expect(runtime.runtimeIdentifier == bundleId)
    }

    @Test("Overlapping runtime keeps simctl's deletable flag")
    func overlapTakesSimctlDeletableFlag() async throws {
        let dir = try tempDirectory()
        defer { TestFileSystem.removeDirectoryRecursively(at: dir) }
        let bundleId = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"
        let plistURL = try writePlist(runtimes: [(bundleId: bundleId, build: "22G86")], in: dir)

        let json = """
        {"\(UUID().uuidString)": {"runtimeIdentifier": "\(bundleId)", "build": "22G86", "sizeBytes": 10, "deletable": false}}
        """
        let executor = SimctlDouble(result: .success(SimctlOutput(status: 0, stdout: json, stderr: "")))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: plistURL)

        let runtime = try #require(try await service.runtimes().first)
        #expect(runtime.isDeletable == false)
    }

    @Test("Overlapping runtime keeps the plist size when simctl reports none")
    func overlapKeepsPlistSizeWhenSimctlReportsZero() async throws {
        let dir = try tempDirectory()
        defer { TestFileSystem.removeDirectoryRecursively(at: dir) }
        let bundleId = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"

        let imageFile = dir.appendingPathComponent("iOS 18.6.dmg")
        try Data(repeating: 0, count: 8192).write(to: imageFile)
        let plistDict: [String: Any] = [
            "images": [
                [
                    "path": ["relative": "file://\(dir.path)/iOS%2018.6.dmg"],
                    "runtimeInfo": ["build": "22G86", "bundleIdentifier": bundleId]
                ] as [String: Any]
            ]
        ]
        let plistURL = dir.appendingPathComponent("images.plist")
        try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0).write(to: plistURL)

        let json = """
        {"\(UUID().uuidString)": {"runtimeIdentifier": "\(bundleId)", "build": "22G86", "sizeBytes": 0, "deletable": true}}
        """
        let executor = SimctlDouble(result: .success(SimctlOutput(status: 0, stdout: json, stderr: "")))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: plistURL)

        let runtime = try #require(try await service.runtimes().first)
        #expect(runtime.sizeBytes > 0)
    }

    @Test("devices() propagates the runtimesUnavailable failure instead of flagging every device")
    func devicesPropagatesRuntimeFailure() async throws {
        let missingPlistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("images.plist")
        let executor = SimctlDouble(result: .failure(SimctlError.executionError("xcrun not found")))
        let service = SimulatorService(simctlRunner: SimctlRunner(executor: executor), imagesPlistURL: missingPlistURL)

        await #expect(throws: SimulatorServiceError.self) {
            _ = try await service.devices()
        }
    }
}
