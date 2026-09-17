import CruftlessCore
import Foundation
import Testing

@Suite("DeletionPlan rescan scope")
struct DeletionPlanRescanScopeTests {
    private func target() -> DeletionTarget {
        .runtimeDelete(identifier: "com.example.runtime", name: "Example", consequence: "", reclaimableBytes: 1)
    }

    @Test("A plan without affected locations falls back to rescanning everything")
    func emptyScopeFallsBackToEverything() {
        #expect(DeletionPlan.batch([]).rescanScope == .everything)
        #expect(DeletionPlan.single(target()).rescanScope == .everything)
    }

    @Test("A plan with affected locations scopes the rescan to them")
    func scopeCarriesLocations() {
        let plan = DeletionPlan.single(target(), affectedLocationIds: ["derivedData", "archives"])
        #expect(plan.rescanScope == .locations(Set(["derivedData", "archives"])))
    }
}
