#if DEBUG
    import CruftlessCore
    import CruftlessFixtures
    import ServiceManagement
    import SwiftUI

    #Preview("1 Where it lives") {
        WelcomeView(model: .preview(step: .location), accessList: .preview([]))
    }

    #Preview("2 Safety promise") {
        WelcomeView(model: .preview(step: .safety), accessList: .preview([]))
    }

    #Preview("3 Access") {
        WelcomeView(
            model: .preview(step: .access, hasAccessNeeds: true),
            accessList: .preview(PreviewFixtures.accessAreasMixed)
        )
    }

    #Preview("4 Setup, Apple only") {
        WelcomeView(model: .preview(step: .setup), accessList: .preview([]))
    }

    #Preview("4 Setup, both platforms") {
        WelcomeView(model: .preview(
            step: .setup,
            detected: DetectedPlatforms(hasApple: true, hasAndroid: true),
            settings: .preview()
        ), accessList: .preview([]))
    }

    #Preview("4 Setup, still checking") {
        WelcomeView(model: .preview(step: .setup, detected: nil, settings: .preview()), accessList: .preview([]))
    }

    #Preview("4 Setup, login item needs approval") {
        WelcomeView(model: .preview(
            step: .setup,
            settings: .preview(launchAtLoginStatus: .requiresApproval, platforms: [.apple])
        ), accessList: .preview([]))
    }
#endif
