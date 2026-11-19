# Android cleanup implementation plan

Status: Stage 1 and the per-attempt Gradle cache warning route implemented on 2026-09-29; manual UI acceptance remains pending. AVD, SDK, and Studio mutations remain disabled.

read_when: changing Android inventory, row affordances, deletion policy, or Android cleanup actions.

This plan turns the Android inventory into limited, reviewed actions. `ANDROID_SUPPORT_PLAN.md` remains the safety contract. Each stage below has an independent release gate; incomplete stages retain an explicit read-only reason. Gradle's one-entry risk acknowledgement is a deliberate user-risk choice, not writer coordination. All validation uses disposable SDK, AVD, Studio, and Gradle fixtures. Do not run deletion acceptance against the user's real development data.

## Observed baseline

- Android-only selection exposes four `.info` and `.readOnly` locations, so the cleanable total is zero. The protected-path policy also rejects every descendant of the Android roots. Changing a label or tier cannot enable deletion safely.
- The 2026-09-29 saved inventory measured about 24.0 GB of AVDs, 9.1 GB of Gradle caches, 7.2 GB of SDK files, and 2.5 GB of Studio system files. These are stored bytes, not deletion estimates.
- Before Stage 1, SDK discovery required `Pkg.Desc` or `Pkg.Path` in `source.properties`. Five installed package roots on this Mac lacked both, although each had a `package.xml` with a `localPackage` identity. The scanner descended into their contents and reached its depth bound.
- Before Stage 1, read-only rows were selectable while `PopoverRow` gave the lock precedence over the chevron in one trailing slot and dimmed the entire row.
- Two Studio `index` directories account for roughly 1.9 GB; their neighboring `LocalHistory` directories are persistent recovery data. Three AVDs account for most measured Android storage. Local command-line management tools exist, but their presence alone grants no deletion authority.

## User-facing contract

1. The Overview distinguishes **cleanable** bytes from **stored, read-only** bytes. Its cleanable total includes measured eligible Gradle children that require a per-attempt warning. A row that opens Detail has a chevron even when deletion is unavailable; the lock describes the deletion restriction only. Accessibility exposes both meanings.
2. Detail shows verified items, unclassified storage, source root, an incomplete-discovery notice, and a reason for each unavailable action. No unreadable, unknown, or unclassified item is counted as cleanable or enters a batch.
3. Every deletion starts with a specific user action and enters Review. Gradle cache deletion first shows a per-attempt warning with the exact child path and active/offline build consequences. SDK/AVD actions, if added later, must name the exact package or device and describe data loss. No selection, scan, hover, or Detail navigation mutates data.
4. Changing selected platforms or root policy invalidates old scans, drill-downs, Reviews, and queued plans. Execution rechecks current policy before each item. Refusals are visible through `AppModel.plan` or result reporting.
5. Android cleanup never uses a raw recursive path deletion for SDK packages or AVDs. Manager operations execute inside `DeletionExecutor` through `BoundedProcess`, with no shell, inherited `PATH`, automatic installation, privilege escalation, or retry after an uncertain outcome.

## Stage 1: fix inventory and navigation

### SDK package discovery

- Enumerate only documented SDK package slots (such as `platform-tools`, `emulator`, `platforms/<id>`, `build-tools/<version>`, `sources/<id>`, and `system-images/<api>/<tag>/<abi>`). Do not recursively interpret arbitrary package contents as candidate packages.
- At each candidate root, read bounded regular-file metadata without following links. Parse `package.xml` with external entities and network resolution disabled, accepting a single `localPackage` whose path maps exactly to that root. Use `source.properties` as a validated fallback; `Pkg.Revision` without `Pkg.Desc` is a valid metadata shape, not a reason to crawl into the package.
- Keep unrecognized bytes as **Unclassified SDK contents** and report a specific metadata or unsupported-layout issue. Keep directory and byte limits for actual unknown traversal, rather than increasing depth globally. Reconcile package sizes with the measured root total and preserve hardlink attribution.
- Add fixtures matching this Mac's platform-tools, build-tools, and sources metadata; malformed XML, oversized files, symlinks, mismatched package paths, duplicate paths, nested mounts, and unknown layouts. Assert that ordinary installed SDK sources produce no depth-limit notice.

