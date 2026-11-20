# Cruftless — UI Specification (v1)

Implementation reference for every SwiftUI view. Precise over exhaustive —
where a value is a mockup approximation, it says so.

Design canvas: https://claude.ai/code/artifact/13f54e0d-857c-4731-8149-079b7a2770d7
(visual source of truth — pixel values here summarize it; if they conflict,
the canvas wins and this file should be corrected).

The List screen's chosen direction is **"B1 Quiet"** from the refinement canvas
at https://claude.ai/code/artifact/b5c1a676-d8e1-4f49-a3cd-74c5c0a148d1 — §2 List
and §6 below carry its metrics.

read_when: building or changing any view in `Cruftless/`; adding a tracked
location's row/detail presentation; touching Settings.

## 1. Navigation model

`MenuBarExtra(.window)` with a **380 pt wide** popover. Inside it, a push
stack: `List → Detail (drill-down entries) → Review → Result`. Select Items
adds `Detail → Selection → Review → Result` within that same stack.

**The stack is a `NavigationStack`**, driven by `model.navigationPath`
(`[AppRoute]`, so the path stays readable — `resolvedHeight` and the back titles
need `.last` and the parent, which `NavigationPath` cannot give). Pushes, pops,
the slide between screens and the system back gesture are all the system's.
`.navigationDestination(for: AppRoute.self)` builds each pushed screen.

**The app's own windows open in front.** The welcome and Settings activate the
app when they open, and opening the popover while either is on screen
activates the app and raises them, so a click on the menu bar icon never leaves
them behind another app. With no window open, the popover activates nothing
(`AppActivation`, `CLAUDE.md` Gotchas).

**The Dock icon shows while the welcome or Settings is open.** The app is a
menu bar app (`LSUIElement`) and switches to the regular activation policy
while either window is on screen or minimized, which also brings the app menu,
and back to accessory once both close (`DockIconController`, decided by
`DockIconPolicy`). The popover alone never shows the icon.

**Every screen is opaque to the one it slides over.** Screens paint no
background of their own — the popover's vibrancy shows through and the bands are
transparent by design — so a push draws both screens at once and every row reads
doubled for the length of the slide. `View.popoverScreen()` backs each screen
with `.ultraThinMaterial`, the thinnest that hides the screen underneath, and
applies it to the root too so no two screens differ in tone at rest.

**Every path mutation carries an animation**, through `AppModel.pushing(_:)`.
On macOS a `NavigationStack` animates only when the change arrives in a
transaction that has one; a bare `append` or `removeLast` swaps the screens in a
single frame. The pace is `PopoverMetrics.pushAnimation`, shared with the
popover's resize so the window is not still growing after the slide has landed.

An earlier revision hand-rolled the stack — a `switch` in a `ZStack` with
`.transition(.push(from:))` — on the grounds that a `NavigationStack` inside
`MenuBarExtra(.window)` draws a second back button and that
`.navigationBarBackButtonHidden(_:)` is unavailable on macOS. **The second claim
is false** on the macOS 26 SDK: that modifier carries no `@available(macOS,
unavailable)` and type-checks against `-target arm64-apple-macos26.0`. Every
pushed screen applies it, along with `.toolbarVisibility(.hidden, for:
.windowToolbar)` — `.windowToolbar` because `ToolbarPlacement.navigationBar` is
the one that really is macOS-unavailable, and on macOS a stack's back button
belongs to the window toolbar. Between them the stack's own chrome stays down
and each screen keeps the single `PopoverHeader` back control it draws itself,
sized for a 380 pt popover.

**Exactly one view sets a `.frame`** — `MainView`, from `PopoverMetrics`. 
List and Detail use a fixed height (520 pt); Review and Result size to their 
content with `minHeight: 240, maxHeight: 520`. A screen that also frames itself 
makes the popover resize on every push.

- **Push**: every available location row pushes `Detail`; a "Clear"/"Delete"
  action anywhere pushes `Review`; confirming transitions the same view to
  `Result` in place (§2, Review).
- **Back**: a top-left circular glass chevron button (26 pt, `chevron.left`, 
  no parent title) in every pushed header pops one layer. `Detail`'s back 
  target is always `List`; `Review`'s is whichever of `List`/`Detail` pushed it.
- **Popover dismissal normally resets to `List`.** Selection flows retain
  their navigation and in-memory selection in AppModel, so reopening resumes
  Selection, Review, progress, or Result. An executing ordinary cleanup also
  retains its stack. Reopening synchronizes selection eligibility; a changed
  policy or listing invalidates Review. Confirmation refuses a second cleanup
  while the shared executor is busy.
- **No sheets, no alerts** — `MenuBarExtra(.window)` resigns key window
  status in ways that make `.sheet`/`.alert` dismiss the popover
  mid-interaction (`CLAUDE.md` Gotchas). Review is a pushed view;
  confirmations and destructive actions are plain in-view buttons.
- **Checkbox selection lives in the same popover**, pushed by Select Items
  from detail screens with child listings. It is scoped to that location and survives
  dismissal. Every cleanup still passes through Review and confirmation.

## 2. Screens

### Empty
Auto-scan without waiting to be asked is a kept decision. The first scan now
starts ~5 s after launch rather than on the first popover open, and the last
scan's rows are restored from disk before that, so this screen is what a first
ever run shows — no snapshot to restore and no scan finished yet. Every later
launch opens on restored rows (footer: "Scanned 3 hours ago") or on Scanning. Header: title
"Cruftless" (20 pt semibold, no capacity strip — nothing to summarize yet),
refresh control present at rest. Body: centered "Nothing scanned yet"
placeholder, large "Scan" capsule, caption "Nothing is deleted without your review."

### Scanning
Refresh control **replaced** by a small `ProgressView` (List's Header bullet —
never dimmed in place), and the footer counts "Scanning 6 of 13…" in place of
the timestamp — a partial rescan counts only what it walks ("Scanning 1 of 2…"),
which is a real count, not a share of a whole it is not covering. Not cancelable (REQUIREMENTS §7). What the body shows depends on
whether there is anything to show already:

- **Rows on screen (a rescan, or restored rows):** every row keeps the number it
  has, *except* the one being measured at that instant, which shows the same
  skeleton a first scan's pending row does — dimmed, "Measuring…", spinner in
  the size slot, no chevron, no hover action
  (`CategoryRowView(isMeasuring:)` → `PopoverRow(isPlaceholder:)`). Walks are
  serial, so the skeleton walks down the list one row at a time rather than
  blanking it; two rows may carry it for the instant a finished walk's row is
  still in transit. Emptying a full list and refilling it reads as the numbers
  having been lost, and the header keeps the finished total rather than
  following a partial sum downward.
  Only a scan **the user asked for** does this (`AppModel.isScanning`). A
  background FSEvents rescan skeletons nothing: it fires every few seconds while
  a simulator is booted, and rows blinking on their own while someone is reading
  the list is exactly the busy indicator that state exists to avoid.
