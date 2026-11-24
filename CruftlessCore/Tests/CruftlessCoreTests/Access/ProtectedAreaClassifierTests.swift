@testable import CruftlessCore
import Foundation
import Testing

@Suite("Protected area classifier")
struct ProtectedAreaClassifierTests {
    private func path(_ fixture: AccessFixture, _ relative: String) -> String {
        fixture.home.appendingPathComponent(relative).path(percentEncoded: false)
    }

    @Test("Each home area is recognized, at its root and below it")
    func homeAreas() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let classifier = fixture.gate.classifier

        #expect(classifier.area(forPath: path(fixture, "Documents")) == .documents)
        #expect(classifier.area(forPath: path(fixture, "Documents/DerivedData/App")) == .documents)
        #expect(classifier.area(forPath: path(fixture, "Desktop/Xcode.app")) == .desktop)
        #expect(classifier.area(forPath: path(fixture, "Downloads/Xcode-beta.app")) == .downloads)
        #expect(classifier.area(forPath: path(fixture, "Library/Mobile Documents/com~apple~CloudDocs/x")) == .fileProvider)
        #expect(classifier.area(forPath: path(fixture, "Library/CloudStorage/Dropbox/x")) == .fileProvider)
    }

    @Test("A sibling whose name only starts like an area is not in it")
    func prefixTrap() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let classifier = fixture.gate.classifier

        #expect(classifier.area(forPath: path(fixture, "DocumentsArchive/x")) == nil)
        #expect(classifier.area(forPath: path(fixture, "Downloads2")) == nil)
        #expect(classifier.area(forPath: path(fixture, "Library/CloudStorageOld/x")) == nil)
        #expect(classifier.area(forPath: path(fixture, "Library/Developer/Xcode/DerivedData")) == nil)
        #expect(classifier.area(forPath: "relative/Documents") == nil)
    }

    @Test("Another spelling of the same folder still classifies")
    func caseAndDotDot() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let classifier = fixture.gate.classifier

        #expect(classifier.area(forPath: path(fixture, "documents/x")) == .documents)
        #expect(classifier.area(forPath: path(fixture, "Library/../Documents/x")) == .documents)
    }

    @Test("A symlink from an unprotected spelling into an area is caught")
    func symlinkIntoArea() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let target = try fixture.directory("Documents/Builds/DerivedData")
        try FileManager.default.createDirectory(at: fixture.home.appendingPathComponent("Library"), withIntermediateDirectories: true)
        let link = fixture.home.appendingPathComponent("Library/DerivedDataLink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { TestFileSystem.removeFile(at: link) }

        #expect(fixture.gate.classifier.area(for: link) == .documents)
        #expect(fixture.gate.classifier.area(for: link.appendingPathComponent("App-abc")) == .documents)
    }

    @Test("Volumes classify by locality, and the boot volume is never protected")
    func volumes() {
        let home = URL(fileURLWithPath: "/Users/nobody-cruftless-test", isDirectory: true)
        let classify = { (volume: ProtectedAreaClassifier.Volume?) in
            ProtectedAreaClassifier(home: home, inspectVolume: { _ in volume })
        }

        let external = classify(.init(mountPoint: "/Volumes/SSD", isLocal: true))
        let network = classify(.init(mountPoint: "/Volumes/Share", isLocal: false))
        let boot = classify(.init(mountPoint: "/", isLocal: true))
        let data = classify(.init(mountPoint: "/System/Volumes/Data", isLocal: true))
        let unknown = classify(nil)

        #expect(external.area(forPath: "/Volumes/SSD/DerivedData") == .removableVolume)
        #expect(external.areaRoot(forPath: "/Volumes/SSD/DerivedData")?.root == "/Volumes/SSD")
        #expect(network.area(forPath: "/Volumes/Share/Archives") == .networkVolume)
        #expect(boot.area(forPath: "/Volumes/Macintosh HD/Users/x") == nil)
        #expect(data.area(forPath: "/Volumes/Data/x") == nil)
        #expect(unknown.area(forPath: "/Volumes/Gone/x") == nil)
        #expect(external.area(forPath: "/Volumes") == nil)
        #expect(external.area(forPath: "/Applications/Xcode.app") == nil)
    }

    @Test("The area root is the folder whose first open raises the alert")
    func areaRoot() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let match = fixture.gate.classifier.areaRoot(forPath: path(fixture, "Library/CloudStorage/Box/Deep/x"))

        #expect(match?.area == .fileProvider)
        #expect(match?.root == path(fixture, "Library/CloudStorage"))
    }
}
