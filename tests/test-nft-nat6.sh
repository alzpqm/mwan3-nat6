#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/nft-nat6.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mwan3-nat6-test.XXXXXX")"
CASE_RC=0
CASE_DIR=''

cleanup() {
	rm -rf "$TEST_ROOT"
}

fail() {
	printf '%s\n' "test-nft-nat6: FAIL: $*" >&2
	exit 1
}

assert_rc() {
	expected="$1"
	[ "$CASE_RC" -eq "$expected" ] ||
		fail "expected rc=$expected, got rc=$CASE_RC; stderr=$(cat "$CASE_DIR/stderr")"
}

assert_contains() {
	needle="$1"
	file="$2"
	grep -Fq "$needle" "$file" || fail "$file does not contain: $needle"
}

assert_no_nft_calls() {
	[ ! -s "$CASE_DIR/state/nft.calls" ] ||
		fail 'nft was called before configuration and interface validation completed'
}

assert_rule_shape() {
	wan_count="$1"
	expected=$((wan_count * wan_count))
	cross=$((wan_count * (wan_count - 1)))
	[ "$(grep -c '^add rule ' "$CASE_DIR/state/apply.batch")" -eq "$expected" ] ||
		fail "$wan_count WANs did not generate $expected rules"
	[ "$(grep -c 'snat ip6 to' "$CASE_DIR/state/apply.batch")" -eq "$cross" ] ||
		fail "$wan_count WANs did not generate $cross cross-SNAT rules"
	[ "$(grep -c 'ip6 saddr 2000::/3.*snat ip6 prefix to' "$CASE_DIR/state/apply.batch")" -eq "$wan_count" ] ||
		fail "$wan_count WANs did not generate $wan_count safe prefix rules"
	[ "$(grep -c 'snat ip6 prefix to' "$CASE_DIR/state/apply.batch")" -eq "$wan_count" ] ||
		fail 'a prefix rule exists outside the global-unicast scope'
}

new_case() {
	name="$1"
	CASE_DIR="$TEST_ROOT/$name"
	mkdir -p "$CASE_DIR/bin" "$CASE_DIR/state" "$CASE_DIR/tmp" "$CASE_DIR/sys/class/net"

	cat >"$CASE_DIR/bin/uci" <<'EOF'
#!/bin/sh
[ "$1" = '-q' ] || exit 1
action="$2"
key="${3:-}"
count="${MOCK_WAN_COUNT:-3}"
case "$action" in
show)
	[ "$key" = 'mwan3-nat6' ] || exit 1
	printf '%s\n' 'mwan3-nat6.globals=globals'
	i=1
	while [ "$i" -le "$count" ]; do
		printf 'mwan3-nat6.wan%s=wan\n' "$i"
		i=$((i + 1))
	done
	;;
get)
	case "$key" in
	mwan3-nat6.globals.table)
		[ "${MOCK_BAD_TABLE:-0}" != '1' ] && printf '%s\n' 'mwan3_nat6' || printf '%s\n' 'bad-table'
		;;
	mwan3-nat6.wan*.*)
		rest="${key#mwan3-nat6.wan}"
		index="${rest%%.*}"
		option="${rest#*.}"
		case "$option" in
		enabled)
			if [ "${MOCK_DISABLE_LAST:-0}" = '1' ] && [ "$index" -eq "$count" ]; then
				printf '%s\n' '0'
			else
				printf '%s\n' '1'
			fi
			;;
		label) printf 'WAN %s\n' "$index" ;;
		interface)
			if [ "${MOCK_DUP_LOGICAL:-0}" = '1' ] && [ "$index" -eq 2 ]; then
				printf '%s\n' 'wan1_6'
			else
				printf 'wan%s_6\n' "$index"
			fi
			;;
		device)
			[ "${MOCK_OPTIONAL_FIELDS:-0}" != '1' ] || exit 1
			printf 'test-uplink-%s\n' "$index"
			;;
		expected_prefix_length)
			[ "${MOCK_OPTIONAL_FIELDS:-0}" != '1' ] || exit 1
			if [ "${MOCK_BAD_EXPECTED_MASK:-0}" = '1' ] && [ "$index" -eq 2 ]; then
				printf '%s\n' '61'
			else
				case "$index" in
				1) printf '%s\n' '56' ;;
				2 | 3) printf '%s\n' '60' ;;
				*) printf '%s\n' '64' ;;
				esac
			fi
			;;
		address_index)
			[ "${MOCK_BAD_INDEX:-0}" != '1' ] && printf '%s\n' '0' || printf '%s\n' '16'
			;;
		prefix_index) printf '%s\n' '0' ;;
		*) exit 1 ;;
		esac
		;;
	*) exit 1 ;;
	esac
	;;
