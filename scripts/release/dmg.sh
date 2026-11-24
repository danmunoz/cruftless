#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/release/common.sh
source "$SCRIPT_DIR/common.sh"

# Window geometry in points; must match scripts/release/dmg/render-background.swift.
readonly ASSET_DIR="$SCRIPT_DIR/dmg"
readonly WINDOW_LEFT=200
readonly WINDOW_TOP=120
readonly WINDOW_WIDTH=660
readonly WINDOW_HEIGHT=420
readonly TITLE_BAR_HEIGHT=32
readonly ICON_SIZE=128
readonly ICON_CENTER_Y=278
readonly APP_CENTER_X=190
readonly APPLICATIONS_CENTER_X=470

usage() {
  cat <<'EOF'
Usage:
  scripts/release/dmg.sh --app PATH --output PATH.dmg

Builds an unsigned, compressed installer DMG with a background, a fixed icon
layout, and the app icon as the volume icon. Finder lays out the window, so
the first run asks to let the terminal control Finder.
EOF
}

app=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) app="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$app" && -n "$output" ]] || { usage >&2; exit 64; }
require_directory "$app"
[[ "$output" == *.dmg ]] || die "--output must end in .dmg"
[[ ! -e "$output" ]] || die "DMG already exists: $output"
require_file "$ASSET_DIR/background.png"
require_file "$ASSET_DIR/background@2x.png"
for tool in hdiutil osascript tiffutil ditto xcrun; do require_command "$tool"; done

readonly mount_point="/Volumes/$PRODUCT_NAME"
[[ ! -e "$mount_point" ]] || die "eject the volume at $mount_point before building the DMG"

work="$(mktemp -d "${TMPDIR:-/tmp}/cruftless-dmg.XXXXXX")"
device=""
cleanup() {
  if [[ -n "$device" ]]; then hdiutil detach "$device" -force -quiet || true; fi
  rm -r "$work"
}
trap cleanup EXIT

stage="$work/stage"
mkdir -p "$stage/.background"
ditto "$app" "$stage/$PRODUCT_NAME.app"
ln -s /Applications "$stage/Applications"
tiffutil -cathidpicheck "$ASSET_DIR/background.png" "$ASSET_DIR/background@2x.png" \
  -out "$stage/.background/background.tiff" >/dev/null 2>&1

writable="$work/writable.dmg"
hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$stage" -fs HFS+ -format UDRW "$writable" >/dev/null

attach_output="$(hdiutil attach "$writable" -readwrite -noverify -noautoopen)"
device="$(awk 'NR == 1 { print $1 }' <<<"$attach_output")"
[[ "$attach_output" == *"$mount_point"* && -d "$mount_point" ]] ||
  die "writable image did not mount at $mount_point"

osascript - "$PRODUCT_NAME" "$PRODUCT_NAME.app" \
  "$WINDOW_LEFT" "$WINDOW_TOP" "$((WINDOW_LEFT + WINDOW_WIDTH))" "$((WINDOW_TOP + WINDOW_HEIGHT + TITLE_BAR_HEIGHT))" \
  "$ICON_SIZE" "$APP_CENTER_X" "$APPLICATIONS_CENTER_X" "$ICON_CENTER_Y" <<'APPLESCRIPT'
on run argv
  set volumeName to item 1 of argv
  set appName to item 2 of argv
  set windowBounds to {(item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer, (item 6 of argv) as integer}
  set iconSize to (item 7 of argv) as integer
  set appX to (item 8 of argv) as integer
  set applicationsX to (item 9 of argv) as integer
  set iconY to (item 10 of argv) as integer
  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to windowBounds
      set viewOptions to icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to iconSize
      set text size of viewOptions to 13
      set shows item info of viewOptions to false
      set shows icon preview of viewOptions to false
      set background picture of viewOptions to file ".background:background.tiff"
      set position of item appName of container window to {appX, iconY}
      set position of item "Applications" of container window to {applicationsX, iconY}
      close
      open
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT

for _ in {1..20}; do
  [[ -f "$mount_point/.DS_Store" ]] && break
  sleep 0.5
done
[[ -f "$mount_point/.DS_Store" ]] || die "Finder did not write the window layout"

# Finder removes a volume icon present during layout, so it goes on afterwards.
volume_icon="$app/Contents/Resources/AppIcon.icns"
if [[ -f "$volume_icon" ]]; then
  cp "$volume_icon" "$mount_point/.VolumeIcon.icns"
  xcrun SetFile -a C "$mount_point"
fi
if [[ -d "$mount_point/.fseventsd" ]]; then rm -r "$mount_point/.fseventsd"; fi
sync
hdiutil detach "$device" -quiet
device=""

hdiutil convert "$writable" -format UDZO -imagekey zlib-level=9 -o "$output" >/dev/null
note "Installer DMG created at $output"
