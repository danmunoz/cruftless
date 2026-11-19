# Xcode toolchain, Android SDK, and voluntary diagnostics

read_when: implementing or reviewing simulator tool selection, SDK package discovery, or diagnostic export.

## Objective and scope

Implement reliable simulator operations when macOS selects Command Line Tools despite an installed Xcode; make Android SDK classification failures specific and recoverable; provide a local, previewable diagnostic report that users manually copy or save. Work on `work/toolchain-sdk-diagnostics`. Preserve unrelated untracked documentation and instructions. Do not commit, push, release, change global Xcode selection, send reports, or execute real simulator mutations as part of development verification.

## Evidence and current integration points

- The affected user reports `/Library/Developer/CommandLineTools` from `xcode-select --print-path`. A read-only local probe with that selection reproduced `xcrun` exit 72 and the exact missing-`simctl` message.
- `Simulators/SimctlRunner.swift`: `DefaultSimctlExecutor` invokes absolute `/usr/bin/xcrun` with a stripped environment. It correctly drops inherited `DEVELOPER_DIR`, but supplies no validated replacement.
- `Locations/XcodeInstallDiscovery.swift`: Spotlight discovery is bounded and cached for the process lifetime; the only filesystem fallback is `/Applications/Xcode.app`. Parsed Spotlight strings are not themselves validated Xcode installations.
- `Scan/ScanEngine.swift`: the scan creates its own simulator service/executor with a 10-second command timeout. `AppModel` and `DeletionExecutor` separately create default simulator services. A fix in only one constructor would leave scan and mutation selection inconsistent.
- `Simulators/SimulatorService.swift`: failed `simctl` lookup falls back to `images.plist`. `ImagesPlist` marks those entries deletable without proving tool availability or obtaining simctl's deletion identifier/capability.
- `Safety/PlanningContext.swift`, `DeletionPlan.swift`, `DeletionPlanner+Simulators.swift`, and `DeletionExecutor`: planning is synchronous, Review stores a plan, and mutation is asynchronous. Availability must be captured before planning, represented in Core, and checked again immediately before commands.
- `Locations/AndroidRootMetadata.swift`: SDK package identification returns an optional. A mismatched `Pkg.Path` rejects a candidate before valid XML can be considered; XML failures/mismatches can also be hidden by properties fallback. Files are bounded at 64 KiB and opened without following metadata symlinks.
- `Locations/DrillDownProvider+Android.swift`: one mutable issue string replaces specific failures; unresolved allocated bytes remain in Unclassified SDK contents.
- `Model/DrillDownContent.swift` and `Scan/ScanDrillDownContents.swift`: drill-down content travels separately from persisted inventory. Preserve that boundary when adding diagnostics.
- `AppModel.scanFailure` uses internal location IDs as visible prefixes. Replace known IDs with catalog titles without losing per-location failure tracking.
- `Views/SettingsView.swift` currently has General and About tabs. A Settings support surface avoids unreliable modal dialogs inside `MenuBarExtra(.window)`.
- DevCleaner's public revision `8039d1bca189ab426f09ae97c9aaade1a1d1a6b2` contains no simctl/toolchain selection implementation. Its feedback flow composes an email with custom paths and log attachments, useful as a workflow reference only. Do not copy its GPL source.

Primary references:
- https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings
- https://developer.android.com/tools/sdkmanager
- https://github.com/vashpan/xcode-dev-cleaner/tree/8039d1bca189ab426f09ae97c9aaade1a1d1a6b2

## Safety and regression invariants

1. Keep PathGuard, protected-path checks, simctl identifier validation, platform policy generation, admission/serialization, review requirements, and per-item outcomes intact.
2. Never substitute direct filesystem runtime/device deletion for simctl, and never retry a failed mutation using another toolchain.
3. Keep inherited developer/toolchain variables untrusted. Only add the explicitly validated developer directory after building the existing minimal environment.
4. Every subprocess uses BoundedProcess, an absolute executable, drained pipes, and bounded time. Discovery/probes must not inherit the 120-second mutation timeout or multiply into unbounded scan delays.
5. Keep blocking filesystem validation off MainActor and cooperative executors. Do not await discovery inside synchronous root resolvers or between a warm drill-down click and push.
6. Preserve fresh per-location scan gates, partial rescan accounting, cached child sizes, hardlink attribution, known-bloat shutdown checks, runtime removal confirmation, and space settling.
7. Keep Android SDK read-only. Improve inventory classification without expanding deletion authority.
8. Diagnostics are ephemeral, local, bounded, and separate from inventory persistence. No background upload, email send, account, tracking ID, raw log bundle, or automatic clipboard writes.

