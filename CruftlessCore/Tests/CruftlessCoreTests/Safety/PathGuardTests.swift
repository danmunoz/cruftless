import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("PathGuard Safety Tests")
struct PathGuardTests {
    @Test("Rejects sibling prefix matching (/foo/barbaz vs /foo/bar)")
    func siblingPrefixMatchingRejected() throws {
        let root = URL(fileURLWithPath: "/tmp/cruftless_test_root")
        let guardInstance = PathGuard(roots: [root])

        let sibling = URL(fileURLWithPath: "/tmp/cruftless_test_root_sibling/file.txt")
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(sibling)
        }
    }

    @Test("Rejects the root directory itself")
    func rootItselfRejected() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempDir) }

        let guardInstance = PathGuard(roots: [tempDir])
        #expect(throws: PathGuardError.matchesRootItself(ProtectedPaths.normalize(tempDir))) {
            _ = try guardInstance.validate(tempDir)
        }
    }

    @Test("Rejects relative paths and dot-dot traversal")
    func relativeAndTraversalRejected() {
        let root = URL(fileURLWithPath: "/tmp/cruftless_safe_root")
        let guardInstance = PathGuard(roots: [root])

        let relativeURL = URL(filePath: "relative/path")
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(relativeURL)
        }

        let traversalURL = root.appendingPathComponent("../escape/secret.txt")
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(traversalURL)
        }
    }

    @Test("Rejects symlink inside root pointing outside the root")
    func symlinkPointingOutsideRejected() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rootDir = tempBase.appendingPathComponent("root")
        let outsideDir = tempBase.appendingPathComponent("outside")

        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let secretFile = outsideDir.appendingPathComponent("secret.txt")
        try "secret data".write(to: secretFile, atomically: true, encoding: .utf8)

        let symlinkInRoot = rootDir.appendingPathComponent("symlink_to_outside")
        try FileManager.default.createSymbolicLink(at: symlinkInRoot, withDestinationURL: secretFile)

        let guardInstance = PathGuard(roots: [rootDir])

        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(symlinkInRoot)
        }
    }

    @Test("Admits valid paths under a symlinked root")
    func symlinkedRootAdmitsValidPath() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let realDir = tempBase.appendingPathComponent("real_root")
        let symlinkRoot = tempBase.appendingPathComponent("symlink_root")

        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: realDir)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let targetFile = realDir.appendingPathComponent("item.txt")
        try "item".write(to: targetFile, atomically: true, encoding: .utf8)

        let guardInstance = PathGuard(roots: [symlinkRoot])
        let candidate = symlinkRoot.appendingPathComponent("item.txt")

        let validated = try guardInstance.validate(candidate)
        #expect(validated.url.resolvingSymlinksInPath() == targetFile.resolvingSymlinksInPath())
    }

    @Test("Case-sensitive fail-closed on mismatched casing")
    func caseSensitivityFailClosed() {
        let root = URL(fileURLWithPath: "/tmp/CruftlessCaseTest")
        let guardInstance = PathGuard(roots: [root])

        let wrongCaseTarget = URL(fileURLWithPath: "/tmp/cruftlesscasetest/subfolder")
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(wrongCaseTarget)
        }
    }

    @Test("Rejects every built-in denylist and device.plist target")
    func protectedPathsDenylist() throws {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let protectedTargets = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System"),
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/bin"),
            URL(fileURLWithPath: "/sbin"),
            URL(fileURLWithPath: "/usr"),
            homeURL,
            homeURL.appendingPathComponent("Library"),
            homeURL.appendingPathComponent("Documents"),
            homeURL.appendingPathComponent("Desktop"),
            homeURL.appendingPathComponent("Library/Developer/CoreSimulator/Devices/ANY-UDID/device.plist")
        ]

        let guardInstance = PathGuard(roots: [
            URL(fileURLWithPath: "/"),
            homeURL
        ])

        for target in protectedTargets {
            #expect(throws: PathGuardError.self, "Target \(target.path) should have been rejected by ProtectedPaths") {
                _ = try guardInstance.validate(target)
            }
        }
    }

    @Test("User custom protected paths take precedence over allowlisted root")
    func customProtectedPathsPrecedence() throws {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let customProtected = root.appendingPathComponent("protected_subfolder")
        let protectedPaths = ProtectedPaths(customProtectedPaths: [customProtected])

        let guardInstance = PathGuard(roots: [root], protectedPaths: protectedPaths)

        let candidate = customProtected.appendingPathComponent("file.txt")
        #expect(throws: PathGuardError.protectedPath(ProtectedPaths.normalize(candidate))) {
            _ = try guardInstance.validate(candidate)
        }
    }

    @Test("ValidatedPath.path is captured at validation time and ignores trailing-slash spelling")
    func validatedPathCapturedAtValidationTime() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = tempDir.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempDir) }

        let guardInstance = PathGuard(roots: [tempDir])

        let withTrailingSlash = URL(fileURLWithPath: target.path(percentEncoded: false) + "/")
        let withoutTrailingSlash = URL(fileURLWithPath: target.path(percentEncoded: false), isDirectory: false)

        let validatedA = try guardInstance.validate(withTrailingSlash)
        let validatedB = try guardInstance.validate(withoutTrailingSlash)

        #expect(validatedA.path == ProtectedPaths.normalize(target))
        #expect(validatedB.path == ProtectedPaths.normalize(target))
        #expect(validatedA.path == validatedB.path)
    }
}