*) exit 1 ;;
esac
EOF

	cat >"$CASE_DIR/bin/ifstatus" <<'EOF'
#!/bin/sh
[ "${MOCK_UNAVAILABLE:-}" != "$1" ] || exit 1
case "$1" in
wan[0-9]*_6) printf '%s' "$1" ;;
*) exit 1 ;;
esac
EOF

	cat >"$CASE_DIR/bin/jsonfilter" <<'EOF'
#!/bin/sh
expression=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	-e) shift; expression="$1" ;;
	esac
	shift
done
logical=''
IFS= read -r logical || [ -n "$logical" ] || exit 1
index="${logical#wan}"
index="${index%_6}"
case "$index" in '' | *[!0-9]*) exit 1 ;; esac
device="test-uplink-$index"
[ "${MOCK_DUP_DEVICE:-0}" != '1' ] || [ "$index" -ne 2 ] || device='test-uplink-1'
address="2001:db8:$index:100::1"
prefix="2001:db8:$index:100::"
case "$index" in
1) mask='56' ;;
2 | 3) mask='60' ;;
*) mask='64' ;;
esac
up='true'
[ "${MOCK_DOWN:-}" != "$logical" ] || up='false'
[ "${MOCK_BAD_LIVE_DEVICE:-}" != "$logical" ] || device='pppoe-wrong'
[ "${MOCK_BAD_LIVE_MASK:-}" != "$logical" ] || mask='61'
[ "${MOCK_BAD_ADDRESS:-}" != "$logical" ] || address='not-an-ipv6-address'
[ "${MOCK_BAD_PREFIX:-}" != "$logical" ] || prefix='not-a-prefix'
case "$expression" in
'@.up') printf '%s\n' "$up" ;;
'@.l3_device') printf '%s\n' "$device" ;;
'@["ipv6-address"][0]["address"]') printf '%s\n' "$address" ;;
'@["ipv6-prefix"][0]["address"]') printf '%s\n' "$prefix" ;;
'@["ipv6-prefix"][0]["mask"]') printf '%s\n' "$mask" ;;
*) exit 1 ;;
esac
EOF

	cat >"$CASE_DIR/bin/nft" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MOCK_STATE/nft.calls"
if [ "$1" = 'list' ] && [ "$2" = 'table' ]; then
	[ "${MOCK_TABLE:-present}" = 'present' ]
	exit
fi
if [ "$1" = 'list' ] && [ "$2" = 'chain' ]; then
	[ "${MOCK_CHAIN:-present}" = 'present' ] || exit 1
	[ -s "$MOCK_STATE/live.rules" ] && cat "$MOCK_STATE/live.rules"
	exit 0
fi
if [ "$1" = 'add' ] && [ "$2" = 'table' ]; then
	[ "${MOCK_ADD_TABLE_FAIL:-0}" != '1' ]
	exit
fi
if [ "$1" = 'add' ] && [ "$2" = 'chain' ]; then
	[ "${MOCK_ADD_CHAIN_FAIL:-0}" != '1' ]
	exit
fi
if [ "$1" = '-c' ] && [ "$2" = '-f' ]; then
	cp "$3" "$MOCK_STATE/check.batch"
	[ "${MOCK_CHECK_FAIL:-0}" != '1' ]
	exit
