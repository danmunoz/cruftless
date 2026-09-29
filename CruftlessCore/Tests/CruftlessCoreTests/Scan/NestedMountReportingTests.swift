import CruftlessCore
import Foundation
import Testing

@Suite("Nested mount reporting")
struct NestedMountReportingTests {
    @Test("A skipped nested volume makes the scan explicitly incomplete")
    func skippedMountIsReported() {
        let root = URL(fileURLWithPath: "/tmp/android-sdk", isDirectory: true)
        let result = SizeResult(
            allocatedBytes: 0,
            newestMtime: nil,
            skippedMountCount: 1,
            firstSkippedMountPath: "/tmp/android-sdk/external"
        )

        let reason = ScanEngine.incompleteScanReason(root: root, result: result)

        #expect(reason.contains("1 nested volume was skipped"))
        #expect(reason.contains("sizes are incomplete"))
        #expect(reason.contains("/tmp/android-sdk/external"))
    }
}
