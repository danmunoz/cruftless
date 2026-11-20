@testable import CruftlessCore
import Foundation
import Testing

@Suite("App footprint removal")
struct AppFootprintTests {
    private struct Home {
        let url: URL
        let footprint: AppFootprint

        init() throws {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("cruftless-footprint-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            url = base.resolvingSymlinksInPath()
            footprint = AppFootprint(
                home: url,
                bundleIdentifier: "com.example.footprint",
                userCacheDirectory: url.appendingPathComponent("var-folders/C", isDirectory: true)
            )
        }

        func populate(_ folders: [AppFootprint.Folder]) throws {
            for folder in folders {
                try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
                try Data(repeating: 1, count: 8192).write(to: folder.url.appendingPathComponent("payload"))
            }
        }

        var protectedPaths: ProtectedPaths {
            ProtectedPaths(customProtectedPaths: [], home: url)
        }

        func remove() {
            TestFileSystem.removeDirectoryRecursively(at: url)
        }
    }

    @Test("Folders are the app's own Library entries under the given home")
    func folderPaths() throws {
        let home = try Home()
        defer { home.remove() }
        let library = home.url.appendingPathComponent("Library").path
        let paths = home.footprint.folders.map(\.url.path)

        #expect(paths == [
            "\(library)/Application Support/Cruftless",
            "\(library)/Caches/com.example.footprint",
            "\(library)/HTTPStorages/com.example.footprint",
            "\(library)/Saved Application State/com.example.footprint.savedState",
            "\(home.url.path)/var-folders/C/com.example.footprint"
        ])
        #expect(home.footprint.preferencesFile.path == "\(library)/Preferences/com.example.footprint.plist")
    }

    @Test("The live footprint uses the shipping bundle identifier and the user's cache folder")
    func liveFootprint() throws {
        let cache = try #require(AppFootprint.darwinUserCacheDirectory())
        #expect(cache.path.hasSuffix("/C"))
        #expect(FileManager.default.fileExists(atPath: cache.path))
        #expect(AppFootprint.live.bundleIdentifier == "com.danmunoz.Cruftless")
        #expect(AppFootprint.live.applicationSupport.path.hasSuffix("/Library/Application Support/Cruftless"))
    }

    @Test("A folder in the real per-user cache under /var/folders is an admissible root")
    func userCacheIsAdmissible() throws {
        let cache = try #require(AppFootprint.darwinUserCacheDirectory())
        let folder = cache.appendingPathComponent("com.example.cruftless.footprint.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: folder) }

        let validated = try PathGuard(roots: [folder]).validateRoot(folder)
        #expect(validated.isRoot)
    }

    @Test("Only folders that exist are planned, each as a validated root")
    func plansExistingFolders() throws {
        let home = try Home()
        defer { home.remove() }
        let present = Array(home.footprint.folders.prefix(2))
        try home.populate(present)

        let plan = try DeletionPlanner.appFootprint(
            home.footprint,
            context: PlanningContext(protectedPaths: home.protectedPaths)
        )

        #expect(plan.items.map(\.name) == present.map(\.title))
        #expect(plan.items.allSatisfy { $0.validatedPath?.isRoot == true })
        #expect(plan.items.allSatisfy { $0.reclaimableBytes > 0 })
        #expect(plan.confirmLabel == "Remove Cruftless Data")
        #expect(plan.affectedLocationIds.isEmpty)
    }

    @Test("Nothing on disk plans nothing, without refusing")
    func emptyFootprint() throws {
        let home = try Home()
        defer { home.remove() }

        let plan = try DeletionPlanner.appFootprint(
            home.footprint,
            context: PlanningContext(protectedPaths: home.protectedPaths)
        )
        #expect(plan.isEmpty)
    }

    @Test("The executor deletes every planned folder and nothing beside it")
    func executesRemoval() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.populate(home.footprint.folders)
        let neighbour = home.url.appendingPathComponent("Library/Application Support/Neighbour", isDirectory: true)
        try FileManager.default.createDirectory(at: neighbour, withIntermediateDirectories: true)

        let plan = try DeletionPlanner.appFootprint(
            home.footprint,
            context: PlanningContext(protectedPaths: home.protectedPaths)
        )
        let result = await DeletionExecutor(capacitySampler: { 100 }, settleSleep: {}).execute(plan)

        #expect(result.allSucceeded)
        for folder in home.footprint.folders {
            #expect(!FileManager.default.fileExists(atPath: folder.url.path))
        }
        #expect(FileManager.default.fileExists(atPath: neighbour.path))
    }

    @Test("A symlinked footprint folder refuses the whole plan")
    func refusesSymlinkedFolder() throws {
        let home = try Home()
        defer { home.remove() }
        let folders = home.footprint.folders
        try home.populate([folders[1]])
        let elsewhere = home.url.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folders[0].url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: folders[0].url, withDestinationURL: elsewhere)

        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.appFootprint(home.footprint, context: PlanningContext(protectedPaths: home.protectedPaths))
        }
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    @Test("A user-protected path inside a footprint folder refuses the whole plan")
    func refusesProtectedDescendant() throws {
        let home = try Home()
        defer { home.remove() }
        try home.populate(home.footprint.folders)
        let kept = home.footprint.applicationSupport.appendingPathComponent("payload")
        let policy = ProtectedPaths(customProtectedPaths: [kept], home: home.url)

        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.appFootprint(home.footprint, context: PlanningContext(protectedPaths: policy))
        }
    }

    @Test("The footprint guard rejects every path outside its folders")
    func guardRejectsOutsidePaths() throws {
        let home = try Home()
        defer { home.remove() }
        try home.populate(home.footprint.folders)
        let pathGuard = PathGuard(roots: home.footprint.folders.map(\.url), protectedPaths: home.protectedPaths)
        let outside = [
            home.url.appendingPathComponent("Library/Application Support/CruftlessOther"),
            home.url.appendingPathComponent("Library/Caches/com.example.footprint.other"),
            home.url.appendingPathComponent("Library/Preferences/com.example.footprint.plist"),
            home.url.appendingPathComponent("Library"),
            home.url
        ]

        for url in outside {
            #expect(throws: PathGuardError.self) { try pathGuard.validate(url) }
            #expect(throws: PathGuardError.self) { try pathGuard.validateRoot(url) }
        }
        let inside = home.footprint.caches.appendingPathComponent("payload")
        #expect(try pathGuard.validate(inside).url.lastPathComponent == "payload")
    }
}