fi
if [ "$1" = '-f' ]; then
	cp "$2" "$MOCK_STATE/apply.batch"
	[ "${MOCK_APPLY_FAIL:-0}" != '1' ] || exit 1
	cp "$2" "$MOCK_STATE/live.rules"
	exit 0
fi
exit 1
EOF

	cat >"$CASE_DIR/bin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MOCK_STATE/logger.calls"
[ "${MOCK_LOGGER_FAIL:-0}" != '1' ]
EOF

	chmod 0755 "$CASE_DIR/bin/uci" "$CASE_DIR/bin/ifstatus" \
		"$CASE_DIR/bin/jsonfilter" "$CASE_DIR/bin/nft" "$CASE_DIR/bin/logger"

	i=1
	while [ "$i" -le 40 ]; do
		device="$CASE_DIR/sys/class/net/test-uplink-$i/statistics"
		mkdir -p "$device"
		for counter in rx_bytes tx_bytes rx_errors tx_errors rx_dropped tx_dropped; do
			printf '%s\n' "$((i * 1000))" >"$device/$counter"
		done
		i=$((i + 1))
	done
}

run_apply() {
	set +e
	env NAT6_PATH="$CASE_DIR/bin:/usr/bin:/bin" \
		NAT6_SYS_CLASS_NET="$CASE_DIR/sys/class/net" \
		TMPDIR="$CASE_DIR/tmp" MOCK_STATE="$CASE_DIR/state" \
		"$@" "$SCRIPT" apply >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
	CASE_RC=$?
	set -e
}

run_status() {
	set +e
	env NAT6_PATH="$CASE_DIR/bin:/usr/bin:/bin" \
		NAT6_SYS_CLASS_NET="$CASE_DIR/sys/class/net" \
		TMPDIR="$CASE_DIR/tmp" MOCK_STATE="$CASE_DIR/state" \
		"$@" "$SCRIPT" status >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
	CASE_RC=$?
	set -e
}

trap cleanup EXIT HUP INT TERM

new_case two_wan
run_apply MOCK_WAN_COUNT=2
assert_rc 0
assert_rule_shape 2
run_status MOCK_WAN_COUNT=2
assert_rc 0
assert_contains '"wan_count":2' "$CASE_DIR/stdout"
assert_contains '"expected_rule_count":4' "$CASE_DIR/stdout"
assert_contains '"profile":"managed"' "$CASE_DIR/stdout"

new_case three_wan
run_apply MOCK_WAN_COUNT=3
assert_rc 0
assert_rule_shape 3

new_case unsafe_profile
run_apply MOCK_WAN_COUNT=2
assert_rc 0
sed 's/ip6 saddr 2000::\/3 //' "$CASE_DIR/state/live.rules" >"$CASE_DIR/state/unsafe.rules"
mv "$CASE_DIR/state/unsafe.rules" "$CASE_DIR/state/live.rules"
run_status MOCK_WAN_COUNT=2
assert_rc 0
assert_contains '"profile":"unsafe"' "$CASE_DIR/stdout"

new_case managed_stale_profile
run_apply MOCK_WAN_COUNT=2
assert_rc 0
run_status MOCK_WAN_COUNT=2 MOCK_DOWN=wan2_6
assert_rc 0
assert_contains '"ready":false' "$CASE_DIR/stdout"
assert_contains '"profile":"managed-stale"' "$CASE_DIR/stdout"

new_case unexpected_profile
run_apply MOCK_WAN_COUNT=2
assert_rc 0
sed '$d' "$CASE_DIR/state/live.rules" >"$CASE_DIR/state/unexpected.rules"
mv "$CASE_DIR/state/unexpected.rules" "$CASE_DIR/state/live.rules"
run_status MOCK_WAN_COUNT=2
assert_rc 0
assert_contains '"profile":"unexpected"' "$CASE_DIR/stdout"

new_case four_wan
run_apply MOCK_WAN_COUNT=4
assert_rc 0
assert_rule_shape 4
assert_contains 'oifname "test-uplink-4"' "$CASE_DIR/state/apply.batch"

new_case optional_checks
run_apply MOCK_WAN_COUNT=2 MOCK_OPTIONAL_FIELDS=1
assert_rc 0
assert_rule_shape 2

