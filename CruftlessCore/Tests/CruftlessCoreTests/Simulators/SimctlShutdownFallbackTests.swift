import CruftlessCore
import Foundation
import Testing

@Suite("simctl shutdown fallback")
struct SimctlShutdownFallbackTests {
    private let validUDID = "6E3C5A2B-1F0D-4E8A-9B7C-0123456789AB"

    @Test("Non-zero exit with the matching substring succeeds without consulting the plist")
    func matchingSubstringSucceeds() async throws {
        let executor = SimctlDouble(status: 1, stderr: "Unable to shutdown: current state: Shutdown")
        let readerCalled = CallFlag()
        let runner = SimctlRunner(executor: executor) { _ in
            readerCalled.set()
            return .booted
        }
        try await runner.shutdown(udid: validUDID)
        #expect(!readerCalled.value, "the fast substring path should short-circuit before the fallback runs")
    }

    @Test("Non-zero exit, no substring match, plist says shutdown succeeds")
    func fallbackSucceedsWhenPlistShutdown() async throws {
        let executor = SimctlDouble(status: 1, stderr: "Some reworded error")
        let runner = SimctlRunner(executor: executor) { udid in
            udid == validUDID ? .shutdown : nil
        }
        try await runner.shutdown(udid: validUDID)
    }

    @Test("Non-zero exit, no substring match, plist says booted fails")
    func fallbackFailsWhenPlistBooted() async {
        let executor = SimctlDouble(status: 1, stderr: "Some reworded error")
        let runner = SimctlRunner(executor: executor) { _ in .booted }
        await #expect(throws: SimctlError.self) {
            try await runner.shutdown(udid: validUDID)
        }
    }

    @Test("Non-zero exit, no substring match, unreadable plist fails")
    func fallbackFailsWhenPlistUnreadable() async {
        let executor = SimctlDouble(status: 1, stderr: "Some reworded error")
        let runner = SimctlRunner(executor: executor) { _ in nil }
        await #expect(throws: SimctlError.self) {
            try await runner.shutdown(udid: validUDID)
        }
    }
}

private final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false

    func set() {
        lock.lock()
        defer { lock.unlock() }
        called = true
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return called
    }
}
