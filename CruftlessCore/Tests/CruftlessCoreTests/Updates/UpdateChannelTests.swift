import CruftlessCore
import Foundation
import Testing

@Suite("Update channel detection")
struct UpdateChannelTests {
    @Test("An Apple silicon Caskroom entry is a cask install")
    func appleSiliconCaskroom() {
        let channel = UpdateChannel.detect { $0 == "/opt/homebrew/Caskroom/cruftless" }
        #expect(channel == .homebrewCask)
    }

    @Test("An Intel Caskroom entry is a cask install")
    func intelCaskroom() {
        let channel = UpdateChannel.detect { $0 == "/usr/local/Caskroom/cruftless" }
        #expect(channel == .homebrewCask)
    }

    @Test("No Caskroom entry is a direct download")
    func noCaskroom() {
        #expect(UpdateChannel.detect { _ in false } == .directDownload)
    }

    @Test("Another cask in the Caskroom does not count")
    func otherCask() {
        let channel = UpdateChannel.detect { $0 == "/opt/homebrew/Caskroom" || $0 == "/opt/homebrew/Caskroom/other" }
        #expect(channel == .directDownload)
    }

    @Test("Detection asks only about the two Caskroom entries")
    func checksOnlyCaskroomPaths() {
        var asked: [String] = []
        _ = UpdateChannel.detect { asked.append($0); return false }
        #expect(asked == UpdateChannel.caskroomPaths)
    }

    @Test("Only a cask install offers the brew command and its delay note")
    func copyPerChannel() {
        #expect(UpdateChannel.homebrewCask.upgradeCommand == "brew upgrade cruftless")
        #expect(UpdateChannel.homebrewCask.availabilityNote != nil)
        #expect(UpdateChannel.directDownload.upgradeCommand == nil)
        #expect(UpdateChannel.directDownload.availabilityNote == nil)
        #expect(!UpdateChannel.directDownload.summary.contains("Homebrew"))
    }

    @Test("The releases link points at this project's GitHub Releases")
    func releasesURL() {
        #expect(UpdateChannel.releasesURL.absoluteString == "https://github.com/danmunoz/cruftless/releases")
    }
}
