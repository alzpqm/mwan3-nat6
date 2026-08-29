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

assert_not_contains() {
	needle="$1"
	file="$2"
	if grep -Fq "$needle" "$file"; then
		fail "$file unexpectedly contains: $needle"
	fi
}

assert_no_nft_calls() {
	[ ! -s "$CASE_DIR/state/nft.calls" ] ||
		fail 'nft was called before configuration and interface validation completed'
}

assert_rule_shape() {
	wan_count="$1"
	expected=$((wan_count * wan_count))
	cross=$((wan_count * (wan_count - 1)))
	[ "$(grep -Ec '^add rule inet [^ ]+ srcnat ' "$CASE_DIR/state/apply.batch")" -eq "$expected" ] ||
		fail "$wan_count WANs did not generate $expected rules"
	[ "$(grep -c 'snat ip6 to' "$CASE_DIR/state/apply.batch")" -eq "$cross" ] ||
		fail "$wan_count WANs did not generate $cross cross-SNAT rules"
	[ "$(grep -c 'ip6 saddr 2000::/3.*snat ip6 prefix to' "$CASE_DIR/state/apply.batch")" -eq "$wan_count" ] ||
		fail "$wan_count WANs did not generate $wan_count safe prefix rules"
	[ "$(grep -c 'snat ip6 prefix to' "$CASE_DIR/state/apply.batch")" -eq "$wan_count" ] ||
		fail 'a prefix rule exists outside the global-unicast scope'
}

assert_local_pin_shape() {
	wan_count="$1"
	mark="${2:-0x3f00}"
	assert_contains 'add chain inet mwan3_nat6 local_icmp { type route hook output priority -140; policy accept; }' \
		"$CASE_DIR/state/apply.batch"
	[ "$(grep -Ec '^add rule inet [^ ]+ local_icmp ' "$CASE_DIR/state/apply.batch")" -eq "$wan_count" ] ||
		fail "$wan_count WANs did not generate $wan_count local ICMP pin rules"
	[ "$(grep -c "meta l4proto ipv6-icmp icmpv6 type echo-request meta mark set $mark" "$CASE_DIR/state/apply.batch")" -eq "$wan_count" ] ||
		fail "local ICMP pin rules do not use mark $mark"
	[ "$(grep -Ec '^add rule inet [^ ]+ local_icmp .*oifname' "$CASE_DIR/state/apply.batch" || true)" -eq 0 ] ||
		fail 'post-routing local ICMP pin incorrectly depends on a pre-reroute oifname'
	[ "$(grep -Ec '^1500: from all oif test-uplink-[0-9]+ lookup [0-9]+ proto 242$' "$CASE_DIR/state/policy.rules")" -eq "$wan_count" ] ||
		fail "$wan_count WANs did not generate $wan_count tagged initial-route RPDB rules"
	i=1
	while [ "$i" -le "$wan_count" ]; do
		assert_contains "1500: from all oif test-uplink-$i lookup $i proto 242" \
			"$CASE_DIR/state/policy.rules"
		i=$((i + 1))
	done
}

assert_no_policy_rules() {
	[ ! -s "$CASE_DIR/state/policy.rules" ] ||
		fail 'managed RPDB rules remain unexpectedly'
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
	case "$key" in
	mwan3-nat6)
		printf '%s\n' 'mwan3-nat6.globals=globals'
		i=1
		while [ "$i" -le "$count" ]; do
			printf 'mwan3-nat6.wan%s=wan\n' "$i"
			i=$((i + 1))
		done
		;;
	mwan3) printf '%s\n' 'mwan3.globals=globals' ;;
	*) exit 1 ;;
	esac
	;;
