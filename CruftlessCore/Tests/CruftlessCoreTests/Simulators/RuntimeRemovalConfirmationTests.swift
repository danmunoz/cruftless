import CruftlessCore
import Foundation
import Testing

@Suite("Runtime removal is confirmed, not assumed")
struct RuntimeRemovalConfirmationTests {
    private static let uuid = "A93FB899-77F0-41C3-9A0C-45D22BFA0A93"
    private static let bundleId = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"

    private static func listOutput(state: String = "Ready", present: Bool = true) -> SimctlOutput {
        guard present else { return SimctlOutput(status: 0, stdout: "{}", stderr: "") }
        let json = """
        {"\(uuid)": {"runtimeIdentifier": "\(bundleId)", "build": "23F77",
         "sizeBytes": 8494282293, "deletable": true, "state": "\(state)"}}
        """
        return SimctlOutput(status: 0, stdout: json, stderr: "")
    }

    private static let installation = SimRuntimeInstallation(identifier: bundleId, build: "23F77")
    private static let emptyInstalled = SimctlOutput(status: 0, stdout: #"{"runtimes":[]}"#, stderr: "")

    private static let deleteAccepted = SimctlOutput(status: 0, stdout: "", stderr: "")

    // MARK: - Waiting for the list to agree

    @Test("A runtime still listed after the delete keeps the wait going, then fails to confirm")
    func stillListedNeverReportsSuccess() async {
        let executor = SimctlDouble(results: [.success(Self.listOutput())])
        let runner = SimctlRunner(executor: executor)

        await #expect(throws: SimctlError.removalNotConfirmed(Self.uuid)) {
            try await runner.awaitRuntimeRemoval(
                identifier: Self.uuid,
                installation: Self.installation,
                timeout: .milliseconds(30),
                pollInterval: .milliseconds(5)
            )
        }
        #expect(executor.arguments.count > 1)
        #expect(executor.arguments.allSatisfy { $0 == ["runtime", "list", "-j"] })
    }

    @Test("The wait ends as soon as the runtime leaves the list")
    func leavingTheListConfirmsRemoval() async throws {
        let executor = SimctlDouble(results: [
            .success(Self.listOutput()),
            .success(Self.listOutput(state: "Deleting")),
            .success(Self.listOutput(present: false)),
            .success(Self.emptyInstalled)
        ])
        let runner = SimctlRunner(executor: executor)

        try await runner.awaitRuntimeRemoval(
            identifier: Self.uuid,
            installation: Self.installation,
            timeout: .seconds(5),
            pollInterval: .milliseconds(1)
        )
        #expect(executor.arguments.count == 4)
    }

