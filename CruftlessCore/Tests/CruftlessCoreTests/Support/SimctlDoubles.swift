import CruftlessCore
import Foundation

final class SimctlDouble: SimctlExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<SimctlOutput, Error>]
    private var recordedArguments: [[String]] = []

    init(results: [Result<SimctlOutput, Error>]) {
        precondition(!results.isEmpty, "SimctlDouble needs at least one result to replay")
        self.results = results
    }

    convenience init(status: Int32 = 0, stdout: String = "{}", stderr: String = "") {
        self.init(results: [.success(SimctlOutput(status: status, stdout: stdout, stderr: stderr))])
    }

    convenience init(result: Result<SimctlOutput, Error>) {
        self.init(results: [result])
    }

    var arguments: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedArguments
    }

    func run(arguments: [String]) async throws -> SimctlOutput {
        let outcome = nextOutcome(for: arguments)
        switch outcome {
        case let .success(output):
            return output
        case let .failure(error):
            throw error
        }
    }

    private func nextOutcome(for arguments: [String]) -> Result<SimctlOutput, Error> {
        lock.lock()
        defer { lock.unlock() }
        recordedArguments.append(arguments)
        if results.count > 1 {
            return results.removeFirst()
        }
        return results.first ?? .success(SimctlOutput(status: 0, stdout: "{}", stderr: ""))
    }
}
