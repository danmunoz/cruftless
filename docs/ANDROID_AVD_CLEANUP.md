# Android device cleanup

read_when: changing Android device deletion, Android CLI setup, or its review and result flow.

Cruftless deletes one stopped, inactive Android Virtual Device at a time through
Google's modern Android CLI. Android SDK packages and Android Studio system data
remain inventory-only. AVD storage stays outside automatic cleanup totals and
batch operations because eligibility and tools are checked only on Delete intent.

## Flow

1. Select **Delete Device** on a recognized AVD row from a current scan.
2. Cruftless checks for prepared Android tools. If they are missing or unverified,
   a pushed screen offers **Install Tools** and **Cancel**. Approval covers the
   official CLI download and its first-run runtime setup. An existing unverified
   launcher also needs this one-time preparation consent because running it can
   bootstrap tooling. Cancel or failure prevents device deletion.
3. Cruftless checks that the selected emulator is inactive, using the emulator's
   native lock and a bounded process listing. Active or unknown state is refused.
4. Review shows the exact device, storage path, allocated size and permanent loss
   of apps, settings, local data and snapshots. Installation does not authorize
   deletion; the separate **Delete Device** confirmation is required.
5. Execution rechecks identity, paths, current policy and device activity, then
   calls only `android --no-metrics --sdk=… emulator remove <name>`, with an
   explicit `ANDROID_USER_HOME`. The registry must be its `avd` child; these CLI
   versions do not honor `ANDROID_AVD_HOME` for removal.
6. Cruftless verifies both the registration and data directory after the command.
   Exit code zero alone does not prove success. Partial deletion or interruption
   is reported, remaining bytes stay visible as unclassified read-only storage,
   and nothing is automatically retried or directly deleted.

The state check does not prevent an external process from starting the emulator
once deletion begins. The user must not start it during removal. This accepted
race does not require closing Android Studio, acquiring a lifetime lock,
quarantining files, or implementing transaction/recovery machinery.

Only ordinary local sibling `.ini` and `.avd` layouts are supported. Redirected or
shared storage, malformed metadata, custom writable image paths, protected paths,
symlinked metadata/roots, mounts and unreadable storage remain refused. Ordinary
SDK skin references are supported. Raw path and whole-location deletion routes
remain blocked for Android devices. No automatic shutdown, `--force`, legacy
`avdmanager` fallback, snapshot-specific cleanup or SDK installation is provided.

Tools install into the user's private Cruftless Application Support directory.
The app downloads Google's native executable directly without running an install
shell script or changing shell profiles. A small prepared-tool receipt binds the
executable fingerprint and Android user home; it is setup state, not deletion
authority or a recovery journal. Changed tools require setup again. Scanning and
navigation never execute or install Android tooling.

## Verification

Focused Core tests cover ordinary Pixel metadata, protection and registry binding,
explicit tool setup, missing/failed installation, active/unknown state, a device
starting while Review is open, zero-exit partial deletion and interruption.

The opt-in integration test downloads the official native CLI into a fresh
owned temporary home and uses the production installer, planner and executor.
It removes only disposable devices, checks immutable-child partial failure and
a bounded timeout, and preserves neighbor-device/shared-SDK sentinels:

```sh
CRUFTLESS_ANDROID_LIVE_TESTS=1 swift test --package-path CruftlessCore --filter AndroidAVDLiveRemovalTests
```

No installed user AVD or shared user SDK data is mutated by that test.

Verification on 2026-10-22: the full Core run passed (503 tests in 81 suites),
strict SwiftLint reported zero violations, and the macOS app build succeeded.
The final production-path official CLI integration passed independently in
9.802 seconds. Existing AVD registration/configuration fingerprints and all
294 files in the original mixed checkout were unchanged.
