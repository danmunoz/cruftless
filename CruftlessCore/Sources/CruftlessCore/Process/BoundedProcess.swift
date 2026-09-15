import Foundation

public enum BoundedProcess {
    public struct Output: Sendable {
        public let status: Int32
        public let stdoutData: Data
        public let stderrData: Data

        public init(status: Int32, stdoutData: Data, stderrData: Data) {
            self.status = status
            self.stdoutData = stdoutData
            self.stderrData = stderrData
        }

        public var stdout: String {
            String(data: stdoutData, encoding: .utf8) ?? ""
        }

        public var stderr: String {
            String(data: stderrData, encoding: .utf8) ?? ""
        }
    }

    public enum RunError: Error, Sendable, Equatable {
        case executionFailed(String)
        case timedOut(String)
    }

    /// A minimal, known child environment.
    public static func minimalEnvironment(
        from inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let passthrough = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"]
        var environment: [String: String] = [:]
        for key in passthrough {
            if let value = inherited[key] {
                environment[key] = value
            }
        }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        return environment
    }

    /// How long a timed-out child gets to honour SIGTERM before SIGKILL.
    public static let defaultTerminationGrace: Duration = .seconds(5)

    /// Runs `executable` with `arguments` and `environment`, verbatim: no PATH resolution, no inherited environment.
    public static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        terminationGrace: Duration = defaultTerminationGrace,
        onLaunch: (@Sendable (pid_t) -> Void)? = nil
    ) async throws -> Output {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            terminationGrace: terminationGrace,
            onLaunch: onLaunch,
            eofGrace: OutputCollector.defaultEOFGrace
        )
    }

    package static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        terminationGrace: Duration = defaultTerminationGrace,
        onLaunch: (@Sendable (pid_t) -> Void)? = nil,
        eofGrace: Duration
    ) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let collector = OutputCollector(eofGrace: eofGrace)
        drain(outPipe, into: collector, isStdout: true)
        drain(errPipe, into: collector, isStdout: false)

        func detachHandlers() {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            collector.finishAll()
        }

        let waiter = TerminationWaiter()
        process.terminationHandler = { finished in
            waiter.finish(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            detachHandlers()
            throw RunError.executionFailed(error.localizedDescription)
        }

        onLaunch?(process.processIdentifier)

        let status: Int32
        do {
            status = try await exitStatus(
                of: process,
                waiter: waiter,
                timeout: timeout,
                terminationGrace: terminationGrace,
                arguments: arguments
            )
        } catch {
            detachHandlers()
            throw error
        }

        await collector.waitForEOF()
        detachHandlers()

        return Output(status: status, stdoutData: collector.stdoutData, stderrData: collector.stderrData)
    }

    /// Drains a pipe on its own thread.
    private static func drain(_ pipe: Pipe, into collector: OutputCollector, isStdout: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                collector.finish(isStdout: isStdout)
            } else {
                collector.append(data, isStdout: isStdout)
            }
        }
    }

    private static func exitStatus(
        of process: Process,
        waiter: TerminationWaiter,
        timeout: Duration,
        terminationGrace: Duration,
        arguments: [String]
    ) async throws -> Int32 {
        let timedOut = AtomicFlag()
        let pid = process.processIdentifier
        let killer = Task {
            try await Task.sleep(for: timeout)
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            try await Task.sleep(for: terminationGrace)
            waiter.forceKillIfUnfinished(pid: pid)
        }
        defer { killer.cancel() }

        // A cancelled caller (the popover closed mid-delete) should not leave the child running either.
        let status = await withTaskCancellationHandler {
            await waiter.wait()
        } onCancel: {
            process.terminate()
        }

        if shouldReportTimeout(timedOut: timedOut.isSet, terminationReason: process.terminationReason) {
            throw RunError.timedOut(arguments.joined(separator: " "))
        }
        return status
    }

    package static func shouldReportTimeout(timedOut: Bool, terminationReason: Process.TerminationReason) -> Bool {
        guard timedOut else { return false }
        return terminationReason == .uncaughtSignal
    }
}

/// Bridges `Process.terminationHandler` to `await`, tolerating either order: the handler may fire before anyone is waiting.
package final class TerminationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    package init() {}

    package func finish(_ terminationStatus: Int32) {
        lock.lock()
        status = terminationStatus
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: terminationStatus)
    }

    package func forceKillIfUnfinished(pid: pid_t, send: (pid_t) -> Void = { kill($0, SIGKILL) }) {
        lock.lock()
        defer { lock.unlock() }
        guard status == nil else { return }
        send(pid)
    }

    package func wait() async -> Int32 {
        await withCheckedContinuation { pending in
            lock.lock()
            if let status {
                lock.unlock()
                pending.resume(returning: status)
            } else {
                continuation = pending
                lock.unlock()
            }
        }
    }
}

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Holds a continuation that two racing callbacks may both try to resume.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}

/// Accumulates the two pipe streams from the reader threads.
package final class OutputCollector: @unchecked Sendable {
    /// How long the final EOF callbacks get to land after the child exits.
    package static let defaultEOFGrace: Duration = .seconds(2)

    /// Serialises the group's `notify` against the deadline timer, so the two racers can never fire on top of each other.
    private static let eofQueue = DispatchQueue(label: "com.cruftless.core.bounded-process.eof")

    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var stdoutFinished = false
    private var stderrFinished = false
    private let group = DispatchGroup()

    private let eofGrace: Duration

    package init(eofGrace: Duration = OutputCollector.defaultEOFGrace) {
        self.eofGrace = eofGrace
        group.enter()
        group.enter()
    }

    func append(_ data: Data, isStdout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if isStdout {
            stdout.append(data)
        } else {
            stderr.append(data)
        }
    }

    /// Retires one stream's `enter()`.
    package func finish(isStdout: Bool) {
        lock.lock()
        let alreadyFinished = isStdout ? stdoutFinished : stderrFinished
        if isStdout {
            stdoutFinished = true
        } else {
            stderrFinished = true
        }
        lock.unlock()
        guard !alreadyFinished else { return }
        group.leave()
    }

    package func finishAll() {
        finish(isStdout: true)
        finish(isStdout: false)
    }

    package func waitForEOF() async {
        let graceInSeconds = Double(eofGrace.components.seconds)
            + Double(eofGrace.components.attoseconds) * 1e-18

        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            group.notify(queue: Self.eofQueue) { once.resume() }
            Self.eofQueue.asyncAfter(deadline: .now() + graceInSeconds) { once.resume() }
        }
    }

    var stdoutData: Data {
        lock.lock()
        defer { lock.unlock() }
        return stdout
    }

    var stderrData: Data {
        lock.lock()
        defer { lock.unlock() }
        return stderr
    }
}
