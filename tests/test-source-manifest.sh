#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$PROJECT_ROOT/scripts/source-manifest.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mwan3-nat6-manifest-test.XXXXXX")"

cleanup() {
	rm -rf "$TEST_ROOT"
}

fail() {
	printf '%s\n' "test-source-manifest: FAIL: $*" >&2
	exit 1
}

trap cleanup EXIT HUP INT TERM

"$MANIFEST" >"$TEST_ROOT/first"
"$MANIFEST" >"$TEST_ROOT/second"
cmp -s "$TEST_ROOT/first" "$TEST_ROOT/second" ||
	fail 'manifest is not deterministic'

cd "$PROJECT_ROOT"
expected_count="$({
	find .github openwrt scripts tests -type f -print
	printf '%s\n' .gitignore AGGREGATION_COMPARISON.md CHANGELOG.md LICENSE \
		Makefile NAT6_HANDOFF.md README.md VERSION
} | wc -l | tr -d ' ')"
actual_count="$(wc -l <"$TEST_ROOT/first" | tr -d ' ')"
[ "$actual_count" -eq "$expected_count" ] ||
	fail "manifest has $actual_count rows, expected $expected_count"

grep -Eq '^755 [0-9a-f]{64} scripts/source-manifest\.sh$' "$TEST_ROOT/first" ||
	fail 'manifest helper mode/hash/path row is missing'
grep -Eq '^[0-9]{3} [0-9a-f]{64} VERSION$' "$TEST_ROOT/first" ||
	fail 'VERSION row is missing'
if grep -Eq '(^| )(/|\.git/|dist/|handoff/|CONTEXT_HANDOFF\.md)' "$TEST_ROOT/first"; then
	fail 'manifest includes a private or excluded path'
fi

printf '%s\n' 'test-source-manifest: PASS'
