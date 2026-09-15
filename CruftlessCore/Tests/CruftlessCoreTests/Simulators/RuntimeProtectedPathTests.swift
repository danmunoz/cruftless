@testable import CruftlessCore
import Foundation
import Testing

@Suite("Runtime deletion honours protected paths")
struct RuntimeProtectedPathTests {
    private func runtime(deletable: Bool = true) -> SimRuntime {
        SimRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            name: "iOS 27.0",
            build: "25A100",
            sizeBytes: 8_000_000_000,
            isDeletable: deletable
        )
    }

    @Test("A runtime plans normally when nothing inside CoreSimulator is protected")
    func plansWithoutProtection() throws {
        let plan = try DeletionPlanner.runtimeDelete(runtime(), context: PlanningContext())
        #expect(plan.count == 1)
    }

    @Test("A protected folder inside the runtime store refuses every runtime delete")
    func refusesWhenStoreHoldsProtectedPath() {
        let protectedPaths = ProtectedPaths(customProtectedPaths: [
            URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Images", isDirectory: true)
        ])
        #expect(throws: DeletionPlanningError.protectedDescendantInSimulator(
            name: "iOS 27.0",
            path: "/Library/Developer/CoreSimulator"
        )) {
            try DeletionPlanner.runtimeDelete(self.runtime(), context: PlanningContext(protectedPaths: protectedPaths))
        }
    }

    @Test("A protected folder elsewhere does not block runtime deletion")
    func unrelatedProtectionDoesNotBlock() throws {
        let protectedPaths = ProtectedPaths(customProtectedPaths: [
            URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)
        ])
        let plan = try DeletionPlanner.runtimeDelete(runtime(), context: PlanningContext(protectedPaths: protectedPaths))
        #expect(plan.count == 1)
    }

    @Test("Both simulator planning refusals carry user-facing copy")
    func simulatorRefusalsHaveDescriptions() {
        let notDeletable = DeletionPlanningError.runtimeNotDeletable(name: "iOS 27.0")
        #expect(notDeletable.errorDescription?.isEmpty == false)
        #expect(notDeletable.localizedDescription.contains("iOS 27.0"))

        let protected = DeletionPlanningError.protectedDescendantInSimulator(
            name: "iPhone 17 Pro",
            path: "/Library/Developer/CoreSimulator"
        )
        #expect(protected.errorDescription?.isEmpty == false)
        #expect(protected.localizedDescription.contains("iPhone 17 Pro"))
        #expect(protected.localizedDescription.contains("/Library/Developer/CoreSimulator"))
    }

    @Test("A bundled runtime is still refused before the path check")
    func bundledRuntimeStillRefused() {
        #expect(throws: DeletionPlanningError.runtimeNotDeletable(name: "iOS 27.0")) {
            try DeletionPlanner.runtimeDelete(self.runtime(deletable: false), context: PlanningContext())
        }
    }
}
