# Changelog

## [1.1.0]

### Changes

- Fixed homebrew call (4d0000c)
- Added (partial) CI automation (28457a1)
- Improved UI (8b59c94)
- Updated refresh symbol (d5bf841)

All notable changes to Cruftless are recorded here. Versions use
[Semantic Versioning](https://semver.org/).

## [1.0] - Initial release

### Added

- Native macOS menu bar app for finding and removing Xcode and CoreSimulator
  disk bloat.
- Drill-down inventory for projects, simulators, runtimes, toolchains, caches,
  archives, logs, and related developer data.
- APFS allocated-size reporting, hardlink deduplication, and separate purgeable
  space reporting.
- Review-before-delete flow with protected paths, symlink and identity checks,
  and `simctl`-mediated simulator mutations.
- Local-only operation with no account, cloud service, analytics, or telemetry.
- macOS 26+ distribution through the `danmunoz/tap` Homebrew cask.
- Developer ID signing and Apple notarization for the distributed release.

[1.0]: https://github.com/danmunoz/cruftless/releases/tag/v1.0
