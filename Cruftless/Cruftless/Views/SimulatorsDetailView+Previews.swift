import CruftlessCore
import SwiftUI

#if DEBUG
    private extension SimDevice {
        static func fixture(
            udid: String,
            name: String,
            runtime: String,
            state: SimDeviceState,
            lastUsedDaysAgo: Int?,
            isUnavailable: Bool = false
        ) -> SimDevice {
            SimDevice(
                udid: udid,
                name: name,
                runtime: runtime,
                state: state,
                lastUsedAt: lastUsedDaysAgo.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) },
                deviceDirectory: URL(fileURLWithPath: "/tmp/simulators/\(udid)"),
                isUnavailable: isUnavailable
            )
        }
    }

    private enum SimulatorsPreviewFixtures {
        static let iOS18 = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"
        static let iOS17 = "com.apple.CoreSimulator.SimRuntime.iOS-17-5"
        static let removedRuntime = "com.apple.CoreSimulator.SimRuntime.iOS-15-0"

        static let booted = SimDevice.fixture(udid: "1", name: "iPhone 17 Pro", runtime: iOS18, state: .booted, lastUsedDaysAgo: 0)
        static let staleShutDown = SimDevice.fixture(
            udid: "2", name: "iPhone 16", runtime: iOS18, state: .shutdown, lastUsedDaysAgo: 45
        )
        static let freshShutDown = SimDevice.fixture(
            udid: "3", name: "iPad Pro 13-inch", runtime: iOS17, state: .shutdown, lastUsedDaysAgo: 2
        )
        static let unavailable = SimDevice.fixture(
            udid: "4", name: "iPhone 13 mini", runtime: removedRuntime, state: .shutdown, lastUsedDaysAgo: 300, isUnavailable: true
        )

        static let devices = [booted, staleShutDown, freshShutDown, unavailable]

        static let sizes: [String: Int64] = [
            "1": 6_200_000_000,
            "2": 4_100_000_000,
            "3": 2_800_000_000,
            "4": 1_500_000_000
        ]

        static let bloat: [String: [BloatSubPath]] = [
            "2": [
                BloatSubPath(
                    relativePath: "Library/Caches",
                    title: "Caches",
                    allocatedBytes: 2_600_000_000,
                    url: URL(fileURLWithPath: "/tmp/simulators/2/data/Library/Caches")
                ),
                BloatSubPath(
                    relativePath: "tmp",
                    title: "Temporary files",
                    allocatedBytes: 900_000_000,
                    url: URL(fileURLWithPath: "/tmp/simulators/2/data/tmp")
                )
            ]
        ]
    }

    @MainActor
    private extension AppModel {
        static func previewSimulators(
            _ devices: [SimDevice] = SimulatorsPreviewFixtures.devices,
            sizes: [String: Int64] = SimulatorsPreviewFixtures.sizes
        ) -> AppModel {
            .previewDrillDown(
                .devices(devices, sizes: sizes),
                for: LocationCatalog.simulatorDevices.id
            )
        }
    }

    #Preview("Simulators: sectioned by runtime") {
        SimulatorsDetailView(
            location: LocationCatalog.simulatorDevices,
            model: .previewSimulators()
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Simulators: expanded known-bloat group") {
        SimulatorsDetailView(
            location: LocationCatalog.simulatorDevices,
            model: .previewSimulators(),
            previewBloat: SimulatorsPreviewFixtures.bloat,
            previewExpanded: ["2"]
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Simulators: no devices") {
        SimulatorsDetailView(
            location: LocationCatalog.simulatorDevices,
            model: .previewSimulators([], sizes: [:])
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Simulators: still reading") {
        SimulatorsDetailView(
            location: LocationCatalog.simulatorDevices,
            model: .previewPopulated()
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Simulators: load error") {
        SimulatorsDetailView(
            location: LocationCatalog.simulatorDevices,
            model: .previewDrillDownFailure(
                "CoreSimulator: permission denied",
                for: LocationCatalog.simulatorDevices.id
            )
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
