@testable import CruftlessCore
import Darwin
import Foundation
import Synchronization
import Testing

@Suite("Access ledger, gate and request")
struct AccessGateTests {
    private static let location = TrackedLocation(
        id: "accessFixture",
        title: "Fixture",
        icon: .symbol("folder"),
        tier: .regen,
        hasDrillDown: true,
        stalenessSource: .topLevelMtime,
        resolveRoots: { [] }
    )

    @Test("The ledger persists asked areas across instances and ignores unknown values")
    func ledgerPersistence() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }

        fixture.ledger.markAsked(.documents)
        fixture.ledger.markAsked(.documents)
        fixture.ledger.markAsked(.removableVolume)
        let reopened = AccessLedger(userDefaults: fixture.defaults)

        #expect(reopened.askedAreas() == [.documents, .removableVolume])
        #expect(fixture.defaults.stringArray(forKey: "cruftless.accessAskedAreas") == ["documents", "removableVolume"])

        fixture.defaults.set(["documents", "futureArea"], forKey: "cruftless.accessAskedAreas")
        #expect(reopened.askedAreas() == [.documents])

        reopened.clearAsked(.documents)
        #expect(AccessLedger(userDefaults: fixture.defaults).hasAsked(.documents) == false)
    }

    @Test("Not asked is blocked; asked or unprotected is clear")
    func gateDecisions() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let inDocuments = fixture.home.appendingPathComponent("Documents/DerivedData")
        let inLibrary = fixture.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")

        #expect(fixture.gate.check(inDocuments) == .blocked(.documents))
        #expect(fixture.gate.check(inLibrary) == .clear)

        fixture.ledger.markAsked(.documents)
        #expect(fixture.gate.check(inDocuments) == .clear)
        #expect(fixture.gate.check(fixture.home.appendingPathComponent("Desktop/x")) == .blocked(.desktop))
    }

    @Test("Partition keeps blocked roots out of the clear list and names each one")
    func partition() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        fixture.ledger.markAsked(.desktop)
        let clear = URL(fileURLWithPath: "/Applications/Xcode.app", isDirectory: true)
        let blocked = fixture.home.appendingPathComponent("Downloads/Xcode-beta.app", isDirectory: true)
        let asked = fixture.home.appendingPathComponent("Desktop/Xcode-old.app", isDirectory: true)

        let gated = fixture.gate.partition([clear, blocked, asked], for: Self.location)

        #expect(gated.clear == [clear, asked])
        #expect(gated.blocked == [BlockedAccess(
            path: blocked.path(percentEncoded: false),
            area: .downloads,
            state: .notAsked,
            reason: "Xcode-beta.app"
        )])
        #expect(gated.askedArea(of: asked) == .desktop)
        #expect(gated.askedArea(of: clear) == nil)
        #expect(gated.all.count == 3)
    }

    @Test("A request marks the area asked before its one open, then maps the opener's result")
    func requestOutcomes() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let path = fixture.home.appendingPathComponent("Documents/DerivedData").path(percentEncoded: false)
        let opened = Mutex<[String]>([])
        let askedDuringOpen = Mutex<Bool?>(nil)
        let result = Mutex<Int32>(0)
        let ledger = fixture.ledger
        let request = AccessRequest(gate: fixture.gate) { opening in
            opened.withLock { $0.append(opening) }
            askedDuringOpen.withLock { $0 = ledger.hasAsked(.documents) }
            return result.withLock { $0 }
        }

        #expect(try request.request(area: .documents, path: path) == .allowed)
        #expect(opened.withLock { $0 } == [fixture.home.appendingPathComponent("Documents").path(percentEncoded: false)])
        #expect(askedDuringOpen.withLock { $0 } == true)
        #expect(fixture.ledger.hasAsked(.documents))

        result.withLock { $0 = EPERM }
        #expect(try request.request(area: .documents, path: path) == .denied)
        result.withLock { $0 = EACCES }
        #expect(try request.request(area: .documents, path: path) == .denied)
        #expect(fixture.ledger.hasAsked(.documents))

        result.withLock { $0 = ENOENT }
        let downloads = fixture.home.appendingPathComponent("Downloads/x").path(percentEncoded: false)
        #expect(try request.request(area: .downloads, path: downloads) == .unavailable(errno: ENOENT))
        #expect(fixture.ledger.hasAsked(.downloads) == false)
        #expect(opened.withLock { $0.count } == 4)
    }

    @Test("A request refuses a path outside the area it names, without opening anything")
    func requestRefusesMismatchedArea() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let opened = Mutex(0)
        let request = AccessRequest(gate: fixture.gate) { _ in
            opened.withLock { $0 += 1 }
            return 0
        }
        let desktop = fixture.home.appendingPathComponent("Desktop/x").path(percentEncoded: false)

        #expect(throws: AccessRequestError.pathOutsideArea) {
            try request.request(area: .documents, path: desktop)
        }
        #expect(throws: AccessRequestError.pathOutsideArea) {
            try request.request(area: .documents, path: "/Applications/Xcode.app")
        }
        #expect(opened.withLock { $0 } == 0)
        #expect(fixture.ledger.askedAreas().isEmpty)
    }

    @Test("Preflight groups existing protected roots by area with their reasons, opening nothing")
    func preflight() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let derived = try fixture.directory("Documents/DerivedData")
        let beta = try fixture.directory("Downloads/Xcode-beta.app")
        let missing = fixture.home.appendingPathComponent("Desktop/Gone.app")
        let library = try fixture.directory("Library/Developer/Xcode/Archives")
        fixture.ledger.markAsked(.downloads)
        let derivedLocation = LocationCatalog.derivedData
        let installs = LocationCatalog.xcodeInstalls
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }

        let needs = AccessPreflight.needs(
            resolved: [(derivedLocation, [derived, library]), (installs, [beta, missing])],
            gate: fixture.gate
        )

        #expect(needs.map(\.area) == [.documents, .downloads])
        #expect(needs.map(\.isAsked) == [false, true])
        #expect(needs[0].reasons.map(\.title) == ["Derived Data location"])
        #expect(needs[1].reasons.map(\.title) == ["Xcode-beta.app"])
        #expect(needs[1].reasons.first?.path == beta.path(percentEncoded: false))
        #expect(recorder.events(under: fixture.home).isEmpty)
    }
}
