# Simulator storage discovery and cleanup

read_when: changing simulator discovery, runtime availability, storage totals, or simulator deletion.

## Xcode test simulators

Xcode's retained XCTest clones live in `~/Library/Developer/XCTestDevices`, a
different device set from `~/Library/Developer/CoreSimulator/Devices`. Cruftless
lists them separately as **Xcode test simulators** and includes a UUID suffix so
clones with identical names remain distinguishable.

**Delete Test Simulator** removes one selected, shut-down clone after Review.
The executor uses `simctl --set <XCTestDevices> delete <UUID>`. It never falls
back to the ordinary device set, erases these clones, or deletes their folders
directly. Batch removal and known-bloat path cleanup do not accept XCTest
devices.

Planning and execution validate the fixed device set, device and plist
fingerprints, current protection settings, runtime authority, and shutdown
state. Execution checks again after capacity sampling and confirms the device
directory is absent before reporting success. Unknown or booted devices remain
visible without deletion authority.

## Installed runtimes and availability

`simctl list runtimes -j` provides installed runtime presence and usability.
`simctl runtime list -j` provides the narrower runtime image management catalog
and its deletion identifiers. Absence from the image catalog does not establish
that a runtime was removed.

Device runtime status distinguishes available, installed but unavailable,
confirmed missing, and unknown. Failed lookups and ambiguous builds remain
unknown. Runtime command authority and device usability are independent: an
installed runtime that cannot be deleted can still support usable simulators.

Installed runtimes omitted by the image catalog remain visible. Their backing
assets are matched by version and build metadata, measured using allocated
bytes, and deduplicated by filesystem identity. Unknown measurements remain
unknown. Stored bytes and eligible cleanup bytes are separate; snapshots persist
them with schema version 4.

Runtime rows use build-aware identities. Deletion requires a management receipt
and a known positive footprint. Confirmation requires both the management UUID
and the exact installed identifier/build to disappear from successful catalog
lookups. Removing a runtime invalidates both simulator device sets.

## Scope

Android device cleanup is excluded from this change. Android Virtual Devices
retain their existing read-only behavior.

## Verification

- 492 Core tests across 79 suites pass.
- Strict SwiftLint and the macOS application build pass.
- Read-only local probing discovers all four retained XCTest clones and iOS
  18.6, 27.0, and 27.1; devices using 18.6 retain available runtime status.
- No existing simulator, runtime, or Android device is removed during verification.
