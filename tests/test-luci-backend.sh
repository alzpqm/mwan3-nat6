#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
BACKEND="$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/root/usr/libexec/rpcd/luci.mwan3-nat6"
VIEW="$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/status.js"
SETTINGS="$PROJECT_ROOT/openwrt/luci-app-mwan3-nat6/htdocs/luci-static/resources/view/mwan3-nat6/settings.js"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mwan3-nat6-luci-test.XXXXXX")"
CASE_DIR="$TEST_ROOT/case"
CASE_RC=0

cleanup() {
	rm -rf "$TEST_ROOT"
}

fail() {
	printf '%s\n' "test-luci-backend: FAIL: $*" >&2
	exit 1
}

assert_contains() {
	needle="$1"
	file="$2"
	grep -Fq "$needle" "$file" || fail "$file does not contain: $needle"
}

run_backend() {
	set +e
	env NAT6_PATH="$CASE_DIR/bin:/usr/bin:/bin" \
		NAT6_SCRIPT="$CASE_DIR/bin/nft-nat6.sh" \
		MOCK_STATE="$CASE_DIR/state" \
		MOCK_STATUS_FAIL="${MOCK_STATUS_FAIL:-0}" \
		MOCK_APPLY_FAIL="${MOCK_APPLY_FAIL:-0}" \
		"$BACKEND" "$@" >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
	CASE_RC=$?
	unset MOCK_STATUS_FAIL MOCK_APPLY_FAIL
	set -e
}

mkdir -p "$CASE_DIR/bin" "$CASE_DIR/state"
cat >"$CASE_DIR/bin/nft-nat6.sh" <<'EOF'
#!/bin/sh
case "$1" in
status)
	[ "${MOCK_STATUS_FAIL:-0}" != '1' ] || exit 1
	printf '%s\n' '{"ok":true,"ready":true,"interfaces":[{"label":"WAN 1","logical":"wan1_6","device":"test-uplink-1","state":"ready"},{"label":"WAN 2","logical":"wan2_6","device":"test-uplink-2","state":"ready"}],"nat":{"table":"mwan3_nat6","present":true,"wan_count":2,"rule_count":4,"expected_rule_count":4,"profile":"managed"}}'
	;;
apply)
	printf '%s\n' apply >>"$MOCK_STATE/apply.calls"
	[ "${MOCK_APPLY_FAIL:-0}" != '1' ]
	;;
*) exit 1 ;;
esac
EOF
chmod 0755 "$CASE_DIR/bin/nft-nat6.sh"

trap cleanup EXIT HUP INT TERM

run_backend list
[ "$CASE_RC" -eq 0 ] || fail "list returned $CASE_RC"
assert_contains '"status":{}' "$CASE_DIR/stdout"
assert_contains '"apply":{}' "$CASE_DIR/stdout"

run_backend call status
[ "$CASE_RC" -eq 0 ] || fail "status returned $CASE_RC"
assert_contains '"wan_count":2' "$CASE_DIR/stdout"
assert_contains '"expected_rule_count":4' "$CASE_DIR/stdout"
assert_contains '"profile":"managed"' "$CASE_DIR/stdout"

MOCK_STATUS_FAIL=1 run_backend call status
[ "$CASE_RC" -eq 0 ] || fail "failed status transport returned $CASE_RC"
assert_contains '"error":"status-failed-check-logread"' "$CASE_DIR/stdout"

run_backend call apply
[ "$CASE_RC" -eq 0 ] || fail "successful apply RPC returned $CASE_RC"
assert_contains '"ok":true' "$CASE_DIR/stdout"
[ "$(wc -l <"$CASE_DIR/state/apply.calls")" -eq 1 ] ||
	fail 'successful apply did not invoke the canonical script exactly once'

MOCK_APPLY_FAIL=1 run_backend call apply
[ "$CASE_RC" -eq 0 ] || fail "failed apply RPC transport returned $CASE_RC"
assert_contains '"ok":false' "$CASE_DIR/stdout"
assert_contains '"error":"apply-failed-check-logread"' "$CASE_DIR/stdout"

mv "$CASE_DIR/bin/nft-nat6.sh" "$CASE_DIR/bin/nft-nat6.sh.missing"
run_backend call status
[ "$CASE_RC" -eq 0 ] || fail "missing-script status returned $CASE_RC"
assert_contains '"error":"nft-nat6-script-missing"' "$CASE_DIR/stdout"

sh -n "$BACKEND"
grep -Fq "object: 'luci.mwan3-nat6'" "$VIEW" ||
	fail 'LuCI view does not call the dedicated RPC object'
grep -Fq "method: 'status'" "$VIEW" || fail 'LuCI view lacks status RPC'
grep -Fq "method: 'apply'" "$VIEW" || fail 'LuCI view lacks apply RPC'
grep -Fq "new form.Map('mwan3-nat6'" "$SETTINGS" ||
	fail 'LuCI settings view does not manage the package-scoped UCI config'
grep -Fq "form.GridSection, 'wan'" "$SETTINGS" ||
	fail 'LuCI settings view lacks dynamic WAN sections'
if command -v node >/dev/null 2>&1; then
	node --check "$VIEW" >/dev/null
	node --check "$SETTINGS" >/dev/null
fi

printf '%s\n' 'test-luci-backend: PASS (6 RPC cases)'
