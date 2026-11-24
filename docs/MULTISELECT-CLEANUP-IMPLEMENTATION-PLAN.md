# Detail selection and batch cleanup

read_when: implementing or reviewing detail selection, popover navigation, or batch planning.

## Approved outcome

Add **Select Items** and checkbox selection to every detail screen, inside the existing Cruftless popover. Daniel clarified on 2026-10-09 that the approved design uses the same window. This supersedes the earlier separate-window interpretation and the stale repository prohibition on popover checkboxes.

Selection state belongs to the existing shared `AppModel`, so focus loss does not destroy it. Do not create a new native window, additional app model, scanner, watcher, or executor. Keep the existing `MenuBarExtra(.window)` and `NavigationStack`, pushed Review, and pushed Result.

Selection starts empty. A user selects individual rows or eligible groups, sees an estimated subtotal, reviews the exact selected set, and explicitly confirms permanent cleanup. Existing individual actions and Clear All stay available outside selection mode. Scope is one category per selection, with independent retained sessions for each category; no cross-category cleanup cart.

Stay on `work/fix-volume-capacity`. Preserve the uncommitted capacity fix, tests, and unrelated/untracked content. No commits, pushes, releases, replacement of the installed app, or cleanup of live user files.

## Coverage and eligibility

| Detail contents | Selection | Planned action |
| --- | --- | --- |
| Ordinary deletable children | Multiple eligible rows | Existing guarded child batch planner |
| Flagged/irreversible children, including Archives | Disabled checkbox with reason; retain existing individual action | No selection batch, even with only one checked row |
| Read-only/reveal/root-owned children | Disabled checkbox with reason | No new deletion authority |
| Recognized Gradle cache children | One checked entry per attempt, explicit explanation | Existing risk warning, acknowledged single-entry planner, Review |
| Unrecognized or user-protected Gradle children | Disabled with reason | None |
| Unavailable simulator devices | Multiple eligible rows | Delete device completely through simctl |
| Healthy simulator devices | Multiple eligible rows | Erase installed apps/data through simctl |
| Booted devices | Eligible when mutation is supported | Explicit shutdown before erase/delete |
| Deletable runtimes | Multiple eligible rows | simctl runtime delete |
| Bundled/removing/tooling-unavailable runtimes or unsupported devices | Disabled with concrete reason | None |
| Protected targets, protected ancestors, or targets containing protected paths | Disabled when determinable; planner rechecks | Refuse, never silently omit |

The runtime-removed warning triangle is not the irreversible flagged tier. Those devices remain eligible for explicit deletion. Nested simulator known-bloat cleanup remains its existing per-device action; selecting the parent erases the device rather than separately selecting its caches.

All three detail view types expose selection consistently. A location with no selectable rows explains its restrictions. Preserve REQUIREMENTS' explicit no-batch Gradle contract and its single-use acknowledgement bound to one exact entry and attempt.

## Same-popover interaction and appearance

1. **Select Items** in the detail header enters a compact checkbox presentation of that same location in the existing popover. Reuse the shared selection session and existing navigation animation; no openWindow call or WindowGroup.
2. Keep `PopoverMetrics.width` and existing height behavior. Use `PopoverHeader`, scrolling rows, and `PopoverFooter`. Do not retain the new standalone view's 620-point minimum width, native window toolbar, or nested NavigationStack.
3. Show readable name, version/status or bounded path metadata, checkbox, and trailing allocated size. Long names truncate sensibly with full accessible labels/help. Native checkbox toggles remain keyboard/VoiceOver operable; state is not communicated by color alone.
4. Preserve runtime groups and Runtime removed section. Compact group controls select only eligible current rows. Global Select All and Clear Selection are available when useful; omit bulk-select controls in Gradle's single-entry mode. Expose group buttons separately to accessibility.
5. Keep selection controls out of hover-only actions. Unavailable choices show their reason without hiding the row. Preserve relevant inventory diagnostics, root source/path information, and incomplete-listing notices in a compact form.
6. Pinned footer shows selected count, `Estimated …`, and **Review Selection**. Zero selection has a neutral prompt. Put the allocated-size/clone caveat in concise help or compact copy rather than filling the popover with a long disclaimer.
7. Review remains a pushed view in the same popover. Reuse `ReviewView` with narrow additions for explicit per-item action labels and session-specific refusal notices if necessary. A mixed device plan clearly distinguishes Delete, Erase, Shut Down and Delete, and Shut Down and Erase. The confirmation label describes the entire plan.
8. Back/Cancel from Review returns to checkbox selection with the same IDs. Gradle passes through its existing per-attempt risk warning in the same push stack; cancelling/rebuilding a plan requires fresh acknowledgement.
9. Confirmation disables selection, refresh, navigation and duplicate execution while the shared executor runs. Result remains in the same popover, reports all outcomes and measured free space, and cannot go Back to an executable completed plan.
10. Done clears that session's selection and returns to its refreshed detail/selection list. No actual deletion occurs on scan, selection, expansion, navigation, opening or closing the popover.

