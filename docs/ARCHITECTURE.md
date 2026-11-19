# Cruftless — Architecture

Last updated: 2026-09-07
read_when: onboarding to the codebase, deciding where a new component belongs,
or tracing how a click in the popover becomes a deleted file.

Companion docs: `REQUIREMENTS.md` (scope and product decisions), `UI.md`
(screens and visual tokens), `CLAUDE.md` (non-negotiable safety rules).

---

## 1. The shape of the thing

Cruftless is a macOS menu bar app that finds Xcode / CoreSimulator disk bloat
and permanently deletes it. Two targets:

```
CruftlessCore/           SPM package, Swift 6 language mode, macOS 26+
  Sources/CruftlessCore     57 files. No SwiftUI, no AppKit. All the logic.
  Sources/CruftlessFixtures Preview/test fixtures. Every file #if DEBUG.
  Tests/CruftlessCoreTests  44 files, 257 tests, 47 suites.

Cruftless/               SwiftUI app target, 22 files.
  CruftlessApp.swift        @main, MenuBarExtra(.window) + Settings scene
  AppModel.swift            The single @Observable owner of app state
  SettingsModel.swift       Login item, reminders, protected paths
  Views/                    11 view files + 3 shared components
```

The split is load-bearing, not cosmetic. Everything that decides *what may be
deleted* lives in Core, because those decisions are only worth anything
unit-tested. A view file doing filesystem work is a bug, not a shortcut.

`CruftlessFixtures` is a normal library product (not test-only) so the app
target can import it for `#Preview` bodies — but every source file inside is
wrapped in `#if DEBUG`, and every app-side import is too.

---

## 2. The one diagram worth having

```
                       ┌─────────────────────────────┐
   MenuBarExtra ──────▶│         AppModel            │  @MainActor @Observable
                       │  inventory, navigationPath  │
                       └──┬────────┬────────┬────────┘
                          │        │        │
              ┌───────────▼──┐  ┌──▼──────┐ └──▶ SettingsModel
              │  ScanEngine  │  │Simulator│         └─ ProtectedPathsStore
              │   (actor)    │  │ Service │
              └───────┬──────┘  │ (actor) │
                      │         └────┬────┘
        LocationCatalog│              │ DeviceStore / ImagesPlist / SimctlRunner
        RootResolver   │              │            └── BoundedProcess
        DirectoryWalker│              │
                      ▼              ▼
                 ┌──────────────────────────┐
                 │       Inventory          │   ← what the popover renders
                 └────────────┬─────────────┘
                              │  user picks a row action
                              ▼
                 ┌──────────────────────────┐
                 │    DeletionPlanner       │   throws, never returns nil
                 │      + PathGuard         │   ← the safety chokepoint
                 └────────────┬─────────────┘
                              │  DeletionPlan
                              ▼
                 ┌──────────────────────────┐
                 │  ReviewView (mandatory)  │   ← nothing deletes before this
                 └────────────┬─────────────┘
                              │  user confirms
                              ▼
                 ┌──────────────────────────┐
                 │   DeletionExecutor       │   sole caller of removeItem
                 │   (actor)                │   sole caller of simctl mutations
                 └────────────┬─────────────┘
                              ▼
                        DeletionResult → ResultView
```

Read it top to bottom and you have the whole app: **scan → plan → review →
execute → report**. Every feature is a variation on that pipeline.

---

## 3. Core, module by module

### 3.1 `Locations/` — what we track and where it lives