get)
	case "$key" in
	mwan3-nat6.globals.table)
		[ "${MOCK_BAD_TABLE:-0}" != '1' ] && printf '%s\n' 'mwan3_nat6' || printf '%s\n' 'bad-table'
		;;
	mwan3-nat6.globals.monitor) printf '%s\n' "${MOCK_MONITOR:-0}" ;;
	mwan3-nat6.globals.interval) printf '%s\n' "${MOCK_INTERVAL:-15}" ;;
	mwan3-nat6.globals.debounce) printf '%s\n' "${MOCK_DEBOUNCE:-2}" ;;
	mwan3-nat6.globals.refresh_mwan3_after_nat) printf '%s\n' "${MOCK_REFRESH_MWAN3:-0}" ;;
	mwan3-nat6.globals.pin_local_icmp) printf '%s\n' "${MOCK_PIN_LOCAL_ICMP:-0}" ;;
	mwan3.globals.mmx_mask) printf '%s\n' "${MOCK_MMX_MASK:-0x3f00}" ;;
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
			[ "${MOCK_LONG_DEVICE:-0}" != '1' ] && printf 'test-uplink-%s\n' "$index" || printf '%s\n' '1234567890123456'
			;;
		expected_prefix_length)
			[ "${MOCK_OPTIONAL_FIELDS:-0}" != '1' ] || exit 1
			if [ "${MOCK_BAD_EXPECTED_MASK:-0}" = '1' ] && [ "$index" -eq 2 ]; then
				printf '%s\n' '2'
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
[ "${MOCK_LOW_LIVE_MASK:-}" != "$logical" ] || mask='2'
[ "${MOCK_BAD_ADDRESS:-}" != "$logical" ] || address='not-an-ipv6-address'
[ "${MOCK_BAD_PREFIX:-}" != "$logical" ] || prefix='not-a-prefix'
[ "${MOCK_ULA_ADDRESS:-}" != "$logical" ] || address='fd00:1::1'
[ "${MOCK_ULA_PREFIX:-}" != "$logical" ] || prefix='fd00:1::'
[ "${MOCK_MALFORMED_ADDRESS:-}" != "$logical" ] || address='2001:::1'
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
if [ "$1" = '-a' ]; then
	shift
fi
if [ "$1" = 'list' ] && [ "$2" = 'table' ]; then
	[ "${MOCK_TABLE:-present}" = 'present' ]
	exit
fi
if [ "$1" = 'list' ] && [ "$2" = 'chain' ]; then
	chain="$5"
	case "$chain" in
	srcnat) [ "${MOCK_CHAIN:-present}" = 'present' ] || exit 1 ;;
	local_icmp)
		if [ -n "${MOCK_LOCAL_CHAIN:-}" ]; then
			[ "$MOCK_LOCAL_CHAIN" = 'present' ] || exit 1
		else
			grep -Eq '^add chain inet [^ ]+ local_icmp ' "$MOCK_STATE/live.rules" 2>/dev/null || exit 1
		fi
		;;
	*) exit 1 ;;
	esac
	[ -s "$MOCK_STATE/live.rules" ] && {
		printf '\tchain %s { # handle 900\n' "$chain"
		if [ "$chain" = local_icmp ]; then
			if [ "${MOCK_LOCAL_BAD_CHAIN:-0}" = 1 ]; then
				printf '\t\ttype filter hook output priority filter; policy accept;\n'
			else
				printf '\t\ttype route hook output priority mangle + 10; policy accept;\n'
			fi
		fi
		awk -v wanted="$chain" '
		$1 == "add" && $2 == "rule" && $5 == wanted {
			line = $0
			sub(/^add rule inet [^ ]+ [^ ]+ /, "", line)
			printf "\t%s # handle %d\n", line, ++handle
		}
		wanted == "srcnat" && /^LIVE / {
			line = $0
			sub(/^LIVE /, "", line)
			printf "\t%s # handle %d\n", line, ++handle
		}
		' "$MOCK_STATE/live.rules"
		printf '\t}\n'
	}
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

	cat >"$CASE_DIR/bin/ip" <<'EOF'
#!/bin/sh
[ "$1" = '-6' ] || exit 1
shift
case "$1:$2" in
rule:show)
	count="${MOCK_WAN_COUNT:-3}"
	i=1
	while [ "$i" -le "$count" ]; do
		printf '%s: from all fwmark 0x%x00/0x3f00 lookup %s\n' "$((2000 + i))" "$i" "$i"
		i=$((i + 1))
	done
	[ ! -s "$MOCK_STATE/policy.rules" ] || sed -n '1,200p' "$MOCK_STATE/policy.rules"
	;;
route:show)
	[ "$3" = table ] || exit 1
	table="$4"
	[ "$5" = default ] || exit 1
	printf 'default via fe80::1 dev test-uplink-%s proto static metric 512 pref medium\n' "$table"
	if [ "${MOCK_AMBIGUOUS_POLICY:-0}" = 1 ] && [ "$table" = 2 ]; then
		printf '%s\n' 'default via fe80::2 dev test-uplink-1 proto static metric 512 pref medium'
	fi
	;;
