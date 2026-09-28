#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/release/common.sh
source "$SCRIPT_DIR/common.sh"

readonly SCHEME="Cruftless"
readonly RELEASE_REPOSITORY="danmunoz/cruftless"

usage() {
  cat <<'EOF'
Usage:
  scripts/release/release.sh [preflight] --version X.Y.Z
  scripts/release/release.sh archive --version X.Y.Z [--identity "Developer ID Application: ..."]
  scripts/release/release.sh notarize-app --version X.Y.Z --notary-profile NAME
  scripts/release/release.sh package-dmg --version X.Y.Z [--identity "Developer ID Application: ..."]
  scripts/release/release.sh notarize-dmg --version X.Y.Z --notary-profile NAME
  scripts/release/release.sh verify --version X.Y.Z
  scripts/release/release.sh draft-release --version X.Y.Z --notes-file PATH --confirm-draft
  scripts/release/release.sh publish-release --version X.Y.Z --confirm-publish

No action runs a read-only preflight. Files are written under dist/releases and
existing output is never overwritten. Apple credentials remain in Keychain.
EOF
}

action="preflight"
if [[ $# -gt 0 && "$1" != --* ]]; then action="$1"; shift; fi
version=""
identity=""
notary_profile=""
notes_file=""
confirm_draft=false
confirm_publish=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --identity) identity="${2:-}"; shift 2 ;;
    --notary-profile) notary_profile="${2:-}"; shift 2 ;;
    --notes-file) notes_file="${2:-}"; shift 2 ;;
    --confirm-draft) confirm_draft=true; shift ;;
    --confirm-publish) confirm_publish=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$version" ]] || die "--version is required"
validate_version "$version"
for tool in git xcodebuild xcrun security codesign spctl lipo shasum gh make; do require_command "$tool"; done

commit="$(git -C "$RELEASE_ROOT" rev-parse HEAD)"
output_dir="$(release_output_dir "$version" "$commit")"
app="$(release_app_path "$output_dir")"
dmg="$(release_dmg_path "$output_dir" "$version")"
build="$(project_build)"
tag="$(release_tag "$version")"

validate_release_source() {
  local actual_version
  ensure_release_checkout
  if grep -Eq '^[[:space:]]*(MARKETING_VERSION|CURRENT_PROJECT_VERSION)[[:space:]]*=' "$PROJECT_FILE"; then
    die "MARKETING_VERSION and CURRENT_PROJECT_VERSION must come only from Version.xcconfig"
  fi
  actual_version="$(project_version)"
  [[ "$actual_version" == "$version" ]] || die "MARKETING_VERSION is ${actual_version}, expected ${version}"
  [[ "$build" =~ ^[0-9]+$ && "$build" -gt 0 ]] || die "CURRENT_PROJECT_VERSION must be a positive integer"
  ensure_changelog_entry "$version"
}

preflight() {
  validate_release_source
  ensure_unreleased_tag "$tag"
  note "Preflight passed for $tag at $commit (build $build)."
}

archive() {
  local resolved_identity team export_options
  preflight
  [[ ! -e "$output_dir" ]] || die "release output already exists: $output_dir"
  resolved_identity="$(find_developer_id_identity "$identity")"
  team="$(project_team)"
  release_checks
  mkdir -p "$RELEASE_ROOT/dist/releases"
  mkdir "$output_dir"
  cat > "$(metadata_path "$output_dir")" <<EOF
VERSION=$version
BUILD=$build
COMMIT=$commit
TAG=$tag
EOF
  export_options="$output_dir/ExportOptions.plist"
  cat > "$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>destination</key><string>export</string>
  <key>method</key><string>developer-id</string>
  <key>signingCertificate</key><string>$resolved_identity</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$team</string>
</dict></plist>
EOF
  xcodebuild archive -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$output_dir/$PRODUCT_NAME.xcarchive" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$resolved_identity" DEVELOPMENT_TEAM="$team"
  xcodebuild -exportArchive -archivePath "$output_dir/$PRODUCT_NAME.xcarchive" \
    -exportPath "$output_dir/export" -exportOptionsPlist "$export_options"
  verify_signed_app "$app" "$version" "$build"
  : > "$output_dir/.app-signed"
  note "Signed universal app archived at $app"
}

release_checks() {
  make -C "$RELEASE_ROOT" lint test
  xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration Debug \
    -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
}

