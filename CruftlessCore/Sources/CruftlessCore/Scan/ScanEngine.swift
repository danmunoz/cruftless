import Foundation

public actor ScanEngine {
    /// Lists the installed simulator runtimes.
    public typealias RuntimeLister = @Sendable () async throws -> [SimRuntime]

    /// Lists runtimes together with the toolchain authority captured by that lookup.
    public typealias RuntimeCatalogLister = @Sendable () async throws -> SimulatorRuntimeListing

    /// Lists the simulator devices, reconciled against a runtime list the scan has already fetched.
    public typealias DeviceLister = @Sendable ([SimRuntime]) -> [SimDevice]
    var cachedCurrentInventory: Inventory?
    var currentGeneration: UInt64 = 0
    var cachedGradleCacheCleanableBytes: Int64 = 0

    /// Sizes captured during the scan, keyed by location id, then by resolved root path, then by each measured path under it.
    var childSizeCache: [String: [String: [String: SizeResult]]] = [:]

    private let signposts = ScanSignposts.shared
    private let runtimeLister: RuntimeCatalogLister
    private let deviceLister: RuntimeCatalogDeviceLister

    /// Ceiling on the `simctl` call that sizes the runtimes row.
    package static let simctlScanTimeout: Duration = .seconds(10)

    /// Creates a scan engine with optional simulator data providers.
    public init(
        runtimeLister: RuntimeLister? = nil,
        deviceLister: DeviceLister? = nil,
        runtimeCatalogLister: RuntimeCatalogLister? = nil
    ) {
        let service = SimulatorService(
            simctlRunner: SimctlRunner(
                executor: DefaultSimctlExecutor(timeout: Self.simctlScanTimeout)
            )
        )
        if let runtimeCatalogLister {
            self.runtimeLister = runtimeCatalogLister
        } else if let runtimeLister {
            self.runtimeLister = {
                SimulatorRuntimeListing(runtimes: try await runtimeLister())
            }
        } else {
            self.runtimeLister = { try await service.runtimeListing() }
        }
        if let deviceLister {
            self.deviceLister = { deviceLister($0.runtimes) }
        } else {
            self.deviceLister = { service.devices(reconciledAgainst: $0) }
        }
    }

    /// What scanning one location produced: the row (if any) and, separately, a reason the row's number is incomplete.
    struct LocationOutcome: Sendable {
        let locationId: String
        let entry: InventoryEntry?
        let failure: String?
        var childBreakdowns: [String: [String: SizeResult]] = [:]
        /// What this location's drill-down should render.
        var contents: DrillDownContent?
    }

    /// Where the walks run.
    private static let walkQueue = DispatchQueue(
        label: "com.danmunoz.cruftless.scan.walk",
        qos: .default
    )

    /// Runs blocking work on `walkQueue` and suspends until it is done.
    private func offActor<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Self.walkQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Performs a full scan over all catalog locations with concurrent per-root execution.
    public func scan(
        catalog: [TrackedLocation] = LocationCatalog.all,
        generation: UInt64 = 0
    ) -> AsyncStream<ScanEvent> {
        guard generation >= currentGeneration else { return Self.finishedStream() }
        currentGeneration = generation
        return run(locations: catalog, merging: false, generation: generation)
    }

    public func rescan(
        locationIds: Set<String>,
        catalog: [TrackedLocation] = LocationCatalog.all,
        generation: UInt64 = 0
    ) -> AsyncStream<ScanEvent> {
        guard generation >= currentGeneration else { return Self.finishedStream() }
        currentGeneration = generation
        guard cachedCurrentInventory != nil else {
            return scan(catalog: catalog, generation: generation)
        }
        let subset = catalog.filter { locationIds.contains($0.id) }
        guard !subset.isEmpty else {
            return AsyncStream { $0.finish() }
        }
        return run(locations: subset, merging: true, generation: generation)
    }

    private static func finishedStream() -> AsyncStream<ScanEvent> {
        AsyncStream { $0.finish() }
    }

    private func run(locations: [TrackedLocation], merging: Bool, generation: UInt64) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.started)
                if locations.contains(where: { $0.id == LocationCatalog.xcodeInstalls.id }) {
                    await RootResolver.prepare()
                }
                guard generation == self.currentGeneration else {
                    continuation.finish()
                    return
                }

                // A full scan shares one inode set across every location, so a file hardlinked into two of them is counted once overall.
                let inodes = InodeSet()
                if !merging {
                    self.childSizeCache = [:]
                    self.cachedGradleCacheCleanableBytes = 0
                }

                // Resolved once, here, and carried into the walk.
                let resolved = locations.map { (location: $0, roots: $0.resolveRoots()) }

                continuation.yield(.planned(
                    resolved.filter { Self.willProduceRow($0.location, roots: $0.roots) }.map(\.location)
                ))

                let collectedEntries = await self.walkAndYield(
                    resolved,
                    inodes: inodes,
                    generation: generation,
                    into: continuation
                )
                guard generation == self.currentGeneration else {
                    continuation.finish()
                    return
                }
                // Captures volume capacity after walking.
                let volumeCapacity = VolumeCapacity.query()

                let inventory = Self.assembledInventory(
                    from: collectedEntries,
                    scanned: locations,
                    capacity: volumeCapacity,
                    cachedInventory: merging ? self.cachedCurrentInventory : nil,
                    optInReclaimableBytes: self.cachedGradleCacheCleanableBytes
                )

                self.cachedCurrentInventory = inventory
                continuation.yield(.completed(inventory))
                continuation.finish()
            }
        }
    }

    /// Walks every resolved location and yields what each produced, in the order the walks land.
    private func walkAndYield(
        _ resolved: [(location: TrackedLocation, roots: [URL])],
        inodes: InodeSet,
        generation: UInt64,
        into continuation: AsyncStream<ScanEvent>.Continuation
    ) async -> [InventoryEntry] {
        let lister = runtimeLister
        let gradleRoots = resolved.first { $0.location.id == LocationCatalog.gradleCaches.id }?.roots ?? []
        let runtimesTask: Task<SimulatorRuntimeListing, any Error>? =
            resolved.contains(where: { Self.needsRuntimes($0.location) })
                ? Task { try await lister() }
                : nil

        var collected: [InventoryEntry] = []

        await withTaskGroup(of: LocationOutcome.self) { group in
            for (location, roots) in resolved {
                group.addTask {
                    await self.scanSingleLocation(
                        location,
                        roots: roots,
                        inodeSet: inodes,
                        runtimesTask: runtimesTask,
                        into: continuation
                    )
                }
            }

            for await outcome in group {
                guard generation == currentGeneration else { continue }
                childSizeCache[outcome.locationId] = outcome.childBreakdowns
                if outcome.locationId == LocationCatalog.gradleCaches.id {
                    cachedGradleCacheCleanableBytes = GradleCacheEntryPolicy.cleanableBytes(
                        in: outcome.contents?.children ?? [],
                        cacheRoots: gradleRoots
                    )
                }
                if let entry = outcome.entry {
                    collected.append(entry)
                    continuation.yield(.locationScanned(entry))
                }
                if let contents = outcome.contents {
                    continuation.yield(.locationContents(locationId: outcome.locationId, contents))
                }
                // Emits partial rows before their failure notices.
                if let failure = outcome.failure {
                    continuation.yield(.failed(locationId: outcome.locationId, reason: failure))
                }
            }
        }

        return collected
    }

    /// Lazily loads drill-down children for a specific location.
    public func children(of locationId: String, catalog: [TrackedLocation] = LocationCatalog.all) async -> [ChildEntry] {
        guard let location = catalog.first(where: { $0.id == locationId }) else {
            return []
        }

        // Read on the actor, before the hop: the closure below runs off it and must not touch stored state.
        let knownSizes = childSizeCache[location.id] ?? [:]

        return await offActor {
            ScanSignposts.shared.measure("LazyDrillDown") {
                DrillDownProvider.loadChildren(for: location, knownSizes: knownSizes)
            }
        }
    }

    /// Measures read-only Android roots and builds their coherent detail inventory.
    public func androidDrillDown(for location: TrackedLocation) async -> DrillDownContent? {
        guard location.platform == .android else { return nil }
        let roots = location.resolveRoots()
        return await offActor {
            ScanSignposts.shared.measure("AndroidDrillDown") {
                ScanEngine.scanFilesystemLocation(location, roots: roots, inodeSet: InodeSet()).contents
            }
        }
    }

    /// Scans one location and reports when measurement begins.
    private func scanSingleLocation(
        _ location: TrackedLocation,
        roots: [URL],
        inodeSet: InodeSet,
        runtimesTask: Task<SimulatorRuntimeListing, any Error>?,
        into continuation: AsyncStream<ScanEvent>.Continuation
    ) async -> LocationOutcome {
        switch location.sizeSource {
        case .simulatorRuntimes:
            // No walk to wait for: this row is the `simctl` lookup, so it is under way as soon as it is awaited.
            continuation.yield(.locationStarted(locationId: location.id))
            let runtimes = await Self.resolveRuntimes(runtimesTask)
            return scanRuntimesLocation(location, runtimes: runtimes.list?.runtimes, failure: runtimes.failure)

        case .filesystemRoots:
            // Awaited only where it is needed.
            let runtimes = Self.needsRuntimes(location)
                ? await Self.resolveRuntimes(runtimesTask)
                : (list: nil, failure: nil)
            let deviceLister = deviceLister

            return await offActor {
                continuation.yield(.locationStarted(locationId: location.id))
                return Self.scanFilesystemLocation(
                    location,
                    roots: roots,
                    inodeSet: inodeSet,
                    runtimeListing: runtimes.list,
                    runtimesFailure: runtimes.failure,
                    deviceLister: deviceLister
                )
            }
        }
    }

    private func scanRuntimesLocation(
        _ location: TrackedLocation,
        runtimes: [SimRuntime]?,
        failure: String?
    ) -> LocationOutcome {
        guard let runtimes else {
            let reason = failure ?? "Could not read the installed simulator runtimes."
            return LocationOutcome(
                locationId: location.id,
                entry: .unavailable(location: location, reason: reason),
                failure: nil,
                contents: .unavailable(reason)
            )
        }

        let total = runtimes.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return LocationOutcome(
            locationId: location.id,
            entry: .sized(
                location: location,
                reclaimableBytes: total,
                staleness: StalenessInfo(lastUsedDate: nil),
                roots: []
            ),
            failure: nil,
            contents: .runtimes(runtimes)
        )
    }
}