- **Nothing on screen (a first ever scan):** the checklist
  (`ScanningChecklistView`). Every location the scan promised
  (`ScanEvent.planned`) is drawn at once — measured rows first, largest first,
  pending rows below in catalog order, dimmed with "Measuring…" and a spinner
  where the size goes (`PopoverRow(isPlaceholder:)`). A placeholder is the same
  fixed 38 pt row as the measured row it becomes — title 13 + caption 11 fits
  inside it — so nothing shifts as one lands. The header's hero climbs with the
  running total as rows land.
- **Before the plan arrives** (a few frames): the indeterminate "Scanning…"
  placeholder.

The first-contact strip (List, below) also sits above the checklist and the
"Scanning…" placeholder until it is retired.

### List
- **Header** (`14/16/10 pt` padding, bottom hairline): hero row —
  cleanable value (28 pt semibold) + "cleanable" (13 pt secondary,
  baseline-aligned) left, refresh control right; no app name. The refresh
  control is the `arrow.clockwise` glyph **bare** — 12 pt medium,
  `.secondary`, plain button, tinting to `.primary` on hover
  (`RefreshGlyphButton`). No glass circle: it sat opposite the largest type in
  the app and competed with it for a command nobody needs to find in a hurry.
  While a scan runs it is **replaced by a small `ProgressView`** framed to the
  same 20 pt, so the header never changes height, not dimmed in
  place: a disabled button that does not visibly move is indistinguishable from
  one that has stopped responding. 12 pt below: the **4 pt** capacity strip
  (used · cleanable · purgeable hatched · free, 1 pt gaps), then 7 pt below
  that a **one-line, three-item legend** — 6 pt swatch (2 pt radius) + 11 pt
  secondary label + 11 pt medium monospaced value with unit, distributed across
  the width, `lineLimit(1)` + `fixedSize` so it can never wrap: "Used 418,1 GB
  · Purgeable 25,3 GB · Free 50,9 GB". **"Cleanable" is not in the legend** —
  the hero says that number once in 28 pt, and the accent segment is the only
  thing it could be; a second copy in 11 pt reads as two measurements of the
  same thing. The strip's accessibility label enumerates all four figures.
- **Row anatomy**: `[16 pt symbol, 20 pt slot] · [title] · [size] ·
  [lock] [chevron]`. Title 13 pt regular, one line, middle truncation. Overview
  rows carry **no ⚠** — the 10 pt warning triangle is reserved for flagged
  child rows inside a drill-down (Archives), where it renders inline after
  the title at 6 pt spacing. The caption slot (11 pt secondary) survives
  for exactly one case: an unavailable row's reason. Size 13 pt monospaced
  digits, right-aligned, `min-width: 56 pt`, always primary so sub-gigabyte
  amounts do not resemble disabled values. Chevron glyph 11 pt semibold
  tertiary in a 12 pt slot on every available row. The lock appears when cleanup is
  unavailable; it does not replace the chevron or dim a selectable row. Row:
  `padding: 10pt horizontal,
  0 vertical; spacing 10pt; radius: 8pt; height: 38pt fixed`; no separators.
  The height is fixed, not a minimum — a row that grows to fit makes the list
  jump the moment a placeholder becomes a measured row. 4 pt of padding above
  the first row.
- **Platform sections:** Apple development and Android development rows are
  grouped under distinct headers, with their order persisted from Settings.
  Within each section, sized entries above 0 B come first, size-descending;
  then a full-width `Hairline` (0.5 pt, `.separator`), then unavailable
  entries (they carry the Access action, so they stay visible), then an
  "Empty N" disclosure header (11 pt semibold secondary, rotating chevron)
  over the entries measured at 0 B. The Empty group starts collapsed for each
  popover session. Row order is deterministic (size, then catalog order, then
  title), so equal rows never shuffle between rescans.
- **Read-only row** (`TrackedLocation.isInventoryOnly` — Simulator dyld cache,
  Android SDK, and Android Studio): a 11 pt `lock` glyph in `.tertiary`, beside
  the chevron when the row opens Detail. A read-only location with a dedicated
  per-item route (`ItemRemoval`: Gradle caches, Android Virtual Devices) shows
  no lock on its List row. Selectable rows keep normal contrast and hover feedback. Unavailable
  rows and measuring placeholders remain dimmed. Android's cleanable total
  includes only eligible, measured Gradle cache children. The Gradle location
  and eligible children have no lock; eligible children expose a Detail-only
  **Clear** action that pushes a per-attempt warning, then the standard Review
  and permanent-delete confirmation. The acknowledgement is not saved and
  does not assert that Gradle writers have stopped. In AVD Detail, each device
  row carries **Delete Device** and no lock; the unclassified remainder stays
  locked. Unknown Gradle children and the SDK and Android Studio rows remain
  locked. The Android section carries a single-line 11 pt `.tertiary` caption
  under its title, "Read-only except Gradle caches and devices"; the full
  sentence (SDK and Android Studio remain read-only, Gradle needs a risk
  review, stopped devices are deleted one at a time) is its `.help` and
  accessibility label. No notice band.
- **Hover-reveal controls**: at rest a row shows only its base anatomy; on
  hover it gets a rounded inset highlight and the trailing controls appear
  before the size (§3), animated `.snappy(duration: 0.16)`. The controls are
  (a) an icon-only per-row rescan button — a 20 pt circular glass button,
  `arrow.clockwise` glyph 11 pt medium, `.buttonStyle(.glass)` +
  `.clipShape(.circle)`, the back-control idiom — followed by (b) the action
  capsule, at 6 pt spacing; together they cost ~26 pt more than the capsule
  alone, and the size is hidden while they are shown, exactly as today. The
  rescan control appears on **every** List row — unavailable ones included,
  where a re-measurement is the only useful action — but not while the row is
  being measured. The slot is **not** reserved at rest — reserving it costs
  the title ~60 pt and permanently truncates long folder names on every row.
  The same controls are on the row's context menu ("Rescan" plus the action),
  for keyboard/accessibility parity.
- **The row is not a `Button`.** Selection is a tap gesture on the row; the
  action capsule is a real sibling `Button`. A `Button` nested inside another
  `Button`'s label is *part of that label*, so AppKit routes the click to the
  outer button and the capsule never fires. Parity comes from explicit
  `.accessibilityAddTraits(.isButton)` and `.accessibilityActions`.
- **The tap region excludes the hover controls**, so one click fires one
  action. Rows are keyboard focusable: Return and Space open Detail.
- **A row offers only an action that can succeed.** Clear appears only where
  `InventoryEntry.canClearWholeLocation` holds: measured above 0 B and
  `TrackedLocation.supportsWholeLocationClear` (path-deleted, deletable, not
  flagged). Rows in the Empty group carry no action capsule, and neither do the
  simulator devices, test simulators and runtimes rows, which `DeletionPlanner`
  refuses as a whole because CoreSimulator owns them; those open Detail. The
  flagged Archives row has no action capsule on the List either and opens
  Detail, where each archive is deleted one at a time. While a plan is being prepared for Clear
  or Delete, the row shows a spinner in place of the chevron. Copy Command
  swaps the capsule label to "Copied" for about 1.5 s and keeps the hover
  controls shown.
