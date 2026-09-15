import CruftlessCore
import Foundation
import Testing

@Suite("Naming and Formatting Tests")
struct NamingTests {
    @Test("ByteFormatter produces base-1000 decimal outputs matching Finder")
    func byteFormatter() {
        let usLocale = Locale(identifier: "en_US")
        #expect(ByteFormatter.format(0, locale: usLocale) == "0 B")
        #expect(ByteFormatter.format(500, locale: usLocale) == "500 B")
        #expect(ByteFormatter.format(1000, locale: usLocale) == "1 KB")
        #expect(ByteFormatter.format(617_000_000, locale: usLocale) == "617 MB")
        #expect(ByteFormatter.format(10_000_000_000, locale: usLocale) == "10.0 GB")
        #expect(ByteFormatter.format(107_300_000_000, locale: usLocale) == "107.3 GB")
    }

    @Test("BuildNumberParser identifies beta builds via suffix and numeric threshold")
    func buildNumberParser() {
        #expect(BuildNumberParser.isBeta("24A5418b"))
        #expect(BuildNumberParser.isBeta("27A5252f"))

        #expect(BuildNumberParser.isBeta("24A5001"))

        #expect(!BuildNumberParser.isBeta("22G86"))
        #expect(!BuildNumberParser.isBeta("21A329"))
        #expect(!BuildNumberParser.isBeta("20F75"))
    }

    @Test("Naming.deviceSupportFolder formats Device Support names into human readable labels")
    func deviceSupportNaming() {
        let formattedBeta = Naming.deviceSupportFolder("iPhone18,1 27.0 (24A5418b)")
        #expect(formattedBeta == "iPhone 17 Pro · iOS 27.0 beta")

        let formattedRelease = Naming.deviceSupportFolder("iPhone17,1 18.0 (22A3354)")
        #expect(formattedRelease == "iPhone 16 Pro · iOS 18.0")

        let unknown = Naming.deviceSupportFolder("FutureGizmo99,1 30.0 (30A100)")
        #expect(unknown == "FutureGizmo99,1 · 30.0")
    }

    @Test("Naming.runtime formats CoreSimulator runtime identifiers")
    func runtimeNaming() {
        #expect(Naming.runtime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-6") == "iOS 18.6")
        #expect(Naming.runtime(identifier: "com.apple.CoreSimulator.SimRuntime.watchOS-11-0") == "watchOS 11.0")
        #expect(Naming.runtime(identifier: "com.apple.CoreSimulator.SimRuntime.xrOS-2-0") == "visionOS 2.0")
        #expect(Naming.runtime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", build: "27A5252f") == "iOS 27.0 beta")
    }

    @Test("Naming.derivedDataFolder strips the per-project hash suffix")
    func derivedDataFolderStripsHash() {
        #expect(Naming.derivedDataFolder("FossilVault-dbzuqmzipxtuqifhhncmvxywdnkl") == "FossilVault")
        #expect(Naming.derivedDataFolder("Cruftless-abcdefghijklmnopqrstuvwxyzab") == "Cruftless")
    }

    @Test("Naming.derivedDataFolder maps known system folder names to plain words")
    func derivedDataFolderMapsSystemFolders() {
        #expect(Naming.derivedDataFolder("ModuleCache.noindex") == "Module cache")
        #expect(Naming.derivedDataFolder("SDKStatCaches.noindex") == "SDK stat caches")
        #expect(Naming.derivedDataFolder("SymbolCache.noindex") == "Symbol cache")
        #expect(Naming.derivedDataFolder("CompilationCache.noindex") == "Compilation cache")
        #expect(Naming.derivedDataFolder("SDKExplicitPrecompiledModules") == "SDK precompiled modules")
        #expect(Naming.derivedDataFolder("Index.noindex") == "Index")
    }

    @Test("Naming.derivedDataFolder passes unrecognized names through unchanged")
    func derivedDataFolderPassthrough() {
        #expect(Naming.derivedDataFolder("Build.noindex") == "Build.noindex")
        #expect(Naming.derivedDataFolder("FossilVault-Dbzuqmzipxtuqifhhncmvxywdnkl") == "FossilVault-Dbzuqmzipxtuqifhhncmvxywdnkl")
        #expect(Naming.derivedDataFolder("FossilVaultXdbzuqmzipxtuqifhhncmvxywdnkl") == "FossilVaultXdbzuqmzipxtuqifhhncmvxywdnkl")
        #expect(Naming.derivedDataFolder("dbzuqmzipxtuqifhhncmvxywdnkl") == "dbzuqmzipxtuqifhhncmvxywdnkl")
    }
}
