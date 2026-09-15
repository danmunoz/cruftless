import CruftlessCore
import Darwin
import Testing

@Suite("Dirent name decoding")
struct DirentTests {
    private static func makeEntry(name: String) -> dirent {
        var entry = dirent()
        withUnsafeMutableBytes(of: &entry.d_name) { buf in
            let bytes = Array(name.utf8) + [0]
            for (index, byte) in bytes.enumerated() {
                buf[index] = byte
            }
        }
        return entry
    }

    @Test("Decodes an ordinary file name")
    func decodesOrdinaryName() {
        var entry = Self.makeEntry(name: "MyApp.xcarchive")
        #expect(Dirent.name(of: &entry) == "MyApp.xcarchive")
    }

    @Test("Decodes the empty name")
    func decodesEmptyName() {
        var entry = Self.makeEntry(name: "")
        #expect(Dirent.name(of: &entry) == "")
    }

    @Test("Decodes dot and dot-dot, same as readdir would report them")
    func decodesDotEntries() {
        var dot = Self.makeEntry(name: ".")
        var dotDot = Self.makeEntry(name: "..")
        #expect(Dirent.name(of: &dot) == ".")
        #expect(Dirent.name(of: &dotDot) == "..")
    }
}