- **Unavailable row**: root exists but unreadable. Caption "Unavailable:
  <reason>" secondary, size "—", no action capsule, no chevron (REQUIREMENTS §4); the hover rescan control is present — re-measuring is the one useful thing there. The
  reason is too specific to compress into a glyph, so this row keeps the
  caption slot — title + caption still fit inside the fixed 38 pt.
- **Needs-access row**: a location the access gate kept the scan out of
  (CLAUDE.md rule 10). Caption `LocationAccessNeed.summary` ("Needs access to
  Documents", or "macOS does not allow reading Documents"), full message in
  `.help`, no chevron. Its capsule is "Allow Access" ("Review Access" when
  macOS refused) and opens the Settings window on its Access tab: an alert can
  dismiss the popover, so granting never happens in the popover itself. The
  action reaches the row through the `openAccessSettings` environment value
  that `MainView` sets.
- **Restored rows** (a row whose location `AppModel.isRestored(_:)` flags as
  never re-measured this session) look exactly like scanned ones — the
  timestamp carries their age. Freshness is per location, so a one-location
  rescan makes exactly that row actionable while the rest stay refused. A
  restored row's action is refused with a `NoticeStrip`: "These sizes are from
  <relative time>. Measuring now: try again in a moment.", and the scan
  starts; the notice clears itself when that scan completes, so it never
  says "measuring now" after measuring has finished. Planning from it would
  put a number read out of a file into Review.
  The hover rescan control is *not* refused — it is the fix for exactly this
  state.
- **Inline notices** above the row list, each an orange/red `NoticeStrip`
  (symbol + text, scrolls with the list): one per refused Xcode
  custom-location preference (`RootPreferenceIssue`), scan failure, plan
  refusal — any subset at once, in that order. They scroll with the list, and
  the list scrolls them into view when a refusal arrives, so a refusal from a
  lower row is never above the fold. The **running-apps warning is
  not among them**: it is true most of the working day, and a permanent band
  spends a row of height on it every time. It reports in the footer instead.
- **First-contact strip**: the first `NoticeStrip` in that stack, accent tint,
  `checkmark.shield.fill`, "Every deletion is reviewed first. Nothing happens
  until you choose.", with a trailing `xmark` dismiss control
  (`NoticeStrip(onDismiss:)`). It shows on the List and Scanning bodies, never
  on a placeholder, until the user dismisses it or confirms their first Review
  (either flow), and never again after that: `FirstContactStore` persists the
  retirement in `UserDefaults`, `FirstContactStrip.isVisible` decides.
- **Footer status**: the scan status ("Scanning 6 of 13…" / "Scanned 3 hours
  ago" / "Not scanned yet"), then, when Xcode or Simulator is up, a tertiary
  " · ", a 6 pt amber dot (the `judgment` tier tint) and "Xcode running" /
  "Simulator running" / "Xcode and Simulator running" in 11 pt `.secondary`.
  The full sentence ("Xcode is running. Anything it changes before deletion is
  skipped.") is the segment's `.help` and its accessibility label —
  `AppModel.runningApps` holds the fact and derives both lengths from it, so
  the short label is never parsed back out of the long one. Everything is
  `lineLimit(1)` + `fixedSize` except the scan status, which is the one thing
  allowed to truncate: Settings/Quit must never be pushed off the end.
- **"Nothing to reclaim"** post-scan (an inventory exists but holds no
  entries at all): centered placeholder, checkmark symbol, no action. A
  list whose entries are all 0 B still shows its rows, below the separator.
- **"Scan failed" placeholder** (inventory still `nil` — a location's
  first-ever scan hit `ScanEvent.failed`): warning symbol, failure message,
  "Try Again" capsule (`refreshScan()`). Once an inventory exists, a later
  failure is a red `NoticeStrip` (above) instead, not this placeholder.
- **Upper-bound info toggle**: beside the hero, an `info.circle`/`.fill`
  button toggling an inline sentence about APFS clone counting — not a native
  tooltip/popover, both unreliable here.
- **Footer** (36 pt, top hairline, `ListFooter`): "Scanning <n> of <total>…"
  while a scan the user asked for runs; otherwise "Scanned just now" under a minute and "Scanned <relative time> ago"
  after (11 pt tertiary, refreshed every 30 s) left, or "Not scanned yet" pre-first-scan; " · Paused in Low Power
  Mode" appended while the automatic scan is held (appended, not substituted —
  how old the numbers are matters more once nothing is refreshing them); "Settings" / "Quit"
  text buttons right, 14 pt gap, bound to ⌘, / ⌘Q.

### Detail
Four views, one per shape: `DetailView` (plain child folders),
`SimulatorsDetailView`, `RuntimesDetailView`, and `LocationSummaryDetailView`
(locations without child listings). Every available List row opens Detail.
Locations without child listings show their measured total, paths, and existing
Clear or Copy Command action, without reading a new child listing.

All four share one skeleton, `LocationDetailScaffold`, so they read as one
family whatever the body holds. Only the body changes between them:
1. **Header**: back button left; entry title centered with a second 11 pt
   secondary line under it, `<total> · <N items|devices|runtimes|folders>`
   (`DetailSummary`; omitted while loading or on a read error, "—" for an
   unmeasured summary location); trailing info control only.
2. **Tier strip** (`LocationTierStrip`), pinned under the header on every
   Detail: 11 pt `<tinted tier word> · <first sentence of consequence>`,
   `lineLimit(2)`, on a faint tint between two hairlines.
3. **Body**: folder list (`DetailView`), device sections
   (`SimulatorsDetailView`), runtime list (`RuntimesDetailView`), or facts
   (`LocationSummaryDetailView`: "Cleared as a whole" with the rest of the
   consequence, or "Delete from Terminal" with the dyld command, then each
   root path with its size).
4. **Footer band**, always present at one height: Select Items (labeled glass
   capsule) left only where `TrackedLocation.supportsBatchSelection` holds, so
   several children can share one review (not Gradle caches, Android Virtual
   Devices, read-only listings or Xcode installs); the location action right: Clear All (folder lists), Clear
   or Copy Command (summary), or an 11 pt status line ("1 booted" on
   simulators). An empty band stays to keep the body height constant.

No Detail shows a 22 pt hero. A large number in a pushed screen means Review:
what is about to be committed.

The info button expands an inline "About this section"
panel above the content, collapsed on entry. It contains the approved
"What it is" and "Deletion risk" copy plus the permanent-deletion reminder.
The panel scrolls with content and remains available in loading, empty, and
error states. Its button exposes an accessible label and expanded/collapsed
value; expansion respects Reduce Motion and never opens a sheet or popover.
- **Notes** (`DetailView`): inventory issues, Android SDK diagnostics and
  Android root provenance sit above the rows, only when present.
- **Rows**: For Derived Data, row title is `Naming.derivedDataFolder(child.name)` 
  with raw name as `.help()`; for other entries, existing naming. Row caption: 
  Derived Data rows show the recorded workspace path, tilde-abbreviated and
  middle-truncated, in 11 pt secondary (`DerivedDataWorkspaceCaption`, full
  path as `.help()`); an orphaned row prefixes it with "Orphaned ·" in orange;
  a folder with no usable record (system folders, unmounted volume) shows no
  caption. Other locations: none — the warning triangle on a flagged child,
  nothing otherwise. Hover action reveals capsule in the size's slot, animated
  `.snappy(duration: 0.16)`.
- **Not measured rows** (`BlockedAccessRow`): after the measured rows, one
  read-only, dimmed row per root the access gate kept the scan out of (an
  Xcode copy in Downloads, say), titled by `BlockedAccess.reason`, captioned
  `BlockedAccess.summary`, "Not measured" in the size column, full path as
  `.help()`, and the same "Allow Access" / "Review Access" capsule as the List.
  They count toward neither the header total nor Clear All.
- **Orphaned projects card** (Derived Data only, when at least one selectable
  folder is orphaned): inset glass group above the rows, 12 pt radius —
  orange `questionmark.folder` icon, 13 pt "Orphaned projects · N · size", 11 pt
  secondary "Their projects were deleted or moved.", trailing small glass
  "Select" button (disabled while a deletion runs). Select pushes Select Items
  with exactly the orphaned, selectable rows checked (replacing any earlier
  selection); nothing is planned until the user reviews and confirms. Review
  re-checks each folder's orphan status (REQUIREMENTS §9).
- **Suggestion card** (Device Support only) — **Deferred, not implemented in
  v1.1**; `DetailView` today renders a flat child list under the shared
  header and tier strip, no grouping. Spec once built: inset glass group — sparkle icon, "Keep
  newest per device" title, caption "Clears N superseded builds · X GB",
  prominent "Review" capsule pushing `Review` pre-populated with every
  superseded build (REQUIREMENTS §9 keep-newest).
- **Footer**: "Clear All" (no size, no ellipsis) capsule right of Select
  Items; for Archives, note "Archives marked ⚠ are not included." between
  them, wrapping to two lines.

The Select Items control pushes a checkbox screen in the existing 380 pt
popover. A compact control band contains Select All, Clear Selection, and
Refresh; a pinned footer shows the selected count and allocated-size estimate. It starts empty. Disabled rows
explain flagged, protected, read-only, bundled, removing, or unavailable items.
Derived Data rows use the workspace path as their subtitle ("Orphaned · ~/path" for an orphaned one, the folder path when none is recorded).
Select All includes eligible rows globally or within a simulator runtime group. Gradle exposes
one eligible entry at a time and keeps its per-attempt risk acknowledgement.
Review names each exact action (including shutdown before simulator deletion),
shows the consequence and current free-space estimate, and requires a separate
confirmation. Cancel retains selection; Done clears it and refreshes the
location. Selection is in-memory and scoped to one tracked location. Focus-loss dismissal
preserves the selection flow; explicit Back exits it. No extra window or
NavigationStack is created.

**Simulators detail** differs:
- **Unavailable section** first (runtime removed): irreversible-red header 
  "Runtime removed" with subtotal; row caption `<runtime name> · Can't boot`; 
  only action "Delete" in red text.
- **Device sections** (one per runtime, ordered by size desc): header 
  `Naming.runtime(...)` with "N devices · size" trailing. Row caption: only 
  "Booted" (green dot); nothing for a shut-down device. Hover action: "Erase" for shut-down; "Shut Down and Erase" 
  for booted (both route through Review).
- **Expanding a device** reveals an indented inset glass group:
  "Cleanable inside this device · N GB" caption, its known-bloat
  sub-paths (Poster extension data store / Caches / Temporary files) each with a size,
  one trailing grouped "Clear" action — the PathGuard-bounded exception in
  REQUIREMENTS §5, never a raw delete of the device; disabled with a "Shut
  the simulator down first." help string while the device is booted.
- Footer: Select Items left; "N booted" status right while any device is
  booted. No Clear All (runtimes are their own top-level `List` entry with
  their own `Detail`).

### Review
Pushed from any "Clear"/"Delete" action. It opens with a **receipt card**
(`ReviewReceiptCard`), the one card no Detail screen has, so Review never
reads as another listing: glass, 12 pt radius, irreversible-red outline at
45 %. Inside, top to bottom: hero row with total (22 pt) + "N items"; a 6 pt
capsule bar of free space after the plan, split into free now (secondary) and
what the plan adds (irreversible red at 55 %); under it, 11 pt secondary
"Free now 24,5 GB" left and "After ~31,2 GB" right — the "now" read live from
`VolumeCapacity.query()` at push time, the "after" the plan's upper-bound
estimate, hence the required "~"; bar and labels are omitted when the
capacity query fails. A hairline, then 11 pt irreversible red: "This can't be
undone. Files are deleted permanently, not moved to the Trash." (REQUIREMENTS
§10 opening sentence). Non-blocking notice when Xcode or Simulator.app is running
(REQUIREMENTS §9 — informational, never a refusal), below the card. Item list:
plain rows separated by hairlines, no per-item cards; title + size on line 1;
consequence as plain secondary text below (no tier word, flush-left, wraps).
Flagged items' consequence text is tinted irreversible red. Footer: 
Cancel (plain, `.keyboardShortcut(.cancelAction)`) and a destructive-prominent
confirm capsule labeled **"Delete Permanently"**, or **"Shut Down and Erase"**
for a booted simulator (`DeletionPlan.confirmLabel`). No "don't ask again".
While a plan runs the header and footer are disabled and the confirm label
becomes a `ProgressView`, but the item list stays scrollable; a second tap in
the gap is a no-op (`AppModel.isDeleting` guard), not a second run. For a batch the card's
hero becomes "Deleting 2 of 5" and its free-space bar gives way to a
determinate progress bar; a single-item plan shows a small spinner beside
"Deleting" and the size instead of a bar (`DeletionRunState`, driven
by `DeletionItemEvent`s from the executor), and every item row carries a
leading status mark: pending circle, spinner (active), green check with
"Freed 18,3 MB", red triangle with the failure reason, or a grey dash with the
skip reason. The active row replaces its consequence text with the phase
detail ("freeing space, this can take a minute" once the mutation is
confirmed), and the list follows the active row until the user scrolls. A
failed item never stops the batch.
`simctl` targets stay on this screen until the space has settled
(`DeletionExecutor`, REQUIREMENTS §10), so Result's numbers are real.

On confirm the same navigation slot becomes **Result**: hero "15.5 GB freed" 
(28 pt); sub line "Free space 2.5 GB → 18.0 GB · 1 item failed · 1 item not
attempted" (each clause only when it applies — a real failure and a cancelled,
never-reached item are counted and worded separately, `DeletionResult
.failedCount` / `.notAttemptedCount`). Per-item outcomes have four states, not
two: check (green) for success, triangle (orange) for `partiallyFailed` — a
target the executor removed part of before hitting an immutable or
root-owned child, still credited the bytes it did free — minus (secondary,
neutral) for `notAttempted(reason:)` — an item the run was cancelled before it
ever reached, or a plan refused outright because another run was already in
progress, so it is not a failure — and x (red) for a target the run reached
and left fully untouched, each with its failure or not-attempted reason
inline. Successes stay visible alongside failures (CLAUDE.md safety rule 6).
An item whose space-settle wait hit its cap is still a success, but its row
carries the note "Free space was still arriving when the result was measured."
in 11 pt secondary — the free-space line was read before the space finished
arriving, and the note says so rather than pretending otherwise.
Footer: "Done" capsule (`.keyboardShortcut(.defaultAction)`), pops to `List`.

