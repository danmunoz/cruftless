# Changelog

## [1.2.0]

### Changes

- Android development support (#6) (815a140)
- read Homebrew download URL from gh assets (#5) (4969a22)

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