## Persistence, freshness, and navigation

Use the existing model-owned selection sessions, renamed away from window-specific terminology as practical. Retain the safe Core selection representation, current stable IDs, and exact-set resolution already implemented.

Selection routes live in the existing `AppRoute`/`navigationPath`. Suggested shape: location-scoped selection, selection review and selection result routes. The ordinary popover flow remains unchanged. New selection routes retain their navigation/session on focus-loss dismissal so reopening resumes selection, review, progress, or result. Explicit Back/Done controls determine exit. Update `MainView.onDisappear`/`popoverDidAppear` only enough to support that exception, while preserving preparation cancellation and animation reset.

There must be one authoritative presentation of an operation. Remove the standalone cleanup WindowGroup and openWindow entrypoint. Reuse shared Review/Result UI and executor callbacks rather than maintaining parallel popover/window implementations. Remove superseded feature-owned files/components after their replacements are in place; preserve unrelated files.

Resolve all selected identities against current rows before planning. Missing, duplicated, newly protected or otherwise ineligible selected IDs invalidate the entire selection, with visible resolution controls. Refresh never auto-selects new rows or silently drops old selected IDs. Selecting an unaffected row must not wipe other valid selection.

Require a successful completed scan of that location, not restored inventory. Retain the implemented active and queued scan scopes so opening selection during a pending scan cannot trust old `scannedLocationIds` or cached drill-downs. Failed scans show the actual reason with Try Again/Refresh enabled; never strand the view on a spinner. During a scan of its location, disable Review confirmation; an identical completed listing can preserve Review, while a changed selected set or policy invalidates it.

Retain policy-generation tracking, including protection edits that advance generation without the platform-change callback. Reopening retained sessions synchronizes policy and eligibility. Platform-disabled categories explain the requirement to enable the platform. Toolchain changes retain executor refusal and refresh/review guidance.

A confirmed operation uses a model-owned task and continues across popover dismissal. Preserve the global deletion mutex, settings lock, exact review plan, per-operation progress and result destination. Other pending sessions must not receive the active operation's result or substitute another plan.

## Core safety contract

- Reuse strict `DeletionPlanner.children` for file selections, including explicit flagged rejection, PathGuard, fingerprints and duplicate/nested-target rejection.
- Retain the implemented validated simulator-device and runtime batch planners. Each selected item uses the existing individual planner. Reject the entire request on any refusal, duplicate identifier, missing/inconsistent toolchain generation or empty batch.
- Preserve planner authorization, policy generation, simulator toolchain generation and affected-location scopes. Runtime deletion invalidates both runtimes and devices. No unauthorized public-plan stitching or silent filtering of requested items.
- Retain tightened simulator protection checks for protected ancestors as well as descendants. Both selection eligibility and individual/batch planners use the same protection semantics.
- Keep the guarded shared executor admission, per-item failure collection, partial outcomes, policy/toolchain checks, shutdown and settlement waits. No extra subprocesses, delete primitives, filesystem roots, helpers or Trash paths.
- Gradle's acknowledged single-entry planner and capability remain unchanged. All other Android mutation restrictions remain enforced.
- Errors go through the shared AppModel planning/reporting wrapper and appear in the requesting selection/review view; no swallowed planning errors.

## Implementation sequence

The primary agent completes the same-popover correction directly, per the latest instruction. Other work exists in this checkout; preserve it and adapt. The earlier implementation already has Core selection, strict batches, policy/scan gating and passing regression tests: reuse them, do not rebuild from scratch.