## Implementation A: shared simulator toolchain resolution

### Core model and resolution

- Introduce small Sendable types for a validated Xcode toolchain, selection source, resolution state, and typed failure. Distinguish runtime deletion capability from intrinsic `isDeletable`.
- Use one shared, injectable resolver/session authority for production scanning, cold listings, planning, commands, and confirmation. Test doubles remain explicit and do not weaken production checks.
- Read the system selection using bounded `/usr/bin/xcode-select --print-path` in the minimal environment. Prefer a selected full Xcode that validates and provides simctl.
- If the selection is Command Line Tools, missing, or invalid, discover full Xcode applications. Validate bundle identity, developer directory, and expected executable; do not trust an `.app` suffix or Spotlight path alone. Normalize and deduplicate candidates.
- Probe candidate tool availability through `/usr/bin/xcrun --find simctl` with an explicit validated DEVELOPER_DIR. Validate the reported executable belongs to that installation. A runtime-list probe establishes whether required runtime commands actually work; reuse that result where practical to avoid duplicate scan calls.
- If exactly one candidate is usable, automatically select it for Cruftless. If several are usable and no valid explicit choice exists, expose an actionable ambiguity state and require selection. Do not choose a beta/newest candidate silently.
- Allow a user-selected Xcode and rediscovery from Settings. Store only the local preference necessary to honor that choice; it is never part of exported diagnostics. Revalidate it on use and refuse stale choices rather than silently switching.
- Give refresh a bounded total probe budget and candidate limit. Cache/coalesce concurrent resolution requests, avoid repeated probes per row, and ensure refresh can discover an Xcode installed after launch. Do not regress the existing once-per-scan shared runtime lookup.

### Planning and execution

- Carry the selected toolchain identity/generation from live runtime/device discovery into the Core planning context and simulator plan. Path-only plans must not require Xcode.
- Refuse simulator planning when resolution is unavailable/ambiguous or the listing came solely from a fallback without mutation capability. Report through existing AppModel.plan/reportPlanFailure. Keep runtime rows and sizes visible; show the actionable tooling reason rather than calling fallback rows built into Xcode.
- Immediately before the first simulator mutation, validate that the plan's toolchain still matches the active selection and exists. Bind all commands for that operation, including shutdown and removal confirmation, to that same toolchain. Selection changes invalidate stale reviews; they must not redirect an already-reviewed mutation.
- Reject missing toolchain authority in production execution, including manually constructed simulator plans. Keep injected simulator command doubles usable through explicit fixtures/dependencies, never a production bypass flag.
- Surface setup/license/permission/unsupported-command/timeout failures with recovery guidance and keep unknown failures honest. Do not run setup or license acceptance commands automatically.
- Preserve the 10-second scan command ceiling, mutation ceiling, confirmation deadline, and settle behavior. A resolution failure must fail before mutating, with zero freed bytes.

### UI

- Show current tooling state and a refresh/select-Xcode control in Settings. Use stable candidate IDs, local display names/versions, and clear loading/error/empty states.
- Runtimes/devices remain browseable when tooling is unavailable. Show why actions are unavailable and how to configure Xcode. Maintain the restored-inventory action gate and existing pushed navigation.
- Include DEBUG previews for normal selection, single fallback Xcode, ambiguity, unavailable/setup error, and loading using shared fixtures.

## Implementation B: SDK metadata diagnostics and reconciliation

### Typed metadata reading

- Replace the SDK identification optional internally with a typed result distinguishing recognized, unrecognized/missing, unreadable, non-regular/symlink, too large, invalid encoding/properties/XML, identity conflict, and unsupported layout.
- Preserve no-follow reads, regular-file checks, metadata bounds, same-volume traversal, candidate/entry limits, and no external entity resolution. Explicitly reject DTD/entity declarations rather than relying on external-entity resolution settings alone.
- Read XML and properties independently. A matching valid XML record can establish identity when optional properties lack identity. Conflicting declared identities become a visible conflict, not a silently accepted fallback or a claim of corrupted SDK.
- Support documented command-line-tools `latest` aliases only with explicit rules and coherent revision/category metadata. Do not treat arbitrary mismatches as aliases. Valid versioned layouts remain supported.
- Implement required Java-properties escapes/continuations only where justified by fixture evidence; keep parsing bounded and preserve existing Studio/AVD property behavior if SDK-specific parsing differs.
- Do not assert the user's package is corrupt or invent a package-specific fix before seeing diagnostics.

### Discovery and delivery

