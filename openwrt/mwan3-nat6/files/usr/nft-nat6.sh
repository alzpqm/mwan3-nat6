#!/bin/sh

# Keep mwan3-selected IPv6 flows inside the delegated prefix of their egress
# WAN. WAN membership is read from /etc/config/mwan3-nat6. An optional,
# router-local compatibility mode gives device-bound sockets an initial RPDB
# lookup in the matching mwan3 table, then pins exact WAN-source ICMPv6 echo
# requests to the bypass mark. It never changes forwarded traffic or mwan3's
# ordinary connection balancing.

PATH="${NAT6_PATH:-/usr/sbin:/usr/bin:/sbin:/bin}"
CONFIG="${NAT6_CONFIG:-mwan3-nat6}"
SYS_CLASS_NET="${NAT6_SYS_CLASS_NET:-/sys/class/net}"
MWAN3TRACK_DIR="${NAT6_MWAN3TRACK_DIR:-/var/run/mwan3track}"
MWAN3_STATUS_DIR="${NAT6_MWAN3_STATUS_DIR:-/var/run/mwan3}"
RUNTIME_DIR="${NAT6_RUNTIME_DIR:-/var/run}"
CHAIN='srcnat'
OUTPUT_CHAIN='local_icmp'
MAX_WANS=32
WAN_FILE=''
RULE_FILE=''
POLICY_FILE=''
OLD_POLICY_FILE=''
LOCK_FILE="$RUNTIME_DIR/mwan3-nat6.apply.lock"
LOCK_HELD=false
WAN_COUNT=0
READY_WAN_COUNT=0
ALL_READY=true
NAT_READY=false
DEGRADED=false
POLICY_READY=true
CONFIG_ERROR=''
CONFIG_ERROR_DETAIL=''
READINESS_ERROR=''
HARD_READINESS_ERROR=''
TABLE='mwan3_nat6'
MONITOR_ENABLED=false
MONITOR_INTERVAL=15
MONITOR_DEBOUNCE=2
REFRESH_MWAN3=false
PIN_LOCAL_ICMP=false
MMX_DEFAULT='0x3f00'
POLICY_PRIORITY=1500
POLICY_PROTOCOL=242

cleanup() {
	[ -z "$WAN_FILE" ] || rm -f "$WAN_FILE" 2>/dev/null || :
	[ -z "$RULE_FILE" ] || rm -f "$RULE_FILE" 2>/dev/null || :
	[ -z "$POLICY_FILE" ] || rm -f "$POLICY_FILE" 2>/dev/null || :
	[ -z "$OLD_POLICY_FILE" ] || rm -f "$OLD_POLICY_FILE" 2>/dev/null || :
	if [ "$LOCK_HELD" = true ]; then
		lock -u "$LOCK_FILE" 2>/dev/null || :
		LOCK_HELD=false
	fi
}

fail() {
	logger -t nft-nat6 -- "ERROR: $*" 2>/dev/null || :
	printf '%s\n' "nft-nat6: ERROR: $*" >&2
	exit 1
}

set_config_error() {
	CONFIG_ERROR="$1"
	CONFIG_ERROR_DETAIL="$2"
	return 1
}

is_uint() {
	case "$1" in
	'' | *[!0-9]*) return 1 ;;
	*) return 0 ;;
	esac
}

is_safe_name() {
	printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_.:@+-]+$'
}

is_safe_device() {
	[ -n "$1" ] && [ "${#1}" -le 15 ] && is_safe_name "$1"
}

is_safe_label() {
	printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_.:@+ /-]+$'
}

# netifd normally emits normalized IPv6 values, but nftables input still needs
# an independent syntax and scope gate. This parser deliberately rejects IPv4
# tails and accepts only 2000::/3 global-unicast addresses.
is_ipv6_gua() {
	printf '%s\n' "$1" | awk '
	function count_side(value, fields, count, field_index) {
		if (value == "")
			return 0
		count = split(value, fields, ":")
		for (field_index = 1; field_index <= count; field_index++)
			if (fields[field_index] !~ /^[0-9A-Fa-f]+$/ || length(fields[field_index]) > 4)
				return -1
		return count
	}
	{
		value = $0
		if (value !~ /^[23][0-9A-Fa-f:]*$/)
			exit 1
		compressed = index(value, "::")
		if (compressed) {
			if (index(substr(value, compressed + 2), "::"))
				exit 1
			left = count_side(substr(value, 1, compressed - 1))
			right = count_side(substr(value, compressed + 2))
			if (left < 0 || right < 0 || left + right >= 8)
				exit 1
		} else if (count_side(value) != 8) {
			exit 1
		}
		exit 0
	}'
}

read_bool() {
	value="$1"
	default="$2"
	case "${value:-$default}" in
	1 | true | yes | on) printf '%s' true ;;
	0 | false | no | off) printf '%s' false ;;
	*) return 1 ;;
	esac
}

uci_get() {
	uci -q get "$CONFIG.$1.$2" 2>/dev/null
}

is_hex_mark() {
	printf '%s\n' "$1" | grep -Eq '^0x[0-9A-Fa-f]{1,8}$' &&
		! printf '%s\n' "$1" | grep -Eq '^0x0+$'
}

