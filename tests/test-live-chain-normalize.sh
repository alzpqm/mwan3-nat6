#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
NORMALIZE="$PROJECT_ROOT/scripts/normalize-nft-chain.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mwan3-nat6-normalize-test.XXXXXX")"

cleanup() {
	rm -rf "$TEST_ROOT"
}

fail() {
	printf '%s\n' "test-live-chain-normalize: FAIL: $*" >&2
	exit 1
}

trap cleanup EXIT HUP INT TERM

cat >"$TEST_ROOT/before" <<'EOF'
		counter packets 0 bytes 0 comment "mwan3-nat6-refusal-test" # handle 123
EOF
cat >"$TEST_ROOT/after-counter" <<'EOF'
		counter packets 14 bytes 1412 comment "mwan3-nat6-refusal-test" # handle 123
EOF
cat >"$TEST_ROOT/after-expression" <<'EOF'
		counter packets 14 bytes 1412 comment "different-rule" # handle 123
EOF
cat >"$TEST_ROOT/after-handle" <<'EOF'
		counter packets 14 bytes 1412 comment "mwan3-nat6-refusal-test" # handle 124
EOF

cmp -s "$TEST_ROOT/before" "$TEST_ROOT/after-counter" &&
	fail 'raw dumps unexpectedly match despite changing counters'

"$NORMALIZE" "$TEST_ROOT/before" >"$TEST_ROOT/before.normalized"
"$NORMALIZE" "$TEST_ROOT/after-counter" >"$TEST_ROOT/after-counter.normalized"
"$NORMALIZE" "$TEST_ROOT/after-expression" >"$TEST_ROOT/after-expression.normalized"
"$NORMALIZE" "$TEST_ROOT/after-handle" >"$TEST_ROOT/after-handle.normalized"

cmp -s "$TEST_ROOT/before.normalized" "$TEST_ROOT/after-counter.normalized" ||
	fail 'dynamic packet/byte values were not normalized'
cmp -s "$TEST_ROOT/before.normalized" "$TEST_ROOT/after-expression.normalized" &&
	fail 'normalization concealed an expression/comment change'
cmp -s "$TEST_ROOT/before.normalized" "$TEST_ROOT/after-handle.normalized" &&
	fail 'normalization concealed a rule replacement/handle change'

if "$NORMALIZE" >"$TEST_ROOT/noarg.stdout" 2>"$TEST_ROOT/noarg.stderr"; then
	fail 'missing input unexpectedly succeeded'
fi
grep -Fq 'usage:' "$TEST_ROOT/noarg.stderr" ||
	fail 'missing-input error did not explain usage'

printf '%s\n' 'test-live-chain-normalize: PASS'