- Collect a bounded list of typed per-package issues and a total/truncation indicator, rather than retaining only whichever issue is encountered last. Sort deterministically.
- Keep full relative paths for local detail only. Export package categories and strictly validated standard identities, never arbitrary directory names or metadata text.
- Keep valid packages listed and all unresolved space in Unclassified SDK contents. Root allocated total and child attribution must remain consistent.
- Carry diagnostics with non-persisted drill-down content/scan events. Partial rescans replace diagnostics only for scanned locations; platform deselection removes stale diagnostics.
- Use a concise main-screen warning and catalog display titles. Provide locally inspectable issue details in the SDK drill-down or Settings support surface, without modal dialogs in the popover.
- Retain compatibility accessors where useful to avoid rewriting unrelated callers, but keep one typed source of truth for user-facing reasons and report summaries.

## Implementation C: voluntary diagnostic report

### Core report builder

- Build a schema-versioned report from structured, allowlisted data only. A readable text format is sufficient; do not serialize arbitrary errors or raw model objects.
- Include sanitized app version/build, macOS version, CPU architecture, toolchain selection classification/source and probe statuses, Xcode versions under report-local labels, SDK root source, package category, bounded metadata sizes/presence/read statuses, reason codes, and identity-match booleans.
- Standard package identities may be included only after strict grammar/category validation; omit custom extras identifiers, arbitrary names, unsafe characters, control characters, paths, and unknown values. Exclude freeform display names.
- Exclude usernames/home paths, hostnames, serial numbers, machine identifiers, UUIDs, absolute/custom paths, project names, raw environment variables, raw stderr/stdout, raw metadata, full inventories, general logs, and protected paths. No hashes of private values.
- Use per-report labels such as Xcode A and SDK A when correlation is necessary. Unknown/unvalidated strings are replaced by fixed categories, not scrubbed with a best-effort regex.
- Limit report size/counts and state truncation. Prepare reports using existing snapshot data plus explicit bounded read-only tooling refresh when needed; never trigger a broad filesystem inventory just to report a warning.

### Manual workflow

- Add a Support settings surface (or an equally native dedicated settings section) accessible independently of an error. Pass the real app model/report provider into Settings without making view bodies read the filesystem.
- `Prepare Diagnostic Report` assembles the local report and shows the exact export text and a short description of included/excluded data. Nothing is copied or saved until the user clicks.
- Provide Copy and Save, with visible success/failure states. Use native save UI from Settings, not the menu-bar popover. Save only the previewed sanitized text to the user-selected destination.
- Offer an ordinary issue tracker link without filling its URL with diagnostic data. Users attach/paste the report themselves. Do not open a preaddressed email or send any report.
- Cancellation is harmless; report regeneration replaces the preview rather than accumulating private history. Keep export off the main thread if it can block.
- Include DEBUG previews for unprepared, preparing, populated, truncated, and failure states using reusable fixtures.

## Regression matrix and verification

### Automated Core tests

- Toolchain resolution: selected full Xcode; CLT plus one Xcode; none; several; explicit choice; custom/renamed path; invalid bundle; missing executable; malicious inherited DEVELOPER_DIR; Spotlight duplicates/unavailable; probe timeout; unsupported runtime command; concurrent request coalescing; refresh after new installation.
- Execution: scan/planner/executor selection agrees; stale selection or missing binary after Review launches no mutation; missing production authority is refused; shutdown/delete/confirmation stay pinned; fallback runtimes remain non-actionable; valid empty runtime list differs from failure; normal mocked deletion, confirmation and settle tests still pass.
- SDK: namespace-qualified XML, XML-only and properties-only packages, valid standard/versioned/latest layouts, coherent alias, conflicting identities, malformed/oversized/unreadable/symlink metadata, DTD/entities, bounds/truncation, deterministic multiple issues, ancillary/unclassified contents, known-size/hardlink totals, partial rescan/deselection handling.
- Privacy: seed private usernames, machine identifiers, custom paths/names, tokens, UUIDs, metadata, stderr, and environment values; assert none are present in exports. Test standard-identity allowlisting, control characters, unknown/freeform values, size cap, report-local labels, deterministic output, and export text equal to preview text.

### Required checks

1. Run the current full Core suite as baseline before implementation changes, recording existing warnings/failures.
2. During implementation run focused resolver, simulator safety, SDK discovery, and privacy suites.
3. After review run `swift test --package-path CruftlessCore`, `swiftlint --strict`, and `xcodebuild -project Cruftless/Cruftless.xcodeproj -scheme Cruftless -destination 'platform=macOS' build` serially where outputs/build stores overlap.
4. Inspect every changed file for safety boundary violations, uncontrolled subprocesses, newly persisted diagnostics, private-value serialization, and scan/navigation timing changes. Avoid unrelated formatting churn.
5. Perform read-only rendered UI checks for tooling unavailable/ambiguous, SDK issue details, and report preview/copy/save. Verify the selected directory remains unchanged. Do not delete an installed runtime/device to verify the fix.
6. Update REQUIREMENTS and ARCHITECTURE in the same task with the final behavior and privacy contract. Mark any manual acceptance or affected-user verification still pending honestly; passing mocked tests does not establish behavior on his machine.