read_counter() {
	device="$1"
	name="$2"
	value='0'
	if [ -n "$device" ] && [ -r "$SYS_CLASS_NET/$device/statistics/$name" ]; then
		value="$(sed -n '1p' "$SYS_CLASS_NET/$device/statistics/$name" 2>/dev/null)"
	fi
	case "$value" in
	'' | *[!0-9]*) value='0' ;;
	esac
	printf '%s' "$value"
}

prepare_wan_file() {
	umask 077
	WAN_FILE="$(mktemp "${TMPDIR:-/tmp}/mwan3-nat6-wans.XXXXXX")" ||
		set_config_error 'temporary-file-failed' 'cannot create WAN state file'
}

prepare_policy_file() {
	umask 077
	POLICY_FILE="$(mktemp "${TMPDIR:-/tmp}/mwan3-nat6-policy.XXXXXX")" ||
		set_config_error 'temporary-file-failed' 'cannot create policy state file'
}

resolve_policy_tables() {
	prepare_policy_file || return 1
	[ "$PIN_LOCAL_ICMP" = true ] || return 0
	command -v ip >/dev/null 2>&1 || {
		set_config_error 'required-command-missing' 'ip is required for local device routing'
		return 1
	}
	rule_tables="$(ip -6 rule show 2>/dev/null | awk '
		/fwmark/ {
			for (i = 1; i <= NF; i++)
				if ($i == "lookup" && $(i + 1) ~ /^[0-9]+$/)
					print $(i + 1)
		}' | sort -nu)"
	[ -n "$rule_tables" ] || {
		set_config_error 'mwan3-policy-table-missing' 'no numeric mwan3 IPv6 policy tables were found'
		return 1
	}

	while IFS='|' read -r section label logical expected_device device expected_mask \
		address prefix prefix_mask state; do
		[ "$state" = ready ] || continue
		matches=''
		for policy_table in $rule_tables; do
			is_uint "$policy_table" || continue
			default_routes="$(ip -6 route show table "$policy_table" default 2>/dev/null)"
			if printf '%s\n' "$default_routes" |
				grep -Eq "(^|[[:space:]])dev[[:space:]]+$device([[:space:]]|$)"; then
				case " $matches " in
				*" $policy_table "*) ;;
				*) matches="$matches $policy_table" ;;
				esac
			fi
		done
		set -- $matches
		[ "$#" -eq 1 ] || {
			set_config_error 'mwan3-policy-table-ambiguous' \
				"$logical has $# matching mwan3 IPv6 policy tables"
			return 1
		}
		printf '%s|%s|%s\n' "$logical" "$device" "$1" >>"$POLICY_FILE" || {
			set_config_error 'temporary-file-failed' 'cannot write policy state file'
			return 1
		}
	done <"$WAN_FILE"
}

snapshot_managed_policy_rules() {
	OLD_POLICY_FILE="$(mktemp "${TMPDIR:-/tmp}/mwan3-nat6-old-policy.XXXXXX")" ||
		fail 'cannot create old policy state file'
	ip -6 rule show 2>/dev/null | awk -v priority="$POLICY_PRIORITY" -v protocol="$POLICY_PROTOCOL" '
		$1 == priority ":" {
			device = table = tagged = ""
			for (i = 1; i <= NF; i++) {
				if ($i == "oif") device = $(i + 1)
				if ($i == "lookup") table = $(i + 1)
				if (($i == "proto" || $i == "protocol") && $(i + 1) == protocol) tagged = "yes"
			}
			if (tagged == "yes" && device ~ /^[A-Za-z0-9_.:@+-]+$/ && table ~ /^[0-9]+$/)
				print device "|" table
		}' >"$OLD_POLICY_FILE" || fail 'cannot inspect managed IPv6 policy rules'
}

remove_policy_entries() {
	file="$1"
	while IFS='|' read -r device policy_table; do
		[ -n "$device" ] || continue
		ip -6 rule del pref "$POLICY_PRIORITY" oif "$device" lookup "$policy_table" \
			protocol "$POLICY_PROTOCOL" >/dev/null 2>&1 || return 1
	done <"$file"
}

add_policy_entries() {
	file="$1"
	while IFS='|' read -r logical device policy_table; do
		[ -n "$device" ] || continue
		if ip -6 rule show | awk -v priority="$POLICY_PRIORITY" -v wanted="$device" '
			$1 == priority ":" {
				for (i = 1; i <= NF; i++)
					if ($i == "oif" && $(i + 1) == wanted) found = 1
			}
			END { exit found ? 0 : 1 }
		'; then
			return 1
		fi
		ip -6 rule add pref "$POLICY_PRIORITY" oif "$device" lookup "$policy_table" \
			protocol "$POLICY_PROTOCOL" >/dev/null 2>&1 || return 1
	done <"$file"
}

