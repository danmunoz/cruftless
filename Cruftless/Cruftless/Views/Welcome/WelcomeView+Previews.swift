#if DEBUG
    import CruftlessCore
    import CruftlessFixtures
    import ServiceManagement
    import SwiftUI

    #Preview("1 Where it lives") {
        WelcomeView(model: .preview(step: .location), accessList: .preview([]), app: AppModel())
    }

    #Preview("2 Safety promise") {
        WelcomeView(model: .preview(step: .safety), accessList: .preview([]), app: AppModel())
    }

    #Preview("Illustrations, light") {
        VStack(spacing: 16) {
            WelcomeMenuBarIllustration()
            WelcomeReviewIllustration()
        }
        .padding(40)
        .frame(width: WelcomeWindow.width)
        .preferredColorScheme(.light)
    }

    #Preview("3 Setup, Apple only") {
        WelcomeView(model: .preview(step: .setup), accessList: .preview([]), app: AppModel())
    }

    #Preview("3 Setup, both platforms, access step follows") {
        WelcomeView(model: .preview(
            step: .setup,
            hasAccessNeeds: true,
            detected: DetectedPlatforms(hasApple: true, hasAndroid: true, xcodeInstallCount: 2),
            settings: .preview()
        ), accessList: .preview(PreviewFixtures.accessAreasNotAsked), app: AppModel())
    }

    #Preview("3 Setup, still checking") {
        WelcomeView(
            model: .preview(step: .setup, detected: nil, settings: .preview()),
            accessList: .preview([]),
            app: AppModel()
        )
    }

    #Preview("3 Setup, login item needs approval") {
        WelcomeView(model: .preview(
            step: .setup,
            settings: .preview(launchAtLoginStatus: .requiresApproval, platforms: [.apple])
        ), accessList: .preview([]), app: AppModel())
    }

    #Preview("4 Access, as first seen") {
        WelcomeView(
            model: .preview(step: .access, hasAccessNeeds: true),
            accessList: .preview(PreviewFixtures.accessAreasNotAsked),
            app: AppModel()
        )
    }

    #Preview("4 Access, one place in each state") {
        WelcomeView(
            model: .preview(step: .access, hasAccessNeeds: true),
            accessList: .preview(PreviewFixtures.accessAreasMixed),
            app: AppModel()
        )
    }

    #Preview("4 Access, waiting for macOS") {
        WelcomeView(
            model: .preview(step: .access, hasAccessNeeds: true),
            accessList: .previewAwaitingAnswer(PreviewFixtures.accessAreasNotAsked, requesting: .documents),
            app: AppModel()
        )
    }

    #Preview("4 Access, request changed nothing") {
        WelcomeView(
            model: .preview(step: .access, hasAccessNeeds: true),
            accessList: .preview(PreviewFixtures.accessAreasNotAsked, failing: .downloads),
            app: AppModel()
        )
    }

    #Preview("5 Scan, starting") {
        WelcomeView(model: .preview(step: .scan), accessList: .preview([]), app: AppModel())
    }

    #Preview("5 Scan, part way through") {
        WelcomeView(model: .preview(step: .scan), accessList: .preview([]), app: .previewScanning())
    }

    #Preview("5 Scan, finished") {
        WelcomeView(model: .preview(step: .scan), accessList: .preview([]), app: .previewPopulated())
    }

    #Preview("5 Scan, finished with places not measured") {
        let app = AppModel.previewPopulated()
        let blocked = PreviewFixtures.accessNeedEntries
        let blockedIds = Set(blocked.map(\.id))
        app.inventory = Inventory(
            entries: PreviewFixtures.sampleEntries.filter { !blockedIds.contains($0.id) } + blocked,
            capacity: PreviewFixtures.sampleCapacity
        )
        return WelcomeView(model: .preview(step: .scan), accessList: .preview([]), app: app)
    }

    #Preview("5 Scan, failed") {
        let app = AppModel()
        app.setScanFailure("The folder could not be read.", for: LocationCatalog.derivedData.id)
        return WelcomeView(model: .preview(step: .scan), accessList: .preview([]), app: app)
    }
#endif
