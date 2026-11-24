# Cruftless — Requirements (v1)

- **Status**: signed off 2026-09-03 · updated 2026-09-29
- **Owner**: Daniel Munoz (`dev@danmunoz.com`)

## 1. Identity

| | |
|---|---|
| Name | Cruftless |
| Bundle ID | `com.danmunoz.Cruftless` |
| Repo | `~/Repos/cruftless` — MIT (`LICENSE`, `README.md` in tree; no git remote yet, so not public) |
| Distribution | Notarized DMG + Homebrew tap. Non-sandboxed. About offers a manual stable-release check; installation remains via `brew upgrade` or manual DMG download. |
| Min macOS | 26.0 |
| Toolchain | Swift 6.4, SwiftUI, `MenuBarExtra(.window)` |

Non-sandboxed is required: a sandboxed app would need `NSOpenPanel` bookmark
grants for `~/Library/Developer` and cannot spawn `simctl` freely.
`/Library/Developer` is root-owned and unwritable by any app, sandboxed or not.

## 2. Problem

Xcode accumulates tens of GB in locations the user never sees and macOS never
reclaims. Reference machine, 2026-09-03 (not a target): **~107 GB
app-reclaimable across 11 locations**, plus ~14 GB visible but not
app-deletable, on a 460 GB disk with 2.5 GB free.

Existing tools (XCleanup, ClearDisk, DevCleaner) cover the obvious paths but
miss: the Previews cache, simulator-internal bloat, runtimes as distinct from
device data, toolchains, and staleness signals.

## 3. Product decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Apple cleanup plus optional Android inventory; recognized Gradle caches require per-attempt risk acceptance | Gradle writers cannot be reliably excluded by this app, so the one-entry override states and accepts that risk without claiming concurrency safety |
| 2 | Overview, per-item actions, and Select Items share the existing popover | AppModel retains location-scoped selection and navigation across focus-loss dismissal |
| 3 | Selection screen uses checkboxes for eligible rows, starts empty, and always requires Review plus confirmation | A location-scoped selection keeps the exact requested set visible in the same popover navigation |
| 4 | Review step before every delete | Pushed view inside popover, not a sheet (focus conflict) |
| 5 | Permanent delete, never Trash | Trash frees no space until emptied — useless on a full disk |
| 6 | Scan once per process, FSEvents-invalidated cache | The first popover open in a process starts a scan automatically — Empty is only the frame before it starts, not an idle state; every later open reuses the in-memory inventory. The cache is in-memory only inside the `ScanEngine` actor: every relaunch re-walks. |
| 7 | Static menu bar icon | Consistent with on-demand scanning; never stale |
| 8 | Risky items shown, flagged, never auto-actioned | Archives hold dSYMs for shipped builds |
| 9 | No privileged helper | Everything deletable is reachable via user perms or `simctl`; root-owned paths are display-only |
| 10 | macOS 26 only | Single testable CoreSimulator storage model |
| 11 | No network, telemetry, or crash reporting | Destructive local tool; nothing leaves the machine |

## 4. Scope — tracked locations

Sizes are from the reference machine, 2026-09-03. `~/Library/Developer/Xcode/CodingAssistant` is deliberately not tracked: it holds assistant history and settings, not cache.

| Entry | Source | Ref size | Drill-down | Tier | Note |
|---|---|---|---|---|---|
| iOS/watchOS/tvOS/visionOS Device Support | `~/Library/Developer/Xcode/*DeviceSupport` | 26.0 GB | per OS build | regen | |
| Simulator devices | `~/Library/Developer/CoreSimulator/Devices` | 31.0 GB | per device → known-bloat paths | judgment | erase/delete destroys installed apps and app data; known-bloat sub-paths are `regen` |
| Simulator runtimes | `SimulatorService.runtimes()` (`images.plist` merged with `simctl runtime list -j`) | 23.6 GB | per runtime | judgment | re-download; this location resolves no filesystem roots at all — its size comes from `SimulatorService`, not a walk (`TrackedLocation.sizeSource == .simulatorRuntimes`); renders "Unavailable" if neither source can answer, same as any other unreadable location |
| Derived Data | resolved root, see below | 10.0 GB | per project + ModuleCache | regen | |
| Previews cache | `~/Library/Developer/Xcode/UserData/Previews` | 7.8 GB | — | regen | |
| Toolchains | `~/Library/Developer/Toolchains` | 6.5 GB | per toolchain | judgment | reinstall cost; warns if it is the toolchain Xcode is currently set to use (§9) |
| SwiftPM cache | `~/Library/Caches/org.swift.swiftpm` | 1.3 GB | — | judgment | re-download |
| Interface Builder support | `~/Library/Developer/Xcode/UserData/IB Support` | 617 MB | — | regen | |
| Archives | `~/Library/Developer/Xcode/Archives` | 186 MB | per archive | ⚠ | **dSYM loss** |
| Build products & logs | `~/Library/Developer/Xcode/…` | <100 MB | — | regen | |
| Xcode installs | Spotlight: `kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"` | 7.0 GB | per install | reveal | |
| Simulator dyld cache | `/Library/Developer/CoreSimulator/Caches/dyld` | 6.6 GB | — | ⓘ | root-owned |

**Tiers**

- `regen` — recreated automatically on next build/run. Safe.
- `judgment` — safe, but costs a reinstall, re-download, or app-data loss.
- `⚠` — real, non-recoverable consequences. Never auto-actioned, never in any
  future batch operation; consequence spelled out in the review step.
- `reveal` — size shown, no in-app delete. Row action is Reveal in Finder
  (`NSWorkspace.activateFileViewerSelecting`).
- `ⓘ` — size shown, not deletable by the app. Row action copies a `sudo`
  command to the clipboard.

**Root resolution**

- Derived Data root is `IDECustomDerivedDataLocation` from `com.apple.dt.Xcode` defaults when set, else `~/Library/Developer/Xcode/DerivedData`. Archives likewise honours `IDECustomDistributionArchivesLocation`. Per-workspace overrides are out of scope for v1.
- A custom location is untrusted input (`RootResolver.customRoot`), refused — default used instead, reason shown in the list — when relative, `/`, equal to or above the home folder, on the protected denylist or holding a protected anchor (`~/Library/Developer` holds the device set), or overlapping another tracked location's root. Empty is not a refusal case: treated as no preference, no `RootPreferenceIssue` raised. An accepted custom location is never itself cleared wholesale: its immediate children plan as individually named Review rows.
- **Protected areas.** A root that resolves into Documents, Desktop, Downloads, iCloud Drive or another file provider (`~/Library/Mobile Documents`, `~/Library/CloudStorage`), or a removable or network volume, is never opened or listed until macOS has asked the user about that area (`AccessLedger`); only `AccessRequest`, run from a user's control, opens there first. Classification is metadata only (`realpath`, `statfs`). A fully blocked location renders "Needs access to <area>" with its reason; Xcode installs measure the copies that are clear and report how many were not measured; a partly blocked location says so in its incomplete notice. A root in an asked area that still cannot be opened reads as not allowed by macOS. Planning a clear of any such row is refused (`DeletionPlanningError.needsAccess`). Xcode copies behind a blocked area are not simulator-tool candidates. A user who granted an area before this gate existed sees it as needing access until a later control lets them confirm it.
- Xcode installs are discovered by Spotlight (`mdfind`) through the bounded subprocess runner, with a 3 s discovery timeout and `/Applications/Xcode.app` fallback. Simulator toolchain resolution validates at most eight deduplicated candidates concurrently, with `xcrun --find simctl` bounded to 2 s and the runtime-list probe to 6 s; a timed-out probe reports `probeFailed`, and a failed resolution is re-probed on the next request rather than cached for the session; Settings refresh may perform a resolution pass and a separate candidate-choice pass.
- A tracked location whose root does not exist is omitted, not shown at 0 B. One that exists but cannot be read renders as "Unavailable" with the reason on hover ("Permission denied reading <path>"); one with *some* readable roots is shown sized on what could be read, with `ScanEvent.failed(locationId:reason:)` flagging the total as incomplete (§8) rather than hiding the bytes it did measure.
- Archives' drill-down descends one level into non-`.xcarchive` date folders and lists the archives found there as top-level rows. Dotfiles are listed in every drill-down (hiding them under-reported a whole-location clear's total). A root that is itself a bundle (`.app`/`.xcodeproj`/`.xcarchive`/`.xcworkspace`) becomes one row named after the bundle. Drill-down rows sort by size, descending.

