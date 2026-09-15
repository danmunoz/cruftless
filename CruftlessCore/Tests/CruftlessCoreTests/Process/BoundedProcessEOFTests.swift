import CruftlessCore
import Foundation
import Testing

@Suite("BoundedProcess EOF wait")
struct BoundedProcessEOFTests {
    private static let environment = BoundedProcess.minimalEnvironment()

    @Test("A child whose pipes close returns on EOF, without paying the grace")
    func promptOnEOF() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let output = try await BoundedProcess.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"],
            environment: Self.environment,
            timeout: .seconds(60),
            eofGrace: .seconds(30)
        )
        let elapsed = clock.now - start

        #expect(output.status == 0)
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
        #expect(elapsed < .seconds(10), "paid the grace: \(elapsed)")
    }

    @Test("A stream that never closes is bounded by the EOF grace", .timeLimit(.minutes(1)))
    func boundedWhenStreamNeverCloses() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let output = try await BoundedProcess.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo early; /bin/sleep 20 & exit 0"],
            environment: Self.environment,
            timeout: .seconds(30)
        )
        let elapsed = clock.now - start

        #expect(output.status == 0)
        #expect(output.stdout.contains("early"))
        #expect(elapsed > .milliseconds(1500), "returned before the grace elapsed: \(elapsed)")
        #expect(elapsed < .seconds(10), "was not bounded: \(elapsed)")
    }
}
