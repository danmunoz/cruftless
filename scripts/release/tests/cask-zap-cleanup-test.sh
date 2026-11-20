#!/usr/bin/env bash

set -euo pipefail

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
script="$(cat "$RELEASE_ROOT/scripts/release/cask-zap-cleanup.sh")"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/cruftless-zap-test.XXXXXX")"
trap 'rm -r "$test_root"' EXIT

bundle_id="com.example.cruftless.zap-test.$$"
log="$test_root/ran"

# Builds a fake bundle whose executable records the arguments it ran with.
make_app() {
	local app="$test_root/$1.app"
	mkdir -p "$app/Contents/MacOS"
	cat > "$app/Contents/MacOS/Cruftless" <<EOF
#!/bin/sh
${2:-}
echo "\$*" >> "$log"
EOF
	chmod +x "$app/Contents/MacOS/Cruftless"
	echo "$app"
}

run_zap() {
	rm -f "$log"
	/bin/sh -c "$script" sh "$1" "$bundle_id" "${2:-15}"
}

expect_ran() {
	[[ "$(cat "$log" 2>/dev/null)" == "--uninstall-cleanup" ]] || { echo "expected cleanup to run: $1" >&2; exit 1; }
}

expect_skipped() {
	[[ ! -e "$log" ]] || { echo "expected cleanup to be skipped: $1" >&2; exit 1; }
}

app="$(make_app plain)"
run_zap "$app"
expect_ran "no quarantine attribute"

app="$(make_app approved)"
xattr -w com.apple.quarantine '01c1;6af743e1;;E8BF3AA8' "$app"
run_zap "$app"
expect_ran "user-approved quarantine"

app="$(make_app unapproved)"
xattr -w com.apple.quarantine '0083;6af743e1;Homebrew Cask;E8BF3AA8' "$app"
run_zap "$app"
expect_skipped "never-opened quarantine"

app="$(make_app malformed)"
xattr -w com.apple.quarantine 'zz;1' "$app"
run_zap "$app"
expect_skipped "malformed quarantine"

run_zap "$test_root/Missing.app"
expect_skipped "missing app"

app="$(make_app "With Space")"
run_zap "$app"
expect_ran "path with a space"

app="$(make_app hangs 'sleep 30')"
started=$SECONDS
run_zap "$app" 2
(( SECONDS - started < 10 )) || { echo "expected the watchdog to end a hung cleanup" >&2; exit 1; }
expect_skipped "hung cleanup killed before it recorded"

echo "cask zap cleanup tests passed"