### Welcome
A `Window` scene (`WelcomeWindow.id`), 520 pt wide with 480 pt of content,
hidden title bar, not resizable, presented at launch on a first run only
(REQUIREMENTS §7). One step at a time. The footer holds step dots on the left
(the current one a 16 pt capsule), then Back and a prominent primary button on
the right. Steps slide in from the side they lie on
(`WelcomeWindow.stepAnimation`), and fade instead under Reduce Motion. Titles
are 22 pt semibold, body 13 pt secondary, captions 11 pt. From step 2 on the
title sits at the same height on every step. Rows sit in `WelcomeCard`: a 12 pt
rounded box on the control background with a 0.5 pt separator stroke.
Illustrations are sketches of bars on a quaternary panel, never sample numbers,
so nothing in them can be read as the user's own data.

1. **Where it lives** (the cover). `WelcomeMenuBarIllustration`, 236 pt tall: the
   screen's top right corner with the menu bar icon picked out in accent, the
   popover below it, and the app name. Then "Cruftless lives in your menu bar"
   with the real menu bar glyph inline in the sentence. Nothing is anchored to
   the real status item, whose frame `MenuBarExtra` does not expose. The sheep
   stands above the app name, 92 pt wide. Every few seconds it looks up at the
   menu bar icon, which answers with a small bounce, and while the pointer is
   over the illustration its eyes follow the pointer. Following the pointer
   holds the blinking and the glance, so the eyes never jump mid-follow.