restore_policy_entries() {
	current="$(mktemp "${TMPDIR:-/tmp}/mwan3-nat6-current-policy.XXXXXX")" || return 1
	ip -6 rule show | awk -v priority="$POLICY_PRIORITY" -v protocol="$POLICY_PROTOCOL" '
		$1 == priority ":" {
			device = table = tagged = ""
			for (i = 1; i <= NF; i++) {
				if ($i == "oif") device = $(i + 1)
				if ($i == "lookup") table = $(i + 1)
				if (($i == "proto" || $i == "protocol") && $(i + 1) == protocol) tagged = "yes"
			}
			if (tagged == "yes" && device ~ /^[A-Za-z0-9_.:@+-]+$/ && table ~ /^[0-9]+$/)
				print device "|" table
		}' >"$current"
	remove_policy_entries "$current" 2>/dev/null || :
	while IFS='|' read -r device policy_table; do
		[ -n "$device" ] || continue
		ip -6 rule add pref "$POLICY_PRIORITY" oif "$device" lookup "$policy_table" \
			protocol "$POLICY_PROTOCOL" >/dev/null 2>&1 || :
	done <"$OLD_POLICY_FILE"
	rm -f "$current"
	ip -6 route flush cache >/dev/null 2>&1 || :
}

reconcile_policy_rules() {
	snapshot_managed_policy_rules
	remove_policy_entries "$OLD_POLICY_FILE" || {
		restore_policy_entries
		return 1
	}
	add_policy_entries "$POLICY_FILE" || {
		restore_policy_entries
		return 1
	}
	ip -6 route flush cache >/dev/null 2>&1 || :
}

cleanup_policy_rules() {
	command -v ip >/dev/null 2>&1 || fail 'ip is not installed'
	command -v lock >/dev/null 2>&1 || fail 'lock is not installed'
	lock -n "$LOCK_FILE" || fail 'another NAT6 apply is in progress'
	LOCK_HELD=true
	snapshot_managed_policy_rules
	remove_policy_entries "$OLD_POLICY_FILE" || fail 'could not remove local device IPv6 policy rules'
	ip -6 route flush cache >/dev/null 2>&1 || :
}