### Row presentation

- Give lock and chevron separate positions in `PopoverRow`. A selectable read-only row keeps normal title/size emphasis and hover feedback. Eligible Gradle cache children have no lock and expose a warning-first Review action in Detail; unclassified children and all other Android rows stay locked. A genuinely unavailable row is visually inactive. Preserve the existing spinner and rescan behavior.
- Base action visibility on mutation capability, not `.info` alone. Gradle's Clear action and cleanable subtotal are limited to recognized direct cache children and do not enable Overview batches. Keep size labels at primary contrast at every size. Update previews for locked/navigable rows, unavailable rows, and the risk screen.
- Verification: focused Core tests, strict SwiftLint, macOS build, and manual Overview-to-Detail navigation with Android only. Record visual acceptance separately from build success.

## Stage 2: first useful cleanup, AVD removal

- Add a dedicated AVD **Delete Device** target and policy. Keep **Wipe Data** separate until a non-launching, supported manager path is verified. Never delete `.avd` folders or `.ini` files directly. No batch delete of AVDs.
- Bind the plan to one registry root, canonical manager identifier, parsed `.ini` identity, resolved data directory, system image reference, all redirected data and SD-card paths, volume, and current policy generation. Reject duplicate/overlapping paths, unsupported redirects, links, nonlocal paths, invalid identifiers, and protected descendants. Do not infer identity from a folder name alone.
- Use a trusted, absolute manager executable with explicit SDK/AVD homes, bounded output and timeout. Reject active/unknown emulator usage and re-read registry and path identity immediately before the manager call. If the manager times out or exits after a partial mutation, reconcile the live registry and disk before reporting an outcome; never blindly retry or fall back to folder deletion.
- Review states that device apps, settings, snapshots, and images are permanently lost; the shared SDK system image is retained. Confirm exactly one AVD. Measure and report allocated bytes and resulting free-space change on its volume without promising the estimate will equal the gain.
- Gate: disposable-home integration tests for successful removal, active device, malformed or duplicated metadata, redirected paths, manager failure/timeout, stale Review, and an emulator starting after planning. Manual UI acceptance uses a disposable AVD only.

### Stage 2 investigation and release gate (2026-09-29)

AVD removal is not implemented or exposed. Disposable CLI probes established:

- This machine's Android SDK has no `cmdline-tools` directory. Homebrew's `avdmanager` is installed, but the official documentation marks it deprecated. Its launcher is an `/usr/bin/env sh` script that locates Java through `JAVA_HOME` or `PATH`, then ultimately `exec`s Java. A future implementation could invoke a pinned absolute Java executable with the installed manager classpath directly, so the wrapper alone is not the decisive blocker; the exact manager version/classpath still needs pinning and disposable integration coverage.
- The installed Google `android` CLI documents `android emulator remove [-h] [--force] <device>` and `--sdk`, but no AVD-home option. Its first `emulator list` invocation began downloading/unpacking an embedded installation and displayed an SDK license and metrics notice instead of listing the disposable AVD. Do not launch it from the app or auto-accept its terms. The documented `--force` behavior removes an orphaned `.ini`; never pass it.
- A disposable `avdmanager list avd` with `ANDROID_AVD_HOME` set listed only the fixture under that home. `avdmanager -s delete avd -n Stage2Disposable` removed the fixture `.ini` and in-home `.avd` directory. A second disposable fixture placed its `.avd` directory outside `ANDROID_AVD_HOME`; deletion followed the registry `path` and removed that external directory too. These probes changed only their `/tmp` fixtures.
- The current scanner already binds registry entries to parsed `.ini` paths and resolves `ANDROID_AVD_HOME`; Core tests cover explicit-home precedence, read-only planner refusal, duplicate identities, and redirected data protection. These checks do not authorize invoking a manager.

