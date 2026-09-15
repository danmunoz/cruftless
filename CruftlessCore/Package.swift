// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CruftlessCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "CruftlessCore", targets: ["CruftlessCore"]),
        .library(name: "CruftlessFixtures", targets: ["CruftlessFixtures"])
    ],
    targets: [
        .target(
            name: "CruftlessCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "CruftlessFixtures",
            dependencies: ["CruftlessCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CruftlessCoreTests",
            dependencies: [
                "CruftlessCore",
                "CruftlessFixtures"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