1. Replace standalone-window presentation with location-scoped routes in the existing NavigationStack. Change Select Items entrypoints across all detail screens.
2. Adapt the checkbox list/group/footer to the existing 380-point popover. Prefer reusable sections/row types with narrow inputs and DEBUG preview coverage.
3. Reuse existing ReviewView/ResultView for selection routes. Add explicit action labels and session notices without altering ordinary single-item semantics. Adapt Gradle risk flow as necessary while preserving per-attempt consent.
4. Route confirmed progress/result through the same popover and keep session/route across focus loss. Preserve independent pending category selections and one global execution lock.
5. Remove superseded feature-owned native-window code/scene. Rename new session/helper APIs where their old window names misdescribe behavior.
6. Update REQUIREMENTS/UI/README and the stale AGENTS checkbox note to describe same-popover state ownership and persistence. Do not leave separate-window claims in current documentation.
7. Verify and repair failures. Leave all changes uncommitted.

## Verification and evidence

Already passed before this presentation correction: 463 Core tests across 76 suites, strict lint, isolated macOS build, diff check, and safe standalone fixture inspection of checkbox selection/totals, mixed simulator review, generic files and disabled runtime reasons. These prove shared logic and the earlier rendering, not final popover layout.

After adapting presentation, run strict lint, macOS build and diff check. Run focused/new Core tests if Core logic changes; a UI-only change does not require repeatedly rerunning the unchanged full suite. Preserve regression coverage for selected-ID resolution, exact totals, group eligibility, stale selections, Gradle single-entry mode, mixed booted/unavailable devices, duplicates, generation mismatch and protected ancestors/descendants.

Verify the final popover rendering with safe DEBUG fixtures, including all three detail entrypoints, checkbox/group/global selection, long names at 380 points, no horizontal overflow, footer visibility, mixed Review, disabled reasons, Cancel retaining selection, and ordinary single-item flow. Check focus-loss/reopen retention if tooling permits. Never confirm deletion of live files to test. Build success is not rendered acceptance; identify any manual checks still pending precisely.

Final delivery links this comprehensive plan, reports implementation and evidence, states same-popover behavior and explicit Gradle/flagged restrictions, and notes no commit. Do not claim the superseded separate-window UI satisfies the corrected request.

## Completed verification

The corrected implementation uses the existing MenuBarExtra and NavigationStack, with no cleanup WindowGroup or openWindow entrypoint. Selection, Gradle risk, Review, execution and Result use location-scoped routes and shared model sessions. The implementation is uncommitted on `work/fix-volume-capacity`.

- Final macOS build passed with isolated DerivedData at `/tmp/CruftlessSelectionDerivedData`.
- Strict SwiftLint passed with zero violations across 210 Swift files; `git diff --check` passed.
- The earlier 463 Core tests across 76 suites cover the unchanged selection and batch-planning logic; subsequent Core edits only changed a documentation comment.
- A temporary DEBUG host rendered the actual MainView at 380 points. All three detail entrypoints entered checkbox selection in its existing stack. Group selection, individual toggles and global Select All produced the expected counts and allocated subtotals. Long file names, disabled runtime explanations, footer and mixed simulator Review fit without horizontal overflow.
- Removing and recreating MainView exercised its dismissal lifecycle. Both Selection and Review resumed with the same selected IDs and route. Review Cancel retained selection. Partial Result displayed both outcomes; Done returned to an empty selection. The ordinary single-device action still opened Review and Cancel returned to Detail.
- Fixture refresh and selection confirmation were disabled; no cleanup was confirmed and no live files were deleted. Fixture host controls are outside the popover content and are not production app code.

Manual checks still pending: actual MenuBarExtra focus-loss/reopen behavior, progress during a real authorized cleanup, Gradle per-attempt warning with a real eligible cache, and VoiceOver/keyboard navigation in the live popover. Native automation could not target the temporary MenuBarExtra status item, so the fixture lifecycle check does not establish actual focus-loss behavior.

Rendered evidence: [selection](/Users/danielmunoz/.codex/visualizations/2026/10/09/01a121ca-fc38-7492-bd1d-cd7e53ccf794/cruftless-popover-selection.png) and [mixed Review](/Users/danielmunoz/.codex/visualizations/2026/10/09/01a121ca-fc38-7492-bd1d-cd7e53ccf794/cruftless-popover-selection-review.png).
