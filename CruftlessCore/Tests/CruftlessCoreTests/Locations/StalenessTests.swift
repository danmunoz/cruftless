import CruftlessCore
import Foundation
import Testing

@Suite("Staleness Label Tests")
struct StalenessTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }

    @Test("nil last-used date never renders a label")
    func nilDateReturnsNil() {
        let info = StalenessInfo(lastUsedDate: nil)
        #expect(info.stalenessLabel(now: now) == nil)
    }

    @Test("Below the staleness threshold, no label renders")
    func belowThresholdReturnsNil() {
        let info = StalenessInfo(lastUsedDate: daysAgo(10))
        #expect(info.stalenessLabel(now: now, thresholdDays: 30) == nil)
    }

    @Test("Days unit applies under 14 days")
    func daysUnit() {
        let info = StalenessInfo(lastUsedDate: daysAgo(5))
        #expect(info.stalenessLabel(now: now, thresholdDays: 1) == "Unused for 5 days")

        let single = StalenessInfo(lastUsedDate: daysAgo(1))
        #expect(single.stalenessLabel(now: now, thresholdDays: 1) == "Unused for 1 day")
    }

    @Test("Weeks unit applies from 14 up to 55 days")
    func weeksUnit() {
        let info = StalenessInfo(lastUsedDate: daysAgo(45))
        #expect(info.stalenessLabel(now: now, thresholdDays: 30) == "Unused for 6 weeks")

        let boundary = StalenessInfo(lastUsedDate: daysAgo(14))
        #expect(boundary.stalenessLabel(now: now, thresholdDays: 1) == "Unused for 2 weeks")
    }

    @Test("Months unit applies from 56 up to 359 days")
    func monthsUnit() {
        let info = StalenessInfo(lastUsedDate: daysAgo(90))
        #expect(info.stalenessLabel(now: now, thresholdDays: 30) == "Unused for 3 months")

        let boundary = StalenessInfo(lastUsedDate: daysAgo(56))
        #expect(boundary.stalenessLabel(now: now, thresholdDays: 1) == "Unused for 1 month")
    }

    @Test("Years unit applies at 360 days and beyond")
    func yearsUnit() {
        let info = StalenessInfo(lastUsedDate: daysAgo(400))
        #expect(info.stalenessLabel(now: now, thresholdDays: 30) == "Unused for 1 year")

        let multi = StalenessInfo(lastUsedDate: daysAgo(800))
        #expect(multi.stalenessLabel(now: now, thresholdDays: 30) == "Unused for 2 years")
    }

    @Test("isStale is unaffected by the label change")
    func isStaleUnchanged() {
        let stale = StalenessInfo(lastUsedDate: daysAgo(45))
        #expect(stale.isStale(now: now, thresholdDays: 30))

        let fresh = StalenessInfo(lastUsedDate: daysAgo(5))
        #expect(!fresh.isStale(now: now, thresholdDays: 30))
    }
}

@Suite("Staleness.resolve dispatch")
struct StalenessResolveDispatchTests {
    private let archiveDate = Date(timeIntervalSince1970: 1)
    private let simulatorDate = Date(timeIntervalSince1970: 2)
    private let newestChildDate = Date(timeIntervalSince1970: 3)
    private let topLevelDate = Date(timeIntervalSince1970: 4)

    private func unexpectedlyEvaluated(_ label: String) -> Date? {
        Issue.record("\(label) closure evaluated for a source that should not need it")
        return nil
    }

    @Test("Every StalenessSource case routes to its own closure", arguments: StalenessSource.allCases)
    func routesToOwnClosure(source: StalenessSource) {
        let expected: Date
        switch source {
        case .archiveCreationDate: expected = archiveDate
        case .simulatorPlist: expected = simulatorDate
        case .newestChildMtime: expected = newestChildDate
        case .topLevelMtime: expected = topLevelDate
        }

        let info = Staleness.resolve(
            source: source,
            archiveCreationDate: source == .archiveCreationDate ? archiveDate : unexpectedlyEvaluated("archiveCreationDate"),
            simulatorLastUsedAt: source == .simulatorPlist ? simulatorDate : unexpectedlyEvaluated("simulatorLastUsedAt"),
            newestChildMtime: source == .newestChildMtime ? newestChildDate : unexpectedlyEvaluated("newestChildMtime"),
            topLevelMtime: source == .topLevelMtime ? topLevelDate : unexpectedlyEvaluated("topLevelMtime")
        )

        #expect(info.lastUsedDate == expected)
    }
}