| Type | Job |
|---|---|
| `TrackedLocation` | A value describing one bloat location: id, platform, title, icon, `Tier`, whether it has a drill-down, staleness source, `SizeSource`, `MutationPolicy`, Review consequence, a discovery-issue closure, and root resolvers. |
| `LocationCatalog` | The 17 tracked locations, as static values. Android rows remain read-only inventory; Gradle's separate one-entry planner route requires a transient risk acknowledgement. |
| `DevelopmentPlatform` / `ActiveCatalog` | Saved Apple/Android scope plus an immutable generation-tagged view of the active location catalog. |
| `RootResolver` | Turns a location into concrete filesystem URLs. `RootResolver+CustomLocationPolicy.swift` holds the policy gate for Xcode's custom Derived Data / Archives preferences (`RootPolicy`, `customRoot`, `refusalReason`). |
| `RootPreferenceIssue` | Why a configured custom location was refused, with user-facing copy. |
| `Staleness` | `StalenessSource` (how a row's age is determined) + `StalenessInfo` (the date, and the "Unused for 6 weeks" label) + `Staleness.resolve`, the one switch over `StalenessSource` that both `ScanEngine` (top-level rows) and `DrillDownProvider` (per-child rows) call, so a new `StalenessSource` case can't be handled in one and missed in the other. |
| `DrillDownProvider` | Lists a location's immediate children as `ChildEntry` rows. Skips symlinks. |
| `ArchiveDates` | Reads `.xcarchive` creation dates in the `Archives/<date>/<App>.xcarchive` layout, so the top-level row and its drill-down agree on the date. |
| `XcodeInstallDiscovery` | Finds `Xcode.app` bundles via bounded `mdfind` (3 s) with `/Applications/Xcode.app` fallback. |
| `ActiveToolchain` | Reads Xcode's `DVTDefaultToolchainOverrideIdentifer` default to warn when you're about to delete the toolchain you're building with. |

Two fields on `TrackedLocation` carry most of the interesting behaviour:

- **`mutationPolicy`** — `.pathDeletion`, `.simctl`, or `.readOnly`. Android
  locations declare `.readOnly`; whole-location and batch routes always refuse.
  Gradle has one separate planner route for a recognized immediate cache child:
  it requires an in-memory, single-use acknowledgement bound to the child path
  and policy generation, then passes through PathGuard, fingerprint checks, and
  the normal Review flow. Studio, SDK, and AVD plans remain refused. Simulator
  devices and runtimes declare `.simctl`, and the planner refuses a path plan
  for them at all.
- **`sizeSource`** — `.filesystemRoots` (walk the roots) or
  `.simulatorRuntimes` (ask `SimulatorService`). Runtimes live in a root-owned
  store the app must not walk, so that location resolves zero roots and is sized
  from `simctl` / `images.plist` instead.

**Consequence copy is location data.** The one-line sentence Review shows for a
whole-location clear (REQUIREMENTS §10) is `TrackedLocation.consequence`, set
beside the title and tier in `LocationCatalog`. It used to be a `switch` over
catalog ids inside `DeletionPlanner`, where a location added without its copy
fell silently through to the generic tier sentence;
`TrackedLocation.defaultConsequence(for:)` is now the explicit fallback. The
planner only *decorates* the copy — `DeletionPlanner+ActiveToolchain` prepends
the active-toolchain warning — and never authors it.

`resolveDefaultRoots` distinguishes a redirected root from a built-in one. If
Xcode points Derived Data at a folder of your choosing, that folder is never
deleted as a folder — `wholeLocation` plans its *children* as named rows.

**`RootResolver.customRoot`** is the policy for outside configuration. A value
from `com.apple.dt.Xcode` is untrusted input: relative paths, `/`,
home-containing paths, protected locations, and paths overlapping another
tracked root all fall back to the default *and* surface a `RootPreferenceIssue`
— never a silent substitution.

Android roots are deliberately narrower: defaults and documented environment
variables are inspected without launching Android tools or evaluating project
configuration. Unsupported, conflicting, and out-of-home roots are surfaced as
unavailable/incomplete rather than treated as complete coverage. Studio
`idea.system.path` and AVD `.ini` metadata are read from bounded files;
recognized same-home redirects are inventoried and protected. SDK package
identity and revision come from bounded `source.properties`; AVD drill-downs
resolve registry entries to one per-device row. Detail screens show each
scanned root's source label and exact path. Studio, SDK, and AVD remain
read-only. The Gradle location contributes only the measured bytes from
recognized direct cache children to the cleanable total; those children can
be planned from Detail after a warning that does not guarantee writer
exclusion. The process cannot observe every invocation-specific IDE or
terminal override. `InventorySnapshot` persists this aggregate but never the
child listing, so restored rows still cannot be planned before a fresh scan.

`SettingsModel` persists non-empty platform identifiers and advances
`platformGeneration` on scope changes. `AppModel` prunes disabled rows and
routes, invalidates scan/watcher work and Reviews, then scans the replacement
`ActiveCatalog`. Scan events and executor plans carry the generation. The
executor refuses stale plans at admission and marks unstarted batch work as not
attempted if the generation changes during execution. Settings reject scope
edits while a deletion is active.

### 3.2 `Scan/` — measuring bytes

| Type | Job |
|---|---|
| `ScanEngine` (actor) | Orchestrates a full scan: a `TaskGroup` per location, yields an `AsyncStream<ScanEvent>`, caches the inventory and per-child sizes in memory. A request carrying a newer generation discards those caches (`adopt`); walks still queued on `walkQueue` read the generation through `ScanGenerationGate` and skip themselves once superseded. |
| `DirectoryWalker` | The actual walk, over `DirectoryEntryReader` entries; never `FileManager` enumeration. `walkWithChildren` splits a root by immediate child in the same pass. Files are counted before subdirectories are entered, so one directory is open at a time per level. |
| `DirectoryEntryReader` | `getattrlistbulk(2)` per directory and `getattrlist(2)` per root: type, identity, link count, allocated size, dates, mount status and the APFS sharing attributes in one call. An entry the bulk read reports an error for falls back to `lstat`. |
| `CloneTally` | Counts a clone family's shared blocks once, and only when every member is inside the measured tree. |
| `Dirent` | Decodes a `dirent`'s fixed-size `d_name` field into a `String` — one helper shared by every `readdir` call site in Core (`DrillDownProvider`, `ArchiveDates`, `DeviceStore`). |
| `SizeAccumulator` / `SizeResult` | Running allocated and exclusive totals, newest mtime, and a count + first path of directories that couldn't be opened. |
| `InodeSet` | Thread-safe `(device, inode)` set for hardlink dedup. |
| `AtomicBundles` | `.app`, `.xcodeproj`, `.xcarchive`, `.xcworkspace` are single items, never trees to break apart. |
| `VolumeCapacity` | Total / free / purgeable / used, for the header bar. |
| `FSEventsInvalidator` | FSEvents stream over the deletable roots, tagged by owning location (`WatchedRoot`). Attributes each event to the locations it landed under and debounces *per location*, so a build under Derived Data rescans Derived Data alone. An unattributable path yields `InvalidationScope.everything`. Roots are watched as `ProtectedPaths.normalize` spells them, whether or not they exist yet: FSEvents matches by path, so a Derived Data created by a later build still reports. Re-registering an unchanged set keeps the running stream. |
| `RescanThrottle` | A minimum gap (60s) between two *automatic* rescans of the same location. The debounce assumes bursts of writes end; with a simulator booted they never do, so without this the app rescans without pause. Held locations are released when their quiet period ends, never dropped. A user-initiated scan does not pass through it. |
| `ScanScheduler` | Decides when each scan runs: one at a time, later requests merged into one pending request, background ones throttled. Background requests are declined before the session's first scan (that scan walks everything after them) and queued while a deletion runs. `AppModel` keeps no scheduling state of its own. |
| `ScanRootWalking` | The read-only half of a scan — readable-root filtering, the walk, staleness, incomplete-scan copy. Takes its inode set as a parameter, which is what lets a partial rescan reuse it. |
| `ScanSignposts` | `os_signpost` around scan phases. |

Design points worth internalising:

- **Sizes are APFS-allocated** (`ATTR_FILE_ALLOCSIZE`, equal to
  `st_blocks * 512`), with hardlinks deduplicated by `(volume, inode)`.
  `SizeResult.exclusiveBytes` is also measured, with clone-shared blocks counted
  only when the whole family is inside the tree, but nothing reads it yet, so
  `Inventory.sizesAreUpperBound` stays `true` and the header keeps its "upper
  bound" note.
- **Symlinks are leaves.** The walker sizes a symlink as itself and never
  follows it.
- **An unreadable directory is counted, not skipped.** `SizeResult` carries the
  count and first offending path so the scan emits `ScanEvent.failed` *after*
  `.locationScanned` — the row shows its partial size, and the notice explains
  why it's partial. The order matters and is asserted by tests.
- **The breakdown is a projection of a walk that already happened.** The scan
  visits every byte anyway, so keeping the per-path split costs bookkeeping
  rather than I/O, and it is what lets a drill-down open from cached sizes
  instead of re-walking. `ChildBreakdown.sizes` is keyed by **resolved path**,
  not by name: depth is not expressible in a name, and two roots routinely hold
  a same-named child. `recordingDepth` says how far down to record —
  `DrillDownProvider.sizeRecordingDepth(for:)` asks for 2 on Archives, whose
  rows are the `.xcarchive`s inside date folders rather than the folders
  themselves; a root that is itself a bundle records only itself, because for
  Xcode installs the bundle is the row. Recording deeper changes where a size
  is written down, never the order the bytes are visited in, so it cannot move
  a total or disturb the hardlink attribution that depends on that order.
- **Drill-downs walk with a fresh `InodeSet` only for what is not cached.**
  Sharing the scan's set meant every already-seen hardlink sized to 0 on the
  second visit. A row served from the cache instead carries the scan's own
  attribution — which is what makes a Detail total sum to the List row.
- **`ScanEngine.children(of:)` runs on `walkQueue`, never on the actor.** It was
  a synchronous actor-isolated method calling blocking C, so an open drill-down
  blocked the scan that was measuring it. It is now the *cold* path only — the
  one a click takes before this session's first scan has covered the location.
- **The scan produces what a drill-down renders.** Each location that has one
  yields `DrillDownContent` on a `ScanEvent.locationContents`, after its
  `.locationScanned` and built on `walkQueue` from the breakdowns the walk just
  produced. `AppModel.drillDowns` mirrors it on the main actor so `openDetail`
  can answer with no suspension, and the three Detail screens are renderers with
  no fetch of their own. Deliberately not a field on `InventoryEntry`: that type
  is persisted, and a persisted listing would bypass the per-location restored
  gate (`AppModel.isRestored(_:)`).
- The inventory cache is **in-memory, per-process**. Nothing persists across
  launches.

### 3.3 `Simulators/` — CoreSimulator, read directly, mutated only via `simctl`

| Type | Job |
|---|---|
| `SimulatorService` (struct) | The read-only façade: `devices()`, `runtimes()`, `knownBloat(for:)`. A `Sendable` value over two immutable fields — it was an actor whose methods were mostly `nonisolated`, and nothing here mutates anything. Planning moved out (see below), so `Simulators/` no longer imports a single `Safety/` type. |
| `DeviceStore` | Parses `device.plist` files directly via `opendir` — no subprocess. Reading is fine; only mutation needs `simctl`. |
| `ImagesPlist` | Parses `/Library/Developer/CoreSimulator/Images/images.plist`. |
| `SimctlRunner` / `DefaultSimctlExecutor` | Typed wrapper over `/usr/bin/xcrun simctl` (JSON parsing, typed errors), using the shared validated toolchain selection. |
| `SimctlIdentifier` | Validates every identifier before a spawn. A UDID must be a UUID; a runtime must not be `all` / `booted` / a flag / a path. |
| `UnavailableDetector` | Reconciles devices against installed runtimes; flags and sorts orphans first. |
| `SimDevice` / `SimRuntime` / `SimDeviceState` | Value models. |

`runtimes()` merges two sources and is deliberate about failure: plist ∪ simctl
when both work, either alone when the other fails, and **throws** when neither
can answer. That last case matters because `UnavailableDetector.reconcile`
reads an empty runtime list as "no runtimes installed" and flags every device —
so an empty list must be an established fact, never a stand-in for a failed
lookup.

Plist-only rows stay browseable but carry no simulator mutation capability or
confirmed deletion identifier. `SimulatorToolchainResolver` is the shared
authority for scan, cold listing, planning, execution, and runtime-removal
confirmation. It validates the Xcode bundle and simulator commands without
changing global selection, records a generation on live simulator listings and
plans, and holds an operation lease so every command in a reviewed mutation
uses one validated Xcode. Stale or fallback listings remain visible but cannot
authorize simulator mutations. Android-only scans do not resolve Xcode tools.

`Settings → Support` exposes explicit refresh and local Xcode selection (applied
when the picker changes; candidates load when the tab opens). Its
diagnostic report builder accepts structured allowlisted fields only; SDK issue
reasons and metadata statuses come from the authoritative bounded reader, while
relative paths remain confined to the local SDK detail view. The exact report
preview is copied or saved only on user action. No diagnostic data is sent to
the issue tracker or uploaded.

Toolchain discovery deduplicates and validates at most eight candidates in
parallel. `xcrun --find simctl` has a 2-second timeout and the runtime-list
probe 6 seconds, since a cold CoreSimulatorService (first call after login or
an update) can take seconds to answer; Settings refresh can run one
selection-resolution pass and a separate candidate-choice pass. Each probe
returns a `SimulatorToolchainProbe`: a timeout resolves to `.probeFailed`
("could not be checked within the time limit"), rejected or unsupported
candidates to `.unavailable`, whose guidance asks the user to finish Xcode
component/license prompts. Only a ready resolution is cached; a failed one is
kept for the Support pane but probed again on the next `resolve()`, so one slow
probe at launch does not mark every simulator row unknown for the session. A successful
empty runtime list keeps its toolchain ID and generation in the immutable
runtime listing catalog, so unavailable devices can still be planned safely;
the empty list is not confused with a failed lookup.

**Every simulator plan is built by `DeletionPlanner`.** The four `plan*`
methods used to sit on `SimulatorService`, and `KnownBloat` used to live in this
folder — which made `Simulators/` depend on `Safety/` for `DeletionTarget`,
`PathGuard`, `ValidatedPath` and `DeletionPlanningError` while `Safety/`
depended back on `Simulators/` for `SimctlRunner`. They are now
`DeletionPlanner.simulatorErase / .simulatorDelete / .simulatorBloat /
.runtimeDelete` in `Safety/DeletionPlanner+Simulators.swift`, with
`Safety/KnownBloat.swift` beside them. Refusals are unchanged: same
`DeletionPlanningError` cases, same `SimctlIdentifier` validation before any
identifier can reach a spawn, same protected-descendant check against the store
each `simctl` command deletes out of.

`KnownBloat` builds a `PathGuard` rooted at that specific device's `data/`
directory and attaches a `DeletionPrecondition.simulatorShutdown` to every
target, so the executor re-reads `device.plist` right before deleting. A device
booted while Review was open is refused at execute time.

`SimctlRunner.shutdown(udid:)` treats "already shut down" as success: `simctl
shutdown` exits non-zero on a device that is already off. The fast path
matches the literal stderr substring `current state: Shutdown`; when that
misses, it falls back to re-reading the device's `device.plist` (through an
injectable `deviceStateReader` seam, defaulting to a real `DeviceStore` read)
and checks `SimDeviceState.isShutdown`, so a reworded Apple string degrades to
a slower check rather than a false failure.

