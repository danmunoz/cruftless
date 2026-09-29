#if DEBUG
    import CruftlessCore
    import Foundation

    enum AboutUpdatePreviewFixtures {
        static let release = CruftlessRelease(
            version: "1.2.0",
            releaseURL: URL(string: "https://github.com/danmunoz/cruftless/releases/tag/v1.2.0")!
        )
    }
#endif
