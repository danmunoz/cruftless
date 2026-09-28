#!/usr/bin/env bash

set -euo pipefail

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly RELEASE_ROOT
readonly PROJECT_PATH="$RELEASE_ROOT/Cruftless/Cruftless.xcodeproj"
readonly PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
readonly VERSION_CONFIG="$RELEASE_ROOT/Cruftless/Version.xcconfig"
readonly PRODUCT_NAME="Cruftless"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

require_file() {
  [[ -f "$1" ]] || die "required file is missing: $1"
}

require_directory() {
  [[ -d "$1" ]] || die "required directory is missing: $1"
}

validate_version() {
	[[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
		die "version must use release SemVer, for example 1.1.0"
}

release_tag() {
  printf 'v%s' "$1"
}

project_setting() {
  local key="$1"
  local values count
  values="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^;]+);/\1/p" "$PROJECT_FILE" | sort -u)"
  count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$count" == "1" ]] || die "expected one ${key} value in project.pbxproj, found ${count}"
  printf '%s\n' "$values"
}

project_version() {
	version_setting MARKETING_VERSION
}

project_build() {
	version_setting CURRENT_PROJECT_VERSION
}

version_setting() {
	local key="$1"
	local values count
	values="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^/[:space:]]+).*$/\1/p" "$VERSION_CONFIG" | sort -u)"
	count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l | tr -d ' ')"
	[[ "$count" == "1" ]] || die "expected one ${key} value in Version.xcconfig, found ${count}"
	printf '%s\n' "$values"
}

project_team() {
  project_setting DEVELOPMENT_TEAM
}

ensure_release_checkout() {
  local branch head remote_main
  branch="$(git -C "$RELEASE_ROOT" branch --show-current)"
  [[ "$branch" == "main" ]] || die "releases must run from the local main branch"
  [[ -z "$(git -C "$RELEASE_ROOT" status --porcelain)" ]] || die "working tree must be clean before a release"
  git -C "$RELEASE_ROOT" fetch --quiet origin main
  head="$(git -C "$RELEASE_ROOT" rev-parse HEAD)"
  remote_main="$(git -C "$RELEASE_ROOT" rev-parse refs/remotes/origin/main)"
  [[ "$head" == "$remote_main" ]] || die "local main must exactly match origin/main before a release"
}

ensure_unreleased_tag() {
  local tag="$1"
  if git -C "$RELEASE_ROOT" rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
    die "tag already exists locally: ${tag}"
  fi
  if git -C "$RELEASE_ROOT" ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
    die "tag already exists on origin: ${tag}"
  fi
}

ensure_changelog_entry() {
  local version="$1"
  require_file "$RELEASE_ROOT/CHANGELOG.md"
  grep -Eq "^##[[:space:]]+\\[${version//./\\.}\\]([[:space:]]|$)" "$RELEASE_ROOT/CHANGELOG.md" ||
    die "CHANGELOG.md needs a ## [${version}] release entry"
}

release_output_dir() {
  printf '%s/dist/releases/%s-%s\n' "$RELEASE_ROOT" "$1" "${2:0:12}"
}

release_app_path() {
  printf '%s/export/%s.app\n' "$1" "$PRODUCT_NAME"
}

release_dmg_path() {
  printf '%s/%s-%s.dmg\n' "$1" "$PRODUCT_NAME" "$2"
}

release_checksum_path() {
  printf '%s/%s-%s.dmg.sha256\n' "$1" "$PRODUCT_NAME" "$2"
}

metadata_path() {
  printf '%s/release-metadata.env\n' "$1"
}

metadata_value() {
  local file="$1" key="$2" value
  require_file "$file"
  value="$(sed -nE "s/^${key}=([^[:space:]]+)$/\1/p" "$file")"
  [[ -n "$value" ]] || die "release metadata is missing ${key}"
  printf '%s\n' "$value"
}

require_marker() {
  require_file "$1/$2"
}

find_developer_id_identity() {
  local requested="${1:-}" identities count
  identities="$(security find-identity -v -p codesigning 2>/dev/null |
    sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p')"
  if [[ -n "$requested" ]]; then
    [[ "$requested" == Developer\ ID\ Application:* ]] || die "identity must be a Developer ID Application identity"
    printf '%s\n' "$identities" | grep -Fqx "$requested" || die "Developer ID identity is unavailable in Keychain"
    printf '%s\n' "$requested"
    return
  fi
  count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$count" == "1" ]] || die "found ${count} Developer ID Application identities; pass --identity with the exact identity name"
  printf '%s\n' "$identities"
}

verify_universal_app() {
  local app="$1" executable archs
  require_directory "$app"
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
  archs="$(lipo -archs "$app/Contents/MacOS/$executable")"
  [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || die "app must contain arm64 and x86_64 (found: ${archs})"
}

verify_signed_app() {
  local app="$1" expected_version="$2" expected_build="$3" details version build
  require_directory "$app"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
  [[ "$version" == "$expected_version" ]] || die "exported app version ${version} does not match ${expected_version}"
  [[ "$build" == "$expected_build" ]] || die "exported app build ${build} does not match ${expected_build}"
  verify_universal_app "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  details="$(codesign -dvvv "$app" 2>&1)"
  grep -Fq 'Authority=Developer ID Application:' <<<"$details" || die "app lacks Developer ID Application signature"
  grep -Fq 'Runtime Version=' <<<"$details" || die "app lacks hardened runtime"
}

verify_notarized_app() {
  xcrun stapler validate "$1"
  spctl --assess --type execute --context context:primary-signature -vv "$1"
}

verify_signed_dmg() {
  local dmg="$1" details
  require_file "$dmg"
  codesign --verify --strict --verbose=2 "$dmg"
  details="$(codesign -dvvv "$dmg" 2>&1)"
  grep -Fq 'Authority=Developer ID Application:' <<<"$details" || die "DMG lacks Developer ID Application signature"
}

verify_notarized_dmg() {
  xcrun stapler validate "$1"
  spctl --assess --type open --context context:primary-signature -vv "$1"
}
