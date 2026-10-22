import Darwin
import Foundation

private enum PathAbsence: Sendable {
    case absent
    case present
    case indeterminate
}

extension DeletionExecutor {
    func executeXCTestSimulatorDelete(
        _ target: DeletionTarget,
        policyGeneration: UInt64,
        affectedLocationIds: Set<String>
    ) async -> ItemOutcome {
        guard case let .xctestSimulatorDelete(deviceSet, udid, directory, deviceFingerprint, plistFingerprint, name, _, bytes) = target
        else {
            return ItemOutcome(target: target, status: .failed(reason: "Refused: invalid test simulator target."), freedBytes: 0)
        }
        report(DeletionProgress(verb: .delete, targetName: name, phase: .mutating))
        let baselineFree = await capacitySampler()
        guard policyGenerationAuthority.withCurrentGeneration(
            policyGeneration,
            affectedLocationIDs: affectedLocationIds,
            admission: { true }
        ) == true,
            validateXCTestTarget(deviceSet: deviceSet, udid: udid, directory: directory,
                                 deviceFingerprint: deviceFingerprint, plistFingerprint: plistFingerprint) else {
            return ItemOutcome(
                target: target,
                status: .failed(reason: "Refused: test simulator identity, protection, or policy changed after review."),
                freedBytes: 0
            )
        }
        do {
            try await simulatorExecutor.deleteTestSimulator(udid: udid, deviceSet: deviceSet)
        } catch {
            return ItemOutcome(target: target, status: .failed(reason: error.localizedDescription), freedBytes: 0)
        }
        let deadline = ContinuousClock.now + xctestConfirmationTimeout
        while ContinuousClock.now < deadline {
            let absence = await Self.offCooperativePool { Self.pathAbsence(directory) }
            if absence == .absent {
                let settle = await waitForSpaceToSettle(
                    verb: .delete,
                    targetName: name,
                    expectedBytes: bytes,
                    baselineFreeBytes: baselineFree
                )
                return ItemOutcome(target: target, status: .succeeded, freedBytes: bytes, spaceSettle: settle)
            }
            if absence == .indeterminate {
                return ItemOutcome(
                    target: target,
                    status: .failed(reason: "Removal could not be confirmed because the test simulator path is unreadable."),
                    freedBytes: 0
                )
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                break
            }
        }
        return ItemOutcome(target: target, status: .failed(reason: "simctl did not confirm removal of this test simulator."), freedBytes: 0)
    }

    private func validateXCTestTarget(
        deviceSet: SimulatorDeviceSet,
        udid: String,
        directory: URL,
        deviceFingerprint: Fingerprint,
        plistFingerprint: Fingerprint
    ) -> Bool {
        let expected = deviceSet.root.appendingPathComponent(udid, isDirectory: true).standardizedFileURL
        guard deviceSet.kind == .xctest, deviceSet.isProductionRoot, directory.standardizedFileURL == expected,
              deviceFingerprint.verify(at: directory) == .valid,
              plistFingerprint.verify(at: directory.appendingPathComponent("device.plist")) == .valid,
              let device = DeviceStore.parseDevicePlist(at: directory.appendingPathComponent("device.plist"),
                                                        deviceDirectory: directory, deviceSet: deviceSet),
              device.udid == udid, device.state.isShutdown else { return false }
        let currentProtection = protectedPathsStore.protectedPaths()
        return !currentProtection.intersectsCustomProtection(directory)
            && !currentProtection.containsCustomProtectedPath(in: directory)
    }

    nonisolated private static func pathAbsence(_ url: URL) -> PathAbsence {
        var value = stat()
        if lstat(url.path(percentEncoded: false), &value) == 0 { return .present }
        return errno == ENOENT || errno == ENOTDIR ? .absent : .indeterminate
    }
}
