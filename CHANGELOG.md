# Changelog

## [1.2.1]

### Changes

- Added Support tab in settings with diagnostics (#8) (646ab89)

## [1.2.0] - 2026-09-29

### Added

- Inventory Android SDK packages, virtual devices, and Gradle caches alongside
  Xcode data. Eligible Gradle cache entries can be cleared after review, with
  additional safeguards for higher-risk entries.
- Check for app updates from Settings.

### Improved

- Filter the inventory by development environment and see clearer explanations
  when cleanup actions are unavailable.

## [1.1.0] - 2026-09-28

### Improved

- Refresh one inventory category without rescanning everything.
- Follow progress during scans and deletions, with more accurate free-space
  results after simulator cleanup.
- Improved the menu bar list, review, and result screens.

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
