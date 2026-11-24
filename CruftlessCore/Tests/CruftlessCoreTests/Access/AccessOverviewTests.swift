@testable import CruftlessCore
import Darwin
import Foundation
import Synchronization
import Testing

@Suite("Access list and service")
struct AccessOverviewTests {
    private static func reason(_ fixture: AccessFixture, _ relativePath: String, id: String = "derivedData") -> AccessNeedReason {
        AccessNeedReason(
            locationId: id,
            title: relativePath,
            path: fixture.home.appendingPathComponent(relativePath).path(percentEncoded: false)
        )
    }

    private static func path(_ fixture: AccessFixture, _ relativePath: String) -> String {
        fixture.home.appendingPathComponent(relativePath).path(percentEncoded: false)
    }

    @Test("An area never asked about is listed as not asked and never opened")
    func notAskedIsNeverOpened() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let opened = Mutex<[String]>([])
        let documents = Self.reason(fixture, "Documents/DerivedData")

        let areas = AccessOverview.areas(
            needs: [AreaAccessNeed(area: .documents, isAsked: false, reasons: [documents])],
            gate: fixture.gate
        ) { path in
            opened.withLock { $0.append(path) }
            return 0
        }

        #expect(areas == [AccessAreaSummary(area: .documents, status: .notAsked, reasons: [documents])])
        #expect(opened.withLock { $0 }.isEmpty)
    }

    @Test("An asked area is opened once at its root and reads as allowed or not allowed")
    func askedAreaStatus() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        fixture.ledger.markAsked(.documents)
        fixture.ledger.markAsked(.downloads)
        fixture.ledger.markAsked(.desktop)
        let opened = Mutex<[String]>([])
        let results: [String: Int32] = [
            Self.path(fixture, "Documents"): 0,
            Self.path(fixture, "Downloads"): EPERM,
            Self.path(fixture, "Desktop"): EACCES
        ]
        let needs = [
            AreaAccessNeed(area: .documents, isAsked: true, reasons: [Self.reason(fixture, "Documents/DerivedData")]),
            AreaAccessNeed(area: .downloads, isAsked: true, reasons: [Self.reason(fixture, "Downloads/Xcode-beta.app")])
        ]

        let areas = AccessOverview.areas(needs: needs, gate: fixture.gate) { path in
            opened.withLock { $0.append(path) }
            return results[path] ?? ENOENT
        }

        #expect(areas.map(\.area) == [.documents, .desktop, .downloads])
        #expect(areas.map(\.status) == [.allowed, .notAllowed, .notAllowed])
        #expect(areas[1].reasons.isEmpty)
        #expect(Set(opened.withLock { $0 }) == Set(results.keys))
        #expect(opened.withLock { $0.count } == 3)
    }

    @Test("An asked area with nothing to show and no answer is left out")
    func indeterminateAreasWithoutNeedsAreOmitted() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        fixture.ledger.markAsked(.removableVolume)
        fixture.ledger.markAsked(.fileProvider)
        fixture.ledger.markAsked(.documents)
        let opened = Mutex(0)
        let needs = [
            AreaAccessNeed(area: .documents, isAsked: true, reasons: [Self.reason(fixture, "Documents/DerivedData")])
        ]

        let areas = AccessOverview.areas(needs: needs, gate: fixture.gate) { _ in
            opened.withLock { $0 += 1 }
            return EIO
        }

        // The volume has no root to open; iCloud Drive's failure is not a refusal and nothing needs it.
        #expect(areas == [AccessAreaSummary(area: .documents, status: .allowed, reasons: needs[0].reasons)])
        #expect(opened.withLock { $0 } == 2)
    }

    @Test("The classifier names each home area's own folder and none for volumes")
    func defaultRoots() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let classifier = fixture.gate.classifier

        #expect(classifier.defaultRoot(for: .downloads) == Self.path(fixture, "Downloads"))
        #expect(classifier.defaultRoot(for: .fileProvider) == Self.path(fixture, "Library/Mobile Documents"))
        #expect(classifier.defaultRoot(for: .removableVolume) == nil)
        #expect(classifier.defaultRoot(for: .networkVolume) == nil)
    }

    @Test("The service loads through the preflight and records the area only after the answer")
    func serviceRequest() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let ledger = fixture.ledger
        let askedDuringOpen = Mutex<Bool?>(nil)
        let documents = Self.reason(fixture, "Documents/DerivedData")
        let service = AccessService.standard(
            gate: fixture.gate,
            opener: { _ in
                askedDuringOpen.withLock { $0 = ledger.hasAsked(.documents) }
                return 0
            },
            preflight: { _, _ in [AreaAccessNeed(area: .documents, isAsked: false, reasons: [documents])] }
        )

        let before = await service.load([])
        #expect(before.map(\.status) == [.notAsked])

        let outcome = try await service.request(before[0])
        #expect(outcome == .allowed)
        #expect(askedDuringOpen.withLock { $0 } == false)
        #expect(ledger.hasAsked(.documents))

        let after = await service.load([])
        #expect(after.map(\.status) == [.allowed])
    }

    @Test("A second request while one waits on macOS is refused without opening anything")
    func oneRequestInFlight() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let entered = DispatchSemaphore(value: 0)
        let answer = DispatchSemaphore(value: 0)
        let opens = Mutex(0)
        let service = AccessService.standard(
            gate: fixture.gate,
            opener: { _ in
                opens.withLock { $0 += 1 }
                entered.signal()
                answer.wait()
                return EPERM
            },
            preflight: { _, _ in [] }
        )
        let documents = AccessAreaSummary(area: .documents, status: .notAsked, reasons: [Self.reason(fixture, "Documents/x")])
        let downloads = AccessAreaSummary(area: .downloads, status: .notAsked, reasons: [])

        let first = Task { try await service.request(documents) }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                entered.wait()
                continuation.resume()
            }
        }

        await #expect(throws: AccessRequestError.requestInFlight) {
            try await service.request(downloads)
        }
        #expect(fixture.ledger.askedAreas().isEmpty)

        answer.signal()
        #expect(try await first.value == .denied)
        #expect(fixture.ledger.askedAreas() == [.documents])

        // The slot is free again; an area with no reasons is asked at its own folder.
        answer.signal()
        #expect(try await service.request(downloads) == .denied)
        #expect(opens.withLock { $0 } == 2)
    }

    @Test("A request that never reached macOS leaves the area unasked and says why")
    func unavailableOutcomeCopy() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let request = AccessRequest(gate: fixture.gate) { _ in ENOENT }

        let outcome = try request.request(area: .documents, path: Self.path(fixture, "Documents/x"))

        #expect(outcome == .unavailable(errno: ENOENT))
        #expect(outcome.isAnswered == false)
        #expect(fixture.ledger.hasAsked(.documents) == false)
        #expect(outcome.message(for: .documents)?.contains("Documents") == true)
        #expect(AccessRequestOutcome.allowed.message(for: .documents) == nil)
        #expect(AccessRequestOutcome.denied.isAnswered)
        #expect(AccessRequestError.requestInFlight.errorDescription != nil)
    }

    @Test("A blocked root names its area by state, and areas have headings")
    func copy() {
        let notAsked = BlockedAccess(path: "/x", area: .downloads, state: .notAsked, reason: "Xcode-beta.app")
        let refused = BlockedAccess(path: "/x", area: .downloads, state: .notAllowed, reason: "Xcode-beta.app")

        #expect(notAsked.summary == "Needs access to Downloads")
        #expect(refused.summary == "macOS does not allow reading Downloads")
        #expect(ProtectedArea.removableVolume.title == "External Drive")
        #expect(ProtectedArea.documents.title == "Documents")
        #expect(AccessOverview.privacySettingsURL?.scheme == "x-apple.systempreferences")
    }
}