notarize_app() {
  local input="$output_dir/$PRODUCT_NAME-$version.app.zip" submission_json submission_id
  [[ -n "$notary_profile" ]] || die "notarize-app requires --notary-profile NAME"
  preflight
  require_marker "$output_dir" .app-signed
  verify_signed_app "$app" "$version" "$build"
  [[ ! -e "$input" ]] || die "notarization input already exists: $input"
  ditto -c -k --keepParent "$app" "$input"
  submission_json="$output_dir/notary-app-submit.json"
  xcrun notarytool submit "$input" --keychain-profile "$notary_profile" --wait --output-format json > "$submission_json"
  submission_id="$(plutil -extract id raw "$submission_json")"
  [[ -n "$submission_id" ]] || die "notarytool returned no app submission id"
  xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" > "$output_dir/notary-app-log.json"
  xcrun stapler staple "$app"
  verify_notarized_app "$app"
  printf '%s\n' "$submission_id" > "$output_dir/notary-app-submission-id.txt"
  : > "$output_dir/.app-notarized"
  note "App notarized and stapled."
}

package_dmg() {
  local resolved_identity stage
  preflight
  require_marker "$output_dir" .app-notarized
  verify_notarized_app "$app"
  [[ ! -e "$dmg" ]] || die "DMG already exists: $dmg"
  resolved_identity="$(find_developer_id_identity "$identity")"
  stage="$output_dir/dmg-staging"
  mkdir "$stage"
  ditto "$app" "$stage/$PRODUCT_NAME.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$stage" -format UDZO "$dmg"
  codesign --force --sign "$resolved_identity" --timestamp "$dmg"
  verify_signed_dmg "$dmg"
  : > "$output_dir/.dmg-signed"
  note "Signed DMG created at $dmg"
}

notarize_dmg() {
  local submission_json="$output_dir/notary-dmg-submit.json" submission_id checksum_file
  [[ -n "$notary_profile" ]] || die "notarize-dmg requires --notary-profile NAME"
  preflight
  require_marker "$output_dir" .app-notarized
  require_marker "$output_dir" .dmg-signed
  verify_notarized_app "$app"
  verify_signed_dmg "$dmg"
  [[ ! -e "$submission_json" ]] || die "notary submission record already exists; inspect it before retrying"
  xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait --output-format json > "$submission_json"
  submission_id="$(plutil -extract id raw "$submission_json")"
  [[ -n "$submission_id" ]] || die "notarytool returned no DMG submission id"
  xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" > "$output_dir/notary-dmg-log.json"
  xcrun stapler staple "$dmg"
  verify_notarized_dmg "$dmg"
  checksum_file="$(release_checksum_path "$output_dir" "$version")"
  shasum -a 256 "$dmg" > "$checksum_file"
  printf '%s\n' "$submission_id" > "$output_dir/notary-dmg-submission-id.txt"
  : > "$output_dir/.dmg-notarized"
  note "DMG notarized, stapled, and checksummed."
}

verify_release() {
  preflight
  require_marker "$output_dir" .app-notarized
  require_marker "$output_dir" .dmg-notarized
  verify_signed_app "$app" "$version" "$build"
  verify_notarized_app "$app"
  verify_signed_dmg "$dmg"
  verify_notarized_dmg "$dmg"
  shasum -a 256 -c "$(release_checksum_path "$output_dir" "$version")"
  cat > "$output_dir/local-verification.txt" <<EOF
tag=$tag
commit=$commit
app_notary_submission=$(<"$output_dir/notary-app-submission-id.txt")
dmg_notary_submission=$(<"$output_dir/notary-dmg-submission-id.txt")
EOF
  : > "$output_dir/.locally-verified"
  note "Local release verification passed."
}

draft_release() {
  [[ "$confirm_draft" == true ]] || die "draft-release requires --confirm-draft"
  require_file "$notes_file"
  preflight
  require_marker "$output_dir" .locally-verified
  gh release create "$tag" "$dmg" "$(release_checksum_path "$output_dir" "$version")" \
    --repo "$RELEASE_REPOSITORY" --target "$commit" --draft \
    --title "$PRODUCT_NAME $version" --notes-file "$notes_file"
  : > "$output_dir/.draft-created"
  note "Draft created; inspect its assets and notes before publication."
}

publish_release() {
  local is_draft
  [[ "$confirm_publish" == true ]] || die "publish-release requires --confirm-publish"
  validate_release_source
  require_marker "$output_dir" .draft-created
  is_draft="$(gh release view "$tag" --repo "$RELEASE_REPOSITORY" --json isDraft --jq .isDraft)"
  [[ "$is_draft" == true ]] || die "GitHub release is not a draft: $tag"
  gh release edit "$tag" --repo "$RELEASE_REPOSITORY" --draft=false
  : > "$output_dir/.release-published"
  note "Published $tag."
}

case "$action" in
  preflight) preflight ;;
  archive) archive ;;
  notarize-app) notarize_app ;;
  package-dmg) package_dmg ;;
  notarize-dmg) notarize_dmg ;;
  verify) verify_release ;;
  draft-release) draft_release ;;
  publish-release) publish_release ;;
  *) usage >&2; die "unknown action: $action" ;;
esac
