import CruftlessCore
import Foundation
import Testing

@Suite("BoundedProcess termination waiter")
struct BoundedProcessTerminationTests {
    @Test("An unfinished child is signalled")
    func signalsWhileUnreaped() {
        let waiter = TerminationWaiter()
        var signalled: [pid_t] = []

        waiter.forceKillIfUnfinished(pid: 424_242) { signalled.append($0) }

        #expect(signalled == [424_242])
    }

    @Test("A child whose termination handler already fired is never signalled")
    func doesNotSignalAfterReaping() {
        let waiter = TerminationWaiter()
        var signalled: [pid_t] = []

        waiter.finish(0)
        waiter.forceKillIfUnfinished(pid: 424_242) { signalled.append($0) }

        #expect(signalled.isEmpty, "SIGKILL sent to a pid the OS may already have recycled")
    }

    @Test("A signalled-but-reaped child is not signalled again")
    func doesNotEscalateAfterSignalledExit() {
        let waiter = TerminationWaiter()
        var signalled: [pid_t] = []

        waiter.finish(SIGTERM)
        waiter.forceKillIfUnfinished(pid: 424_242) { signalled.append($0) }
        waiter.forceKillIfUnfinished(pid: 424_242) { signalled.append($0) }

        #expect(signalled.isEmpty)
    }

    @Test("The waiter still delivers the status to a caller that arrives late")
    func deliversStatusAfterFinish() async {
        let waiter = TerminationWaiter()
        waiter.finish(3)
        #expect(await waiter.wait() == 3)
    }
}
