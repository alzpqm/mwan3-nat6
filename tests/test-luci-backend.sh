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
	printf '%s\n' '{"ok":true,"ready":true,"all_ready":true,"degraded":false,"policy_ready":true,"interfaces":[{"label":"WAN 1","logical":"wan1_6","device":"test-uplink-1","state":"ready","tracker":{"tracked":true,"state":"online","score":10}},{"label":"WAN 2","logical":"wan2_6","device":"test-uplink-2","state":"ready","tracker":{"tracked":false,"state":"untracked","score":0}}],"nat":{"table":"mwan3_nat6","present":true,"wan_count":2,"active_wan_count":2,"inactive_wan_count":0,"rule_count":4,"expected_rule_count":4,"profile":"managed"},"local_icmp":{"enabled":true,"present":true,"rule_count":2,"expected_rule_count":2,"mark":"0x3f00","profile":"managed"},"monitor":{"enabled":true,"interval":15,"debounce":2,"refresh_mwan3":false}}'
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
assert_contains '"active_wan_count":2' "$CASE_DIR/stdout"
assert_contains '"degraded":false' "$CASE_DIR/stdout"
assert_contains '"expected_rule_count":4' "$CASE_DIR/stdout"
assert_contains '"profile":"managed"' "$CASE_DIR/stdout"
assert_contains '"local_icmp":{"enabled":true' "$CASE_DIR/stdout"

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
grep -Fq "'monitor'" "$SETTINGS" || fail 'LuCI settings view lacks renewal monitor control'
grep -Fq "'refresh_mwan3_after_nat'" "$SETTINGS" ||
	fail 'LuCI settings view lacks the renamed default-off compatibility option'
grep -Fq "'pin_local_icmp'" "$SETTINGS" ||
	fail 'LuCI settings view lacks router-local ICMP pin control'
grep -Fq 'localIcmp.profile' "$VIEW" ||
	fail 'LuCI status view lacks router-local ICMP pin state'
grep -Fq "nat.profile !== 'unexpected'" "$VIEW" ||
	fail 'LuCI status view does not block Apply for unexpected NAT state'
grep -Fq "localIcmp.profile !== 'unexpected'" "$VIEW" ||
	fail 'LuCI status view does not block Apply for unexpected local state'
grep -Fq 'active_wan_count' "$VIEW" || fail 'LuCI status view lacks ready-subset state'
grep -Fq 'item.tracker' "$VIEW" || fail 'LuCI status view lacks mwan3 tracker state'
grep -Fq "'id': 'mwan3-nat6-dashboard'" "$VIEW" ||
	fail 'LuCI status view lacks the scoped dashboard root'
grep -Fq 'mwan3-nat6-metric-grid' "$VIEW" ||
	fail 'LuCI status view lacks the health metric grid'
grep -Fq 'mwan3-nat6-wan-grid' "$VIEW" ||
	fail 'LuCI status view lacks responsive WAN cards'
grep -Fq "'aria-live': 'polite'" "$VIEW" ||
	fail 'LuCI status summary lacks an accessible live region'
if grep -Eq '(^|})[[:space:]]*\.cbi-section[[:space:]]*\{' "$VIEW"; then
	fail 'LuCI dashboard style escapes its package scope'
fi
if command -v node >/dev/null 2>&1; then
	node --check "$VIEW" >/dev/null
	node --check "$SETTINGS" >/dev/null
fi

printf '%s\n' 'test-luci-backend: PASS (6 RPC cases)'