## Delegation and completion

After this plan is saved, delegate implementation to a Luna subagent (`gpt-6-luna`) in this branch. The subagent reads applicable repo instructions and this plan, implements Core/UI/tests/docs, and reports deviations and check results. The primary agent reviews the resulting diff and resolves concrete issues before final verification. No commit or push is requested.

Acceptance: a CLT-selected machine with one usable Xcode can list and review simulator operations without global configuration changes; ambiguous/unavailable tooling is actionable and fails closed; Android classification exposes specific reasons while preserving measured space; a user can preview and manually copy/save an allowlisted report with no automatic sharing. Required checks pass or exact pre-existing/external blockers are documented.

## Implementation review and evidence

- Baseline: 403 tests in 67 suites passed; strict lint had no violations.
- Implemented immutable runtime catalog authority, including a successful empty catalog, rather than deriving authority from the first runtime row. This preserves cleanup of unavailable devices and prevents unrelated plist-only entries from disabling confirmed devices.
- Revalidation compares the complete toolchain value, so an Xcode version replaced at the same path invalidates the reviewed operation. Acquisition/operation leases prevent selection changes from redirecting shutdown, mutation, or confirmation.
- The SDK reader emits precise reasons while retaining independently usable metadata and unclassified allocated bytes. Local details retain relative paths; exported issues omit them.
- Added deterministic concurrency, replacement, empty-catalog, fallback refusal, production zero-launch refusal, SDK parsing/bounds/accounting, and adversarial privacy/export regressions. The reviewed full suite passed 442 tests in 73 suites.
- Probe failures currently become a generic unavailable state with instructions to finish setup in Xcode and refresh. Timeout/license/permission stderr is neither persisted nor exported. An unavailable report does not establish which setup problem occurred.
- Real runtime/device deletion remains outside development verification. Acceptance on the affected user's machine remains necessary because its SDK metadata has not been inspected.

### Final verification

- macOS app build passed using derived data at `/tmp/cruftless-toolchain-diagnostics-derived`.
- Strict SwiftLint passed with zero violations across 199 files; `git diff --check` passed.
- The opt-in installed-Xcode probe passed with a simulated Command Line Tools selection and a real read-only runtime lookup. No runtime/device mutation was executed. The system selection remains `/Applications/Xcode.app/Contents/Developer`, matching the initial local check.
- Xcode bundle metadata now rejects oversized files, symlinks, and FIFOs using bounded nonblocking regular-file reads. Settings also provides a native application chooser for Xcode installs absent from Spotlight discovery.
- Rendered UI verification is pending: native automation returned `timeoutReached` (-10005) when attaching to the exact running menu-bar app. Process and code-signature checks confirmed the verified build launched successfully. Report preview/copy/save, chooser cancellation, unavailable/ambiguous states, and SDK detail layout still require a manual walkthrough. Automated tests verify sanitized report text, exact file export, failure bounds, and mutation refusal.
- No commit, push, release, global Xcode selection change, or external report sharing was performed.

### Review after rebase onto main

- Rebased the diagnostics commit onto `main` (`2fbcd5e`) without conflicts. The replayed patch is identical by `git range-diff`; main's release version and changelog are retained. Recovery branch: `work/toolchain-sdk-diagnostics-pre-main-rebase`.
- Reviewed the resulting diff against main, including toolchain discovery, operation leases, runtime authority, SDK accounting, report privacy, and application wiring. Existing Android support is already on main and is not replayed as separate commits.
- Fixed unavailable explicit Xcode selection recovery by keeping Use System Selection visible, and allowed runtime setup guidance to wrap. Path-only known-bloat cleanup remains available for shut-down devices without simctl; execution still rechecks device state.
- Corrected the SDK warning to cover malformed optional metadata with a valid fallback without claiming that classified package bytes are unclassified.
- Added regressions for reset after an invalid explicit selection, guarded path-only cleanup without Xcode with both shut-down and newly booted execution states, and accurate fallback classification messaging.
- Verification: 444 Core tests in 73 suites pass; strict lint reports zero violations across 199 files; macOS build passes; the opt-in real read-only Xcode fallback probe passes; `git diff --check` passes. Rendered UI and affected-user acceptance remain pending as above.
- Rebase is local. Review fixes remain uncommitted; no push or simulator mutation was performed.
