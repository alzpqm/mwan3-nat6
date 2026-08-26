#!/bin/sh

# Keep mwan3-selected IPv6 flows inside the delegated prefix of their egress
# WAN. WAN membership is read from /etc/config/mwan3-nat6. This script does not
# add marks or routes; mwan3 remains the load balancer.

PATH="${NAT6_PATH:-/usr/sbin:/usr/bin:/sbin:/bin}"
CONFIG="${NAT6_CONFIG:-mwan3-nat6}"
SYS_CLASS_NET="${NAT6_SYS_CLASS_NET:-/sys/class/net}"
CHAIN='srcnat'
MAX_WANS=32
WAN_FILE=''
RULE_FILE=''
WAN_COUNT=0
ALL_READY=true
CONFIG_ERROR=''
CONFIG_ERROR_DETAIL=''
READINESS_ERROR=''
TABLE='mwan3_nat6'

cleanup() {
	[ -z "$WAN_FILE" ] || rm -f "$WAN_FILE" 2>/dev/null || :
	[ -z "$RULE_FILE" ] || rm -f "$RULE_FILE" 2>/dev/null || :
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

is_safe_label() {
	printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_.:@+ /-]+$'
}

uci_get() {
	uci -q get "$CONFIG.$1.$2" 2>/dev/null
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

load_configuration() {
	WAN_COUNT=0
	ALL_READY=true
	CONFIG_ERROR=''
	CONFIG_ERROR_DETAIL=''
	READINESS_ERROR=''
	seen_logicals='|'
	seen_devices='|'

	prepare_wan_file || return 1

	configured_table="$(uci_get globals table)"
	[ -z "$configured_table" ] || TABLE="$configured_table"
	printf '%s\n' "$TABLE" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || {
		set_config_error 'invalid-table' "invalid nft table name: $TABLE"
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
		[ -z "$expected_device" ] || is_safe_name "$expected_device" || {
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
			is_uint "$expected_mask" && [ "$expected_mask" -ge 1 ] &&
				[ "$expected_mask" -le 64 ] || {
				set_config_error 'invalid-expected-prefix-length' "$section expects a prefix length outside 1-64"
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
			elif ! is_safe_name "$live_device"; then
				state='invalid-live-device'
			elif [ -n "$expected_device" ] && [ "$live_device" != "$expected_device" ]; then
				state='unexpected-device'
			elif ! is_uint "$prefix_mask" || [ "$prefix_mask" -lt 1 ] || [ "$prefix_mask" -gt 64 ]; then
				state='invalid-prefix-length'
			elif [ -n "$expected_mask" ] && [ "$prefix_mask" != "$expected_mask" ]; then
				state='unexpected-prefix-length'
			else
				case "$address" in
				'' | *[!0-9A-Fa-f:]*) state='invalid-address' ;;
				*) state='ready' ;;
				esac
				case "$prefix_address" in
				'' | *[!0-9A-Fa-f:]*) state='invalid-prefix' ;;
				esac
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
		else
			ALL_READY=false
			prefix=''
			[ -n "$READINESS_ERROR" ] || READINESS_ERROR="$logical is not ready: $state"
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
	return 0
}

generate_rules() {
	RULE_FILE="$(mktemp "${TMPDIR:-/tmp}/mwan3-nat6-rules.XXXXXX")" ||
		fail 'cannot create rule file'
	{
		printf 'delete chain inet %s %s\n' "$TABLE" "$CHAIN"
		printf 'add chain inet %s %s { type nat hook postrouting priority srcnat; policy accept; }\n' \
			"$TABLE" "$CHAIN"
	} >"$RULE_FILE" || fail 'cannot write rule file'

	while IFS='|' read -r destination_section destination_label destination_logical \
		destination_expected_device destination_device destination_expected_mask \
		destination_address destination_prefix destination_mask destination_state; do
		while IFS='|' read -r source_section source_label source_logical \
			source_expected_device source_device source_expected_mask source_address \
			source_prefix source_mask source_state; do
			[ "$destination_section" = "$source_section" ] && continue
			printf 'add rule inet %s %s oifname "%s" ip6 saddr %s snat ip6 to %s\n' \
				"$TABLE" "$CHAIN" "$destination_device" "$source_address" \
				"$destination_address" >>"$RULE_FILE" || fail 'cannot write cross-SNAT rule'
		done <"$WAN_FILE"
	done <"$WAN_FILE"

	while IFS='|' read -r section label logical expected_device device expected_mask \
		address prefix prefix_mask state; do
		printf 'add rule inet %s %s oifname "%s" ip6 saddr 2000::/3 ip6 saddr != %s snat ip6 prefix to %s\n' \
			"$TABLE" "$CHAIN" "$device" "$prefix" "$prefix" >>"$RULE_FILE" ||
			fail 'cannot write prefix-SNAT rule'
	done <"$WAN_FILE"
}

apply_rules() {
	load_configuration || fail "$CONFIG_ERROR_DETAIL"
	[ "$ALL_READY" = true ] || fail "$READINESS_ERROR"
	generate_rules

	nft list table inet "$TABLE" >/dev/null 2>&1 ||
		nft add table inet "$TABLE" || fail "cannot create table $TABLE"
	nft list chain inet "$TABLE" "$CHAIN" >/dev/null 2>&1 ||
		nft add chain inet "$TABLE" "$CHAIN" || fail "cannot seed $CHAIN chain"
	nft -c -f "$RULE_FILE" || fail 'generated nft rules failed validation'
	nft -f "$RULE_FILE" || fail 'could not replace nft rules'

	logger -t nft-nat6 -- \
		"installed $WAN_COUNT-WAN prefix NAT in inet $TABLE ($((WAN_COUNT * WAN_COUNT)) rules)" \
		2>/dev/null || :
}

emit_status_error() {
	error="$1"
	printf '{"ok":false,"ready":false,"error":"%s","interfaces":[],' "$error"
	printf '"nat":{"table":"%s","present":false,"wan_count":0,' "$TABLE"
	printf '%s\n' '"rule_count":0,"expected_rule_count":0,"profile":"unknown"}}'
}

emit_status() {
	if ! command -v uci >/dev/null 2>&1 ||
		! command -v ifstatus >/dev/null 2>&1 ||
		! command -v jsonfilter >/dev/null 2>&1 ||
		! command -v nft >/dev/null 2>&1; then
		emit_status_error 'required-command-missing'
		return 0
	fi
	if ! load_configuration; then
		emit_status_error "$CONFIG_ERROR"
		return 0
	fi

	expected_rule_count=$((WAN_COUNT * WAN_COUNT))
	rules="$(nft list chain inet "$TABLE" "$CHAIN" 2>/dev/null)"
	nft_rc="$?"
	rule_count=0
	prefix_count=0
	safe_prefix_count=0
	present=false
	profile='inactive'
	devices_present=true
	current_values=true
	if [ "$nft_rc" -eq 0 ]; then
		present=true
		rule_count="$(printf '%s\n' "$rules" | grep -c 'oifname')"
		prefix_count="$(printf '%s\n' "$rules" | grep -c 'snat ip6 prefix to')"
		safe_prefix_count="$(printf '%s\n' "$rules" |
			grep -c 'ip6 saddr 2000::/3.*snat ip6 prefix to')"
		while IFS='|' read -r section label logical expected_device device expected_mask \
			address prefix prefix_mask state; do
			check_device="${device:-$expected_device}"
			if [ -z "$check_device" ] ||
				! printf '%s\n' "$rules" | grep -Fq "oifname \"$check_device\""; then
				devices_present=false
			fi
			if [ "$state" != 'ready' ] ||
				! printf '%s\n' "$rules" | grep -Fq "$address" ||
				! printf '%s\n' "$rules" | grep -Fq "$prefix"; then
				current_values=false
			fi
		done <"$WAN_FILE"

		if [ "$rule_count" -eq "$expected_rule_count" ] &&
			[ "$prefix_count" -eq "$WAN_COUNT" ] &&
			[ "$safe_prefix_count" -eq "$WAN_COUNT" ] &&
			[ "$devices_present" = true ]; then
			if [ "$current_values" = true ]; then
				profile='managed'
			else
				profile='managed-stale'
			fi
		elif [ "$rule_count" -eq "$expected_rule_count" ] &&
			[ "$prefix_count" -eq "$WAN_COUNT" ] &&
			[ "$safe_prefix_count" -eq 0 ] &&
			[ "$devices_present" = true ]; then
			profile='unsafe'
		else
			profile='unexpected'
		fi
	fi

	printf '{"ok":true,"ready":%s,"interfaces":[' "$ALL_READY"
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
		[ "$first" = true ] || printf ','
		first=false
		printf '{"label":"%s","logical":"%s","device":"%s",' \
			"$label" "$logical" "$counter_device"
		printf '"expected_mask":"%s","actual_mask":"%s",' "$expected_mask" "$prefix_mask"
		printf '"state":"%s","address":"%s","prefix":"%s",' "$state" "$address" "$prefix"
		printf '"rx_bytes":%s,"tx_bytes":%s,"rx_errors":%s,"tx_errors":%s,' \
			"$rx_bytes" "$tx_bytes" "$rx_errors" "$tx_errors"
		printf '"rx_dropped":%s,"tx_dropped":%s}' "$rx_dropped" "$tx_dropped"
	done <"$WAN_FILE"
	printf '],"nat":{"table":"%s","present":%s,"wan_count":%s,' \
		"$TABLE" "$present" "$WAN_COUNT"
	printf '"rule_count":%s,"expected_rule_count":%s,"profile":"%s"}}\n' \
		"$rule_count" "$expected_rule_count" "$profile"
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
	apply_rules
	;;
status)
	emit_status
	;;
*) fail 'usage: nft-nat6.sh [apply|status]' ;;
esac