2. **Safety promise.** "Nothing is deleted without you" over
   `WelcomeReviewIllustration` (a sketch of the Review step) and three rows from
   `WelcomePolicy.safetyPromises`. Each promise carries its own symbol; the
   flagged one uses the app's warning triangle in orange.
3. **What to scan.** "Choose what to scan": two checkboxes under "Platforms",
   each captioned by `DetectedPlatforms.note(for:)` (the Apple one counts the
   Xcode installs found), then a "Launch at login" switch under "Menu bar" with
   the same error, notice and "Open Login Items" control as the General pane.
   The access check re-runs whenever the selection changes, and the primary
   button is disabled until it answers, so its label ("Continue" or "Start
   Scanning") is never wrong at the moment of the click.
4. **Access**, only when `AccessPreflight` finds a need for the chosen platforms.
   "Some places need your OK" over one card with a block per protected place
   (`WelcomeAccessAreaRow`): its status ("Not asked yet", "Waiting for your
   answer", "Allowed", "Not allowed"), "Allow" or "Open Privacy Settings", and
   one line per tracked item there. Same `AccessListModel` as Settings > Access.
   The card scrolls only when the places do not fit; the skip note stays below
   it. The primary button is "Start Scanning".
5. **First scan.** Entering this step starts the scan and the window stays open.
   `WelcomeScanStep` renders a `WelcomeScanSummary`: the cleanable total at
   44 pt, a 4 pt progress bar, and up to five 36 pt rows (landed sizes, then
   "Measuring…", then "Waiting"). When the inventory lands the title becomes
   "Your first scan is ready", the rows that do not fit fold into "N more in
   the menu bar", and a place that was skipped or refused is named with the
   same "Allow Access" or "Review Access" action a blocked list row carries.
   The button reads "Close" while scanning and "Done" after. There is no Back.
   The sheep sits right of the title, 72 pt wide: neutral and looking at the
   numbers while scanning, happy when the scan is ready, worried when it failed.

**The mascot** (`MascotView`). The sheep is on screen from the start and its
body never moves: no entrance, no bounce. While neutral, vector eyes drawn over
the art blink and follow a gaze; an expression change is a 0.2 s crossfade. With
Reduce Motion the eyes are still. In dark appearance it carries a thin light
keyline so its plum outline stays visible. It appears on welcome steps 1 and 5
only: the safety, setup and access steps stay plain. `docs/mascot/BRIEF.md` has
the character rules.

Closing the window at any step counts as finishing. The copy for whether to
show it, which steps exist, the safety lines, the platform notes and the scan
summary all live in Core.

### Settings
Native SwiftUI `Settings` scene containing a `TabView` of `Tab`s — the standard
macOS preferences window, which AppKit renders with the system toolbar tab bar
("General", "Access", "Support", "About", in that order). The scene sets only `.windowResizability(.contentSize)`,
so the window sizes itself to whichever tab is showing.

Tabs are the right shape here, not a two-panel sidebar. A settings *window* is
specified as an `NSToolbar` in `NSWindow.toolbarStyle = .preference`, which is
what the `Settings` scene renders — and the sizing rule runs opposite to
intuition: a toolbar exists to group a *large* number of settings, and few
enough settings means dropping the toolbar for a single pane, never adding a
sidebar. Apple's own macOS 26 apps (Safari, Mail, Notes, Finder, Terminal) are
all still toolbar tabs after the Liquid Glass pass. System Settings is not the
counterexample: it is a settings *app* of ~30 panes with its own window class,
and has never been the template for a third-party preferences window. Cruftless
has four panes; a sidebar holding four rows is a column of chrome.

**Do not use `NavigationSplitView` here.** It was tried and it is wrong in
every visible way: the sidebar runs to the top of the window so the traffic
lights land inside it with no titlebar band, a "Hide Sidebar" button appears
(Settings windows never have one), the toolbar/sidebar Liquid Glass materials
never resolve, and sidebar selection draws as a full-bleed blue rectangle
instead of the inset capsule. `.windowToolbarStyle(.unified(showsTitle:))`
does not rescue it. The tabbed form gets traffic-light placement, the glass
toolbar band, the window title, and per-tab resizing from the system for free.

That failure indicts `NavigationSplitView`, not sidebars as such — do not read
it as "a sidebar is impossible here". **If the pane count ever outgrows a
toolbar row** (RocketSim, the app usually cited for this, carries eight; four
still fits comfortably), the supported route on macOS 26 is
`TabView { … }.tabViewStyle(.sidebarAdaptable)`, with `TabSection` for
grouping. It keeps the `Settings` scene and its ⌘, semantics, and the system
draws the sidebar and its selection. Reach for that, never a hand-built split
view. Worth knowing before you do: Tahoe's sidebar rendering was the most
criticised part of that release (margins, isolated containers, an icon-sizing
bug), and macOS 27 Golden Gate reworks sidebars again — full-bleed to the
window edge under a unified toolbar. A sidebar adopted early is a sidebar
retuned every autumn.

Panes are a fixed 540 pt wide (`SettingsMetrics.paneWidth`). Do not imitate
system chrome with custom overlays, manually positioned controls, or a root
`.glassEffect()`.

**Pane height follows the content.** A grouped `Form` is a scroll view with no
intrinsic height, so General and Support apply `View.settingsPaneSizing(estimate:cap:)`
(`Views/Components/SettingsPaneSizing.swift`). It reads the form's scroll
content height through `onScrollGeometryChange`, records it in a Core
`SettingsPaneHeight`, and frames the pane at `min(measured, cap)`.
Past the cap the form scrolls. The cap is 800 pt, further limited to the main
screen's visible height minus 140 pt of window chrome. `estimate` stands in for
the first frame so the window does not open at a wrong size. Only `contentSize`
counts: the window already reserves its toolbar, and the scroll view's container
size and content insets follow the window frame. While the window animates to a
new tab the top inset is interpolated pass by pass, so a height that included it
restarted the resize on every layout pass until AppKit aborted the app.
No pane carries a hand-tuned height constant.
About is not a form and sizes to its intrinsic content.

- **General**: one `Form` with `.formStyle(.grouped)` — grouped is correct at
  this pane width (the earlier warning about "wide iPad-like cards" applied to
  an edge-to-edge split-view detail pane, not to a 540 pt preferences tab). A
  single Form keeps one label column across all groups; splitting the rows
  across several Forms is what previously left the two toggles misaligned.
  Sections use title-case headers: Startup, Reminders, Platforms to Scan, an
  optional Main Page Order (shown only when both platforms are selected), and
  Protected Paths, each with a real `Section` footer rather than hand-rolled
  caption `Text`.
  - **Startup**: "Launch at login" (toggle, off by default). The login item's
    approval-pending notice (`LaunchAtLoginPolicy.statusMessage`) renders from
    the status alone, including when the pane opens, as a secondary
    `SettingsNoticeRow`; a failed write shows a red `SettingsErrorRow` instead.
    A `.notFound` status says nothing until an enable fails, then explains it
    (`LaunchAtLoginPolicy.notFoundMessage`). While approval is pending, or after
    that failure, an "Open Login Items" button opens System Settings.
  - **Reminders**: "Weekly scan reminder" (toggle, off by default). The footer
    says it is a weekly local notification and never scans. If notifications
    are revoked in System Settings the toggle turns itself off and shows the
    permission message; the pane checks on appear and on app activation with a
    non-prompting authorization query.
  - **Platforms to Scan**: Apple and Android development toggles (both enabled
    by default; at least one stays selected; locked while a deletion runs, with
    the busy message beneath). The footer calls out shared Gradle caches,
    read-only SDK and Android Studio storage, the Android tools needed to delete
    devices, and the extra Gradle risk review. Scope changes invalidate Reviews
    and start a fresh scan.
  - **Main Page Order**: a segmented "Show first" picker, persisted.
  - **Protected Paths**: each row is folder icon + folder name +
    tilde-abbreviated path, trailing remove button, over an "Add Folder…"
    button that presents a SwiftUI `.fileImporter`; an empty list shows "No
    protected folders". A folder refused by `ProtectedPathPolicy` (`/`, `$HOME`,
    or one already covered) shows a red `SettingsErrorRow` under the button
    rather than failing silently. Add Folder and the remove buttons are disabled
    while a deletion runs, and the busy error clears when it ends. No selection
    state, no bordered list, no custom glass cards.
  - There is no staleness threshold — nothing renders a staleness label any
    more, so the preference that tuned it is gone. Which controls are locked and
    what a locked control says live in Core (`SettingsControlPolicy`), not in
    the view.
- **Access** (`AccessSettingsPane` over the reusable `AccessListView`): one
  grouped `Form`, one section per protected area that has a current need
  (`AccessPreflight`) or was asked before, headed by `ProtectedArea.title`.
  The first row is the status: "Allowed" (green check, no button), "Not asked
  yet" with an "Allow" button, or "Not allowed" (red) with "Open Privacy
  Settings" and the line "macOS will not ask again. Turn on Cruftless under
  Files and Folders." Below it, each reason (folder or app icon, title,
  tilde-abbreviated path), or "Nothing Cruftless tracks is here right now."
  for an asked area with no current need. Allow runs one `AccessRequest` off
  the main thread; while macOS's alert is up the row reads "Waiting for your
  answer" with a spinner and every Allow button is disabled. A request that
  never reached macOS shows its reason in orange under the area. With no areas
  the pane shows "Nothing Cruftless tracks is in a protected place". The
  footer says only places holding something tracked are listed, nothing there
  is read until allowed, and the rest of the app works without it. State is
  re-read on appear and on app activation. The popover's "Allow Access"
  capsule selects this tab through `SettingsModel.requestedSettingsSection`.