Every available location opens a detail screen with an info button. It toggles
a collapsible inline explanation of the contents and deletion risks, including
the permanent-deletion reminder. Locations without child listings show a
summary and retain their existing reviewed cleanup or Copy Command action.
Opening a detail or its info panel never creates a deletion plan.

## 5. Simulator handling

- **Enumerate** by reading each `device.plist` directly — fast, no process spawn. Row name comes from the plist's `name`; no lookup table needed. Devices with `isDeleted == true` and dot-prefixed device directories are skipped — CoreSimulator's own ephemeral bookkeeping, not real devices.
- **Mutate** only via `simctl` (`erase`, `delete`, `runtime delete`). Never `rm -rf` on `Devices/` — it corrupts CoreSimulator's device set.
- **Exception**: known-bloat sub-paths inside a device's `data/` are deleted directly through PathGuard, because `simctl` has no partial-clear verb. Requires the device to be **Shutdown** — checked at plan time and again immediately before deletion, since Review can stay open while the user boots the device. PathGuard root is the device's own `data/` directory; `device.plist` and other CoreSimulator state are never targets. A sub-path at 0 B is hidden rather than listed empty; if all three are 0 B the group reads "Nothing cleanable inside this device."
  - `data/Library/Application Support/PRBPosterExtensionDataStore` (6.4 GB on ref machine) — "Poster extension data store"
  - `data/Library/Caches` — "Caches"
  - `data/tmp` — "Temporary files"