load_configuration() {
	WAN_COUNT=0
	READY_WAN_COUNT=0
	ALL_READY=true
	NAT_READY=false
	DEGRADED=false
	CONFIG_ERROR=''
	CONFIG_ERROR_DETAIL=''
	READINESS_ERROR=''
	HARD_READINESS_ERROR=''
	POLICY_READY=true
	seen_logicals='|'
	seen_devices='|'

	prepare_wan_file || return 1

	configured_table="$(uci_get globals table)"
	[ -z "$configured_table" ] || TABLE="$configured_table"
	printf '%s\n' "$TABLE" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || {
		set_config_error 'invalid-table' "invalid nft table name: $TABLE"
		return 1
	}
	monitor_value="$(uci_get globals monitor)"
	MONITOR_ENABLED="$(read_bool "$monitor_value" 0)" || {
		set_config_error 'invalid-monitor' 'globals has an invalid monitor value'
		return 1
	}
	refresh_value="$(uci_get globals refresh_mwan3_after_nat)"
	REFRESH_MWAN3="$(read_bool "$refresh_value" 0)" || {
		set_config_error 'invalid-refresh-mwan3-after-nat' \
			'globals has an invalid refresh_mwan3_after_nat value'
		return 1
	}
	pin_value="$(uci_get globals pin_local_icmp)"
	PIN_LOCAL_ICMP="$(read_bool "$pin_value" 0)" || {
		set_config_error 'invalid-pin-local-icmp' \
			'globals has an invalid pin_local_icmp value'
		return 1
	}
	if [ "$PIN_LOCAL_ICMP" = true ]; then
		if [ -r "$MWAN3_STATUS_DIR/mmx_mask" ]; then
			MMX_DEFAULT="$(sed -n '1p' "$MWAN3_STATUS_DIR/mmx_mask" 2>/dev/null)"
		else
			MMX_DEFAULT="$(uci -q get mwan3.globals.mmx_mask 2>/dev/null)"
		fi
		MMX_DEFAULT="${MMX_DEFAULT:-0x3f00}"
		is_hex_mark "$MMX_DEFAULT" || {
			set_config_error 'invalid-mwan3-mask' \
				'mwan3 globals has an invalid or zero mmx_mask'
			return 1
		}
	fi
	MONITOR_INTERVAL="$(uci_get globals interval)"
	MONITOR_INTERVAL="${MONITOR_INTERVAL:-15}"
	is_uint "$MONITOR_INTERVAL" && [ "$MONITOR_INTERVAL" -ge 5 ] &&
		[ "$MONITOR_INTERVAL" -le 3600 ] || {
		set_config_error 'invalid-monitor-interval' 'monitor interval must be between 5 and 3600 seconds'
		return 1
	}
	MONITOR_DEBOUNCE="$(uci_get globals debounce)"
	MONITOR_DEBOUNCE="${MONITOR_DEBOUNCE:-2}"
	is_uint "$MONITOR_DEBOUNCE" && [ "$MONITOR_DEBOUNCE" -ge 1 ] &&
		[ "$MONITOR_DEBOUNCE" -le 10 ] || {
		set_config_error 'invalid-monitor-debounce' 'monitor debounce must be between 1 and 10 samples'
		return 1
	}

	sections="$(uci -q show "$CONFIG" 2>/dev/null |
		sed -n "s/^${CONFIG}\.\([^.=]*\)=wan$/\1/p")"
	[ -n "$sections" ] || {
		set_config_error 'no-wans' 'no WAN sections are configured'
		return 1
	}

	for section in $sections; do
		enabled="$(uci_get "$section" enabled)"
		case "${enabled:-1}" in
		1 | true | yes | on) ;;
		0 | false | no | off) continue ;;
		*) set_config_error 'invalid-enabled' "$section has an invalid enabled value"; return 1 ;;
		esac

		logical="$(uci_get "$section" interface)"
		expected_device="$(uci_get "$section" device)"
		expected_mask="$(uci_get "$section" expected_prefix_length)"
		address_index="$(uci_get "$section" address_index)"
		prefix_index="$(uci_get "$section" prefix_index)"
		label="$(uci_get "$section" label)"
		address_index="${address_index:-0}"
		prefix_index="${prefix_index:-0}"
		label="${label:-$logical}"

		[ -n "$logical" ] && is_safe_name "$logical" || {
			set_config_error 'invalid-interface' "$section has an invalid logical interface"
			return 1
		}
		[ -z "$expected_device" ] || is_safe_device "$expected_device" || {
			set_config_error 'invalid-device' "$section has an invalid device"
			return 1
		}
		is_safe_label "$label" || {
			set_config_error 'invalid-label' "$section has an invalid label"
			return 1
		}
		case "$seen_logicals" in
		*"|$logical|"*)
			set_config_error 'duplicate-interface' "logical interface $logical is configured more than once"
			return 1
			;;
		esac
		seen_logicals="$seen_logicals$logical|"

		for index_value in "$address_index" "$prefix_index"; do
			is_uint "$index_value" && [ "$index_value" -le 15 ] || {
				set_config_error 'invalid-index' "$section has an address/prefix index outside 0-15"
				return 1
			}
		done
		if [ -n "$expected_mask" ]; then
			is_uint "$expected_mask" && [ "$expected_mask" -ge 3 ] &&
				[ "$expected_mask" -le 64 ] || {
				set_config_error 'invalid-expected-prefix-length' "$section expects a prefix length outside 3-64"
				return 1
			}
		fi

		state='unavailable'
		live_device=''
		address=''
		prefix_address=''
		prefix_mask=''
		status="$(ifstatus "$logical" 2>/dev/null)"
		if [ "$?" -eq 0 ]; then
			up="$(printf '%s' "$status" | jsonfilter -e '@.up' 2>/dev/null)"
			live_device="$(printf '%s' "$status" | jsonfilter -e '@.l3_device' 2>/dev/null)"
			address="$(printf '%s' "$status" |
				jsonfilter -e "@[\"ipv6-address\"][$address_index][\"address\"]" 2>/dev/null)"
			prefix_address="$(printf '%s' "$status" |
				jsonfilter -e "@[\"ipv6-prefix\"][$prefix_index][\"address\"]" 2>/dev/null)"
			prefix_mask="$(printf '%s' "$status" |
				jsonfilter -e "@[\"ipv6-prefix\"][$prefix_index][\"mask\"]" 2>/dev/null)"

			if [ "$up" != 'true' ]; then
				state='down'
			elif ! is_safe_device "$live_device"; then
				state='invalid-live-device'
			elif [ -n "$expected_device" ] && [ "$live_device" != "$expected_device" ]; then
				state='unexpected-device'
			elif ! is_uint "$prefix_mask" || [ "$prefix_mask" -lt 3 ] || [ "$prefix_mask" -gt 64 ]; then
				state='invalid-prefix-length'
			elif [ -n "$expected_mask" ] && [ "$prefix_mask" != "$expected_mask" ]; then
				state='unexpected-prefix-length'
			elif ! is_ipv6_gua "$address"; then
				state='invalid-address'
			elif ! is_ipv6_gua "$prefix_address"; then
				state='invalid-prefix'
			else
				state='ready'
			fi
		fi

		if [ "$state" = 'ready' ]; then
			case "$seen_devices" in
			*"|$live_device|"*)
				set_config_error 'duplicate-device' "device $live_device is used by more than one WAN"
				return 1
				;;
			esac
			seen_devices="$seen_devices$live_device|"
			prefix="$prefix_address/$prefix_mask"
			READY_WAN_COUNT=$((READY_WAN_COUNT + 1))
		else
			ALL_READY=false
			prefix=''
			[ -n "$READINESS_ERROR" ] || READINESS_ERROR="$logical is not ready: $state"
			case "$state" in
			down | unavailable) ;;
			*)
				[ -n "$HARD_READINESS_ERROR" ] || \
					HARD_READINESS_ERROR="$logical failed a safety check: $state"
				;;
			esac
		fi

		printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
			"$section" "$label" "$logical" "$expected_device" "$live_device" \
			"$expected_mask" "$address" "$prefix" "$prefix_mask" "$state" >>"$WAN_FILE" || {
			set_config_error 'temporary-file-failed' 'cannot write WAN state file'
			return 1
		}
		WAN_COUNT=$((WAN_COUNT + 1))
		[ "$WAN_COUNT" -le "$MAX_WANS" ] || {
			set_config_error 'too-many-wans' "more than $MAX_WANS WANs are enabled"
			return 1
		}
	done

	[ "$WAN_COUNT" -ge 2 ] || {
		set_config_error 'too-few-wans' 'at least two WANs must be enabled'
		return 1
	}
	[ "$READY_WAN_COUNT" -eq "$WAN_COUNT" ] || DEGRADED=true
	if [ "$READY_WAN_COUNT" -ge 1 ] && [ -z "$HARD_READINESS_ERROR" ]; then
		NAT_READY=true
	fi
	resolve_policy_tables || return 1
	return 0
}