- **Support**: one grouped `Form` with three sections.
  - **Simulator Tools**: the current toolchain status (a ready Xcode with its
    version and source, an unavailable reason, or "Not checked. Refresh to
    inspect simulator tools."), a "Use Xcode" picker over the usable Xcodes, a
    "Refresh Toolchain Status" and "Choose Xcode…" row, and "Use System
    Selection". The candidates load when the tab opens. The picker applies on
    change, with no confirm button, and shows a "Choose an Xcode" placeholder
    while the Xcode in use is not among the listed ones. "Use System Selection"
    is enabled only when it would change the resolution. Every toolchain control
    is disabled while a cleanup runs, with an "Unavailable while a cleanup is
    running." note. The footer says the choice is local and never changes
    macOS's Xcode selection.
  - **Diagnostic Report**: "Prepare Diagnostic Report", an inline monospaced
    preview, "Copy Report" and "Save Report…", a one-line notice, and an "Open
    Issue Tracker" link. Toolchain work and report preparation have separate
    busy states and spinners. Copy and save confirmations fall back to the
    prepared notice after 2 s. When the toolchain summary changes after a report
    was prepared the preview dims, Copy and Save are disabled, and the notice
    reads "This report is out of date. Prepare it again." The footer states that
    only allowlisted version and status fields are included.
  - **Uninstall**: for a Homebrew cask install, the
    `brew uninstall --zap --cask cruftless` command with Copy; otherwise a
    destructive "Remove Cruftless Data" button (no ellipsis: its sheet is the
    review step). The sheet moves through measuring, review (each folder with
    path, size and consequence, the registrations undone, and what stays),
    removing, and a result listing each step with a check or a warning. The
    result's only way out is "Quit Cruftless"; a refusal shows the reason and
    the manual path list with "Close".
- **About**: centered — 72 pt app icon, "Cruftless" (17 pt
  semibold), the version read from the built bundle via
  `CruftlessVersion.display()` — never a literal, and the line is omitted
  entirely rather than invented if the bundle carries neither key — "MIT
  License · © 2026 Daniel Munoz", an inset bordered group with three rows
  ("Project Website", "GitHub Repository", "Acknowledgements", trailing
  external-link arrow), then an update section. A Homebrew cask install
  (`UpdateChannel.detect`: a `cruftless` entry exists under
  `/opt/homebrew/Caskroom` or `/usr/local/Caskroom`, existence checks only)
  reads "Updates ship through Homebrew." with a selectable monospaced
  `brew upgrade cruftless` and a copy button whose checkmark resets after 2 s;
  any other install reads "Download new versions from GitHub Releases." with a
  "GitHub Releases" link instead. Both end in a "Check for Updates" push button. The check reports the latest stable GitHub
  release with a link to its release page; it never downloads or installs the
  app. A build with no release version to compare shows its own message instead
  of a generic failure. For a cask install only, an available update adds that
  Homebrew may take a little while to publish the matching cask.

## 3. Action labels

| Tier / context | Label | Notes |
|---|---|---|
| `regen` | "Clear" | No ellipsis — Review-gated |
| `judgment` | "Clear" | Device Support superseded builds, SwiftPM cache, simulator known-bloat; No ellipsis — Review-gated |
| `⚠` (Archives, flagged child rows in Detail) | "Delete" | Red text on default glass capsule; No ellipsis — Review-gated. The List's Archives row has no capsule and opens Detail |
| `reveal` (Xcode installs) | "Show in Finder" | Opens Finder directly, no review step |
| `ⓘ` (dyld cache) | "Copy Command" | Copies `sudo rm -rf /Library/Developer/CoreSimulator/Caches/dyld` to the pasteboard, no review step; the capsule reads "Copied" for about 1.5 s |
| Simulator device, shut down | "Erase" | No ellipsis — Review-gated |
| Simulator device, booted | "Shut Down and Erase" | Erase alone unavailable while booted; routes through Review |
| Simulator device, unavailable | "Delete" | Red text; only action offered; routes through Review |
| Simulator runtime | "Delete" | No ellipsis — Review-gated |
| Toolchain | "Delete" | No ellipsis — Review-gated; warns in Review if this is the toolchain Xcode's `DVTDefaultToolchainOverrideIdentifer` currently names — not an `xcode-select` check |
| Grouped known-bloat (device detail) | "Clear" | No ellipsis — Review-gated |
| Suggestion card (keep-newest) | "Review" | **Deferred, not implemented in v1.1** — see §2 Detail |
| Review confirm | "Delete Permanently" / "Shut Down and Erase" | From `DeletionPlan.confirmLabel`; the latter only for a booted simulator |
| Settings footer | "Settings" | Opens system Preferences window |
| Result | "Done" | Pops to List |

Trailing ellipsis only appears on actions that open a picker ("Add Folder…").
Review-gated actions carry none because every deletion is reviewed, and
Settings carries none either — an always-available footer command, not a
provisional action.

## 4. Tier presentation

No badges or pills, and **no tier word on a list row** — the words below are
written once on the Detail tier strip and in Review, never repeated per row.
A flagged row is marked with the tinted 10 pt warning triangle alone — in a
drill-down; an Overview row shows no marker at all (§2 Row anatomy). Exact
words and colors:

| Tier | Word | Light | Dark |
|---|---|---|---|
| `regen` | Regenerates | `#1F8A3D` | `#5CD97A` |
| `judgment` | Needs re-download / Needs reinstall / Holds app data (per location) | `#A85F00` | `#FFB340` |
| `judgment` (Xcode coding assistant) | Holds history | `#A85F00` | `#FFB340` |
| `⚠` | Not recoverable (+ 10 pt warning-triangle glyph on flagged drill-down child rows) | `#C1271D` | `#FF6B62` |
| `reveal` | Show in Finder only | `rgba(0,0,0,0.45)` | `rgba(255,255,255,0.5)` |
| `ⓘ` | Needs sudo | `rgba(0,0,0,0.45)` | `rgba(255,255,255,0.5)` |

**Hover rule**: on hover a row's trailing group is a `ZStack(alignment: .trailing)` 
where the size text and action capsule occupy the same slot; on hover the size 
fades out and capsule fades in (`.snappy(duration: 0.16)`). The title/caption 
block's width must not change.

**Copy rules** (what never renders):
- Silent defaults: "Shut down", "unknown", "0 B", "used today", staleness
- Exceptions that speak: Booted, Runtime removed
- Each fact rendered once at its tier level, not repeated per row
- The three verbs: **Clear** what Xcode rebuilds · **Erase** a simulator's 
  contents · **Delete** what is gone for good

## 5. Icon model

`RowIcon` is `case symbol(String)` (SF Symbol name) or `case image(String)`
(bundled resource), resolved per tracked-location descriptor. Rendered at
**16 pt**, `.symbolRenderingMode(.hierarchical)`, secondary label color
(image icons render as-is unless marked template). `.image("xcode")` names a
resource this app never bundles; `RowIconView` falls back to
`NSImage(named:)`, then `NSWorkspace.shared.icon(forFile:)` on the row's
resolved Xcode.app path, then `app.dashed` — what a user with no Xcode sees.

| Entry | Icon |
|---|---|
| Simulator devices | `iphone` |
| iOS/watchOS/tvOS/visionOS Device Support | `cable.connector.horizontal` |
| Simulator runtimes | `square.stack.3d.up` |
| Derived Data | `hammer` |
| Previews cache | `eye` |
| Xcode installs | **custom image** — the Xcode app icon |
| Simulator dyld cache | `internaldrive` |
| Toolchains | `wrench.adjustable` |
| SwiftPM cache | `shippingbox` |
| Interface Builder support | `rectangle.3.group` |
| Archives | `archivebox` |
| Xcode coding assistant | `sparkles` |
| Build products & logs | `doc.text` |

## 6. Visual tokens

Liquid Glass throughout; no opaque panels. Values are the canvas's
approximations — use the SwiftUI mapping where one exists; the literal
value is authoritative only where marked *mockup* (no system equivalent).

| Token | Mockup value | SwiftUI mapping |
|---|---|---|
| Popover material | `blur(48px) saturate(1.7)` glass | none — `MenuBarExtra(.window)` already draws a vibrant background. Painting `.ultraThinMaterial` or `windowBackgroundColor` over it is what made the popover read as a flat, pasted-on panel. Header and footer bands are transparent, separated by a 0.5 pt `Hairline` |
| Capsule (default) | glass pill, 24 pt tall | `.buttonStyle(.glass)` |
| Capsule (prominent/destructive) | tinted glass fill | `.buttonStyle(.glassProminent)` + `.tint(.accentColor)`/`.tint(.red)` |
| Inset glass group | `rgba(255,255,255,0.5)` fill, inset highlight | `.glassEffect(in: .rect(cornerRadius: 12))` |
| Row highlight (hover) | `rgba(0,0,0,0.065)`, radius 8 pt, inset 6 pt, no separators | `RoundedRectangle().fill(.quaternary.opacity(...))` on hover — there is no `List`, rows are `ScrollView` + `LazyVStack`, so `.listRowSeparator(.hidden)` never appears |
| Header/footer hairline | `0 0.5px 0 rgba(0,0,0,0.09)` | custom `Hairline`: `Rectangle().fill(.separator).frame(height: 0.5)` — *mockup*, not `Divider()` |
| Text primary/secondary/tertiary | `0.88/0.55/0.32` black, `0.92/0.6/0.35` white | `.primary` / `.secondary` / `.tertiary` |
| Type — hero | 28 pt semibold, `-0.5pt` tracking | `.font(.system(size: 28, weight: .semibold))` |
| Type — row title | 13 pt regular | `.font(.system(size: 13))` |
| Type — caption | 11 pt | `.font(.system(size: 11))` everywhere — `.font(.caption)` is never used |
| Row metrics | height 38 pt fixed, radius 8 pt, inset 10 pt, spacing 10 pt, icon 16 pt in a 20 pt slot, size column 56 pt, trailing lock/chevron column | `PopoverMetrics.rowHeight` / `.rowCornerRadius` / `.rowInset` / `.rowSpacing` / `.iconSlot` / `.sizeColumn` / `.chevronColumn` |
| Capacity strip height | 4 pt, 1 pt segment gaps | `.frame(height: 4)` on the `GeometryReader`, `HStack(spacing: 1)` clipped to a capsule |
| Legend swatch | 6 × 6 pt, 2 pt radius | `RoundedRectangle(cornerRadius: 2, style: .continuous)` |
| Read-only row | 11 pt `lock` beside a navigational chevron; selectable content stays full contrast | `PopoverRow(isReadOnly:)` |
| Running-app dot | 6 pt amber, `#A85F00` / dark `#FFB340` | `DesignTokens.tierColor(for: .judgment)` |
| Capacity strip — used/reclaimable/free | flat fills, see §2 List | `Rectangle().fill()`; reclaimable is `.fill(Color.accentColor)`, not `.tint` |
| Capacity strip — purgeable | 45° hatched stripes | *mockup* — custom `Canvas` pattern, no system equivalent |
| Accent | `#007AFF` / dark `#0A84FF` | `Color.accentColor` |

Dark mode mirrors every light value per the canvas's dark tokens (design
canvas link at the top of this file). Implemented as hardcoded hex pairs
behind a dynamic `NSColor` provider (`DesignTokens.tierColor(for:)`), not
semantic `Color` assets or `@Environment(\.colorScheme)` — this resolves per
appearance correctly both inside and outside a view body, which `@Environment`
cannot do.

