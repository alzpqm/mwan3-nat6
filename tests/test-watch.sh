#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
WATCHER="$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/sbin/mwan3-nat6-watch"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mwan3-nat6-watch-test.XXXXXX")"
CASE_DIR=''
CASE_RC=0

cleanup() {
	rm -rf "$TEST_ROOT"
}

fail() {
	printf '%s\n' "test-watch: FAIL: $*" >&2
	exit 1
}

new_case() {
	CASE_DIR="$TEST_ROOT/$1"
	MOCK_MONITOR=1
	MOCK_CYCLES=2
	MOCK_DEBOUNCE=2
	MOCK_REFRESH=0
	MOCK_FINGERPRINT_FAIL=0
	MOCK_APPLY_FAIL=0
	MOCK_MWAN3_FAIL=0
	MOCK_MWAN3_OUTPUT=''
	MOCK_LOCAL_PROFILE=disabled
	mkdir -p "$CASE_DIR/bin" "$CASE_DIR/state"
	printf '%s\n' managed >"$CASE_DIR/state/profile"
	cat >"$CASE_DIR/state/fingerprint" <<'EOF'
table|mwan3_nat6|2
wan|wan1_6|pppoe-wan1|2001:db8:1::1|2001:db8:101::/56
wan|wan2_6|pppoe-wan-c|2001:db8:2::1|2001:db8:202::/56
EOF

	cat >"$CASE_DIR/bin/uci" <<'EOF'
#!/bin/sh
[ "$1" = '-q' ] && [ "$2" = get ] || exit 1
case "$3" in
mwan3-nat6.globals.monitor) printf '%s\n' "${MOCK_MONITOR:-1}" ;;
mwan3-nat6.globals.interval) printf '%s\n' "${MOCK_INTERVAL:-5}" ;;
mwan3-nat6.globals.debounce) printf '%s\n' "${MOCK_DEBOUNCE:-2}" ;;
mwan3-nat6.globals.refresh_mwan3_after_nat) printf '%s\n' "${MOCK_REFRESH:-0}" ;;
mwan3.wan1_6 | mwan3.wan2_6) printf '%s\n' interface ;;
*) exit 1 ;;
esac
EOF
	cat >"$CASE_DIR/bin/nft-nat6.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"$MOCK_STATE/core.calls"
case "$1" in
fingerprint)
	[ "${MOCK_FINGERPRINT_FAIL:-0}" != 1 ] || exit 1
	cat "$MOCK_STATE/fingerprint"
	;;
status)
	printf '{"ok":true,"ready":true,"nat":{"profile":"%s"},"local_icmp":{"profile":"%s"}}\n' \
		"$(cat "$MOCK_STATE/profile")" "${MOCK_LOCAL_PROFILE:-disabled}"
	;;
apply)
	printf '%s\n' apply >>"$MOCK_STATE/apply.calls"
	[ "${MOCK_APPLY_FAIL:-0}" != 1 ] || exit 1
	printf '%s\n' managed >"$MOCK_STATE/profile"
	;;
*) exit 1 ;;
esac
EOF
	cat >"$CASE_DIR/bin/jsonfilter" <<'EOF'
#!/bin/sh
expression=''
while [ "$#" -gt 0 ]; do
	case "$1" in -e) shift; expression="$1" ;; esac
	shift
done
cat >/dev/null
case "$expression" in
@.ready) printf '%s\n' true ;;
@.nat.profile) cat "$MOCK_STATE/profile" ;;
@.local_icmp.profile) printf '%s\n' "${MOCK_LOCAL_PROFILE:-disabled}" ;;
*) exit 1 ;;
esac
EOF
cat >"$CASE_DIR/bin/mwan3" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >>"$MOCK_STATE/mwan3.calls"
[ -z "${MOCK_MWAN3_OUTPUT:-}" ] || printf '%s\n' "$MOCK_MWAN3_OUTPUT"
[ "${MOCK_MWAN3_FAIL:-0}" != 1 ]
EOF
	cat >"$CASE_DIR/bin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MOCK_STATE/logger.calls"
