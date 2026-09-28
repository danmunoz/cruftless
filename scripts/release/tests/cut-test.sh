#!/usr/bin/env bash

set -euo pipefail

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/cruftless-cut-test.XXXXXX")"
trap 'rm -r "$test_root"' EXIT

fixture="$test_root/repo"
mkdir -p "$fixture/scripts/release" "$fixture/Cruftless"
cp "$RELEASE_ROOT/scripts/release/common.sh" "$fixture/scripts/release/common.sh"
cp "$RELEASE_ROOT/scripts/release/cut.sh" "$fixture/scripts/release/cut.sh"
cat > "$fixture/Cruftless/Version.xcconfig" <<'EOF'
MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
EOF
cat > "$fixture/CHANGELOG.md" <<'EOF'
# Changelog

## [1.0] - Initial release

- Initial release.
EOF

git -C "$fixture" init --initial-branch=main --quiet
git -C "$fixture" config user.name "Release Test"
git -C "$fixture" config user.email "release-test@example.invalid"
git -C "$fixture" add .
git -C "$fixture" commit --quiet -m "docs: initialize release fixture"
git -C "$fixture" tag v1.0
git -C "$fixture" commit --allow-empty --quiet -m "feat: add a release feature"
git -C "$fixture" commit --allow-empty --quiet -m "fix: correct a release edge case"

"$fixture/scripts/release/cut.sh" 1.1.0

[[ "$(git -C "$fixture" branch --show-current)" == release/1.1.0 ]]
grep -Fqx 'MARKETING_VERSION = 1.1.0' "$fixture/Cruftless/Version.xcconfig"
grep -Fqx 'CURRENT_PROJECT_VERSION = 2' "$fixture/Cruftless/Version.xcconfig"
grep -Fq '## [1.1.0]' "$fixture/CHANGELOG.md"
grep -Fq 'add a release feature' "$fixture/CHANGELOG.md"
grep -Fq 'correct a release edge case' "$fixture/CHANGELOG.md"

changed_files="$(git -C "$fixture" show --format= --name-only HEAD | sort)"
expected_files="$(printf '%s\n' CHANGELOG.md Cruftless/Version.xcconfig | sort)"
[[ "$changed_files" == "$expected_files" ]]

git -C "$fixture" switch --quiet main
if invalid_output="$("$fixture/scripts/release/cut.sh" 1.1 2>&1)"; then
	printf 'expected malformed release version to fail\n' >&2
	exit 1
fi
[[ "$invalid_output" == *"version must use release SemVer"* ]]
[[ "$(git -C "$fixture" branch --show-current)" == main ]]

if stale_output="$("$fixture/scripts/release/cut.sh" 1.0.0 2>&1)"; then
	printf 'expected a non-increasing release version to fail\n' >&2
	exit 1
fi
[[ "$stale_output" == *"must be newer than the current app version"* ]]
[[ "$(git -C "$fixture" branch --show-current)" == main ]]

printf 'Release cut helper tests passed.\n'