rule:add)
	shift 2
	priority=''; device=''; table=''; protocol=''
	while [ "$#" -gt 0 ]; do
		case "$1" in
		pref) shift; priority="$1" ;;
		oif) shift; device="$1" ;;
		lookup) shift; table="$1" ;;
		protocol) shift; protocol="$1" ;;
		esac
		shift
	done
	[ "${MOCK_IP_ADD_FAIL:-0}" != 1 ] || exit 1
	printf '%s: from all oif %s lookup %s proto %s\n' "$priority" "$device" "$table" "$protocol" >>"$MOCK_STATE/policy.rules"
	;;
rule:del)
	shift 2
	priority=''; device=''; table=''; protocol=''
	while [ "$#" -gt 0 ]; do
		case "$1" in
		pref) shift; priority="$1" ;;
		oif) shift; device="$1" ;;
		lookup) shift; table="$1" ;;
		protocol) shift; protocol="$1" ;;
		esac
		shift
	done
	[ "${MOCK_IP_DEL_FAIL:-0}" != 1 ] || exit 1
	awk -v wanted="$priority: from all oif $device lookup $table proto $protocol" '
		$0 == wanted && !removed { removed = 1; next }
		{ print }
		END { if (!removed) exit 1 }
	' "$MOCK_STATE/policy.rules" >"$MOCK_STATE/policy.rules.new" || {
		rm -f "$MOCK_STATE/policy.rules.new"
		exit 1
	}
	mv "$MOCK_STATE/policy.rules.new" "$MOCK_STATE/policy.rules"
	;;
route:flush)
	[ "$3" = cache ] || exit 1
	;;
*) exit 1 ;;
esac
EOF

	cat >"$CASE_DIR/bin/lock" <<'EOF'
#!/bin/sh
case "$1" in
-n)
	[ "${MOCK_LOCK_FAIL:-0}" != '1' ] || exit 1
	printf '%s\n' locked >"$MOCK_STATE/lock.state"
	;;
-u) rm -f "$MOCK_STATE/lock.state" ;;
*) exit 1 ;;
esac
EOF

	cat >"$CASE_DIR/bin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MOCK_STATE/logger.calls"
[ "${MOCK_LOGGER_FAIL:-0}" != '1' ]
EOF

	chmod 0755 "$CASE_DIR/bin/uci" "$CASE_DIR/bin/ifstatus" \
		"$CASE_DIR/bin/jsonfilter" "$CASE_DIR/bin/nft" "$CASE_DIR/bin/logger" \
		"$CASE_DIR/bin/lock" "$CASE_DIR/bin/ip"

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
		NAT6_MWAN3TRACK_DIR="$CASE_DIR/state/mwan3track" \
		NAT6_MWAN3_STATUS_DIR="$CASE_DIR/state/mwan3" \
		NAT6_RUNTIME_DIR="$CASE_DIR/state" \
		TMPDIR="$CASE_DIR/tmp" MOCK_STATE="$CASE_DIR/state" \
		"$@" "$SCRIPT" apply >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
	CASE_RC=$?
	set -e
}

run_status() {
	set +e
	env NAT6_PATH="$CASE_DIR/bin:/usr/bin:/bin" \
		NAT6_SYS_CLASS_NET="$CASE_DIR/sys/class/net" \
		NAT6_MWAN3TRACK_DIR="$CASE_DIR/state/mwan3track" \
		NAT6_MWAN3_STATUS_DIR="$CASE_DIR/state/mwan3" \
		NAT6_RUNTIME_DIR="$CASE_DIR/state" \
		TMPDIR="$CASE_DIR/tmp" MOCK_STATE="$CASE_DIR/state" \
		"$@" "$SCRIPT" status >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
	CASE_RC=$?
	set -e
}

