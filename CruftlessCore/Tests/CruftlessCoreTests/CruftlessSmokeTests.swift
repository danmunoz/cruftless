@testable import CruftlessCore
@testable import CruftlessFixtures
import Testing

@Suite("Smoke Tests")
struct CruftlessSmokeTests {
    @Test("Package loads and smoke test passes")
    func smokeTest() {
        #expect(FixtureHelper.sampleString == "sample")
    }
}