- Installed runtimes come from `images.plist` (schema verified 2026-09-03) merged with `simctl runtime list -j`, joined on runtime identifier; either source alone suffices, and if neither can answer the device list is an error state with Retry, never a list where every device reads "runtime removed". On a collision the fields are merged per source rather than one side winning wholesale: the plist owns naming (`name`, `build`) since it is the enumeration source, while `sizeBytes`, `identifier`, `isDeletable` and `state` come from `simctl`. The plist has no size field at all — `ImagesPlist` can only `stat` the image an entry names, and the current-OS runtime names a directory, which APFS allocates no blocks of its own — so a plist size is used only when `simctl` reports none; `identifier` must be simctl's per-instance UUID because that is what `simctl runtime delete` is handed; `isDeletable` is hardcoded `true` in `ImagesPlist` because the plist does not say, so "bundled with Xcode, not deletable" would be lost if the plist's value won; and `state` is `.unreported` from the plist, which stores it as an undocumented integer. The merged list sorts size-descending. A runtime the plist alone reports keeps its plist fields, size 0 included.
- **`simctl runtime delete` only starts the removal.** The command exits as soon as CoreSimulator accepts the request — measured at 350 ms for an 8.5 GB runtime — while `simdiskimaged` unmounts the runtime volume and unlinks its image afterwards, retrying for as long as anything still holds the mount. Two consequences, both required:
  - The executor does not report the delete until the runtime has left `simctl runtime list -j` (`SimctlRunner.awaitRuntimeRemoval`, polled at 1 s up to 90 s). A lookup that fails is not evidence of removal — it keeps waiting. If the runtime is still listed at the deadline the item is `failed` with 0 B freed and the copy "CoreSimulator accepted the delete but the runtime is still installed. It may still be removing in the background — scan again in a minute to check." Under-reporting freed bytes is the safe direction; the free-space line on Result is measured, not derived from the plan.
  - A runtime whose `state` is `Deleting` is not offered as a fresh delete. `SimRuntime.state` (`SimRuntimeState`, from `simctl`'s `state` field) drives `canPlanDelete`; the row caption reads "Removing…" with no action, and `DeletionPlanner.runtimeDelete` throws `runtimeBeingDeleted` if one reaches it anyway. Only `Deleting` blocks — `Unusable` stays deletable (`simctl runtime delete --unusable` exists for exactly those), and an unmodelled state is carried as `.other` rather than read as Ready.
- Device state mapping: `state` in `device.plist` (1 = Shutdown, 3 = Booted).
- A device whose runtime is gone is **unavailable**: ⚠ badge, sorted to the top of the device list, under a "Runtime removed" section header, row caption "<runtime> · Can't boot". It is pure dead weight and `Delete Simulator` is the only offered action.
- Per-device actions on a healthy device: `Erase` (`Shut Down and Erase` while booted) only — erase reclaims essentially all of a device's bytes, and deleting a working device is a configuration decision better left to Xcode's own Devices window. `Delete Simulator` is offered only for an unavailable device, and shuts a booted one down first, same as Erase.

## 6. Naming and display

Raw identifiers are unreadable. Ship a bundled device-identifier table plus a
build-number parser so rows render as **"iPhone 17 Pro · iOS 27.0 beta"**.
Needed for:

- Device Support folder names: `iPhone18,1 27.0 (24A5418b)`
- Runtime identifiers: `com.apple.CoreSimulator.SimRuntime.iOS-27-0` → `iOS 27.0`

Platform prefix ("iOS", "iPadOS", "watchOS", "tvOS", "visionOS") is inferred from the model-identifier prefix (`iPhone…`/`iPad…`/`Watch…`/`AppleTV…`/`Reality…`/`Vision…`); an unknown model falls back to the raw identifier. A runtime's `xrOS` platform token is rewritten to `visionOS`. Beta rule: final character is a lowercase letter, or numeric seed ≥ 5000.

Simulator device rows use `device.plist` `name` directly (§5).

Derived Data child folders strip Xcode's per-project hash — trailing `-` plus 28 lowercase ASCII letters (`FossilVault-dbzuqmzipxtuqifhhncmvxywdnkl` → `FossilVault`); six known `.noindex`/system folder names (`ModuleCache.noindex`, `SDKStatCaches.noindex`, `SymbolCache.noindex`, `CompilationCache.noindex`, `SDKExplicitPrecompiledModules`, `Index.noindex`) render as plain words instead.

Each Derived Data project folder's row also shows the project it was built from: the `WorkspacePath` key of the folder's `info.plist` (binary or XML, read with `PropertyListSerialization`), tilde-abbreviated, as the row's secondary text (`DerivedDataWorkspaceReader`, `Naming.abbreviatingHome`). The scan classifies every Derived Data child while it builds `DrillDownContent`: `.live(path)` when that path exists, `.orphaned(path)` when it is gone (the project was deleted or moved), and `.unknown` otherwise. `.unknown` is never orphaned: a missing, unreadable or malformed plist, an empty or relative path, a path under `/Volumes/<name>/` whose volume is not mounted (checked with `statfs`, symlinks resolved), and any existence check that fails with something other than `ENOENT`/`ENOTDIR` (a permission error, a dangling symlink). System folders such as `ModuleCache.noindex` record no workspace and stay `.unknown`. Other locations never read an `info.plist`.

Sizes are decimal (base 1000, matching Finder and Disk Utility). KB and MB render with no decimal place; GB and TB render with one.

## 7. Popover

**Header** shows: total capacity · free · **purgeable (separately)** ·
reclaimable. Rendered as the hero number — labeled "cleanable" — plus a
capacity strip with a legend (used · cleanable · purgeable · free). No app
name in the header; the status item already identifies the app.

- Free is physically available space from `URLResourceValues.volumeAvailableCapacity`. Purgeable is an estimate of additional reclaimable space: `max(0, …ImportantUsage − free)`. The opportunistic allowance is not physical free space. Clamp both partitions to total capacity; used is the remainder after free and purgeable.
- Cleanable = sum of on-disk sizes for `regen` + `judgment` + `⚠` entries, plus measured allowlisted Gradle cache children that require per-attempt risk acceptance. Excludes `reveal`, other `ⓘ` entries, and unclassified Gradle contents.
- Main-list rows are grouped into Apple and Android sections; Settings persists which platform section appears first.
- An info toggle beside the hero number explains why totals are an upper bound (hardlink-only dedup, §8).

**States**

- First launch: empty list, no header capacity strip — a process that has not scanned yet. In practice this is only the frame before the automatic first scan starts (decision 6): no manual Scan button gating it. The one exception is a first run, where the welcome window holds the first scan (next bullet).
- First run: a welcome window opens once, before anything is scanned (`WelcomePolicy.shouldShow`: not completed and no saved scan, so someone updating from an earlier version never sees it). It has four steps, or five when a tracked location lies in a protected area: where the app lives, the safety promise, what to scan (platforms preselected by `PlatformDetection`, launch at login offered and off by default), access (the same list as Settings > Access, §11), and the first scan. Access comes after the platform choice because `AccessPreflight` only looks at the chosen platforms; the check re-runs whenever the selection changes, so nobody is asked about a place they just turned off. Every automatic scan is held until the scan step (`AppModel.isWelcomePending`): the launch timer, the popover's auto-start and the rescan a platform change triggers. Pressing "Start Scanning", or closing the window before that, records `cruftless.welcomeCompleted` and starts the first scan at once. After "Start Scanning" the window stays open on the scan step, which shows the running total, then the finished total and where to find it; closing it changes nothing about the scan. A place that was skipped or refused is named there with the action that opens Settings > Access. The popover's own Scan button still works during the welcome, because pressing it is an explicit request.
- Scanning: indeterminate "Scanning…" state; no per-root progress; not cancelable.
- Populated: rows sorted by size descending, with no caption under the title — no tier word, no staleness label (see **Staleness display** below). Rows with nothing to show (0 B measurements, then unavailable) sit below a hairline separator at the bottom of the list; the whole order is deterministic (size, catalog order, title). Clicking a row with a drill-down pushes its detail view; the per-row action appears on hover (and in the row's context menu), and a per-row rescan control beside it re-measures that one location without touching the rest (`AppModel.rescan(locationIds:)`; the footer counts only what it walks). See `docs/UI.md`.
- Scanned, nothing reclaimable: a distinct "Nothing to reclaim" state, separate from the pre-scan empty state.
- First contact: the Scanning and Populated states carry one dismissible strip above the rows, "Every deletion is reviewed first. Nothing happens until you choose.", until the user dismisses it or confirms their first Review, whichever comes first; it never returns after that (`FirstContactStrip`, persisted by `FirstContactStore` in `UserDefaults`). Placeholder states never show it.
- Re-scans also fire without user action: FSEvents invalidation on a watched root, a protected-path change (root resolution reads the protected list), and after every deletion — scoped to the locations the plan touched (`DeletionPlan.rescanScope`; everything when the set is empty).

## 8. Scan engine

- Sizes are **APFS allocated**, not logical: `ATTR_FILE_ALLOCSIZE` from
  `getattrlistbulk(2)`, which equals `lstat`'s `st_blocks * 512` (tested in
  `CloneAwareSizingTests`), not `totalFileAllocatedSizeKey`. The walker reads a
  whole directory's attributes per syscall (`DirectoryEntryReader`) rather than
  `URLResourceValues` or an `lstat` per entry, for speed.
- Hardlinks deduplicated by `(st_dev, st_ino)` identity (`InodeSet`), not
  `fileResourceIdentifierKey` — equivalent, but not the mechanism in code.
- APFS clones: **measured, not yet surfaced.** The same `getattrlistbulk` call
  reads `ATTR_CMNEXT_PRIVATESIZE`, `ATTR_CMNEXT_CLONEID` and
  `ATTR_CMNEXT_CLONE_REFCNT`. `SizeResult.exclusiveBytes` is the private bytes
  plus each clone family's shared blocks counted once, and only when every
  member of the family is inside the measured tree. A compressed file, or a
  volume that reports no private size, counts its allocated size. Rows, plans
  and the hero still read `allocatedBytes`, and totals stay labelled an upper
  bound until the UI decides how a family split across two rows reads: each
  row's exclusive share is 0 while their parent's includes it, so rows no longer
  sum to the parent.
- Traversal never follows symlinks; a symlink is a leaf sized as itself. Regression test: a root containing a symlink to a larger external directory does not inflate.
- Concurrency is **per location**, not per root: each location scans in its own task; a location with several roots (Device Support) walks them sequentially within that task. Cold scan target **< 15 s** for ~110 GB.
- Child sizes are computed **during** the scan and cached, not lazily on expand — the same bytes are visited either way, so splitting them per child at walk time is free and lets a drill-down open instantly.
- **Every walk passes the access gate first** (§4, ARCHITECTURE §3.7): roots are partitioned once per scan or rescan, and drill-downs, the Android drill-down and the simulator toolchain check go through the same gate. FSEvents registration is not gated; a rescan it triggers still is.
- A directory the walker cannot `opendir` is not silently dropped from the total: `SizeResult` carries an unreadable-directory count and the first offending path, and the scan emits `ScanEvent.failed(locationId:reason:)` alongside that location's `.locationScanned` rather than hiding the shortfall.
- **Launch behaviour**: the first scan runs ~5 s after launch, from the app
  delegate, not on the first popover open — the popover is otherwise the only
  thing that ever starts one, and every session's first open waits on a full
  walk. Opening the popover before the delay expires brings the scan forward
  rather than adding a second one. Skipped only while **Low Power Mode** is on,
  and then run when the mode ends; a scan asked for by the popover or Refresh is
  never gated.
- **A scan says what it will cover before it measures anything**:
  `ScanEvent.planned` lists, in catalog order, the locations that will produce a
  row — a runtimes location always, a filesystem one when at least one of its
  roots exists. The list draws that as a checklist and fills it in, so a first
  ever scan shows what is happening rather than an indeterminate spinner. No
  percentage: the denominator is a count of locations, and one location can be
  most of the wall time.
- **The last scan is remembered** (snapshot schema 5 adds the needs-access state; versions 1 to 4 still decode) in `Application Support/Cruftless/inventory.json`
  and restored at launch, so the popover shows real rows immediately with the
  footer's timestamp saying how old they are. Volume capacity is re-queried, not
  restored. Restored rows are display-only, gated per location: a row is
  actionable only once a scan has *landed* its location this session
  (`AppModel.isRestored(_:)`), so a one-location rescan makes exactly that row
  actionable while the rest stay refused. Each row also carries a hover rescan
  control that re-measures just its location (§7).
- Cache invalidated by FSEvents on the tracked, deletable roots (Xcode installs are excluded — too static to be worth watching): 3 s debounce, 1 s stream latency, `FileEvents | NoDefer | UseCFTypes`. A build's file-level event storm collapses into one rescan after writes settle, not one per event.
- Treat `.app` / `.xcodeproj` / `.xcarchive` / `.xcworkspace` as atomic; never expand internals.
- `os_signpost` covers two named intervals, `ScanLocation` and `LazyDrillDown` — not the scan as a whole or the Spotlight prepare step.

## 9. Safety

- **PathGuard**: every delete validated against an allowlist of known roots with symlinks resolved; anything outside is refused. Non-negotiable. Roots are validated too (`/`, relative, denylisted, or anchor-holding roots are dropped), a target that contains a user-protected path or a built-in anchor is refused since every delete is recursive, and a target whose final component is a symlink is refused rather than resolved. A target must also be an absolute `file://` URL with no host, no embedded NUL, and no literal `..` component (a host is silently dropped by `URL.path`; a NUL would truncate the C string `lstat`/`removefile` actually see).
- Protected-path denylist that can never be deleted regardless of caller: exact-path (`/`, `/System`, `/Library`, `/Applications`, `/bin`, `/sbin`, `/usr`, `/etc`, `/opt`, `/var`, `/var/db`, `/var/log`, `/var/root`, `/private`, `/Users`, `/Volumes`) plus content-protected prefixes for most of the same roots — deliberately *not* a blanket `/var` or `/private` prefix, since per-user scratch space (`/var/folders`, including this app's own) lives there. Case-insensitive, covers both `/private` spellings, other accounts' home folders and `/Volumes` mount points, and is structural for CoreSimulator: nothing at or above `Devices/<udid>/data` is ever a path target (§5). Any file literally named `device.plist`, anywhere, is protected outright. `simctl runtime delete` names no path to guard, so `DeletionPlanner.runtimeDelete` refuses outright when any user-protected path sits inside `/Library/Developer/CoreSimulator` — the store that command deletes out of. User-protected paths are stored unresolved and matched in both written and resolved spelling, so a dangling symlink or unplugged volume never makes a protection stop applying.
- **Drill-down listings never contain symlinks**, and a batch is refused if two rows resolve to the same path or one contains another.
- **Planning refusals are reported, never swallowed.** The planner throws a reason for every refusal; a batch with one refused entry is refused whole so Review never shows a plan missing something the list showed. `DeletionPlan.init(items:)` is not public API — only `.single(_:)` (allows a flagged item, for the one-at-a-time Detail action) and `.batch(_:)` (strictly drops flagged items) can construct a plan, so the flagged-exclusion invariant cannot be bypassed by a caller that forgets to ask for it.
- **simctl arguments are validated.** A device UDID must parse as a UUID; a runtime identifier must start with an alphanumeric character and must not be a sentinel (`all`, `booted`, `available`, `unavailable`) or a flag — the leading-alphanumeric rule blocks `.`/`..`/`...` specifically, since `simctl runtime delete` treats its identifier as a path. Invalid values from `device.plist` are dropped at enumeration and refused at planning. Every subprocess (`simctl`, `mdfind`) runs through `BoundedProcess`: absolute executable path, minimal environment with `PATH` pinned to `/usr/bin:/bin:/usr/sbin:/sbin`, drained pipes, a 2 s bounded wait for the final EOF, and a timeout (120 s per mutation `simctl` call, 10 s for scan `simctl`, 3 s for Spotlight, 2 s for `xcrun --find simctl`, 6 s for the runtime-list toolchain probe) that sends SIGTERM and escalates to SIGKILL after a 5 s grace period. Toolchain validation classifies rejected and unsupported candidates as unavailable, with guidance to complete Xcode setup/license prompts and refresh, and timed-out probes as `probeFailed`.
- **Re-stat before delete.** Immediately before each `removeItem` call, the executor re-checks the target's fingerprint (identity: resolved path + inode + device + type, plus mtime for files only — a directory's own mtime ticks on every child add/remove and is not an identity signal) and refuses if the fingerprint's resolved path disagrees with the path `PathGuard` validated at plan time. See §10 for the exact per-outcome copy.
- Batch deletes never abort early — collect per-item failures and report. A recursive delete that fails partway is reported as partially failed with the bytes actually freed, re-walking what remains. Only entries that predate the delete count as remaining: a target rewritten while it is removed (Xcode's indexer refilling a Derived Data folder is the everyday case) refills with bytes that were never in the plan, and counting those reported a completed delete as a partial failure. When nothing predating the delete survives, the item succeeded, whatever `removeItem` said about the emptied directory it could not unlink. Deletion is cancellable *between* items (never mid-item); a cancelled run still reports every remaining item as "not attempted" rather than dropping it.
- Warn, non-blocking, before any delete if Xcode or Simulator is running (`NSWorkspace.runningApplications`, bundle IDs `com.apple.dt.Xcode`, `com.apple.iphonesimulator`). Re-checked on every popover open and again the moment Review is opened, since either can launch in between. Xcode exposes no public "building" signal; the re-stat rule is the v1 guard against deleting mid-build (§15).
- **Active-toolchain warning, implemented.** Xcode records the toolchain it is set to build with in the `com.apple.dt.Xcode` defaults domain, under `DVTDefaultToolchainOverrideIdentifer` (Apple's spelling) — not `xcode-select -p`, which names an installed Xcode.app and never a toolchain. When the planned target is (or, for a whole-location clear, contains) the `.xctoolchain` bundle whose `CFBundleIdentifier` matches that override, the Review consequence is prefixed with a warning (exact string in §10). A warning only, never a refusal.
- **Staleness**: shown per row, threshold **30 days** (configurable, §11). "Last use" is:

  | Entry | Timestamp |
  |---|---|
  | Simulator device | newest `lastUsedAt` across that location's `device.plist` files |
  | Derived Data project (drill-down row) | newest mtime among the project folder's immediate children |
  | Archive (top-level and drill-down row) | newest `CreationDate` among the `.xcarchive` bundles under the root, including one level of Xcode's date folders |
  | Everything else, including the Derived Data and Simulator devices top-level rows | newest mtime found anywhere under the root, recursively |

  Every location's top-level row now reads its declared source (`stalenessSource`) the same way its drill-down does — Archives and Simulator devices used to show the recursive-newest-mtime date at the top level while their rows below showed the real source, so the same location reported two ages. Recursive-newest-mtime for "everything else" (rather than only the root's own mtime) is deliberate: a directory's own mtime only ticks on a *direct* child change, so a root touched deep inside would otherwise read as untouched. Never atime or `kMDItemLastUsedDate`; neither is reliably populated for these paths.
- **Orphaned Derived Data projects are suggested, never auto-deleted.** Derived Data's Detail offers "Orphaned projects · N · size" (`OrphanedProjectsSuggestion`: orphaned, deletable, unflagged, unprotected folders only). Its Select control opens Select Items with those rows checked; Review and confirmation still follow. Planning re-reads each orphaned folder's `info.plist` and refuses the batch if the record changed or the project is no longer confirmed missing (`DeletionPlanningError.orphanedProjectChanged`), and the target carries `DeletionPrecondition.derivedDataProjectMissing`, which the executor checks again right before `removeItem`. This applies to every plan of an orphaned folder, including a single-row Clear, because its Review copy states the project is gone.
- Nothing is ever deleted without an explicit per-row action plus review.

## 10. Review step

Pushed view inside the popover. Shows per item: name · size · consequence text (plain secondary, no tier word). Exact consequence strings (`DeletionPlanner.consequence(for:)` unless noted):

- derivedData: "Xcode rebuilds indexes and intermediates on the next build. The next build is slower."
- derivedData, orphaned project folder (`DrillDownProvider.orphanedConsequence`): "Its project, {~/path}, no longer exists. Xcode recreates this folder only if that project is built again." Refused at plan time with "{name}'s project is no longer confirmed missing. Rescan Derived Data and try again."; refused at execute time with "Refused: {name}'s project is no longer confirmed missing".
- previewsCache: "Xcode Previews regenerates this the next time a preview runs."
- deviceSupport: "Xcode re-creates it the next time that device is connected."
- swiftPMCache: "Packages are re-downloaded the next time they resolve. Needs a network connection."
- ibSupport: "Interface Builder rebuilds this on demand."
- productsLogsDocCache: "Build products and documentation caches are re-created on demand. Device logs are not."
- toolchains: "The toolchain must be re-downloaded and re-installed to use it again." — prefixed with
  "This is the toolchain Xcode is currently set to use. Builds fail until you pick another under
  Xcode ▸ Toolchains. " when the target is the active toolchain (§9).
- archives: "Deletes the dSYMs and the archived app. Crash reports from these builds can never be symbolicated, and the build can't be re-exported." Per-archive drill-down rows use the shorter "Deletes the dSYMs for this build. Crash reports from it can never be symbolicated again."
- Generic tier fallback, for any location without a specific string above: regen "Xcode recreates this on the next build."; judgment "Needs a re-download or reinstall if you want it back."; irreversible "This cannot be recovered."; reveal "Reveal in Finder."; info "Root-owned. Run the copied command in Terminal to delete." (drill-down children use their own near-identical fallback set, `DrillDownProvider.defaultConsequence`.)
- simulatorKnownBloat (`KnownBloat`): "Removes cached simulator system data. The simulator regenerates it when needed."
- simulatorErase, booted: "Shuts this simulator down, then removes all installed apps and their data."; shut down: "Removes all installed apps and their data from this simulator."
- simulatorDelete: "Deletes this simulator completely. Installed apps and configuration will be permanently lost."
- simulatorRuntimes (`runtimeDelete`): "Deletes the {name} simulator runtime ({size}). It must be re-downloaded to run simulators on this OS version. Simulators that use it stop working until it is installed again."

Every review step states **"This can't be undone. Files are deleted permanently, not moved to the Trash."** Under that sentence Review shows "Free now X · After ~Y" — the volume's free space read live at push time (`VolumeCapacity.query()`), plus the plan's `totalReclaimableBytes`; the "~" is required because the plan total is the APFS-clone upper bound (§8) and Result's measured delta can be smaller. The line is omitted if the capacity query fails. Confirm button verb matches the action: "Delete Permanently" for every path delete, simulator delete, and runtime delete (including a non-booted Erase — the confirm verb is the destructive action, not the button label above it); "Shut Down and Erase" only for erasing a booted device; known-bloat's confirm carries the size, "Clear <size>" (e.g. "Clear 6.4 GB") — "Clear" never appears bare. Cancel is the other. No "don't ask again".

**Result** is a separate view pushed in the same navigation slot as Review — Back from Result can never land on a plan that already ran, because Result replaces Review on the navigation stack rather than sharing it. It shows a free-space line, "Free space X → Y" (measured before and after execution, not derived from the plan's estimate), and each item's outcome. A third status, `partiallyFailed`, sits between success and failure: a recursive delete that stopped partway is reported with the bytes actually freed (re-measured by walking what remains, counting only entries that predate the delete) rather than as a flat failure at 0 B. A fourth status, `notAttempted` (`ItemOutcomeStatus.notAttempted`), is not a failure at all: it is what a cancelled run reports for every item it never reached. The four counts on `DeletionResult` are mutually exclusive and sum to the item count: `succeededCount`, `partiallyFailedCount`, `failedCount` and `notAttemptedCount`. A partial removal gets a column of its own because its bytes are already in the headline total — folding it into `failedCount` printed "0 items deleted, 1 failed" above a headline of gigabytes freed. `hasFailures` covers both real failures and partial ones; `allSucceeded` requires every item to be a clean success. The screen names each in its own clause — "N partially removed", "N failed", "N not attempted" — rather than folding any of them together. Exact per-item failure copy: "Item no longer exists on disk"; "Resolved path changed: expected X, got Y"; "Refused: <reason>" (precondition and fingerprint-mismatch refusals); "Partially removed: <error> N still on disk." (the error's own trailing period is not doubled); and, for an item skipped because the run was cancelled between items, "Not attempted: the operation was cancelled." — every remaining item still gets an outcome, even a cancelled run never silently drops one. Successes are not hidden by failures.

**`simctl` mutations report success only when the space is actually back.**
`simctl erase` / `simctl delete` return in ~0.33 s regardless of size — a
fire-and-forget request to CoreSimulatorService — while the free space arrives
over ~15-25 s for a 3-4 GB device, in bursts with plateaus of up to ~1.8 s
(~210 MB/s, so a 20 GB simulator extrapolates to ~95 s; `purgeable` is
unaffected). `DeletionExecutor` therefore runs two phases for `simctl` targets
only (never `.path` targets, whose `removeItem` frees the space in one step):
phase one confirms the mutation itself — erase: the device directory's
allocated walk falls under 64 MB, polled at 1 s for up to 15 s; delete: the
device directory is gone; runtime: the existing `awaitRuntimeRemoval` — and
phase two waits for the space to settle: five consecutive 1 s samples within a
64 MB tolerance *and* at least 90 % of the expected bytes arrived, capped at
`max(60, bytes/105 MB)` seconds. A capped wait is still a success: the item
stays `.succeeded` and its Result row carries the note "Free space was still
arriving when the result was measured." The settle wait must never turn a
confirmed mutation into a reported failure, and it changes nothing about what
is deleted. Review shows the two phases while it runs ("Erasing iPhone 17
Pro…", then "freeing space, this can take a minute"), and
`AppModel.executeDeletion` reads Result's free space only after the wait, so
"Free space X → Y" is the settled number.

**Staleness display**: **not rendered.** Staleness is still measured (§9) and carried on every entry, but no view shows it — the list and every drill-down dropped the "Unused for N …" label, along with the tinted tier word, in the 2026-09-08 caption cleanup. The `stalenessThresholdDays` preference and its `StalenessThreshold` clamp were removed with it; `StalenessInfo.stalenessLabel` survives as an unused formatter with its tests.

## 11. Settings window

A standard macOS preferences window — an `NSToolbar` in the `.preference`
style, which the SwiftUI `Settings` scene renders from a `TabView` — with four
panes, in this order: **General** (the items below), **Access** (protected-area
access, below), **Support** (simulator
toolchain selection and the voluntary diagnostic report, §20), and **About**
(version, license, website, repository and acknowledgements links, and manual
release check). The update section offers `brew upgrade cruftless` only for a
Homebrew cask install, detected by existence checks for a `cruftless` entry in
`/opt/homebrew/Caskroom` or `/usr/local/Caskroom` (`UpdateChannel.detect`, no
directory listing); any other install links to GitHub Releases. Panes size to their content up to
a cap, past which the form scrolls (`docs/UI.md` §2).

Not a sidebar. A settings *window* groups with a toolbar, and the sizing rule
runs opposite to intuition: the toolbar is what you reach for when there are
*many* settings, and too few means one pane with no toolbar at all — a sidebar
is not the third option. System Settings is a settings *app* of ~30 panes, not
the template for this. `docs/UI.md` §2 carries the full rationale and the
supported escape hatch (`.tabViewStyle(.sidebarAdaptable)`) if the pane count
ever outgrows a toolbar row.

- Launch at login (**off** by default). The toggle reports `SMAppService.mainApp.status`, not whether `register()` threw: macOS returns success and moves the item to `.requiresApproval` when the user must confirm it in System Settings, and a toggle that read "did it throw" showed on with nothing registered. Status is re-read on `NSApplication.didBecomeActiveNotification` as well as pane appearance — approving the item in System Settings, or removing it there, is the only way that change reaches the pane. `.requiresApproval` (`LaunchAtLoginPolicy.statusMessage`) shows its notice from the status alone, including when the pane opens, with an "Open Login Items" button. `.notFound` is silent until a toggle attempt: `SMAppService.mainApp` also reports it for an app that was never registered, and on a Mac with several copies sharing the bundle ID, so warning from the status alone showed a false "Move Cruftless to Applications" on an installed copy. After a failed enable it shows `LaunchAtLoginPolicy.notFoundMessage`, which asks for a move only when the running bundle is outside `/Applications` and `~/Applications`, and otherwise offers "Open Login Items".
- Optional scan reminder (**off** by default), stored under `scanReminderEnabled` in the same suite: a repeating weekly `UNCalendarNotificationTrigger` handed to the notification daemon under the identifier `cruftless.scan-reminder` with `[.alert, .sound]`. `ScanReminderScheduler` (Core) arms it: a pending request with the same body is left alone, because re-adding a request resets its countdown, and launch, platform changes and protected-path changes all re-arm. When the body must change (the platform selection names it), the request is re-added in the same weekly slot, persisted as `scanReminderSchedule` (one week after it was first enabled; cleared on disable), so the change never pushes the next reminder back. Never scans or touches the disk. It is not an in-process timer. If permission is refused the toggle switches back off with the reason beside it, rather than persisting an "on" that can never fire. Permission revoked later in System Settings is caught the same way: pane appearance and app activation run a non-prompting authorization query (`ScanReminderScheduler.checkPermission`) and turn an enabled reminder off with the message.
- Choose which platforms to scan and, when both are selected, which section the main list shows first. Platform toggles, Add Folder and the protected-path remove buttons are disabled while a deletion runs, and a busy message left by a refused attempt clears when the deletion ends. Which controls lock and what they say is decided in Core (`SettingsControlPolicy`). The folder picker is a SwiftUI `.fileImporter`.
- Manage protected paths, stored as lexically-normalized strings under `cruftless.customProtectedPaths` (deliberately unresolved — see §9). A folder is vetted by `ProtectedPathPolicy` before it is stored: `/` (protecting the startup disk turns every action in the app into a refusal), `$HOME` (already protected), and anything under a folder already listed are refused with the reason shown in the pane. These are not safety checks — `PathGuard` is — they keep the list meaningful. Adding or removing an entry triggers a rescan, because root resolution reads the protected list (`RootResolver.resolveCustom`) and not only planning does.
- Allow access to protected areas (Access pane, `CLAUDE.md` rule 10). Lists each area (Documents, Desktop, Downloads, iCloud Drive, an external drive, a network volume) where `AccessPreflight` found something tracked, or that was asked before, with its reasons and one of three states from `AccessOverview` (Core): **Not asked yet** (Allow), **Allowed**, **Not allowed** (Open Privacy Settings at Privacy & Security > Files and Folders, since macOS will not ask twice). Allowed and not allowed are read live by opening an asked area's root once; an area never asked is never opened. Allow runs `AccessRequest` for that one area off the main thread through `AccessService`, which admits one request at a time across the process because macOS queues alerts. The area is recorded as asked only once macOS answers, so quitting while the alert is up leaves it unasked and the next unattended scan still skips it. An answer rescans the locations it changed through `AppModel.rescan(locationIds:)` (only once the first scan has started). A popover row that needs access offers "Allow Access", which opens this pane. The built app carries the six usage strings (`NSDocumentsFolderUsageDescription`, `NSDesktopFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription`, `NSFileProviderDomainUsageDescription`) as `INFOPLIST_KEY_` build settings.
- The two Xcode custom-location preferences (`IDECustomDerivedDataLocation`, `IDECustomDistributionArchivesLocation`, §4) and the active-toolchain override (`DVTDefaultToolchainOverrideIdentifer`, §9) are all read from the `com.apple.dt.Xcode` `UserDefaults` suite — a file this app does not own, so every value read from it is treated as untrusted input.

## 12. Architecture

- `CruftlessCore` — SPM package: scanning, inventory, deletion, naming. Fully
  unit-tested, no UI imports.
- `Cruftless` — thin SwiftUI app target.
- Files kept under ~500 LOC.
- A tracked location does not ship until a test proves PathGuard rejects
  paths outside its root (CLAUDE.md safety rule 5).

## 13. Out of scope for v1

Cross-category cleanup cart · global tool caches
(npm/pnpm/gradle/cargo/uv/Homebrew) · project artifacts (`node_modules`,
`.build`) · scheduled auto-cleaning · privileged helper for root-owned paths ·
per-workspace Derived Data overrides · scan cancellation · undo ·
localization · telemetry, analytics, crash reporting, any network call ·
accessibility work beyond SwiftUI's default VoiceOver and keyboard support.

## 14. Open items

- Verify `Cruftless` is free: domain, App Store, Homebrew formula name
- App icon and menu bar glyph: done, both the sheep mascot. `docs/mascot/build_icons.py` generates `AppIcon.appiconset` and `MenuBarIcon.imageset` from the mascot art; `docs/mascot/BRIEF.md` has the rules. The app icon is still built from a 1K render, so a vector redraw remains open.
- Device-identifier table: sourced (`DeviceIdentifierTable.swift`, `scripts/generate-device-table.swift`, license-compatible — DevCleaner's is GPL-3). The generator reads the *generating machine's own* `CoreSimulator/Profiles/DeviceTypes` plus a DeviceKit MIT-licensed baseline for historical models, so regenerating it on a machine with fewer installed simulator platforms can drop entries — re-run it on a machine with a broad set of platforms installed.
- **Deferred to v1.1 — keep-newest suggestion for Device Support**: per device model, keep the highest version + build and offer the rest as a one-click suggestion that still goes through review. (Ref machine has three iOS 27.0 betas for one model; two are pure waste.) Not implemented: no grouping logic exists in `DeletionPlanner`, and `DetailView` renders a flat child list with no suggestion card.

## 15. Spikes before implementation

- APFS clone detection: `F_LOG2PHYS_EXT` (2026-09-03) was a no-go at ~109%
  scan-time overhead. `getattrlistbulk` with the `ATTR_CMNEXT_*` sharing
  attributes (2026-11-16) is a go: across Derived Data, Simulator devices,
  Device Support, the SwiftPM cache and Previews it walked 38% faster than
  `readdir` + `lstat` (12.9 s against 20.7 s, medians of three), with
  byte-identical allocated sizes for every row. Exclusive bytes came to 84.9% of
  allocated for Derived Data and 64.3% for the SwiftPM cache. Open: surfacing
  it (§8).
- "Xcode is building" signal: any reliable detector (XCBuildData lock files,
  open file descriptors)? If found, upgrade the §9 warning to a refusal for
  Derived Data.
- `images.plist` path and schema on macOS 26 (§5): completed 2026-09-03. Verified
  schema: `images` array with `runtimeInfo` dict containing `bundleIdentifier` and `build`.

## 16. Revision notes — 2026-09-03 review

Changes from the signed-off draft, for re-sign-off:

- Simulator devices retagged `regen` → `judgment`; only known-bloat sub-paths
  are `regen`.
- SwiftPM cache retagged `regen` → `judgment` (network re-download).
- Toolchains retagged `⚠ judgment` → `judgment`; a reinstall is recoverable,
  so it does not meet the `⚠` definition. The `xcode-select` warning covers
  the real risk. Override if you want the batch-exclusion that `⚠` implies.
- Known-bloat sub-path deletion made an explicit, bounded exception to
  `simctl`-only mutation (§5). Previously it silently contradicted CLAUDE.md
  rule 2.
- Tier column split into Tier + Note; `reveal` added as its own tier.
- Defined: reclaimable, staleness timestamps, size units, missing/unreadable
  roots, popover states, review-step content and result screen.
- Added: re-stat before delete, toolchain `xcode-select` warning, symlink
  traversal policy, hardlink identity, clone-detection caveat, custom Derived
  Data root, Spotlight-based Xcode enumeration.
- "Refuse Derived Data deletion while building" downgraded to warn + re-stat;
  no public signal exists. Tracked as a spike.
- Keep-newest rule regrouped by device model + version/build.
- Reference total corrected: ~107 GB app-reclaimable (was "110 GB across 8").
- Decision 11 (no network/telemetry) and non-goals for undo, cancellation,
  accessibility added.

## 17. UI pass — 2026-09-03

Visual direction settled on the design canvas (link in `docs/UI.md`):

- Direction A: hero reclaimable number over a flat, size-sorted list.
- Liquid Glass menu bar extra; quiet rows with hover-revealed actions.
- Drill-down is **push**, not inline expansion (decision 2 amended).
- Row icons are SF Symbols by name, with an optional custom image per entry.
- Settings is a toolbar-tab preferences window: General, Support, About.
  Amended 2026-09-07 — the original "sidebar window" wording predated the
  implementation and never matched it. Support was added with §20.

## 18. Revision notes — 2026-09-07 drift reconciliation

Reconciles this document with the implemented app (`swift test` 208/208,
`swiftlint --strict` clean). One line each:

- Decision 6 rewritten: the popover auto-scans on first open per process; the
  Empty state is only the pre-scan frame, not a manual gate. Cache is
  in-memory only, and now documented as such.
- Simulator runtimes row: documented as sized via `SimulatorService.runtimes()`
  (`TrackedLocation.sizeSource`), not a filesystem walk — it resolves no roots.
- Scan failures: `ScanEvent.failed(locationId:reason:)` and the unreadable-
  directory accounting in `SizeResult` documented (§4, §8).
- Staleness: top-level rows now honour `stalenessSource` per location
  (Archives, simulator devices) instead of always using recursive newest
  mtime; staleness table and §9 rewritten accordingly.
- Active-toolchain warning implemented and documented with its exact copy;
  every `xcode-select -p` reference removed — the real signal is
  `DVTDefaultToolchainOverrideIdentifer`.
- `TrackedLocation.note` removed from the codebase; all doc references to it
  (Xcode installs "marks the xcode-select -p install") dropped.
- `DeletionPlan.init(items:)` documented as non-public; `.single`/`.batch` are
  the only construction paths (§9).
- `AppModel.openReview` re-checks running apps; §9's running-apps warning
  updated to say so.
- Keep-newest suggestion for Device Support explicitly marked deferred to
  v1.1 and moved to §14, rather than read as implemented.
- Repo now has a `LICENSE` (MIT) and `README.md` with an Acknowledgements
  section; §1 drops "public" since there is still no git remote.
- Root resolution, Archives drill-down, simulator enumeration/runtime-merge,
  naming rules, popover states, scan-engine mechanics, PathGuard/denylist
  detail, subprocess constants, Review consequence strings, Result screen
  behaviour, and Settings storage keys all filled in against source that had
  drifted ahead of this document since the 2026-09-03/04 revisions.

## 19. Android inventory — 2026-09-29

The implementation adds optional platform scope and four Android rows to the
catalog. Apple remains the migrated default. Android rows use the existing
allocated-size walker and remain excluded from the cleanable total by their
`.info` tier. Android-only scans do not invoke Xcode discovery or `simctl`.

The implementation resolves default macOS roots and the documented SDK,
Gradle, and AVD environment variables. It accepts only readable, existing,
same-volume directories under the current user's home. Unsupported, conflicting,
or external roots stay unresolved and are reported as incomplete/unavailable.
Android Studio `idea.system.path` and AVD `.ini` metadata are bounded to 64 KiB;
recognized same-home redirects are inventoried and protected, while unsupported
or out-of-scope paths make the row visibly incomplete. SDK package identity is
reconciled from bounded `source.properties` and `package.xml` metadata. The SDK
detail view retains bounded typed diagnostics for missing, unreadable, unsafe,
malformed, conflicting, and unsupported metadata while keeping unresolved bytes
in Unclassified SDK contents. AVD rows are keyed from registry metadata and
sized from each resolved device directory.
Detail screens show the source label and exact path for each scanned root. The
inventory does not claim complete coverage of every Android configuration or
user-level tool override.

Android Studio and SDK rows remain read-only. AVDs are deleted one stopped
device at a time through the reviewed Android CLI route
(`docs/ANDROID_AVD_CLEANUP.md`); the AVD location is still `.readOnly` for
every path planner route. A read-only location with such a dedicated route
declares it as `TrackedLocation.itemRemoval`, and only an inventory-only
location (`isInventoryOnly`) shows the List lock. The Gradle location cannot
be cleared as a whole or in a batch. Its cleanable contribution is the measured
sum of recognized immediate child directories under the resolved `caches/`
root; the Overview shows that subtotal with the other cleanable bytes. In
Detail, one such child can proceed only after a per-attempt warning and the
normal Review step. The current positive name policy accepts Gradle-version
directories, `build-cache-1`, `modules-2`, `jars-N`, and `transforms-N`;
unrecognized names, files, nested entries, the `caches/` container, and the
Gradle User Home remain locked. The Gradle location and eligible children do
not display a read-only lock, while unclassified children remain locked.

The warning explains that Gradle may be using the files, builds may be
interrupted or require rebuilds and downloads, offline builds may fail, and
Cruftless cannot guarantee project integrity. The user explicitly accepts
uncoordinated direct deletion for that one entry and attempt. This warning is
not a concurrency protocol: the app does not claim to detect or exclude active
or newly starting Gradle writers. The acknowledgement is an in-memory,
single-use capability bound to the selected path and policy generation; it is
not saved. SDK package removal, AVD wipe, project discovery, Android
logs, custom external roots, and Studio cleanup remain deferred. The Android
inventory does not claim complete coverage of all IDE, Gradle, SDK, or emulator
storage.

Platform selection is saved as recognized identifiers. A missing preference
defaults to both Apple and Android; empty or unknown-only values are persisted
as Apple-only, and unknown values alongside a recognized value are ignored. At
least one platform remains selected. The main-page order setting appears only
when both platforms are selected, and its preference is retained while hidden.
Changes advance a policy generation, prune rows and routes, replace watchers, invalidate
old scan work and Reviews, and start a scan for the new catalog. Core rejects
read-only plans and the executor rejects plans carrying a stale generation.
Settings controls are disabled during deletion, and programmatic edits report
a busy reason.

## 20. Simulator toolchain and voluntary diagnostics — 2026-10-02

Simulator listing and actions use one shared validated Xcode toolchain
resolution. A valid selected Xcode is preferred; when selection points to
Command Line Tools or an invalid installation, one usable discovered Xcode can
be selected automatically. Multiple usable installations require an explicit
local choice. Refresh and selection never change macOS's global `xcode-select`
setting. Device/runtime listings carry their listing generation, and simulator
plans are refused if the toolchain is unavailable, a fallback listing cannot
confirm mutation authority, or the listing became stale. A simulator operation
revalidates and pins one Xcode through mutation and confirmation. Path-only
plans do not require Xcode. Android-only scans do not invoke Xcode discovery or
`simctl`.

Settings → Support has two sections, "Simulator Tools" and "Diagnostic Report".
Simulator Tools offers explicit toolchain refresh, an Xcode picker that applies
on change (with a placeholder while the Xcode in use is not listed), "Choose
Xcode…", and "Use System Selection", which is enabled only when it would change
the resolution. Candidates load when the tab opens, and every toolchain control
is disabled while a cleanup runs. Toolchain work and report preparation have
separate busy states. The Diagnostic Report is voluntary. The report is assembled from allowlisted local snapshots,
shown for review, and copied or saved only after an explicit action. It may
include sanitized app/macOS versions, architecture, toolchain status/version,
SDK root source, package category, standard package identity, bounded metadata
sizes/statuses, fixed reason codes, and identity-match results. Paths,
usernames, hostnames, identifiers, arbitrary package names, logs, environment
values, metadata contents, and inventory rows are excluded. When the toolchain is
unavailable or ambiguous the report lists the usable candidates' Xcode versions
(sanitized, at most eight) so the choice can be diagnosed. A prepared report is
marked out of date, with Copy and Save disabled, when the toolchain summary
changes afterwards; copy and save confirmations last two seconds. Report data is
not uploaded or attached to the issue tracker automatically; the pane links to
the issue tracker as "Open Issue Tracker".

## 21. Uninstall — 2026-11-20

A user can remove every trace Cruftless creates, by the route they installed it.
Nothing outside the app's own footprint is touched, and nothing Cruftless
already deleted comes back.

**Footprint** (`AppFootprint`, the single list): `~/Library/Application
Support/Cruftless` (saved scan, prepared Android tools),
`~/Library/Caches/<bundle id>`, `~/Library/HTTPStorages/<bundle id>`,
`~/Library/Saved Application State/<bundle id>.savedState`, the per-user
`DARWIN_USER_CACHE_DIR/<bundle id>` (Metal caches), the preferences domain, the
`SMAppService.mainApp` login item, scheduled and delivered scan reminders, and
the privacy decisions macOS recorded for the bundle. Out of scope: crash
reports macOS keeps, the notification-settings entry macOS keeps, diagnostic
reports the user saved, and files the Android command-line tools write in the
user's Android folders.

**Homebrew route.** `brew uninstall --zap --cask cruftless`. The cask's `zap
script` runs the app's headless `--uninstall-cleanup` mode before Homebrew
removes the bundle (login item, reminders, `tccutil reset All`, access ledger,
preferences domain), then `zap trash` removes the folders and plist. A copy that
was never opened is not run, because it would raise a Gatekeeper prompt and it
registered nothing; its privacy decisions are still reset. Settings › Support
shows the command instead of a button for a cask install.

**Direct-download route.** Settings › Support › "Remove Cruftless Data" opens a
sheet listing every folder with its size and consequence, plus the
registrations it undoes; that sheet is the review step. Confirming stops every
scan, watch, timer and reminder for the rest of the process, undoes the
registrations, and deletes the folders through `DeletionPlanner.appFootprint`
and `DeletionExecutor` (each folder a `validateRoot` root; any refused folder
refuses the whole plan, and the sheet shows why plus the manual path list). The
result sheet's only exit is "Quit Cruftless", which shows the app in Finder
(not for a translocated or read-only copy), clears the preferences domain, and
exits in the same step. The app never deletes or trashes its own bundle.

**Preferences file.** Clearing the domain is the guarantee; `cfprefsd` may
write an empty plist back at an unpredictable time afterwards, including after
an external delete, so a 42-byte empty file can remain. It holds no settings.