generate_rules() {
	table_exists="$1"
	chain_exists="$2"
	output_chain_exists="$3"
	RULE_FILE="$(mktemp "${TMPDIR:-/tmp}/mwan3-nat6-rules.XXXXXX")" ||
		fail 'cannot create rule file'
	{
		[ "$table_exists" = true ] || printf 'add table inet %s\n' "$TABLE"
		[ "$chain_exists" = false ] || printf 'delete chain inet %s %s\n' "$TABLE" "$CHAIN"
		[ "$output_chain_exists" = false ] || \
			printf 'delete chain inet %s %s\n' "$TABLE" "$OUTPUT_CHAIN"
		printf 'add chain inet %s %s { type nat hook postrouting priority srcnat; policy accept; }\n' \
			"$TABLE" "$CHAIN"
		if [ "$PIN_LOCAL_ICMP" = true ]; then
			printf 'add chain inet %s %s { type route hook output priority -140; policy accept; }\n' \
				"$TABLE" "$OUTPUT_CHAIN"
		fi
	} >"$RULE_FILE" || fail 'cannot write rule file'

	while IFS='|' read -r destination_section destination_label destination_logical \
		destination_expected_device destination_device destination_expected_mask \
		destination_address destination_prefix destination_mask destination_state; do
		[ "$destination_state" = ready ] || continue
		while IFS='|' read -r source_section source_label source_logical \
			source_expected_device source_device source_expected_mask source_address \
			source_prefix source_mask source_state; do
			[ "$source_state" = ready ] || continue
			[ "$destination_section" = "$source_section" ] && continue
			printf 'add rule inet %s %s oifname "%s" ip6 saddr %s snat ip6 to %s\n' \
				"$TABLE" "$CHAIN" "$destination_device" "$source_address" \
				"$destination_address" >>"$RULE_FILE" || fail 'cannot write cross-SNAT rule'
		done <"$WAN_FILE"
	done <"$WAN_FILE"

	while IFS='|' read -r section label logical expected_device device expected_mask \
		address prefix prefix_mask state; do
		[ "$state" = ready ] || continue
		printf 'add rule inet %s %s oifname "%s" ip6 saddr 2000::/3 ip6 saddr != %s snat ip6 prefix to %s\n' \
			"$TABLE" "$CHAIN" "$device" "$prefix" "$prefix" >>"$RULE_FILE" ||
			fail 'cannot write prefix-SNAT rule'
	done <"$WAN_FILE"

	if [ "$PIN_LOCAL_ICMP" = true ]; then
		while IFS='|' read -r section label logical expected_device device expected_mask \
			address prefix prefix_mask state; do
			[ "$state" = ready ] || continue
			printf 'add rule inet %s %s ip6 saddr %s meta l4proto ipv6-icmp icmpv6 type echo-request meta mark set %s comment "mwan3-nat6 local ICMP pin %s"\n' \
				"$TABLE" "$OUTPUT_CHAIN" "$address" "$MMX_DEFAULT" "$logical" >>"$RULE_FILE" ||
				fail 'cannot write local ICMP pin rule'
		done <"$WAN_FILE"
	fi
}

apply_rules() {
	load_configuration || fail "$CONFIG_ERROR_DETAIL"
	[ -z "$HARD_READINESS_ERROR" ] || fail "$HARD_READINESS_ERROR"
	[ "$READY_WAN_COUNT" -ge 1 ] || fail "${READINESS_ERROR:-no enabled WAN is ready}"
	command -v lock >/dev/null 2>&1 || fail 'lock is not installed'
	lock -n "$LOCK_FILE" || fail 'another NAT6 apply is in progress'
	LOCK_HELD=true

	table_exists=false
	chain_exists=false
	output_chain_exists=false
	if nft list table inet "$TABLE" >/dev/null 2>&1; then
		table_exists=true
		if nft list chain inet "$TABLE" "$CHAIN" >/dev/null 2>&1; then
			chain_exists=true
		fi
		if nft list chain inet "$TABLE" "$OUTPUT_CHAIN" >/dev/null 2>&1; then
			output_chain_exists=true
		fi
	fi
	generate_rules "$table_exists" "$chain_exists" "$output_chain_exists"

	nft -c -f "$RULE_FILE" || fail 'generated nft rules failed validation'
	reconcile_policy_rules || fail 'could not reconcile local device IPv6 policy rules'
	if ! nft -f "$RULE_FILE"; then
		restore_policy_entries
		fail 'could not replace nft rules'
	fi

	logger -t nft-nat6 -- \
		"installed $READY_WAN_COUNT/$WAN_COUNT ready-WAN prefix NAT in inet $TABLE ($((READY_WAN_COUNT * READY_WAN_COUNT)) NAT rules; local device policy $PIN_LOCAL_ICMP)" \
		2>/dev/null || :
}

