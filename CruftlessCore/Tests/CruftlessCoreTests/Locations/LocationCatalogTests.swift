import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("LocationCatalog and Root Safety Tests")
struct LocationCatalogTests {
    @Test("Every catalog location rejects sibling path outside its roots (Non-negotiable Rule 5)", arguments: LocationCatalog.all)
    func pathGuardRejectsSiblingOutsideRoot(location: TrackedLocation) throws {
        let roots = location.resolveRoots()

        guard !roots.isEmpty else {
            #expect(
                location.mutationPolicy == .simctl || location.mutationPolicy == .readOnly,
                "\(location.id) has no roots and no explicit non-path mutation policy"
            )
            return
        }

        for root in roots {
            let guardInstance = PathGuard(roots: [root])
            let rootPath = ProtectedPaths.normalize(root)

            if location.id == LocationCatalog.xcodeInstalls.id {
                #expect(guardInstance.roots.isEmpty, "\(rootPath) should not be usable as a root")
            }

            let siblingURL = URL(fileURLWithPath: "\(rootPath)_sibling/escape.txt")

            #expect(throws: PathGuardError.self, "Location \(location.id) must reject sibling \(siblingURL.path)") {
                _ = try guardInstance.validate(siblingURL)
            }
        }
    }

    @Test("Derived Data respects IDECustomDerivedDataLocation user default")
    func customDerivedDataRoot() {
        let suite = UserDefaults(suiteName: "com.apple.dt.Xcode")
        let key = "IDECustomDerivedDataLocation"
        let previous = suite?.string(forKey: key)
        defer {
            if let previous {
                suite?.set(previous, forKey: key)
            } else {
                suite?.removeObject(forKey: key)
            }
        }

        let customPath = "/tmp/CustomDerivedDataTest"
        suite?.set(customPath, forKey: key)

        let resolved = RootResolver.derivedDataRoots()
        let expected = ProtectedPaths.normalize(URL(fileURLWithPath: customPath, isDirectory: true))
        #expect(resolved.first.map(ProtectedPaths.normalize) == expected)
        #expect(RootResolver.preferenceIssues().isEmpty)

        suite?.set("~/Library/Developer", forKey: key)
        let refused = RootResolver.derivedDataRoots()
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #expect(refused.map(ProtectedPaths.normalize)
            == [ProtectedPaths.normalize(RootResolver.defaultDerivedDataRoot(home: home))])
        let issues = RootResolver.preferenceIssues()
        #expect(issues.map(\.preferenceKey) == [key])
        #expect(issues.first?.reason == .protectedLocation)
        #expect(issues.first?.message.contains("~/Library/Developer") == true)
    }

    @Test("ScanEngine omits nonexistent roots from inventory")
    func missingRootsOmitted() async {
        let fakeLocation = TrackedLocation(
            id: "nonexistent",
            title: "Nonexistent",
            icon: .symbol("xmark"),
            tier: .regen,
            hasDrillDown: false,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [URL(fileURLWithPath: "/nonexistent/path/cruftless_phantom", isDirectory: true)] }
        )

        let engine = ScanEngine()
        var scannedEntries: [InventoryEntry] = []
        for await event in await engine.scan(catalog: [fakeLocation]) {
            if case let .locationScanned(entry) = event {
                scannedEntries.append(entry)
            }
        }

        #expect(scannedEntries.isEmpty)
    }

    @Test("Code completion models is tiered as judgment, not regen")
    func codingAssistantIsJudgmentTier() {
        #expect(LocationCatalog.codingAssistant.tier == .judgment)
    }

    @Test("Staleness calculation: archiveCreationDate extracts Info.plist date")
    func archiveCreationDateStaleness() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archiveURL = tempBase.appendingPathComponent("App.xcarchive")
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let testDate = Date(timeIntervalSince1970: 1_700_000_000) // Nov 2023
        let plistDict: [String: Any] = ["CreationDate": testDate]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try plistData.write(to: archiveURL.appendingPathComponent("Info.plist"))

        let staleness = DrillDownProvider.readArchiveCreationDate(at: archiveURL)
        #expect(staleness.lastUsedDate != nil)
        if let lastUsed = staleness.lastUsedDate {
            #expect(abs(lastUsed.timeIntervalSince(testDate)) < 1.0)
        }
    }

    @Test(
        "Every drill-down location is either filesystem-rooted or has another size source",
        arguments: LocationCatalog.all.filter(\.hasDrillDown)
    )
    func drillDownLocationsCanBeSized(location: TrackedLocation) {
        guard location.sizeSource == .filesystemRoots else { return }

        guard location.id != LocationCatalog.xcodeInstalls.id,
              location.platform != .android
        else { return }

        #expect(
            !location.resolveRoots().isEmpty,
            "\(location.id) has a drill-down but resolves no roots and no non-filesystem size source"
        )
    }

    @Test("Simulator runtimes are sized from SimulatorService, not from a walk")
    func simulatorRuntimesDeclareTheirSizeSource() {
        #expect(LocationCatalog.simulatorRuntimes.sizeSource == .simulatorRuntimes)
        #expect(LocationCatalog.simulatorRuntimes.resolveRoots().isEmpty)
    }
}
