import CruftlessCore
import Foundation
import Testing

@Suite("BoundedProcess output collector EOF accounting")
struct BoundedProcessOutputCollectorTests {
    private static let stretchedGrace: Duration = .seconds(30)

    private static let promptly: Duration = .seconds(5)

    private func completingCollector() -> OutputCollector {
        OutputCollector(eofGrace: Self.stretchedGrace)
    }

    @Test("Finishing one stream twice leaves the group exactly once")
    func repeatedFinishForOneStreamIsIdempotent() async {
        let collector = completingCollector()

        collector.finish(isStdout: true)
        collector.finish(isStdout: true)
        collector.finish(isStdout: false)

        let clock = ContinuousClock()
        let start = clock.now
        await collector.waitForEOF()
        #expect(clock.now - start < Self.promptly, "the group never completed; the wait paid the EOF grace")
    }

    @Test("One stream finished is not enough: the wait is still bounded by the grace")
    func oneStreamAloneDoesNotCompleteTheGroup() async {
        let shortGrace: Duration = .milliseconds(400)
        let collector = OutputCollector(eofGrace: shortGrace)
        collector.finish(isStdout: true)

        let clock = ContinuousClock()
        let start = clock.now
        await collector.waitForEOF()
        #expect(
            clock.now - start >= shortGrace / 2,
            "the group completed with a stream still open"
        )
    }

    @Test("Finishing all streams after a partial finish completes the group")
    func finishAllRetiresTheRemainingStream() async {
        let collector = completingCollector()
        collector.finish(isStdout: false)
        collector.finishAll()

        let clock = ContinuousClock()
        let start = clock.now
        await collector.waitForEOF()
        #expect(clock.now - start < Self.promptly, "finishAll left the group waiting")
    }

    @Test("Repeated finishAll is safe")
    func repeatedFinishAllIsIdempotent() async {
        let collector = completingCollector()
        collector.finishAll()
        collector.finishAll()

        let clock = ContinuousClock()
        let start = clock.now
        await collector.waitForEOF()
        #expect(clock.now - start < Self.promptly)
    }

    @Test("Concurrent finishes for the same stream still leave once")
    func concurrentFinishesLeaveOnce() async {
        let collector = completingCollector()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 16 {
                group.addTask { collector.finish(isStdout: index.isMultiple(of: 2)) }
            }
        }

        let clock = ContinuousClock()
        let start = clock.now
        await collector.waitForEOF()
        #expect(clock.now - start < Self.promptly)
    }
}