emit_status_error() {
	error="$1"
	printf '{"ok":false,"ready":false,"all_ready":false,"degraded":false,'
	printf '"policy_ready":false,"error":"%s","interfaces":[],' "$error"
	printf '"nat":{"table":"%s","present":false,"wan_count":0,' "$TABLE"
	printf '"active_wan_count":0,"inactive_wan_count":0,'
	printf '"rule_count":0,"expected_rule_count":0,"profile":"unknown"},'
	printf '"local_icmp":{"enabled":false,"present":false,"rule_count":0,'
	printf '"expected_rule_count":0,"mark":"","routing_rule_count":0,'
	printf '"expected_routing_rule_count":0,"routing_priority":%s,' "$POLICY_PRIORITY"
	printf '"profile":"disabled"},'
	printf '%s\n' '"monitor":{"enabled":false,"interval":0,"debounce":0,"refresh_mwan3":false}}'
}

emit_status() {
	if ! command -v uci >/dev/null 2>&1 ||
		! command -v ifstatus >/dev/null 2>&1 ||
		! command -v jsonfilter >/dev/null 2>&1 ||
		! command -v nft >/dev/null 2>&1 ||
		! command -v ip >/dev/null 2>&1; then
		emit_status_error 'required-command-missing'
		return 0
	fi
	if ! load_configuration; then
		emit_status_error "$CONFIG_ERROR"
		return 0
	fi

	expected_rule_count=$((READY_WAN_COUNT * READY_WAN_COUNT))
	rules="$(nft -a list chain inet "$TABLE" "$CHAIN" 2>/dev/null)"
	nft_rc="$?"
	rule_count=0
	cross_count=0
	prefix_count=0
	safe_prefix_count=0
	present=false
	profile='inactive'
	exact_current=true
	if [ "$nft_rc" -eq 0 ]; then
		present=true
		rule_count="$(printf '%s\n' "$rules" | awk '
			/# handle [0-9]+$/ && $1 != "chain" { count++ }
			END { print count + 0 }
		')"
		cross_count="$(printf '%s\n' "$rules" | grep -c 'snat ip6 to')"
		prefix_count="$(printf '%s\n' "$rules" | grep -c 'snat ip6 prefix to')"
		safe_prefix_count="$(printf '%s\n' "$rules" |
			grep -c 'ip6 saddr 2000::/3.*snat ip6 prefix to')"
		while IFS='|' read -r destination_section destination_label destination_logical \
			destination_expected_device destination_device destination_expected_mask \
			destination_address destination_prefix destination_mask destination_state; do
			[ "$destination_state" = ready ] || continue
			prefix_tuple="oifname \"$destination_device\" ip6 saddr 2000::/3 ip6 saddr != $destination_prefix snat ip6 prefix to $destination_prefix"
			[ "$(printf '%s\n' "$rules" | grep -F -c "$prefix_tuple")" -eq 1 ] ||
				exact_current=false
			while IFS='|' read -r source_section source_label source_logical \
				source_expected_device source_device source_expected_mask source_address \
				source_prefix source_mask source_state; do
				[ "$source_state" = ready ] || continue
				[ "$destination_section" = "$source_section" ] && continue
				cross_tuple="oifname \"$destination_device\" ip6 saddr $source_address snat ip6 to $destination_address"
				[ "$(printf '%s\n' "$rules" | grep -F -c "$cross_tuple")" -eq 1 ] ||
					exact_current=false
			done <"$WAN_FILE"
		done <"$WAN_FILE"

		managed_shape=false
		unsafe_shape=false
		if [ "$prefix_count" -ge 1 ] &&
			[ "$cross_count" -eq "$((prefix_count * (prefix_count - 1)))" ] &&
			[ "$rule_count" -eq "$((prefix_count * prefix_count))" ]; then
			[ "$safe_prefix_count" -eq "$prefix_count" ] && managed_shape=true
			[ "$safe_prefix_count" -eq 0 ] && unsafe_shape=true
		fi
		if [ "$rule_count" -eq "$expected_rule_count" ] &&
			[ "$cross_count" -eq "$((READY_WAN_COUNT * (READY_WAN_COUNT - 1)))" ] &&
			[ "$prefix_count" -eq "$READY_WAN_COUNT" ] &&
			[ "$safe_prefix_count" -eq "$READY_WAN_COUNT" ] &&
			[ "$exact_current" = true ]; then
			profile='managed'
		elif [ "$managed_shape" = true ]; then
			profile='managed-stale'
		elif [ "$unsafe_shape" = true ]; then
			profile='unsafe'
		else
			profile='unexpected'
		fi
	fi

	local_rules="$(nft -a list chain inet "$TABLE" "$OUTPUT_CHAIN" 2>/dev/null)"
	local_nft_rc="$?"
	local_present=false
	local_rule_count=0
	local_expected_rule_count=0
	local_profile='disabled'
	local_exact=true
	local_safe_count=0
	local_chain_safe=false
	mark_digits="$(printf '%s\n' "$MMX_DEFAULT" | tr 'A-F' 'a-f' | sed 's/^0x0*//')"
	[ "$PIN_LOCAL_ICMP" = false ] || local_expected_rule_count="$READY_WAN_COUNT"
	if [ "$local_nft_rc" -eq 0 ]; then
		local_present=true
		if printf '%s\n' "$local_rules" |
			grep -Eq 'type route hook output priority (-140|mangle \+ 10); policy accept;'; then
			local_chain_safe=true
		fi
		local_rule_count="$(printf '%s\n' "$local_rules" | awk '
			/# handle [0-9]+$/ && $1 != "chain" { count++ }
			END { print count + 0 }
		')"
		local_safe_count="$(printf '%s\n' "$local_rules" |
			grep -Ei -c "^[[:space:]]*ip6 saddr [23][0-9a-f:]+ (meta l4proto ipv6-icmp )?icmpv6 type echo-request meta mark set 0x0*${mark_digits} comment \"mwan3-nat6 local ICMP pin [A-Za-z0-9_.:@+-]+\" # handle [0-9]+$")"
	fi
	if [ "$PIN_LOCAL_ICMP" = true ]; then
		while IFS='|' read -r section label logical expected_device device expected_mask \
			address prefix prefix_mask state; do
			[ "$state" = ready ] || continue
			local_prefix="ip6 saddr $address"
			local_comment="comment \"mwan3-nat6 local ICMP pin $logical\""
			[ "$(printf '%s\n' "$local_rules" | grep -F "$local_prefix" |
				grep -F 'icmpv6 type echo-request' |
				grep -F "$local_comment" |
				grep -Ei -c "meta mark set 0x0*${mark_digits}")" -eq 1 ] ||
				local_exact=false
		done <"$WAN_FILE"
		if [ "$local_present" = true ] &&
			[ "$local_chain_safe" = true ] &&
			[ "$local_rule_count" -eq "$local_expected_rule_count" ] &&
			[ "$local_safe_count" -eq "$local_expected_rule_count" ] &&
			[ "$local_exact" = true ]; then
			local_profile='managed'
		elif [ "$local_present" = false ]; then
			local_profile='missing'
		elif [ "$local_chain_safe" = true ] &&
			[ "$local_rule_count" -eq "$local_safe_count" ] &&
			[ "$local_rule_count" -gt 0 ]; then
			local_profile='managed-stale'
		else
			local_profile='unexpected'
		fi
	elif [ "$local_present" = true ] &&
		[ "$local_chain_safe" = true ] &&
		[ "$local_rule_count" -eq "$local_safe_count" ]; then
		local_profile='managed-stale'
	elif [ "$local_present" = true ]; then
		local_profile='unexpected'
	fi

	policy_rules="$(ip -6 rule show 2>/dev/null)"
	policy_rule_count="$(printf '%s\n' "$policy_rules" | awk \
		-v priority="$POLICY_PRIORITY" -v protocol="$POLICY_PROTOCOL" '
		$1 == priority ":" {
			device = table = tagged = ""
			for (i = 1; i <= NF; i++) {
				if ($i == "oif") device = $(i + 1)
				if ($i == "lookup") table = $(i + 1)
				if (($i == "proto" || $i == "protocol") && $(i + 1) == protocol) tagged = "yes"
			}
			if (tagged == "yes" && device ~ /^[A-Za-z0-9_.:@+-]+$/ && table ~ /^[0-9]+$/) count++
		}
		END { print count + 0 }')"
	policy_expected_rule_count=0
	policy_exact=true
	[ "$PIN_LOCAL_ICMP" = false ] || policy_expected_rule_count="$READY_WAN_COUNT"
	if [ "$PIN_LOCAL_ICMP" = true ]; then
		while IFS='|' read -r logical device policy_table; do
			[ -n "$device" ] || continue
			matches="$(printf '%s\n' "$policy_rules" | awk \
				-v priority="$POLICY_PRIORITY" -v protocol="$POLICY_PROTOCOL" \
				-v wanted_device="$device" -v wanted_table="$policy_table" '
				$1 == priority ":" {
					device = table = tagged = ""
					for (i = 1; i <= NF; i++) {
						if ($i == "oif") device = $(i + 1)
						if ($i == "lookup") table = $(i + 1)
						if (($i == "proto" || $i == "protocol") && $(i + 1) == protocol) tagged = "yes"
					}
					if (tagged == "yes" && device == wanted_device && table == wanted_table) count++
				}
				END { print count + 0 }')"
			[ "$matches" -eq 1 ] || policy_exact=false
		done <"$POLICY_FILE"
		if [ "$policy_rule_count" -ne "$policy_expected_rule_count" ] ||
			[ "$policy_exact" != true ]; then
			if [ "$policy_rule_count" -eq 0 ]; then
				local_profile='missing'
			else
				local_profile='unexpected'
			fi
		fi
	elif [ "$policy_rule_count" -gt 0 ]; then
		if [ "$local_profile" = disabled ] ||
			[ "$local_profile" = managed-stale ]; then
			local_profile='managed-stale'
		else
			local_profile='unexpected'
		fi
	fi

	POLICY_READY="$NAT_READY"
	while IFS='|' read -r section label logical expected_device device expected_mask \
		address prefix prefix_mask state; do
		[ "$state" = ready ] || continue
		if [ -r "$MWAN3TRACK_DIR/$logical/STATUS" ]; then
			tracker_state="$(sed -n '1p' "$MWAN3TRACK_DIR/$logical/STATUS" 2>/dev/null)"
			[ "$tracker_state" = online ] || POLICY_READY=false
		fi
	done <"$WAN_FILE"

	printf '{"ok":true,"ready":%s,"all_ready":%s,"degraded":%s,' \
		"$NAT_READY" "$ALL_READY" "$DEGRADED"
	printf '"policy_ready":%s,"interfaces":[' "$POLICY_READY"
	first=true
	while IFS='|' read -r section label logical expected_device device expected_mask \
		address prefix prefix_mask state; do
		counter_device="${device:-$expected_device}"
		rx_bytes="$(read_counter "$counter_device" rx_bytes)"
		tx_bytes="$(read_counter "$counter_device" tx_bytes)"
		rx_errors="$(read_counter "$counter_device" rx_errors)"
		tx_errors="$(read_counter "$counter_device" tx_errors)"
		rx_dropped="$(read_counter "$counter_device" rx_dropped)"
		tx_dropped="$(read_counter "$counter_device" tx_dropped)"
		tracker_state='untracked'
		tracker_score='0'
		tracker_tracked=false
		if [ -r "$MWAN3TRACK_DIR/$logical/STATUS" ]; then
			tracker_tracked=true
			tracker_state="$(sed -n '1p' "$MWAN3TRACK_DIR/$logical/STATUS" 2>/dev/null)"
			case "$tracker_state" in
			online | offline | connecting | disconnecting) ;;
			*) tracker_state='unknown' ;;
			esac
			tracker_score="$(sed -n '1p' "$MWAN3TRACK_DIR/$logical/SCORE" 2>/dev/null)"
			is_uint "$tracker_score" || tracker_score='0'
		fi
		[ "$first" = true ] || printf ','
		first=false
		printf '{"label":"%s","logical":"%s","device":"%s",' \
			"$label" "$logical" "$counter_device"
		printf '"expected_mask":"%s","actual_mask":"%s",' "$expected_mask" "$prefix_mask"
		printf '"state":"%s","address":"%s","prefix":"%s",' "$state" "$address" "$prefix"
		printf '"tracker":{"tracked":%s,"state":"%s","score":%s},' \
			"$tracker_tracked" "$tracker_state" "$tracker_score"
		printf '"rx_bytes":%s,"tx_bytes":%s,"rx_errors":%s,"tx_errors":%s,' \
			"$rx_bytes" "$tx_bytes" "$rx_errors" "$tx_errors"
		printf '"rx_dropped":%s,"tx_dropped":%s}' "$rx_dropped" "$tx_dropped"
	done <"$WAN_FILE"
	printf '],"nat":{"table":"%s","present":%s,"wan_count":%s,' \
		"$TABLE" "$present" "$WAN_COUNT"
	printf '"active_wan_count":%s,"inactive_wan_count":%s,' \
		"$READY_WAN_COUNT" "$((WAN_COUNT - READY_WAN_COUNT))"
	printf '"rule_count":%s,"expected_rule_count":%s,"profile":"%s"},' \
		"$rule_count" "$expected_rule_count" "$profile"
	printf '"local_icmp":{"enabled":%s,"present":%s,"rule_count":%s,' \
		"$PIN_LOCAL_ICMP" "$local_present" "$local_rule_count"
	printf '"expected_rule_count":%s,"mark":"%s",' \
		"$local_expected_rule_count" "$MMX_DEFAULT"
	printf '"routing_rule_count":%s,"expected_routing_rule_count":%s,' \
		"$policy_rule_count" "$policy_expected_rule_count"
	printf '"routing_priority":%s,"profile":"%s"},' \
		"$POLICY_PRIORITY" "$local_profile"
	printf '"monitor":{"enabled":%s,"interval":%s,"debounce":%s,"refresh_mwan3":%s}}\n' \
		"$MONITOR_ENABLED" "$MONITOR_INTERVAL" "$MONITOR_DEBOUNCE" "$REFRESH_MWAN3"
}

