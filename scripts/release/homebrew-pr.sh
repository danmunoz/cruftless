#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/release/common.sh
source "$SCRIPT_DIR/common.sh"

readonly RELEASE_REPOSITORY="danmunoz/cruftless"
readonly TAP_REPOSITORY="danmunoz/homebrew-tap"

usage() {
  cat <<'EOF'
Usage:
  scripts/release/homebrew-pr.sh --version X.Y.Z --tap-dir PATH --confirm-homebrew-pr

The command verifies the published asset, updates the cask in a clean local tap
checkout, pushes a version branch, and opens a PR using local gh authentication.
EOF
}

version=""
tap_dir=""
confirm=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --tap-dir) tap_dir="${2:-}"; shift 2 ;;
    --confirm-homebrew-pr) confirm=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$version" ]] || die "--version is required"
[[ -n "$tap_dir" ]] || die "--tap-dir is required"
[[ "$confirm" == true ]] || die "opening the Homebrew PR requires --confirm-homebrew-pr"
validate_version "$version"
for tool in gh git shasum curl codesign xcrun spctl brew ruby; do require_command "$tool"; done
require_directory "$tap_dir"

commit="$(git -C "$RELEASE_ROOT" rev-parse HEAD)"
output_dir="$(release_output_dir "$version" "$commit")"
dmg="$(release_dmg_path "$output_dir" "$version")"
checksum_file="$(release_checksum_path "$output_dir" "$version")"
tag="$(release_tag "$version")"
require_marker "$output_dir" .release-published
require_file "$dmg"
require_file "$checksum_file"

is_draft="$(gh release view "$tag" --repo "$RELEASE_REPOSITORY" --json isDraft --jq .isDraft)"
[[ "$is_draft" == false ]] || die "GitHub release must be published before opening the Homebrew PR"
published_asset="$(gh release view "$tag" --repo "$RELEASE_REPOSITORY" --json assets --jq '.assets[] | select(.name == "Cruftless-'"${version}"'.dmg") | .browserDownloadUrl')"
[[ -n "$published_asset" ]] || die "published GitHub Release is missing Cruftless-$version.dmg"

download_dir="$RELEASE_ROOT/dist/releases/homebrew-check"
mkdir -p "$download_dir"
downloaded="$download_dir/Cruftless-$version.dmg"
[[ ! -e "$downloaded" ]] || die "verification download already exists: $downloaded"
curl --fail --location --silent --show-error --output "$downloaded" "$published_asset"
expected_checksum="$(awk '{print $1}' "$checksum_file")"
actual_checksum="$(shasum -a 256 "$downloaded" | awk '{print $1}')"
[[ "$expected_checksum" =~ ^[0-9a-fA-F]{64}$ && "$actual_checksum" == "$expected_checksum" ]] ||
  die "published DMG checksum does not match the locally verified release"
codesign --verify --strict --verbose=2 "$downloaded"
codesign -dvvv "$downloaded" 2>&1 | grep -Fq 'Authority=Developer ID Application:' ||
  die "published DMG lacks Developer ID Application signature"
xcrun stapler validate "$downloaded"
spctl --assess --type open --context context:primary-signature -vv "$downloaded"

[[ -z "$(git -C "$tap_dir" status --porcelain)" ]] || die "tap checkout must be clean"
[[ "$(git -C "$tap_dir" branch --show-current)" == "main" ]] || die "tap checkout must be on main"
git -C "$tap_dir" fetch --quiet origin main
tap_head="$(git -C "$tap_dir" rev-parse HEAD)"
tap_remote_main="$(git -C "$tap_dir" rev-parse refs/remotes/origin/main)"
[[ "$tap_head" == "$tap_remote_main" ]] || die "tap main must exactly match origin/main"
tap_origin="$(git -C "$tap_dir" remote get-url origin)"
[[ "$tap_origin" == *"$TAP_REPOSITORY"* ]] || die "tap origin is not $TAP_REPOSITORY"

branch="cruftless-$version"
git -C "$tap_dir" show-ref --verify --quiet "refs/heads/$branch" && die "local tap branch already exists: $branch"
if git -C "$tap_dir" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  die "remote tap branch already exists: $branch"
fi

cask_path="$tap_dir/Casks/cruftless.rb"
require_file "$cask_path"
ruby - "$cask_path" "$version" "$expected_checksum" <<'RUBY'
path, version, checksum = ARGV
content = File.read(path)
abort("expected exactly one version stanza") unless content.scan(/^  version "[^"]+"$/).length == 1
abort("expected exactly one SHA-256 stanza") unless content.scan(/^  sha256 "[0-9a-fA-F]{64}"$/).length == 1
content = content.sub(/^  version "[^"]+"$/, %(  version "#{version}"))
content = content.sub(/^  sha256 "[0-9a-fA-F]{64}"$/, %(  sha256 "#{checksum}"))
File.write(path, content)
RUBY

git -C "$tap_dir" switch -c "$branch"
(
  cd "$tap_dir"
  brew style --cask Casks/cruftless.rb
  brew audit --new --cask Casks/cruftless.rb
)
git -C "$tap_dir" add Casks/cruftless.rb
git -C "$tap_dir" diff --cached --check
git -C "$tap_dir" commit -m "cask: update Cruftless to $version"
git -C "$tap_dir" push -u origin "$branch"
gh pr create --repo "$TAP_REPOSITORY" --head "$branch" --base main \
  --title "cask: update Cruftless to $version" \
  --body "Updates Cruftless to the published $tag release. The local release script verified the downloaded asset checksum, Developer ID signature, stapled ticket, and Gatekeeper assessment."

note "Homebrew PR opened from $branch."