run_cleanup_policy() {
	set +e
	env NAT6_PATH="$CASE_DIR/bin:/usr/bin:/bin" \
		NAT6_RUNTIME_DIR="$CASE_DIR/state" \
		TMPDIR="$CASE_DIR/tmp" MOCK_STATE="$CASE_DIR/state" \
		"$@" "$SCRIPT" cleanup-policy >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
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
assert_contains '"active_wan_count":2' "$CASE_DIR/stdout"
assert_contains '"inactive_wan_count":0' "$CASE_DIR/stdout"
assert_contains '"all_ready":true' "$CASE_DIR/stdout"
assert_contains '"degraded":false' "$CASE_DIR/stdout"
assert_contains '"expected_rule_count":4' "$CASE_DIR/stdout"
assert_contains '"profile":"managed"' "$CASE_DIR/stdout"
assert_contains '"local_icmp":{"enabled":false,"present":false,"rule_count":0,"expected_rule_count":0,"mark":"0x3f00","routing_rule_count":0,"expected_routing_rule_count":0,"routing_priority":1500,"profile":"disabled"}' "$CASE_DIR/stdout"

new_case local_icmp_pin
run_apply MOCK_WAN_COUNT=3 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
assert_rule_shape 3
assert_local_pin_shape 3
run_status MOCK_WAN_COUNT=3 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
assert_contains '"local_icmp":{"enabled":true,"present":true,"rule_count":3,"expected_rule_count":3,"mark":"0x3f00","routing_rule_count":3,"expected_routing_rule_count":3,"routing_priority":1500,"profile":"managed"}' "$CASE_DIR/stdout"

new_case local_icmp_policy_missing
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
: >"$CASE_DIR/state/policy.rules"
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
assert_contains '"routing_rule_count":0,"expected_routing_rule_count":2,"routing_priority":1500,"profile":"missing"' "$CASE_DIR/stdout"

new_case local_icmp_policy_wrong_table
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
sed 's/oif test-uplink-1 lookup 1/oif test-uplink-1 lookup 2/' \
	"$CASE_DIR/state/policy.rules" >"$CASE_DIR/state/policy.rules.wrong"
mv "$CASE_DIR/state/policy.rules.wrong" "$CASE_DIR/state/policy.rules"
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
assert_contains '"routing_rule_count":2,"expected_routing_rule_count":2,"routing_priority":1500,"profile":"unexpected"' "$CASE_DIR/stdout"

new_case local_icmp_policy_ambiguous
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1 MOCK_AMBIGUOUS_POLICY=1
assert_rc 1
assert_contains 'has 2 matching mwan3 IPv6 policy tables' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case local_icmp_policy_add_failure
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1 MOCK_IP_ADD_FAIL=1
assert_rc 1
assert_contains 'could not reconcile local device IPv6 policy rules' "$CASE_DIR/stderr"
assert_no_policy_rules
[ ! -e "$CASE_DIR/state/apply.batch" ] || fail 'nft apply ran after RPDB reconciliation failure'

new_case local_icmp_policy_conflict
printf '%s\n' '1500: from all oif test-uplink-1 lookup 99 proto 99' >"$CASE_DIR/state/policy.rules"
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 1
assert_contains 'could not reconcile local device IPv6 policy rules' "$CASE_DIR/stderr"
assert_contains '1500: from all oif test-uplink-1 lookup 99 proto 99' "$CASE_DIR/state/policy.rules"
[ ! -e "$CASE_DIR/state/apply.batch" ] || fail 'nft apply ran after RPDB priority/oif conflict'

new_case local_icmp_custom_mask
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1 MOCK_MMX_MASK=0x7f00
assert_rc 0
assert_rule_shape 2
assert_local_pin_shape 2 0x7f00

new_case local_icmp_runtime_mask
mkdir -p "$CASE_DIR/state/mwan3"
printf '%s\n' '0x5a00' >"$CASE_DIR/state/mwan3/mmx_mask"
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1 MOCK_MMX_MASK=0x7f00
assert_rc 0
assert_rule_shape 2
assert_local_pin_shape 2 0x5a00

new_case local_icmp_padded_mark_status
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
sed 's/meta mark set 0x3f00/meta mark set 0x00003f00/g' \
	"$CASE_DIR/state/live.rules" >"$CASE_DIR/state/padded.rules"
mv "$CASE_DIR/state/padded.rules" "$CASE_DIR/state/live.rules"
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
assert_contains '"local_icmp":{"enabled":true,"present":true,"rule_count":2,"expected_rule_count":2,"mark":"0x3f00","routing_rule_count":2,"expected_routing_rule_count":2,"routing_priority":1500,"profile":"managed"}' "$CASE_DIR/stdout"

new_case local_icmp_nft_normalized_status
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
sed 's/meta l4proto ipv6-icmp //g' \
	"$CASE_DIR/state/live.rules" >"$CASE_DIR/state/nft-normalized.rules"
mv "$CASE_DIR/state/nft-normalized.rules" "$CASE_DIR/state/live.rules"
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
assert_contains '"local_icmp":{"enabled":true,"present":true,"rule_count":2,"expected_rule_count":2,"mark":"0x3f00","routing_rule_count":2,"expected_routing_rule_count":2,"routing_priority":1500,"profile":"managed"}' "$CASE_DIR/stdout"

new_case local_icmp_wrong_chain_profile
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1 MOCK_LOCAL_BAD_CHAIN=1
assert_rc 0
assert_contains '"local_icmp":{"enabled":true,"present":true,"rule_count":2,"expected_rule_count":2,"mark":"0x3f00","routing_rule_count":2,"expected_routing_rule_count":2,"routing_priority":1500,"profile":"unexpected"}' "$CASE_DIR/stdout"

new_case local_icmp_unexpected_profile
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
sed 's/meta l4proto ipv6-icmp/meta l4proto tcp/' \
	"$CASE_DIR/state/live.rules" >"$CASE_DIR/state/unexpected-local.rules"
mv "$CASE_DIR/state/unexpected-local.rules" "$CASE_DIR/state/live.rules"
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
assert_contains '"local_icmp":{"enabled":true,"present":true,"rule_count":2,"expected_rule_count":2,"mark":"0x3f00","routing_rule_count":2,"expected_routing_rule_count":2,"routing_priority":1500,"profile":"unexpected"}' "$CASE_DIR/stdout"

new_case invalid_local_icmp_pin
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=maybe
assert_rc 1
assert_contains 'invalid pin_local_icmp value' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_mwan3_mask
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1 MOCK_MMX_MASK=0x0
assert_rc 1
assert_contains 'invalid or zero mmx_mask' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case local_icmp_ready_subset
run_apply MOCK_WAN_COUNT=3 MOCK_PIN_LOCAL_ICMP=1 MOCK_DOWN=wan3_6
assert_rc 0
assert_rule_shape 2
assert_local_pin_shape 2
run_status MOCK_WAN_COUNT=3 MOCK_PIN_LOCAL_ICMP=1 MOCK_DOWN=wan3_6
assert_rc 0
assert_contains '"local_icmp":{"enabled":true,"present":true,"rule_count":2,"expected_rule_count":2,"mark":"0x3f00","routing_rule_count":2,"expected_routing_rule_count":2,"routing_priority":1500,"profile":"managed"}' "$CASE_DIR/stdout"

new_case local_icmp_disable_cleanup
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=0
assert_rc 0
assert_contains '"local_icmp":{"enabled":false,"present":true,"rule_count":2,"expected_rule_count":0,"mark":"0x3f00","routing_rule_count":2,"expected_routing_rule_count":0,"routing_priority":1500,"profile":"managed-stale"}' "$CASE_DIR/stdout"
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=0
assert_rc 0
assert_contains 'delete chain inet mwan3_nat6 local_icmp' "$CASE_DIR/state/apply.batch"
assert_not_contains 'add chain inet mwan3_nat6 local_icmp' "$CASE_DIR/state/apply.batch"
run_status MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=0
assert_rc 0
assert_contains '"local_icmp":{"enabled":false,"present":false,"rule_count":0,"expected_rule_count":0,"mark":"0x3f00","routing_rule_count":0,"expected_routing_rule_count":0,"routing_priority":1500,"profile":"disabled"}' "$CASE_DIR/stdout"
assert_no_policy_rules

new_case package_policy_cleanup
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
cp "$CASE_DIR/state/live.rules" "$CASE_DIR/state/live.before-cleanup"
run_cleanup_policy
assert_rc 0
assert_no_policy_rules
cmp -s "$CASE_DIR/state/live.before-cleanup" "$CASE_DIR/state/live.rules" ||
	fail 'policy-only cleanup changed nft rules'

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
assert_contains '"ready":true' "$CASE_DIR/stdout"
assert_contains '"all_ready":false' "$CASE_DIR/stdout"
assert_contains '"degraded":true' "$CASE_DIR/stdout"
assert_contains '"active_wan_count":1' "$CASE_DIR/stdout"
assert_contains '"expected_rule_count":1' "$CASE_DIR/stdout"
assert_contains '"profile":"managed-stale"' "$CASE_DIR/stdout"

new_case swapped_tuple_profile
run_apply MOCK_WAN_COUNT=2
assert_rc 0
sed 's/oifname "test-uplink-1"/oifname "temporary-uplink"/g; s/oifname "test-uplink-2"/oifname "test-uplink-1"/g; s/oifname "temporary-uplink"/oifname "test-uplink-2"/g' \
	"$CASE_DIR/state/live.rules" >"$CASE_DIR/state/swapped.rules"
mv "$CASE_DIR/state/swapped.rules" "$CASE_DIR/state/live.rules"
run_status MOCK_WAN_COUNT=2
assert_rc 0
assert_contains '"profile":"managed-stale"' "$CASE_DIR/stdout"

new_case unexpected_profile
run_apply MOCK_WAN_COUNT=2
assert_rc 0
sed '$d' "$CASE_DIR/state/live.rules" >"$CASE_DIR/state/unexpected.rules"
mv "$CASE_DIR/state/unexpected.rules" "$CASE_DIR/state/live.rules"
run_status MOCK_WAN_COUNT=2
assert_rc 0
assert_contains '"profile":"unexpected"' "$CASE_DIR/stdout"

new_case extra_rule_profile
run_apply MOCK_WAN_COUNT=2
assert_rc 0
printf '%s\n' 'LIVE counter accept' >>"$CASE_DIR/state/live.rules"
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
assert_rc 0
assert_rule_shape 2
run_status MOCK_WAN_COUNT=3 MOCK_DOWN=wan3_6
assert_rc 0
assert_contains '"ready":true' "$CASE_DIR/stdout"
assert_contains '"all_ready":false' "$CASE_DIR/stdout"
assert_contains '"degraded":true' "$CASE_DIR/stdout"
assert_contains '"active_wan_count":2' "$CASE_DIR/stdout"
assert_contains '"inactive_wan_count":1' "$CASE_DIR/stdout"
assert_contains '"profile":"managed"' "$CASE_DIR/stdout"

new_case wan_unavailable
run_apply MOCK_WAN_COUNT=2 MOCK_UNAVAILABLE=wan1_6
assert_rc 0
assert_rule_shape 1
run_status MOCK_WAN_COUNT=2 MOCK_UNAVAILABLE=wan1_6
assert_rc 0
assert_contains '"ready":true' "$CASE_DIR/stdout"
assert_contains '"active_wan_count":1' "$CASE_DIR/stdout"
assert_contains '"expected_rule_count":1' "$CASE_DIR/stdout"
assert_contains '"profile":"managed"' "$CASE_DIR/stdout"

new_case no_ready_wans
run_apply MOCK_WAN_COUNT=2 MOCK_UNAVAILABLE=wan1_6 MOCK_DOWN=wan2_6
assert_rc 1
assert_contains 'wan1_6 is not ready: unavailable' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case wrong_device
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_LIVE_DEVICE=wan2_6
assert_rc 1
assert_contains 'wan2_6 failed a safety check: unexpected-device' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case wrong_pd
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_LIVE_MASK=wan2_6
assert_rc 1
assert_contains 'wan2_6 failed a safety check: unexpected-prefix-length' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_live_pd_scope
run_apply MOCK_WAN_COUNT=2 MOCK_LOW_LIVE_MASK=wan2_6 MOCK_OPTIONAL_FIELDS=1
assert_rc 1
assert_contains 'wan2_6 failed a safety check: invalid-prefix-length' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_expected_pd_scope
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_EXPECTED_MASK=1
assert_rc 1
assert_contains 'outside 3-64' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_address
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_ADDRESS=wan1_6
assert_rc 1
assert_contains 'wan1_6 failed a safety check: invalid-address' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case invalid_prefix
run_apply MOCK_WAN_COUNT=2 MOCK_BAD_PREFIX=wan2_6
assert_rc 1
assert_contains 'wan2_6 failed a safety check: invalid-prefix' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case ula_address
run_apply MOCK_WAN_COUNT=2 MOCK_ULA_ADDRESS=wan1_6
assert_rc 1
assert_contains 'wan1_6 failed a safety check: invalid-address' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case ula_prefix
run_apply MOCK_WAN_COUNT=2 MOCK_ULA_PREFIX=wan2_6
assert_rc 1
assert_contains 'wan2_6 failed a safety check: invalid-prefix' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case malformed_ipv6
run_apply MOCK_WAN_COUNT=2 MOCK_MALFORMED_ADDRESS=wan1_6
assert_rc 1
assert_contains 'wan1_6 failed a safety check: invalid-address' "$CASE_DIR/stderr"
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

new_case long_device
run_apply MOCK_WAN_COUNT=2 MOCK_LONG_DEVICE=1
assert_rc 1
assert_contains 'invalid device' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case too_many
run_apply MOCK_WAN_COUNT=33
assert_rc 1
assert_contains 'more than 32 WANs are enabled' "$CASE_DIR/stderr"
assert_no_nft_calls

new_case seed
run_apply MOCK_WAN_COUNT=2 MOCK_TABLE=absent MOCK_CHAIN=absent
assert_rc 0
assert_contains 'add table inet mwan3_nat6' "$CASE_DIR/state/check.batch"
assert_contains 'add chain inet mwan3_nat6 srcnat' "$CASE_DIR/state/check.batch"
[ "$(grep -c '^add table ' "$CASE_DIR/state/nft.calls")" -eq 0 ] ||
	fail 'table was created outside the validated atomic batch'

new_case absent_table_check_failure
printf '%s\n' 'known-good-rules' >"$CASE_DIR/state/live.rules"
run_apply MOCK_WAN_COUNT=2 MOCK_TABLE=absent MOCK_CHAIN=absent MOCK_CHECK_FAIL=1
assert_rc 1
assert_contains 'generated nft rules failed validation' "$CASE_DIR/stderr"
[ "$(cat "$CASE_DIR/state/live.rules")" = 'known-good-rules' ] ||
	fail 'absent-table validation failure changed live state'
[ "$(grep -c '^add table ' "$CASE_DIR/state/nft.calls")" -eq 0 ] ||
	fail 'absent table was seeded live before validation'

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

new_case nft_apply_failure_restores_policy
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1
assert_rc 0
cp "$CASE_DIR/state/policy.rules" "$CASE_DIR/state/policy.before"
run_apply MOCK_WAN_COUNT=2 MOCK_PIN_LOCAL_ICMP=1 MOCK_APPLY_FAIL=1
assert_rc 1
assert_contains 'could not replace nft rules' "$CASE_DIR/stderr"
cmp -s "$CASE_DIR/state/policy.before" "$CASE_DIR/state/policy.rules" ||
	fail 'nft apply failure did not restore the previous RPDB rules'

new_case logger_failure
run_apply MOCK_WAN_COUNT=2 MOCK_LOGGER_FAIL=1
assert_rc 0
assert_rule_shape 2

new_case apply_lock
run_apply MOCK_WAN_COUNT=2 MOCK_LOCK_FAIL=1
assert_rc 1
assert_contains 'another NAT6 apply is in progress' "$CASE_DIR/stderr"
[ ! -e "$CASE_DIR/state/check.batch" ] || fail 'locked apply reached nft validation'

new_case tracker_offline
run_apply MOCK_WAN_COUNT=2
assert_rc 0
mkdir -p "$CASE_DIR/state/mwan3track/wan1_6"
printf '%s\n' offline >"$CASE_DIR/state/mwan3track/wan1_6/STATUS"
printf '%s\n' 0 >"$CASE_DIR/state/mwan3track/wan1_6/SCORE"
run_status MOCK_WAN_COUNT=2
assert_rc 0
assert_contains '"policy_ready":false' "$CASE_DIR/stdout"
assert_contains '"tracker":{"tracked":true,"state":"offline","score":0}' "$CASE_DIR/stdout"

new_case down_tracker_excluded
run_apply MOCK_WAN_COUNT=3 MOCK_DOWN=wan3_6
assert_rc 0
mkdir -p "$CASE_DIR/state/mwan3track/wan3_6"
printf '%s\n' offline >"$CASE_DIR/state/mwan3track/wan3_6/STATUS"
printf '%s\n' 0 >"$CASE_DIR/state/mwan3track/wan3_6/SCORE"
run_status MOCK_WAN_COUNT=3 MOCK_DOWN=wan3_6
assert_rc 0
assert_contains '"policy_ready":true' "$CASE_DIR/stdout"
assert_contains '"active_wan_count":2' "$CASE_DIR/stdout"

new_case missing_uci
rm "$CASE_DIR/bin/uci"
run_apply MOCK_WAN_COUNT=2
assert_rc 1
assert_contains 'uci is not installed' "$CASE_DIR/stderr"
assert_no_nft_calls

printf '%s\n' 'test-nft-nat6: PASS (57 cases)'