new_case disabled_wan
run_apply MOCK_WAN_COUNT=4 MOCK_DISABLE_LAST=1
assert_rc 0
assert_rule_shape 3

new_case too_few
run_apply MOCK_WAN_COUNT=1
assert_rc 1
assert_contains 'at least two WANs must be enabled' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case no_wans
run_status MOCK_WAN_COUNT=0
assert_rc 0
assert_contains '"error":"no-wans"' "$CASE_DIR/stdout"
assert_no_nft_calls

new_case wan_down
run_apply MOCK_WAN_COUNT=3 MOCK_DOWN=wan3_6
assert_rc 1
assert_contains 'wan3_6 is not ready: down' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case wan_unavailable
run_apply MOCK_WAN_COUNT=2 MOCK_UNAVAILABLE=wan1_6
assert_rc 1
assert_contains 'wan1_6 is not ready: unavailable' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case wrong_device
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_LIVE_DEVICE=wan2_6
assert_rc 1
assert_contains 'wan2_6 is not ready: unexpected-device' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case wrong_pd
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_LIVE_MASK=wan2_6
assert_rc 1
assert_contains 'wan2_6 is not ready: unexpected-prefix-length' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_address
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_ADDRESS=wan1_6
assert_rc 1
assert_contains 'invalid-address' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_prefix
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_PREFIX=wan2_6
assert_rc 1
assert_contains 'invalid-prefix' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case duplicate_logical
run_apply MOCK_WAN_COUNT=2 MOCK_DUP_LOGICAL=1
assert_rc 1
assert_contains 'configured more than once' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case duplicate_device
run_apply MOCK_WAN_COUNT=2 MOCK_DUP_DEVICE=1 MOCK_OPTIONAL_FIELDS=1
assert_rc 1
assert_contains 'used by more than one WAN' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_table
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_TABLE=1
assert_rc 1
assert_contains 'invalid nft table name' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_index
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_INDEX=1
assert_rc 1
assert_contains 'outside 0-15' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case too_many
run_apply MOCK_WAN_COUNT=33
assert_rc 1
assert_contains 'more than 32 WANs are enabled' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case seed
run_apply MOCK_WAN_COUNT=2 MOCK_TABLE=absent MOCK_CHAIN=absent
assert_rc 0
assert_contains 'add table inet mwan3_nat6' "$CASE_DIR/state/nft.calls"
assert_contains 'add chain inet mwan3_nat6 srcnat' "$CASE_DIR/state/nft.calls"

new_case nft_check_failure
printf '%s\n' 'known-good-rules' >"$CASE_DIR/state/live.rules"
run_apply MOCK_WAN_COUNT=2 MOCK_CHECK_FAIL=1
assert_rc 1
assert_contains 'generated nft rules failed validation' "$CASE_DIR/stderr"
[ "$(cat "$CASE_DIR/state/live.rules")" = 'known-good-rules' ] ||
	fail 'nft validation failure changed live rules'
[ ! -e "$CASE_DIR/state/apply.batch" ] || fail 'nft apply ran after validation failure'

new_case nft_apply_failure
printf '%s\n' 'known-good-rules' >"$CASE_DIR/state/live.rules"
run_apply MOCK_WAN_COUNT=2 MOCK_APPLY_FAIL=1
assert_rc 1
assert_contains 'could not replace nft rules' "$CASE_DIR/stderr"
[ "$(cat "$CASE_DIR/state/live.rules")" = 'known-good-rules' ] ||
	fail 'mocked atomic apply failure changed live rules'

new_case logger_failure
run_apply MOCK_WAN_COUNT=2 MOCK_LOGGER_FAIL=1
assert_rc 0
assert_rule_shape 2

new_case missing_uci
rm "$CASE_DIR/bin/uci"
run_apply MOCK_WAN_COUNT=2
assert_rc 1
assert_contains 'uci is not installed' "$CASE_DIR/stderr"
assert_no_nft_calls

printf '%s\n' 'test-nft-nat6: PASS (26 cases)'
