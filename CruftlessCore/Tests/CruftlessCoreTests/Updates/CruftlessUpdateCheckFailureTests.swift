@testable import CruftlessCore
import Foundation
import Testing

@Suite("Update check failure mapping")
struct CruftlessUpdateCheckFailureTests {
    @Test("A missing or unparsable installed version maps to the development-build case")
    func installedVersionProblems() {
        #expect(CruftlessUpdateCheckFailure(CruftlessReleaseCheckError.missingInstalledVersion) == .installedVersionUnavailable)
        #expect(CruftlessUpdateCheckFailure(CruftlessReleaseCheckError.invalidVersion) == .installedVersionUnavailable)
    }

    @Test("Network and response errors stay generic")
    func otherErrors() {
        #expect(CruftlessUpdateCheckFailure(CruftlessReleaseCheckError.invalidResponse) == .checkFailed)
        #expect(CruftlessUpdateCheckFailure(URLError(.notConnectedToInternet)) == .checkFailed)
    }
}