### 3.4 `Safety/` — the part that actually matters

This is the module to read first if you're touching anything.

**The chain of custody for a path:**

```
URL from a scan/drill-down
   │
   ▼  PathGuard.validate(_:)  or  .validateRoot(_:)
ValidatedPath              ← opaque receipt, only PathGuard constructs it
   │  + Fingerprint.capture(at:)   (inode, device, mtime, type, resolved path)
   ▼
DeletionTarget.path(...)   ← carries both, plus tier/consequence/bytes
   │
   ▼  DeletionPlan (single or batch)  →  ReviewView  →  user confirms
   ▼
DeletionExecutor
   • fingerprint.path == validatedPath.path?     else refuse
   • precondition still holds?                   else refuse
   • fingerprint.verify(at:) → .valid?           else refuse
   • FileManager.removeItem(at:)                 ← the only call in the codebase
```

| Type | Job |
|---|---|
| `PathNormalizer` | Deterministic normalization: lexical first (`~`, `.`, `..`, trailing slash), then `realpath` of the longest *existing* ancestor with the rest appended verbatim. `package`-visible; `Fingerprint` and `DeletionExecutor` call it directly rather than through `ProtectedPaths.normalize`/`.standardize`, which exist for the denylist's own use. |
| `ProtectedPaths` | The denylist. System roots, home subdirs, other users' folders, `/Volumes` mount points, every `device.plist`, and the CoreSimulator device-set structure. Plus **structural anchors** — paths that must never sit *inside* a target. |
| `ProtectedPathsStore` | Persists the user's own protected paths, stored **unresolved**. |
| `PathGuard` | Allowlist + denylist enforcement. Produces `ValidatedPath`. |
| `ValidatedPath` | Opaque receipt. The executor accepts nothing else. |
| `Fingerprint` | Filesystem identity at plan time; re-verified immediately before deletion. |
| `DeletionPlanner` (+`+ActiveToolchain`, +`+Simulators`) | Builds plans — every plan in the app, paths and `simctl` mutations alike. Every refusal throws a `DeletionPlanningError`. Consequence copy is not written here — it comes from `TrackedLocation.consequence` (or a `ChildEntry`'s own), decorated with the active-toolchain warning. |
| `DeletionPlanningError` | The one refusal vocabulary, with the user-facing copy written once on `errorDescription`. Its own file: it is public API for every planner entry point and for `KnownBloat`. |
| `KnownBloat` | The one bounded path-deletion exception inside a device: `Library/Caches`, `tmp`, `PRBPosterExtensionDataStore` under a **shut-down** device's `data/`, behind a `PathGuard` rooted at that device's `data/`. A planner, so it lives here rather than in `Simulators/`. |
| `PlanningContext` | The planner's dependencies as one `Sendable` value: the user's `ProtectedPaths`, Xcode's active-toolchain override, and the children provider for a redirected root. Built once per plan by `AppModel.plan(_:)` (`PlanningContext.live`). It replaced three defaulted parameters threaded through every entry point, one of which re-read `UserDefaults` on every call from whatever isolation the caller was in. |
| `DeletionPlan` / `DeletionTarget` / `DeletionPrecondition` | The reviewable value. `DeletionPlan.affectedLocationIds` (set by the planner factories) → `rescanScope`, the locations the post-deletion rescan must re-measure. |
| `DeletionExecutor` (actor) | Executes. Sole caller of `removeItem` and of the `simctl` mutation protocol. Runs the two-phase settle after `simctl` mutations (see `SpaceSettleDetector`) and reports what it is doing through `DeletionProgress`. Its `capacitySampler` / `deviceDirectory` / `settleSleep` seams make both phases testable without a real disk. |
| `SpaceSettleDetector` | The settle rule as a pure state machine: five quiet 1 s samples within a 64 MB tolerance plus ≥ 90 % of the expected bytes arrived, capped at `max(60, bytes/105 MB)` samples. Also `SpaceSettleOutcome` (`.settled` / `.capped`) with the capped note's copy. |
| `DeletionProgress` | What a run is doing right now — `(verb, targetName, phase)` with the user-facing labels ("Erasing iPhone 17 Pro…", "freeing space, this can take a minute") written here, beside `DeletionPlanningError`'s copy. |
| `DeletionResult` / `ItemOutcome` | Per-item outcomes including `partiallyFailed` and `notAttempted(reason: NotAttemptedReason)` — `.cancelled` (the run was cancelled before the executor reached it) or `.executorBusy` (a second, overlapping `execute` call was refused outright); neither is a failure, both excluded from `failedCount`. |

**Why `PathNormalizer` exists at all.**
`URL.standardizedFileURL.resolvingSymlinksInPath()` is not a function of the
path alone — it resolves symlinks only for the parts that exist. So `/tmp/X`
became `/private/tmp/X` while its nonexistent child `/tmp/X/child` stayed
`/tmp/X/child`, and prefix matching between a root and a target inside it failed
on spelling. Everything in the safety layer normalizes through this one type.

**`validate` vs `validateRoot`.** Two entry points, deliberately asymmetric:

- `validate(_:)` — for a target *inside* a root. Refuses a root itself, requires
  strict `root + "/"` prefix matching (so `/foo/barbaz` never matches root
  `/foo/bar`). Never widen this to admit a root.
- `validateRoot(_:)` — the *only* entry point that may return a root, for a
  deliberate whole-location clear. Demands exact equality with an allowlisted
  root, refuses `/`, applies the denylist.

Both refuse a target whose final component is a symlink, and both refuse a
target that *contains* a protected path — because every path delete is
recursive. Roots themselves are vetted in `PathGuard.init` via
`ProtectedPaths.isUsableRoot`, since roots arrive from resolvers that read
outside configuration.

**Why `Fingerprint.verify` doesn't check directory mtime.** It ticks on every
child added or removed, so checking it refused nearly every Derived Data clear
made while Xcode was running. A user refused three times reaches for `rm -rf`,
which has no checks at all. Identity (resolved path + inode + device + type) is
the guarantee; mtime is only meaningful for files.

**Two enforcement points for "never `rm -rf` a simulator":**
1. `TrackedLocation.mutationPolicy == .simctl` → `DeletionPlanner` refuses to
   build a path plan.
2. `ProtectedPaths.isCoreSimulatorStructure` refuses everything at or above
   `CoreSimulator/Devices/<udid>/data` structurally, whatever the allowlist says.

**Failure honesty.** `removefile` is not atomic — a recursive delete that hits an
immutable child has already removed part of the tree. `DeletionExecutor`
re-walks the remainder and reports `partiallyFailed` with the bytes actually
freed. Batches never abort early: every item in a plan gets an outcome, and
even a cancelled run returns one outcome per item.

**Where the blocking work runs.** The whole check-then-delete sequence for a
path — precondition read, `fingerprint.verify`, `removeItem`, and the recovery
re-walk — blocks for as long as the disk takes, so `DeletionExecutor` hops it
onto a private serial `DispatchQueue` and suspends on a continuation rather than
parking a cooperative-pool thread for the length of a 40 GB delete.
`Task.detached` would not do: it draws from the same pool. The sequence is
unchanged and still runs on one thread, so the window between `verify` and
`removeItem` is no wider than before. The settle's phase-one confirmation walks
(`DirectoryWalker` over the device directory) run on the same queue; the wait
itself only samples capacity and sleeps, so it suspends cooperatively and
blocks nothing.

**Reentrancy.** Because that branch now suspends, and an actor excludes callers
only *between* suspension points, `execute` holds a private `isExecuting` flag
for the length of a run. A second, overlapping plan is refused rather than
interleaved: it comes back with one `.failed` outcome per item carrying
`DeletionExecutor.concurrentRefusalReason`, so the result screen says why
instead of showing a silent no-op. `AppModel.isDeleting` is a display flag, not
a lock.

### 3.5 `Process/BoundedProcess` — every subprocess

One type, four guarantees: absolute executable path (never `/usr/bin/env`, never
`PATH` resolution), a minimal child environment (`DEVELOPER_DIR` and `DYLD_*`
stripped, `PATH` pinned), pipes drained on a handler *before* waiting, and a
timeout that actively sends SIGTERM then SIGKILL.

The last one is subtle: a task group racing a sleep against
`withCheckedContinuation` never returns on the one input the timeout exists for
— a child that never exits — because the group waits for every child and
cancellation doesn't resume a continuation. The timeout task must terminate the
process itself, and the termination handler must be installed before `run()`.
The SIGKILL half of that escalation hangs off the termination waiter's own
state rather than an `isRunning` check — Foundation reaps the child, so a pid
read before the signal can already belong to somebody else; the check and the
`kill` happen under the lock the termination handler also takes.

Neither wait blocks a thread. The exit wait bridges `Process.terminationHandler`
to `await`; the final EOF wait — the short grace that lets the pipe handlers'
last empty-`availableData` callback land after the child exits — used to be a
`DispatchGroup.wait(timeout:)`, which parked a cooperative-pool thread for up to
two seconds per spawn. It is now `group.notify` racing a deadline timer on one
serial queue, with a `ResumeOnce` box so exactly one of them resumes the
continuation. Deliberately not a task group racing `Task.sleep`, for the reason
above: that shape never returns on a stream that never closes, which is the only
input the bound exists for. The group's two `enter()`s are retired by an
idempotent per-stream `finish`, and tearing the read handlers down finishes
whatever they still owed: an over-`leave` traps the process outright, and a
stream detached before EOF would otherwise leave the group short forever.

Two callers: `DefaultSimctlExecutor` and `XcodeInstallDiscovery`.

### 3.6 `Model/`, `Naming/`, `Settings/`

- **`Model/`** — `Tier` (regen / judgment / irreversible / reveal / info; the
  first three are deletable, `irreversible` is the flagged ⚠ one),
  `InventoryEntry` (`.sized` with per-root `RootSize` breakdown and an optional
  `LocationAccessNeed` for roots it skipped, `.unavailable` with a reason, or
  `.needsAccess` when every root is behind a protected area), `Inventory`, `ChildEntry`, `ScanEvent`,
  `RowIcon`, `ScanProgress` (what a scan someone is watching has covered so
  far — planned locations, landed rows, what is still pending, and the running
  deletable-tier total; a value type in Core because the interesting part is the
  arithmetic and the app target has no test bundle), plus `InventorySnapshot` /
  `InventoryStore` — the last scan's rows
  written to `Application Support/Cruftless/inventory.json` so the popover has
  something real to show at launch. `Inventory` cannot be `Codable` itself (a
  `TrackedLocation` holds the closures that resolve its roots), so the snapshot
  stores location ids and numbers and rehydrates against the live catalog,
  dropping rows whose location has left it. Capacity is never persisted: it is
  re-queried on every launch, because free space is the one number that must not
  come from a file. The store is best effort in both directions — a missing,
  unreadable or malformed file is "no snapshot", never an error to report.
- **`Naming/`** — `DeviceIdentifierTable` + `BuildNumberParser` + `Naming` turn
  `iPhone18,1 27.0 (24A5418b)` into `iPhone 17 Pro · iOS 27.0 beta`.
  `ByteFormatter` for sizes.
- **`Settings/`** — `LaunchAtLoginPolicy` (translating `SMAppService.Status`
  into a sentence, shown from the status alone — `register()` returns without
  throwing when macOS parks the item in `.requiresApproval`),
  `ProtectedPathRejection`, `SettingsControlPolicy` (which General controls lock
  during a deletion and what they report), and `ScanReminderScheduler` (the
  weekly `UNCalendarNotificationTrigger` request, which keeps a pending
  request's countdown, and the non-prompting permission check).

### 3.7 `Access/` — what the scan may open

macOS raises a privacy alert the first time an app *opens* a file or *lists* a
folder in Documents, Desktop, Downloads, iCloud Drive / file providers, or
(assumed) a removable or network volume. Metadata calls (`stat`, `lstat`,
`access(F_OK)`, `realpath`, `statfs`, `fileExists`, starting an FSEvents
stream) never do, and a missing path is always `ENOENT`. The planning note
`.planning/first-run-experience/ACCESS_MECHANISM.md` has the measurements.

| Type | Job |
|---|---|
| `ProtectedArea` / `AreaAccessState` | The six areas, and `notAsked` vs `notAllowed`. |
| `ProtectedAreaClassifier` | Path in, area or nil out. Checks the path as written and with symlinks resolved (`PathNormalizer`), compares against `root + "/"`, and asks an injected `statfs` inspector whether a `/Volumes/<name>` path is local, network, or the boot volume. Home and volume inspection are injected. |
| `AccessLedger` | Persists one fact per area, "asked", under `cruftless.accessAskedAreas` in an injected `UserDefaults`. |
| `AccessGate` | `check(url)` is `.clear` or `.blocked(area)`; `partition(roots, for:)` splits a location's roots into `GatedRoots` (`clear`, `blocked: [BlockedAccess]`). `GatedRoots` has a file-private init, so only the gate makes one. `AccessGate.shared` is the app's. |
| `LocationAccessNeed` / `BlockedAccess` | The typed blocked state that reaches the UI and `inventory.json`: which roots, which area, asked or refused, and a reason ("Xcode-beta.app", "Derived Data location"). |
| `AccessPreflight` | Metadata-only: resolves the catalog (one Spotlight query) and groups existing protected roots by area with reasons. Feeds `AccessOverview`. |
| `AccessRequest` | The only code allowed to open in an unasked area. Opens the area's root once through an injected opener, maps the result to allowed / denied, and only then marks the area asked; a non-permission failure leaves it unasked. One area per call, no UI. |
| `AccessOverview` | The access list: `AccessAreaSummary` (area, `AccessAreaStatus` not asked / allowed / not allowed, reasons) for every area with a need or already asked. Reads an asked area's status by opening its root once; never opens an unasked one. Holds the Privacy & Security > Files and Folders URL. |
| `AccessService` | `load(catalog)` and `request(summary)` as injectable closures, both off the caller's thread. `.live` shares one request slot across the process, so a second request while macOS's alert is up throws `AccessRequestError.requestInFlight`. `AccessAnswer` tells the host which locations an answer changed. |
| `FileAccessAudit` | Package-internal seam every read and listing on the scan's paths reports through (`openDirectory`, `contentsOfDirectory`, `data(contentsOf:)`, `record`). No-op unless a test observes it. |

Where the gate is enforced:

- **`ScanEngine.run`** partitions every location's resolved roots once, before
  `.planned`; the walk, staleness reads and drill-down contents only ever see
  `GatedRoots.clear`. Scans and rescans share this path.
- **`ScanEngine.scanFilesystemLocation(_:roots:...)`** (Android drill-down)
  and **`DrillDownProvider.loadChildren`** (cold drill-down, planning's
  `childrenProvider`) partition through the same `AccessGate.partition`.
- **`RootResolver.listAVDRegistry`** is the one place the Android resolvers
  list an AVD registry; it, and `androidAVDInventory`'s per-device reads, ask
  the gate first. A blocked registry counts as unresolved redirect metadata,
  which keeps `ProtectedPaths` protecting the whole home.
- **`SimulatorToolchainResolver.probe(candidate:gate:)`** returns
  `.blocked(area)` before reading `Info.plist` or running `xcrun` with that
  `DEVELOPER_DIR`.

A root in an asked area whose open still fails is reported `notAllowed`
(`ScanEngine+Access`), never as a generic unreadable folder. FSEvents
registration is not gated. Deletion is unchanged: `PathGuard` stays the only
authority on what may be deleted, and `DeletionPlanner.wholeLocation` refuses
any row carrying a `LocationAccessNeed` with `DeletionPlanningError.needsAccess`.

---

### 3.8 `Welcome/` — the first run

- **`WelcomePolicy`** decides whether the welcome window shows (not completed,
  no saved scan), which steps it has (the access step only when something needs
  access, after the platform choice it depends on), how stepping moves (the
  scan step has no way back), and holds the safety promise copy.
- **`WelcomeScanSummary`** turns `ScanProgress`, the inventory and a failure
  into what the last step shows: phase, cleanable total, a capped list of rows,
  the folded remainder, and the sentence and action for places not measured.
- **`PlatformDetection`** reports which platforms are present using metadata
  and Spotlight only, and `DetectedPlatforms` turns that into the selection to
  preselect and the note under each checkbox.

The app side is `WelcomeModel` (step state, preselection through
`SettingsModel`, the access check for the current selection, completion flag)
and `Views/Welcome/`. `AppModel.isWelcomePending` holds every automatic scan
until `welcomeDidFinish()`, which `WelcomeModel.advance()` reaches on entering
the scan step and `finish()` reaches when the window closes first.

## 4. The app target

### 4.1 `AppModel` — one observable, main-actor state owner

Owns `inventory`, `scanScheduler` (and `activeScan`, read from it), `navigationPath`, `planFailure`,
`runningAppsWarning`, `freeSpaceDelta`, `preferenceIssues`, and the three Core
services (`ScanEngine`, `SimulatorService`, `DeletionExecutor`).

Notable responsibilities:

- **Launch lives in `AppModel+Launch`.** `MenuBarExtra(.window)` does not build
  its content until the icon is clicked, so the popover used to be the only
  thing that ever started a scan. `AppDelegate.applicationDidFinishLaunching`
  calls `startAtLaunch()`, which restores the last session's rows, registers
  FSEvents, and schedules the first scan ~5s out — late enough not to fight the
  login I/O storm, since nobody is waiting on it. `popoverDidAppear()` repeats
  only the running-apps check and routes through the same
  `startInitialScanIfNeeded` gate, so an early open scans at once and the timer
  does not then start a second one.
- **The Low Power Mode gate covers the unattended scan only.** If Low Power Mode
  is on when the timer fires, the scan is held, `isAutomaticScanPaused` says so
  in the footer, and a watcher on `NSProcessInfoPowerStateDidChange` runs it
  when the mode ends — deferred, never dropped. A scan the popover or Refresh
  asks for is never gated: someone is looking at it.
- **Restored rows are never planned from.** `AppModel.scannedLocationIds` holds
  the ids a scan actually landed this session (`ScanEvent.locationScanned`, not
  `.failed` and not a merged inventory's ids), and `AppModel.isRestored(_:)`
  gates each row on its own location. `DeletionPlanner.wholeLocation`
  reads `entry.roots` and copies each root's recorded size into Review, and for a
  redirected root it plans children out of a cache no scan has filled yet — so a
  plan built from restored rows would show a number read out of a file, or come
  back empty. `ListView` refuses the action with copy that says why and starts
  the scan instead; the per-row rescan control is the one action that works on a
  restored row, and it makes exactly that row fresh.
- **`scanProgress` is filled in only for a full scan someone asked for.** A
  partial rescan has no denominator worth showing and a background one is
  deliberately invisible, so the decision is taken once at the start of `run`
  (a user request that lands mid-scan can promote `activeScan`, and progress
  recorded from halfway through a plan never seen would draw an empty
  checklist). It is reset at the start of every scan, not only at the end,
  because `run` is re-entered for a queued scope.
- **`activeScan` says who asked, not just that something is running.** `.user`
  (launch, Refresh, a settings change, the rescan after a deletion) drives the
  header spinner and the "Scanning…" placeholder through `isScanning`;
  `.background` (an FSEvents invalidation) drives nothing that looks busy — the
  footer's "Scanned …" timestamp moving is the whole report. A user request that
  lands while a background rescan is running promotes the display to `.user`,
  because a scan really is in flight and theirs is queued behind it.
- **`executeDeletion` guards re-entry** with `isDeleting`, captures free space
  before and after so `ResultView` can show what actually moved (not just what
  the plan claimed), then replaces `.review` with `.result` in the stack so Back
  never lands on an already-executed plan. After execution it starts a rescan
  scoped to `plan.rescanScope` rather than a full `refreshScan()`.
- **`reportPlanFailure`** is the sink for every refusal. A refusal the user
  can't see is a dead button.
- **`plan(_:)`** is the one wrapper every screen uses to build a plan: it opens
  Review on success and reports `error.localizedDescription` on any throw. No
  view re-authors refusal copy per case — a `default` branch there prints a raw
  error description for the next case anyone adds. It also builds the
  `PlanningContext` and hands it to the closure, so the protected-path list and
  Xcode's toolchain override are read once per plan, here, rather than once per
  planner call on the main actor. A screen with children already in hand — the
  list, clearing a redirected root — passes `context.withChildren`.

### 4.2 Navigation

`AppRoute` is `.detail(TrackedLocation) | .review(DeletionPlan) |
.result(DeletionResult)`, and `MainView` switches on `navigationPath.last`.

This is a hand-rolled stack, not `NavigationStack`. Inside
`MenuBarExtra(.window)` a `NavigationStack` insists on drawing its own
navigation bar — a second back button above the one each screen draws — and
`.navigationBarBackButtonHidden` doesn't exist on macOS. Sanctioned by `UI.md`
§1. It also keeps the popover to exactly one `.frame`.

List and Detail are pinned to `PopoverMetrics.height`; Review and Result size to
their content via a `ContentHeightPreference` that each measures and reports
(`ScrollView` has no reliable ideal size to ask for).

`onDisappear → popToRoot()` — reopening the popover never shows a stale screen.

### 4.3 Views

```
MainView          popover root, the push stack, height resolution
├── ListView          capacity header + 13 location rows + footer
├── DetailScreen      routes by location.id:
│   ├── DetailView            plain folder drill-downs
│   ├── SimulatorsDetailView  devices, sectioned by runtime, unavailable first
│   └── RuntimesDetailView    installed runtimes
├── ReviewView        the mandatory confirm step
└── ResultView        per-item outcomes + real free-space delta

SettingsView (separate window) → GeneralSettingsPane, AccessSettingsPane,
                                  SupportSettingsPane
                                  (SupportToolchainSection, DiagnosticReportSection),
                                  AboutSettingsPane

Access/      AccessListModel (@Observable over AccessService) + AccessListView
             (reusable grouped Form: Settings and the welcome window),
             AccessSettingsPane, BlockedAccessRow (Detail "Not measured" row),
             openAccessSettings environment action set by MainView

Components/  PopoverChrome (metrics, header, footer, placeholder, hairline)
             PopoverRow (row + action + icon + caption)
             LoadStateView (loading/error/empty/content branching, used by
             SimulatorsDetailView and RuntimesDetailView)
             SettingsPaneSizing (fits a settings Form to its content, capped)
             AppModel+Previews
DesignTokens tier words, tier colors, action labels, the sudo dyld command
CapacityBarView / CategoryRowView
```

`SimulatorsDetailView`'s and `ListView`'s fixture-heavy `#Preview` blocks live
in sibling `<View>+Previews.swift` files, split out once the host file
approached the 500-line ceiling.

UI constraints that are architectural, not stylistic:

- **No modals.** `MenuBarExtra(.window)` resigns key focus, so `.sheet` and
  `.alert` are unreliable and can dismiss the whole popover mid-interaction.
  Review is a pushed screen.
- **Checkbox selection shares the popover.** Select Items pushes a screen
  scoped to one detail location. AppModel retains selection and its routes
  across dismissal; each request still passes through Review and confirmation.
- **Flagged rows never join a batch.** `DetailView` filters them out of "Clear
  All" and shows a line saying so; `DeletionPlanner.wholeLocation` refuses a
  flagged location outright, and `DeletionPlan.batch` filters as belt-and-braces.
- **Every view has `#Preview` coverage** in `#if DEBUG`, covering empty /
  loading / populated / error states. Views take preview-only init seams
  (`previewChildren`, `previewDevices`, …) so a preview never races the real
  filesystem or `simctl`.

---

## 5. Two traces worth following

### 5.1 A scan

0. At launch, `AppModel.startAtLaunch()` restores the last session's snapshot
   into `inventory` (with live capacity), registers the FSEvents stream, and
   schedules step 1 for ~5s later — or holds it, in Low Power Mode, until the
   mode ends. Opening the popover brings step 1 forward.
1. `startInitialScanIfNeeded` → `refreshScan()` → `ScanEngine.scan()`.
2. The engine awaits `RootResolver.prepare()` (one bounded `mdfind` for Xcode
   installs), and resets the `InodeSet` and child cache. `VolumeCapacity` is
   queried after the walk (step 4), so a long scan publishes a capacity from
   the end of its walk rather than the start.
3. A `TaskGroup` runs one `scanSingleLocation` per catalog entry. Each either
   asks `SimulatorService.runtimes()` (runtimes location) or filters its roots
   to the readable ones and calls `DirectoryWalker.walkWithChildren` — on
   `ScanEngine.walkQueue`, not on the actor. The walk is blocking C that never
   suspends, so running it on the actor's executor starved the parent's
   `for await` until every child had finished and delivered the whole scan in
   one burst at the end. The queue is serial: one location at a time, in catalog
   order, exactly as before; only the delivery changes. Per-child sizes come
   home in the `LocationOutcome` and are filed under `childSizeCache` by the
   parent, since the walk can no longer touch actor state.
3b. Before that group starts, roots are resolved once for every location — two
   of those resolvers read Xcode's preferences and one reads Spotlight's answer,
   so the walk takes them as a parameter instead of resolving again — and passed
   through `AccessGate.partition` (§3.7): a blocked root is reported on the row,
   never walked. Then
   `.planned([TrackedLocation])` names, in catalog order, the locations that will
   produce a row (`ScanRootWalking.willProduceRow`: a runtimes location always
   does; a filesystem one needs at least one root that exists). It is the second
   event, after `.started`.
4. Each outcome yields `.locationScanned(entry)`, then `.failed(...)` if the
   walk couldn't read everything. `AppModel` collects failures and updates
   progress.
5. `.completed(Inventory)` lands; the engine caches it; `AppModel` sets
   `inventory`, unions this scan's landed ids into `scannedLocationIds`, writes the snapshot to disk
   (synchronously, on the main actor — scans are serialized there, so the write
   inherits their order and cannot land out of sequence), clears the spinner
   unconditionally, and recomputes `preferenceIssues`.
6. `FSEventsInvalidator` will later fire (debounced per location) with an
   `InvalidationScope`. `.locations(ids)` runs `ScanEngine.rescan(locationIds:)`,
   which walks only those roots and merges the result into the cached inventory;
   `.everything` runs a full `refreshScan()`. An invalidation arriving while a
   scan is in flight is merged into `ScanScheduler.pending` and run when that scan
   finishes, never dropped. Two gates apply to background requests only: before
   the session's first scan they are declined, since a rescan with no cached
   inventory is a full scan that would skip the launch delay and the Low Power
   Mode pause; during a deletion they wait in `pending`, so no walk races the
   delete, and `resumeDeferredScans()` runs them when it ends. After each
   completed scan `startMonitoring` re-registers the roots, which restarts the
   stream only when a root's resolution changed.

   A background invalidation passes `RescanThrottle` first. The queue above is
   otherwise a treadmill: a booted simulator writes under the Previews cache and
   the device set every few seconds, so the next invalidation is already queued
   before the scan it triggered has finished, and the next scan starts the
   instant that one ends — forever. Locations inside their 60s quiet period are
   held, and `AppModel.scheduleThrottleWake` releases them when it expires.

   Two things a partial rescan deliberately does differently. It walks with a
   fresh `InodeSet`, because the locations it is not walking have already
   recorded their inodes and reusing the shared set would size the rescanned
   location's hardlinks to 0 — the same trade `children(of:)` makes, and it can
   only push the aggregate up, which is already published as an upper bound. And
   it is authoritative only for the locations it walked: `AppModel` keys scan
   failures by location id so clearing Derived Data's notice cannot discard the
   one Archives reported.

### 5.2 A deletion

1. User taps "Clear" on a Derived Data child row in `DetailView`. The action
   goes through `AppModel.plan(_:)`, which builds one `PlanningContext` for
   this plan and passes it in.
2. `DeletionPlanner.child(_:in:context:)`:
   location deletable? → path-deletion policy? → child tier deletable? →
   `PathGuard.validate(child.url)` → `Fingerprint.capture` → build
   `DeletionTarget.path` with tier, consequence copy, and bytes.
3. Any refusal throws a `DeletionPlanningError`; `AppModel.plan(_:)` catches
   and calls `reportPlanFailure` with the error's own copy. No silent `try?`
   anywhere on this path, and no per-case copy in a view.
4. `AppModel.openReview` re-checks whether Xcode / Simulator are running and
   pushes `.review(plan)`.
5. `ReviewView` shows the size, the item list, each item's consequence, the
   running-apps notice (informational, never a refusal), and the confirm label
   the plan carries.
6. Confirm → `AppModel.executeDeletion` (re-entry guarded) → free space read →
   `DeletionExecutor.execute(plan)` with an `onProgress` callback that feeds
   `AppModel.deletionProgress`, rendered by Review while `isDeleting`.
7. Per item: fingerprint/validated-path agreement → precondition → fresh
   `verify` → `removeItem`. A failure is re-measured for partial success. No
   item aborts the batch.
8. A `simctl` target runs the two-phase settle before its outcome exists: phase
   one confirms the mutation (erase: the device directory walks under 64 MB;
   delete: the directory is gone; runtime: `awaitRuntimeRemoval` inside
   `deleteRuntime`), phase two waits for free space to settle
   (`SpaceSettleDetector`). `.path` targets skip both.
9. `DeletionResult` → free space read again (after the settle, so the delta is
   real) → a rescan scoped to `plan.rescanScope` (the locations the plan touched; `.everything` when the set is empty) → `.review`
   replaced by `.result` → `ResultView` shows outcomes, the real delta, and any
   capped-settle notes.

A simulator action takes the same trace: step 2 is
`DeletionPlanner.simulatorErase` / `.simulatorDelete` / `.simulatorBloat` /
`.runtimeDelete` instead, and step 7 hands the target to `SimctlRunner` rather
than to `removeItem` (except known bloat, which is a guarded path delete with a
shutdown precondition).

---

## 6. Enforcement you get for free

Beyond types, three mechanical guards:

- **SwiftLint custom rules.** `no_raw_removeitem` forbids
  `FileManager.removeItem` outside `Safety/DeletionExecutor.swift`;
  `no_raw_posix_delete` forbids `unlink` / `rmdir` / `removefile` / `trashItem`
  outside that file plus the test-only `Support/TestFileSystem.swift`.
- **The type system.** `DeletionExecutor` accepts only `ValidatedPath`, which
  only `PathGuard` can construct (`package init`).
- **Tests.** Every tracked location needs a test proving the guard rejects paths
  outside its root before the location ships. The deletion-path audit
  (2026-09-06) findings each landed with a regression test — see
  `REQUIREMENTS.md` §9.

Build and verify:

```bash
swift test --package-path CruftlessCore
```

```bash
swiftlint --strict
```

```bash
xcodebuild -project Cruftless/Cruftless.xcodeproj -scheme Cruftless -destination 'platform=macOS' build
```

`make fmt` runs swiftformat; `make run` builds and relaunches.

---

## 7. Where to put new code

| You're adding… | It belongs in… |
|---|---|
| A new bloat location | `LocationCatalog` + a `RootResolver` function + a guard-rejection test |
| A rule about what may be deleted | `DeletionPlanner` or `ProtectedPaths`, never a view |
| A new way to measure something | `Scan/`, behind `DirectoryWalker` or `ScanEngine` |
| Anything that spawns a process | Through `BoundedProcess`, with an absolute executable |
| A simulator mutation | `SimctlRunner` + the `SimulatorCommandExecuting` protocol; its *plan* goes in `DeletionPlanner+Simulators`, never on `SimulatorService` |
| Presentation, copy, layout | `Views/` and `DesignTokens` only |
| A preview fixture used twice | `CruftlessFixtures`, not a one-off double in a view file |
| Any read of a path the app did not choose | Behind `AccessGate` (`partition` for roots, `check` for one path), reporting through `FileAccessAudit` |

Keep files under ~500 LOC — `SimulatorsDetailView.swift` (455) and
`ListView.swift` (407) are the current ceiling-scrapers.