EOF
	cat >"$CASE_DIR/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod 0755 "$CASE_DIR/bin/uci" "$CASE_DIR/bin/nft-nat6.sh" \
		"$CASE_DIR/bin/jsonfilter" "$CASE_DIR/bin/mwan3" \
		"$CASE_DIR/bin/logger" "$CASE_DIR/bin/sleep"
}

run_watcher() {
	set +e
	env NAT6_PATH="$CASE_DIR/bin:/usr/bin:/bin" \
		NAT6_SCRIPT="$CASE_DIR/bin/nft-nat6.sh" \
		NAT6_RUNTIME_DIR="$CASE_DIR/state" MOCK_STATE="$CASE_DIR/state" \
		NAT6_WATCH_MAX_CYCLES="${MOCK_CYCLES:-2}" \
		MOCK_MONITOR="${MOCK_MONITOR:-1}" MOCK_DEBOUNCE="${MOCK_DEBOUNCE:-2}" \
		MOCK_REFRESH="${MOCK_REFRESH:-0}" MOCK_FINGERPRINT_FAIL="${MOCK_FINGERPRINT_FAIL:-0}" \
		MOCK_APPLY_FAIL="${MOCK_APPLY_FAIL:-0}" \
		MOCK_MWAN3_FAIL="${MOCK_MWAN3_FAIL:-0}" \
		MOCK_MWAN3_OUTPUT="${MOCK_MWAN3_OUTPUT:-}" \
		MOCK_LOCAL_PROFILE="${MOCK_LOCAL_PROFILE:-disabled}" \
		"$WATCHER" >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
	CASE_RC=$?
	set -e
}

trap cleanup EXIT HUP INT TERM

new_case disabled
MOCK_MONITOR=0 MOCK_CYCLES=1 run_watcher
[ "$CASE_RC" -eq 0 ] || fail "disabled monitor returned $CASE_RC"
[ ! -e "$CASE_DIR/state/core.calls" ] || fail 'disabled monitor called the core'

new_case current
MOCK_CYCLES=1 run_watcher
[ "$CASE_RC" -eq 0 ] || fail "current monitor returned $CASE_RC"
[ ! -e "$CASE_DIR/state/apply.calls" ] || fail 'managed profile was reapplied'
cmp -s "$CASE_DIR/state/fingerprint" "$CASE_DIR/state/mwan3-nat6.applied" ||
	fail 'managed fingerprint was not adopted'
[ "$(LC_ALL=C ls -l "$CASE_DIR/state/mwan3-nat6.applied" | cut -c1-10)" = '-rw-------' ] ||
	fail 'applied fingerprint is not mode 0600'

new_case stale
printf '%s\n' managed-stale >"$CASE_DIR/state/profile"
run_watcher
[ "$CASE_RC" -eq 0 ] || fail "stale renewal returned $CASE_RC"
[ "$(wc -l <"$CASE_DIR/state/apply.calls")" -eq 1 ] ||
	fail 'stable stale profile was not applied exactly once'
[ ! -e "$CASE_DIR/state/mwan3.calls" ] ||
	fail 'default-off stale renewal refreshed mwan3'

new_case unexpected
printf '%s\n' unexpected >"$CASE_DIR/state/profile"
run_watcher
[ "$CASE_RC" -eq 0 ] || fail "unexpected-profile monitor returned $CASE_RC"
[ ! -e "$CASE_DIR/state/apply.calls" ] || fail 'unexpected profile was overwritten automatically'
grep -Fq 'refusing automatic replacement' "$CASE_DIR/state/logger.calls" ||
	fail 'unexpected-profile refusal was not logged'

new_case local_missing
MOCK_LOCAL_PROFILE=missing run_watcher
[ "$CASE_RC" -eq 0 ] || fail "missing local-profile renewal returned $CASE_RC"
[ "$(wc -l <"$CASE_DIR/state/apply.calls")" -eq 1 ] ||
	fail 'stable missing local ICMP chain was not applied exactly once'

