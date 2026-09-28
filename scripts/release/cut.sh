#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/release/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
	printf 'Usage: %s X.Y.Z\n' "${0##*/}" >&2
}

[[ $# == 1 ]] || { usage; exit 2; }
version="$1"
validate_version "$version"
require_command git
require_command ruby
require_file "$VERSION_CONFIG"
require_file "$RELEASE_ROOT/CHANGELOG.md"

branch="$(git -C "$RELEASE_ROOT" branch --show-current)"
[[ "$branch" == main ]] || die "run release cut from main"
[[ -z "$(git -C "$RELEASE_ROOT" status --porcelain)" ]] || die "working tree must be clean before cutting a release"

current_version="$(project_version)"
current_build="$(project_build)"
[[ "$current_build" =~ ^[0-9]+$ ]] || die "CURRENT_PROJECT_VERSION must be a positive integer"
current_build_number=$((10#$current_build))
(( current_build_number > 0 && current_build_number < 2147483647 )) ||
	die "CURRENT_PROJECT_VERSION must be between 1 and 2147483646"
next_build="$((current_build_number + 1))"

version_is_newer() {
	ruby -rrubygems -e 'exit(Gem::Version.new(ARGV[0]) > Gem::Version.new(ARGV[1]) ? 0 : 1)' "$1" "$2"
}

if ! version_is_newer "$version" "$current_version"; then
	die "$version must be newer than the current app version $current_version"
fi

latest_tag="$(git -C "$RELEASE_ROOT" tag --list 'v*' --sort=-version:refname |
	awk '/^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$/ { print; exit }')"

if [[ -n "$latest_tag" ]]; then
	latest_version="${latest_tag#v}"
	if ! version_is_newer "$version" "$latest_version"; then
		die "$version must be newer than the latest release tag $latest_tag"
	fi
	changelog_base="$latest_tag"
else
	changelog_base="$(git -C "$RELEASE_ROOT" rev-list --max-parents=0 HEAD | tail -n1)"
fi

tag="$(release_tag "$version")"
if git -C "$RELEASE_ROOT" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
	die "release tag already exists: $tag"
fi
if git -C "$RELEASE_ROOT" show-ref --verify --quiet "refs/heads/release/$version"; then
	die "release branch already exists locally: release/$version"
fi
if grep -qE "^##[[:space:]]+\\[$version\\]([[:space:]]|$)" "$RELEASE_ROOT/CHANGELOG.md"; then
	die "CHANGELOG.md already contains a release entry for $version"
fi

commits="$(git -C "$RELEASE_ROOT" log --no-merges --format='%h%x09%s' "$changelog_base..HEAD")"
[[ -n "$commits" ]] || die "no commits since $changelog_base; there is nothing to prepare for release"

entry_file="$(mktemp "${TMPDIR:-/tmp}/cruftless-release-entry.XXXXXX")"
config_file="$(mktemp "$VERSION_CONFIG.XXXXXX")"
changelog_file="$(mktemp "$RELEASE_ROOT/CHANGELOG.md.XXXXXX")"
trap 'rm -f "$entry_file" "$config_file" "$changelog_file"' EXIT

{
	printf '## [%s]\n\n### Changes\n\n' "$version"
	while IFS=$'\t' read -r hash subject; do
		case "$subject" in
			docs:*|docs\(*\):*|chore:*|chore\(*\):*|build:*|build\(*\):*|ci:*|ci\(*\):*|test:*|test\(*\):*|style:*|style\(*\):*) continue ;;
		esac
		subject="$(printf '%s' "$subject" | sed -E 's/^(feat|fix|perf|refactor)(\([^)]*\))?!?:[[:space:]]*//')"
		printf -- '- %s (%s)\n' "$subject" "$hash"
	done <<< "$commits"
} > "$entry_file"

if ! grep -qE '^-[[:space:]]' "$entry_file"; then
	die "commits since $changelog_base contain no release-facing changes"
fi

awk -v version="$version" -v build="$next_build" '
BEGIN { marketing = 0; project = 0 }
/^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ {
	marketing++
	sub(/=.*/, "= " version)
}
/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
	project++
	sub(/=.*/, "= " build)
}
{ print }
END { if (marketing != 1 || project != 1) exit 1 }
' "$VERSION_CONFIG" > "$config_file" || die "Version.xcconfig must contain exactly one marketing version and build number"

if ! awk -v entry_file="$entry_file" '
BEGIN {
	while ((getline line < entry_file) > 0) entry = entry line "\n"
	close(entry_file)
	inserted = 0
}
!inserted && /^# Changelog$/ { print; print ""; printf "%s", entry; inserted = 1; next }
{ print }
END { if (!inserted) exit 1 }
' "$RELEASE_ROOT/CHANGELOG.md" > "$changelog_file"; then
	die "CHANGELOG.md must contain a # Changelog heading"
fi

git -C "$RELEASE_ROOT" switch -c "release/$version"
chmod 644 "$config_file" "$changelog_file"
mv "$config_file" "$VERSION_CONFIG"
mv "$changelog_file" "$RELEASE_ROOT/CHANGELOG.md"
git -C "$RELEASE_ROOT" add -- Cruftless/Version.xcconfig CHANGELOG.md
git -C "$RELEASE_ROOT" diff --cached --check
git -C "$RELEASE_ROOT" commit -m "build(release): cut $version"

note "Prepared release/$version with build $next_build from $changelog_base. Review the generated changelog before merging."