emit_fingerprint() {
	load_configuration || return 1
	[ "$NAT_READY" = true ] || return 1
	printf 'table|%s|%s\n' "$TABLE" "$READY_WAN_COUNT"
	printf 'local_icmp|%s|%s\n' "$PIN_LOCAL_ICMP" "$MMX_DEFAULT"
	while IFS='|' read -r section label logical expected_device device expected_mask \
		address prefix prefix_mask state; do
		[ "$state" = ready ] || continue
		printf 'wan|%s|%s|%s|%s\n' "$logical" "$device" "$address" "$prefix"
	done <"$WAN_FILE"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

case "${1:-apply}" in
apply)
	command -v uci >/dev/null 2>&1 || fail 'uci is not installed'
	command -v nft >/dev/null 2>&1 || fail 'nft is not installed'
	command -v ifstatus >/dev/null 2>&1 || fail 'ifstatus is not installed'
	command -v jsonfilter >/dev/null 2>&1 || fail 'jsonfilter is not installed'
	command -v ip >/dev/null 2>&1 || fail 'ip is not installed'
	apply_rules
	;;
status)
	emit_status
	;;
fingerprint)
	command -v uci >/dev/null 2>&1 || exit 1
	command -v ifstatus >/dev/null 2>&1 || exit 1
	command -v jsonfilter >/dev/null 2>&1 || exit 1
	emit_fingerprint
	;;
cleanup-policy)
	cleanup_policy_rules
	;;
*) fail 'usage: nft-nat6.sh [apply|status|fingerprint|cleanup-policy]' ;;
esac