## 7. Previews required

Every view ships `#Preview` coverage in `#if DEBUG`, using shared fixtures
(not one-off doubles), covering at minimum:

Shared preview models live in `Views/Components/AppModel+Previews.swift`
(`.previewPopulated()`, `.previewScanning()`, `.previewFailed()`,
`.previewWithXcodeRunning()`, `.previewWithXcodeAndSimulatorRunning()`) over `CruftlessFixtures` — never one-off doubles
inside a view file. A fixture-heavy `#Preview` block that would push its host
view file toward the 500-line ceiling lives instead in a sibling
`<View>+Previews.swift` file (see `SimulatorsDetailView+Previews.swift`,
`ListView+Previews.swift`) — same rule, just a different file.

`SimulatorsDetailView` and `RuntimesDetailView` share their loading/error/empty
branching via `Views/Components/LoadStateView.swift` rather than repeating the
four-way `if` chain; it ships its own `#Preview` for all four states.

| View | States (named as the `#Preview` titles in code) |
|---|---|
| `WelcomeView` | Where it lives, Safety promise, Setup (Apple only; both platforms with the access step following; still checking; login item needing approval), Access (as first seen; one place in each state; waiting for macOS; request changed nothing), Scan (starting; part way through; finished; finished with places not measured; failed) |
| `PlatformInventorySection` | Apple (Empty collapsed), Apple with Empty expanded, Android |
| `ListView` | Populated (covers the flagged, read-only and sub-GB rows from `PreviewFixtures.sampleEntries`), rows below the separator, Xcode and Simulator running, Empty, Nothing to reclaim, Plan refusal notice, Scanning, Rescanning one row, Rescanning a flagged row, Scanning before the plan lands, Restored from last session, Paused in Low Power Mode, Scan failed, Preference issue, Populated with unavailable row, First-contact strip, First-contact strip while scanning, First-contact strip retired |
| `CategoryRowView` | Rows — every tier (drill-down, regen, reveal, read-only, flagged — no ⚠ on Overview rows, sub-GB, 0 B, unavailable), Rows — being re-measured, Rows — needs access, with the Access action |
| `ScanningChecklistView` | part way through, nothing measured yet |
| `ListFooter` | every state, including scanned just now and both apps running |
| `DetailView` (generic entry) | Derived Data (populated), Derived Data (orphaned projects), Derived Data (no orphans), single item, Archives (flagged, batchable excluded), empty. **Deferred, not in v1.1:** with suggestion card, all-superseded (§2) |
| `OrphanedProjectsCard` / `DerivedDataWorkspaceCaption` | Orphaned projects card (enabled, disabled), Workspace captions (live, orphaned, none recorded) |
| `CleanupSelectionView` | empty, refreshing, failed scan, stale IDs, simulator groups, disabled runtimes, orphaned projects preselected, selected files |
| `GradleCacheRiskView` | populated warning, exact path, cancel, accept risk and continue to Review |
| `SimulatorsDetailView` | sectioned by runtime, expanded known-bloat group, no devices, load error |
| `RuntimesDetailView` | populated, empty, bundled only (non-deletable), load error |
| `LocationSummaryDetailView` | coding assistant, restored cache, read-only (dyld command), no inventory |
| `LocationDetailScaffold` | collapsed info with Clear All, expanded info before a summary exists, expanded info on an error |
| `LocationTierStrip` / `DetailSummary` | every tier; each count unit and an unmeasured size |
| `ReviewReceiptCard` | with free space, capacity unknown |
| `ReviewView` | regular, executing (mutating phase), single item running (spinner), batch in progress, freeing space (settle phase), flagged (`⚠`), Xcode running, mixed batch, booted simulator erase, free space estimate |
| `ResultView` | all succeeded, partial failure, item partially failed, all failed, space still arriving (capped settle) |
| `SettingsView` | General, Android selected, Android first, Protected paths, Access, Support, About |
| `AccessSettingsPane` | Empty, Not asked, Allowed, Not allowed, Mixed, Request in flight, Request failed (models from `AccessListModel.preview`, data from `PreviewFixtures.accessAreas*`) |
| `BlockedAccessRow` | Not asked and not allowed |
| `GeneralSettingsPane` | Default, Errors (launch, reminder and protected-path `SettingsErrorRow`s at once), Protected paths, Login approval pending, Deletion running, Platform selection refused |
| `SupportSettingsPane` | loading, ready, Cruftless selection, ambiguous, unavailable, invalid selection, cleanup running, report preview, report copied, stale report, preparing report, truncated report, report failure |
| `UninstallSection` | direct download, Homebrew |
| `UninstallSheet` | review, review with nothing on disk, preparing, refused, finished, finished with failures |
| `AboutSettingsPane` | About Settings, and the update section: update available, up to date, checking, check error, development build (no release version), command copied, direct download, direct download with update available |
| `MainView` | Popover (empty), Populated list, Detail pushed |