    @Test("A Deleting entry does not count as removed")
    func deletingStateIsNotRemoved() async {
        let executor = SimctlDouble(results: [.success(Self.listOutput(state: "Deleting"))])
        let runner = SimctlRunner(executor: executor)

        await #expect(throws: SimctlError.removalNotConfirmed(Self.uuid)) {
            try await runner.awaitRuntimeRemoval(
                identifier: Self.uuid,
                installation: Self.installation,
                timeout: .milliseconds(20),
                pollInterval: .milliseconds(5)
            )
        }
    }

    @Test("The bundle identifier matches the same runtime as its UUID")
    func matchesEitherIdentifierForm() async {
        let executor = SimctlDouble(results: [.success(Self.listOutput())])
        let runner = SimctlRunner(executor: executor)

        await #expect(throws: SimctlError.removalNotConfirmed(Self.bundleId)) {
            try await runner.awaitRuntimeRemoval(
                identifier: Self.bundleId,
                installation: Self.installation,
                timeout: .milliseconds(20),
                pollInterval: .milliseconds(5)
            )
        }
    }

    @Test("A failed lookup is not evidence of removal")
    func failedLookupDoesNotConfirm() async {
        let executor = SimctlDouble(result: .failure(SimctlError.executionError("no simctl")))
        let runner = SimctlRunner(executor: executor)

        await #expect(throws: SimctlError.removalNotConfirmed(Self.uuid)) {
            try await runner.awaitRuntimeRemoval(
                identifier: Self.uuid,
                installation: Self.installation,
                timeout: .milliseconds(20),
                pollInterval: .milliseconds(5)
            )
        }
    }

    // MARK: - The command executor the app actually uses

    @Test("deleteRuntime sends the delete and then confirms the runtime is gone")
    func adapterConfirmsAfterDeleting() async throws {
        let executor = SimctlDouble(results: [
            .success(Self.deleteAccepted),
            .success(Self.listOutput(present: false)),
            .success(Self.emptyInstalled)
        ])
        let commands = DefaultSimulatorCommandExecutor(runner: SimctlRunner(executor: executor))

        try await commands.deleteRuntime(identifier: Self.uuid, installation: Self.installation)

        #expect(executor.arguments == [
            ["runtime", "delete", Self.uuid],
            ["runtime", "list", "-j"],
            ["list", "runtimes", "-j"]
        ])
    }

    // MARK: - Planning against a runtime already on its way out

    @Test("A runtime CoreSimulator is still removing cannot be deleted again")
    func planningRefusesARuntimeBeingDeleted() throws {
        let runtime = SimRuntime(
            identifier: Self.uuid,
            runtimeIdentifier: Self.bundleId,
            name: "iOS 26.5",
            build: "23F77",
            sizeBytes: 8_494_282_293,
            isDeletable: true,
            state: .deleting
        )
        #expect(!runtime.canPlanDelete)

        #expect(throws: DeletionPlanningError.runtimeBeingDeleted(name: "iOS 26.5")) {
            try DeletionPlanner.runtimeDelete(runtime, context: PlanningContext(protectedPaths: ProtectedPaths()))
        }
    }

    // MARK: - Where the state comes from

    @Test("simctl's state field reaches the runtime")
    func listRuntimesParsesState() async throws {
        let executor = SimctlDouble(result: .success(Self.listOutput(state: "Deleting")))
        let runtimes = try await SimctlRunner(executor: executor).listRuntimes()

        #expect(runtimes.count == 1)
        #expect(runtimes[0].state == .deleting)
        #expect(runtimes[0].state.isBeingDeleted)
    }

    @Test("An unmodelled state is carried, not read as Ready")
    func unknownStateIsNotReady() {
        #expect(SimRuntimeState(simctlValue: "Preparing") == .other("preparing"))
        #expect(SimRuntimeState(simctlValue: nil) == .unreported)
        #expect(!SimRuntimeState(simctlValue: "Preparing").isBeingDeleted)
        #expect(!SimRuntimeState(simctlValue: "Unusable").isBeingDeleted)
    }

    @Test("A management UUID disappearing does not confirm a build still installed")
    func installedMembershipPreventsFalseSuccess() async {
        let installed = SimctlOutput(
            status: 0,
            stdout: #"""
            {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","version":"26.5",
            "buildversion":"23F77","isAvailable":true}]}
            """#,
            stderr: ""
        )
        let executor = SimctlDouble(results: [.success(Self.listOutput(present: false)), .success(installed)])
        await #expect(throws: SimctlError.removalNotConfirmed(Self.uuid)) {
            try await SimctlRunner(executor: executor).awaitRuntimeRemoval(identifier: Self.uuid, installation: Self.installation,
                                                                           timeout: .milliseconds(10), pollInterval: .milliseconds(1))
        }
        #expect(executor.arguments.contains(["list", "runtimes", "-j"]))
    }

    @Test("An unrelated installed build does not prevent exact-build confirmation")
    func unrelatedBuildMayRemain() async throws {
        let installed = SimctlOutput(
            status: 0,
            stdout: #"""
            {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","version":"26.5",
            "buildversion":"23F99","isAvailable":true}]}
            """#,
            stderr: ""
        )
        let executor = SimctlDouble(results: [.success(Self.listOutput(present: false)), .success(installed)])
        try await SimctlRunner(executor: executor).awaitRuntimeRemoval(identifier: Self.uuid, installation: Self.installation,
                                                                       timeout: .milliseconds(10), pollInterval: .milliseconds(1))
    }

    @Test("The production adapter refuses receiptless runtime removal")
    func receiptlessAdapterRefuses() async {
        let executor = SimctlDouble(result: .success(Self.deleteAccepted))
        let commands = DefaultSimulatorCommandExecutor(runner: SimctlRunner(executor: executor))
        await #expect(throws: SimctlError.self) { try await commands.deleteRuntime(identifier: Self.uuid) }
        #expect(executor.arguments.isEmpty)
    }
}
