#!/usr/bin/env bash

set -euo pipefail

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/cruftless-signature-test.XXXXXX")"
trap 'rm -r "$test_root"' EXIT

# shellcheck source=scripts/release/common.sh
source "$RELEASE_ROOT/scripts/release/common.sh"

mkdir "$test_root/bin"
cat > "$test_root/bin/codesign" <<'EOF'
#!/usr/bin/env bash
# The authority line comes first, followed by enough output to fill a pipe.
case "$FAKE_CODESIGN_MODE" in
	developer-id) echo 'Authority=Developer ID Application: Example (TEAM123456)' ;;
	*) echo 'Authority=Apple Development: Example (TEAM123456)' ;;
esac
yes 'Padding=0123456789abcdef0123456789abcdef' | head -n 20000
EOF
chmod +x "$test_root/bin/codesign"
PATH="$test_root/bin:$PATH"

FAKE_CODESIGN_MODE=developer-id has_developer_id_signature /unused ||
	{ echo "expected a Developer ID signature to be detected" >&2; exit 1; }

if FAKE_CODESIGN_MODE=development has_developer_id_signature /unused; then
	echo "expected a non-Developer ID signature to be rejected" >&2
	exit 1
fi