new_case local_stale
printf '%s\n' managed-stale >"$CASE_DIR/state/profile"
MOCK_LOCAL_PROFILE=managed-stale run_watcher
[ "$CASE_RC" -eq 0 ] || fail "stale local-profile renewal returned $CASE_RC"
[ "$(wc -l <"$CASE_DIR/state/apply.calls")" -eq 1 ] ||
	fail 'stable stale local ICMP subset was not applied exactly once'

new_case local_unexpected
MOCK_LOCAL_PROFILE=unexpected run_watcher
[ "$CASE_RC" -eq 0 ] || fail "unexpected local-profile monitor returned $CASE_RC"
[ ! -e "$CASE_DIR/state/apply.calls" ] || fail 'unexpected local ICMP chain was overwritten automatically'
grep -Fq 'refusing automatic replacement of local ICMP profile' "$CASE_DIR/state/logger.calls" ||
	fail 'unexpected local-profile refusal was not logged'

new_case periodic_refusal_log
MOCK_LOCAL_PROFILE=unexpected MOCK_CYCLES=61 run_watcher
[ "$CASE_RC" -eq 0 ] || fail "periodic refusal monitor returned $CASE_RC"
[ "$(grep -c 'refusing automatic replacement of local ICMP profile' "$CASE_DIR/state/logger.calls")" -eq 2 ] ||
	fail 'stuck local-profile refusal was not logged initially and periodically'

new_case no_tracker_refresh
printf '%s\n' inactive >"$CASE_DIR/state/profile"
MOCK_REFRESH=0 run_watcher
[ "$CASE_RC" -eq 0 ] || fail "refresh-disabled renewal returned $CASE_RC"
[ "$(wc -l <"$CASE_DIR/state/apply.calls")" -eq 1 ] ||
	fail 'refresh-disabled case did not renew NAT'
[ ! -e "$CASE_DIR/state/mwan3.calls" ] || fail 'refresh-disabled case invoked mwan3'

new_case one_changed_tracker
printf '%s\n' managed-stale >"$CASE_DIR/state/profile"
cat >"$CASE_DIR/state/mwan3-nat6.applied" <<'EOF'
table|mwan3_nat6|2
wan|wan1_6|pppoe-wan1|2001:db8:1::9|2001:db8:109::/56
wan|wan2_6|pppoe-wan-c|2001:db8:2::1|2001:db8:202::/56
EOF
MOCK_REFRESH=1 run_watcher
[ "$CASE_RC" -eq 0 ] || fail "one-change renewal returned $CASE_RC"
[ "$(wc -l <"$CASE_DIR/state/mwan3.calls")" -eq 1 ] ||
	fail 'one changed WAN did not cause exactly one tracker refresh'
grep -Fq 'ifup wan1_6' "$CASE_DIR/state/mwan3.calls" ||
	fail 'the changed tracker was not refreshed'

new_case unavailable
MOCK_FINGERPRINT_FAIL=1 run_watcher
[ "$CASE_RC" -eq 0 ] || fail "unavailable monitor returned $CASE_RC"
[ ! -e "$CASE_DIR/state/apply.calls" ] || fail 'unavailable WAN data triggered apply'
[ ! -e "$CASE_DIR/state/mwan3.calls" ] || fail 'unavailable WAN data refreshed mwan3'

new_case ifup_warning
printf '%s\n' managed-stale >"$CASE_DIR/state/profile"
MOCK_REFRESH=1 MOCK_MWAN3_OUTPUT='RTNETLINK answers: File exists' run_watcher
[ "$CASE_RC" -eq 0 ] || fail "successful ifup warning case returned $CASE_RC"
[ "$(wc -l <"$CASE_DIR/state/mwan3.calls")" -eq 2 ] ||
	fail 'ifup warning case did not refresh both initially changed interfaces'
grep -Fq 'refresh output: RTNETLINK answers: File exists' "$CASE_DIR/state/logger.calls" ||
	fail 'successful ifup warning output was not retained in the log'

sh -n "$WATCHER"
printf '%s\n' 'test-watch: PASS (12 cases)'