Release remains blocked until Cruftless can pin and invoke the manager through `BoundedProcess` with an exact SDK and AVD home, bind and revalidate every registry and redirected data path, reconcile partial/timeout outcomes without retry, and prove that an emulator cannot start across the mutation window. The disposable redirect probe proves the current manager removes the `.ini` target and follows its `path=` to an arbitrary external `.avd` directory, so a path-based allowlist of only the AVD home cannot bound its footprint. The current process-list and manager probes do not establish an exclusive launch barrier. Keep AVDs read-only; do not add a Review action or mutation target until these gates, disposable integration tests, and manual UI acceptance pass. References: [Android CLI removal](https://developer.android.com/tools/agents/android-cli/commands/emulator_remove), [avdmanager](https://developer.android.com/tools/avdmanager), [Android environment variables](https://developer.android.com/tools/variables).

## Stage 3: SDK package uninstall

- Add a dedicated manager-backed target for one installed package. Use the validated `localPackage` identity and bind its SDK root, installed revision, footprint, manager executable, and policy generation. Reject missing, ambiguous, or changed metadata. No whole-SDK or arbitrary path action.
- Show references from known AVDs; block removal of an image used by a known AVD. State that unknown projects may still require other packages. Refuse active/unknown SDK use under the supported coordination policy. Execute the package manager's uninstall command with an exact argument array, then reconcile installed metadata and disk usage. Do not auto-uninstall dependencies or other packages.
- Gate: disposable SDK tests cover normal removal, references, identifier injection, renamed or replaced paths, manager failure/timeout/partial result, and policy changes. Manually review a disposable package before enabling this action.

## Stage 4: carefully scoped caches and project outputs

- **Studio:** define a positive manifest of version-tested regenerable child paths, initially `index` and only after confirming the exact supported layout. Preserve `LocalHistory`, plugins, project state, and unknown siblings. Refuse while Studio or helpers may write; if no supported way excludes writers during deletion, keep direct cleanup disabled and show the IDE's own Invalidate Caches route.
- **Gradle:** use its documented retention behavior as the default. The explicit product exception permits one recognized immediate child of the resolved `caches/` root after a per-attempt warning and the normal Review flow. The warning states that writer coordination is unavailable and asks the user to accept the risk; it is not a safety guarantee. Preserve the Gradle User Home, `caches/` container, unknown names, files, nested entries, and all batch/whole-location routes.
- **Project output:** use an explicit project picker, no home crawl and no execution of project Gradle scripts. Resolve only known default output locations; refuse configured or uncertain build directories. Guard exact child paths and show consequences in Review.
- For any permitted path cleanup, keep deletion inside the existing guarded executor and test persistent-data sentinels, races, symlinks, mounts, partial failures, and user-protected paths. Do not relax the blanket Android protected prefixes without replacing them with a narrower Core policy proven against those tests.

### Studio index cleanup investigation (2026-09-29)

- The current inventory resolves versioned system roots such as `~/Library/Caches/Google/AndroidStudio<version>` and includes their complete contents. The measured index directories share those roots with `LocalHistory` and other IDE state, so a whole-root plan cannot be used.
- `ProtectedPaths.isAndroidStudioPath` intentionally protects every path below a recognized Studio system/configuration directory. `PathGuard.init` drops protected roots, and the current planner/executor has no Android Studio-specific mutation capability. A non-mutating `AndroidStudioIndexPath.validate` foundation now recognizes only the exact default versioned `index` directory and rejects parent/neighbor paths, symlinks, redirects, mount-device changes along the path to the index, custom protected paths that overlap it, and paths outside the supplied home. It does not alter `ProtectedPaths`, authorize `PathGuard`, or create a plan/target. Any later mutation must also re-walk and reject nested mounts immediately before mutation; the existing directory walker reports `skippedMountCount` for this gate.
- No existing executor precondition or process seam coordinates with Android Studio. A process-list check followed by a second check immediately before deletion is still a launch race, and cannot establish that Studio or a helper will not write during recursive removal. No cross-process lock/API shared with the IDE has been identified. Since a live cache mutation can interrupt or damage IDE operation, the index-only action remains disabled until writer coordination is established and disposable race tests demonstrate the policy. A regenerable cache designation alone does not satisfy this gate.
- No real Studio data was changed as part of this investigation.

### Index tombstone recovery foundation (2026-09-29)

- A non-exposed Core record store now writes a bounded UUID record under Cruftless Application Support, outside the Studio cache tree. It requires the exact home-relative Application Support path, checks each ancestor without following symlinks, and requires user ownership plus non-group/world-writable permissions beneath home. It uses exclusive no-follow creation, fsyncs the record and parent directory, and binds the exact validated version directory plus source inode, device, and birthtime before any future same-volume rename. `prepared` records are recovery evidence only; they cannot authorize deletion without fresh Review and full index validation.
- Recovery inspection recognizes `prepared` (source identity still at `index`), `pending` (matching tombstone identity, whether or not Studio recreated `index`), `completed` (no source or tombstone), and `stale` (identity/path mismatch). Malformed records are ignored; record count and read sizes are bounded. A partial tombstone remains discoverable by the recorded inode. Tests cover pre-rename and post-rename crash states, replacement `index` recreation, partial removal, completion, tampering, and refusal of arbitrary/protected paths.
- This foundation does not rename or delete directories and is not integrated with scanning, planning, execution, cleanable-byte accounting, or UI. The action remains disabled. A later executor must keep the durable record until exact tombstone removal completes and expose pending tombstones only through a fresh Review.
- No shared lock or IDE-supported writer exclusion is available in the app. A process check cannot stop Studio or a helper from starting after the check, and atomic rename does not stop an already-open handle from writing into the tombstone while recursive deletion runs. Keep index cleanup read-only until a defensible writer coordination mechanism exists and is proven with disposable race tests.

## Completion and release gates

- Each stage updates `REQUIREMENTS.md`, architecture/UI documentation, settings copy, and previews when behavior changes. The cleanable total includes only eligible measured actions; its persisted aggregate is a display snapshot, and installed storage remains separately labeled.
- Run `swift test --package-path CruftlessCore`, `swiftlint --strict`, and the macOS `xcodebuild` scheme. Run focused disposable-tool integration tests for each manager action. Build success is not manual UI acceptance.
- Check the exact working tree before any commit. Keep commits atomic, use `committer` with explicit paths, and do not push unless requested. Preserve all unrelated or pre-existing changes in this checkout.
- Ship Stage 1 independently. AVD, SDK, and Studio remain read-only until their individual safety and manual acceptance gates pass. The Gradle direct-delete route remains limited to its explicit one-entry risk flow.

## Verification record, 2026-09-29

- Gradle risk route: strict SwiftLint passed and the macOS app build succeeded. No tests or manual UI acceptance were run for this change; the route remains pending disposable-data acceptance.
- Stage 1: focused Android discovery tests passed (11/11); full CruftlessCore test suite passed (393 tests in 65 suites); strict SwiftLint reported zero violations; macOS app build succeeded; `git diff --check` passed.
- The Android-only zero-cleanable notice and its Overview preview compile in the macOS app build; strict SwiftLint and `git diff --check` pass. The notice directs device and SDK package removal through Android Studio while in-app cleanup is unavailable.
- SDK package parsing and the row affordance are verified by source review and automated checks. The running menu-bar UI has not yet received recorded visual acceptance.
- The SDK's expected `licenses`, `skins`, `fonts`, and command-line manager metadata remain visible in the unclassified size row without an incomplete-discovery warning. Unknown top-level SDK contents still report incomplete inventory.
- Stage 2 disposable `avdmanager` probes verified exact `ANDROID_AVD_HOME` listing and removal, including that a registry `path` redirects deletion outside the AVD home. No deletion was tested against installed development data.
- Stage 2's Review action and mutation target remain unimplemented and disabled pending the manager, redirected-footprint, process coordination, timeout/reconciliation, and manual UI gates above. Stage 3–4 actions remain unimplemented and disabled.
- The non-mutating Studio index validator and recovery record have ten disposable safety tests. After their addition, the full Core suite passed (403 tests in 67 suites), strict SwiftLint found zero violations, the macOS app built, and `git diff --check` passed. The running UI has not been manually accepted.
