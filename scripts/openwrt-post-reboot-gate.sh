#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
	printf '%s\n' "usage: $0 VERSION BACKUP_DIR PAYLOAD_MANIFEST" >&2
	exit 2
fi

VERSION="$1"
BACKUP_DIR="$2"
PAYLOAD_MANIFEST="$3"
RUN_ROOT="$BACKUP_DIR/post-reboot-$VERSION"

fail() {
	printf '%s\n' "openwrt-post-reboot-gate: ERROR: $*" >&2
	exit 1
}

assert_eq() {
	expected="$1"
	actual="$2"
	label="$3"
	[ "$actual" = "$expected" ] ||
		fail "$label: expected '$expected', got '$actual'"
}

report_timeout() {
	latest_status="$1"
	if /etc/init.d/mwan3-nat6 running; then
		watcher_state=running
	else
		watcher_state=not-running
	fi
	printf 'openwrt-post-reboot-gate: timeout watcher=%s\n' "$watcher_state" >&2
	[ -s "$latest_status" ] || {
		printf '%s\n' 'openwrt-post-reboot-gate: timeout status JSON is unavailable' >&2
		return 0
	}
	timeout_ready="$(jsonfilter -i "$latest_status" -e '@.ready' 2>/dev/null || true)"
	timeout_all_ready="$(jsonfilter -i "$latest_status" -e '@.all_ready' 2>/dev/null || true)"
	timeout_policy="$(jsonfilter -i "$latest_status" -e '@.policy_ready' 2>/dev/null || true)"
	timeout_profile="$(jsonfilter -i "$latest_status" -e '@["nat"]["profile"]' 2>/dev/null || true)"
	timeout_wans="$(jsonfilter -i "$latest_status" -e '@["nat"]["wan_count"]' 2>/dev/null || true)"
	timeout_active="$(jsonfilter -i "$latest_status" -e '@["nat"]["active_wan_count"]' 2>/dev/null || true)"
	printf 'openwrt-post-reboot-gate: timeout ready=%s all_ready=%s policy_ready=%s profile=%s wan_count=%s active_wan_count=%s\n' \
		"${timeout_ready:-unknown}" "${timeout_all_ready:-unknown}" "${timeout_policy:-unknown}" \
		"${timeout_profile:-unknown}" "${timeout_wans:-unknown}" \
		"${timeout_active:-unknown}" >&2
	case "$timeout_wans" in ''|*[!0-9]*) return 0 ;; esac
	timeout_index=0
	while [ "$timeout_index" -lt "$timeout_wans" ]; do
		logical="$(jsonfilter -i "$latest_status" -e "@[\"interfaces\"][$timeout_index][\"logical\"]" 2>/dev/null || true)"
		interface_state="$(jsonfilter -i "$latest_status" -e "@[\"interfaces\"][$timeout_index][\"state\"]" 2>/dev/null || true)"
		tracker_state="$(jsonfilter -i "$latest_status" -e "@[\"interfaces\"][$timeout_index][\"tracker\"][\"state\"]" 2>/dev/null || true)"
		tracker_score="$(jsonfilter -i "$latest_status" -e "@[\"interfaces\"][$timeout_index][\"tracker\"][\"score\"]" 2>/dev/null || true)"
		if [ -n "$logical" ] && ifstatus "$logical" \
			>"$RUN_ROOT/ifstatus-$timeout_index.json" \
			2>"$RUN_ROOT/ifstatus-$timeout_index.stderr"; then
			ifstatus_rc=0
		else
			ifstatus_rc=$?
		fi
		printf 'openwrt-post-reboot-gate: timeout interface=%s state=%s tracker=%s score=%s ifstatus_rc=%s\n' \
			"${logical:-unknown}" "${interface_state:-unknown}" \
			"${tracker_state:-unknown}" "${tracker_score:-unknown}" \
			"$ifstatus_rc" >&2
		timeout_index=$((timeout_index + 1))
	done
}

case "$VERSION" in
	''|*[!0-9.]*) fail 'unsafe version string' ;;
esac
for required in "$BACKUP_DIR/pre-reboot-boot-id.txt" \
	"$BACKUP_DIR/pre-reboot-fingerprint" "$BACKUP_DIR/mwan3-nat6.uci" \
	"$BACKUP_DIR/mwan3.uci" "$BACKUP_DIR/network.uci" \
	"$BACKUP_DIR/firewall.uci" "$PAYLOAD_MANIFEST"; do
	[ -s "$required" ] || fail "missing persistent evidence: $required"
done
[ ! -e "$RUN_ROOT" ] || fail "post-reboot evidence directory exists: $RUN_ROOT"
mkdir -m 0700 "$RUN_ROOT"

pre_boot_id="$(cat "$BACKUP_DIR/pre-reboot-boot-id.txt")"
post_boot_id="$(cat /proc/sys/kernel/random/boot_id)"
[ -n "$pre_boot_id" ] && [ -n "$post_boot_id" ] || fail 'boot ID is empty'
[ "$post_boot_id" != "$pre_boot_id" ] || fail 'boot ID did not change'
printf '%s\n' "$post_boot_id" >"$RUN_ROOT/boot-id.txt"

i=0
while :; do
	i=$((i + 1))
	if /usr/nft-nat6.sh status >"$RUN_ROOT/status-poll-$i.json" 2>/dev/null; then
		ready="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@.ready')"
		all_ready="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@.all_ready')"
		policy="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@.policy_ready')"
		profile="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@["nat"]["profile"]')"
		rules="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@["nat"]["rule_count"]')"
		expected_rules="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@["nat"]["expected_rule_count"]')"
		configured_wans="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@["nat"]["wan_count"]')"
		active_wans="$(jsonfilter -i "$RUN_ROOT/status-poll-$i.json" -e '@["nat"]["active_wan_count"]')"
		if [ "$ready" = true ] && [ "$all_ready" = true ] && [ "$policy" = true ] &&
			[ "$profile" = managed ] && [ "$configured_wans" = "$active_wans" ] &&
			[ "$rules" = "$expected_rules" ] && /etc/init.d/mwan3-nat6 running; then
			break
		fi
	fi
	if [ "$i" -ge 36 ]; then
		report_timeout "$RUN_ROOT/status-poll-$i.json"
		fail 'ready/managed/running state not reached within 180 seconds'
	fi
	sleep 5
done
cp "$RUN_ROOT/status-poll-$i.json" "$RUN_ROOT/status-final.json"

apk list --installed >"$RUN_ROOT/installed-packages.txt" 2>&1
grep -q "^mwan3-nat6-$VERSION-r1 " "$RUN_ROOT/installed-packages.txt" ||
	fail 'expected core package version is not installed'
grep -q "^luci-app-mwan3-nat6-$VERSION-r1 " "$RUN_ROOT/installed-packages.txt" ||
	fail 'expected LuCI package version is not installed'
cmp -s "$BACKUP_DIR/mwan3-nat6.uci" /etc/config/mwan3-nat6 || fail 'project UCI changed across reboot'
cmp -s "$BACKUP_DIR/mwan3.uci" /etc/config/mwan3 || fail 'mwan3 UCI changed across reboot'
cmp -s "$BACKUP_DIR/network.uci" /etc/config/network || fail 'network UCI changed across reboot'
cmp -s "$BACKUP_DIR/firewall.uci" /etc/config/firewall || fail 'firewall UCI changed across reboot'
sha256sum -c "$PAYLOAD_MANIFEST" >"$RUN_ROOT/payload-check.txt"

/etc/init.d/mwan3-nat6 enabled || fail 'project watcher is not enabled after reboot'
/etc/init.d/mwan3-nat6 running || fail 'project watcher is not running after reboot'
ubus call service list '{"name":"mwan3-nat6"}' >"$RUN_ROOT/service.json"
assert_eq true "$(jsonfilter -i "$RUN_ROOT/service.json" -e '@["mwan3-nat6"]["instances"]["instance1"]["running"]')" 'ubus running'
assert_eq /usr/sbin/mwan3-nat6-watch "$(jsonfilter -i "$RUN_ROOT/service.json" -e '@["mwan3-nat6"]["instances"]["instance1"]["command"][0]')" 'ubus command'

wan_count="$(jsonfilter -i "$RUN_ROOT/status-final.json" -e '@["nat"]["wan_count"]')"
case "$wan_count" in ''|*[!0-9]*) fail 'invalid post-reboot WAN count' ;; esac
[ "$wan_count" -ge 2 ] || fail 'post-reboot WAN count is below two'
index=0
while [ "$index" -lt "$wan_count" ]; do
	tracker_state="$(jsonfilter -i "$RUN_ROOT/status-final.json" -e "@[\"interfaces\"][$index][\"tracker\"][\"state\"]")"
	tracker_score="$(jsonfilter -i "$RUN_ROOT/status-final.json" -e "@[\"interfaces\"][$index][\"tracker\"][\"score\"]")"
	assert_eq online "$tracker_state" "tracker $index state"
	assert_eq 10 "$tracker_score" "tracker $index score"
	index=$((index + 1))
done

/usr/nft-nat6.sh fingerprint >"$RUN_ROOT/fingerprint-current"
cmp -s "$RUN_ROOT/fingerprint-current" /var/run/mwan3-nat6.applied ||
	fail 'post-reboot applied fingerprint is not current'
awk -F '|' '
	NR == FNR { if ($1 == "wan") old[$2] = $0; next }
	$1 == "wan" && old[$2] != $0 { print $2 }
' "$BACKUP_DIR/pre-reboot-fingerprint" "$RUN_ROOT/fingerprint-current" >"$RUN_ROOT/changed-logicals.txt"

logread | grep -F 'mwan3-nat6-watch:' >"$RUN_ROOT/watcher.log" || true
grep -Fq 'renewed NAT6 after 2 stable samples' "$RUN_ROOT/watcher.log" ||
	fail 'boot log lacks debounced NAT renewal'
if grep -Fq 'refreshed mwan3 interface ' "$RUN_ROOT/watcher.log"; then
	fail 'default-off compatibility mode unexpectedly refreshed mwan3'
fi

fw4 check >"$RUN_ROOT/fw4-check.txt" 2>&1
mwan3 status >"$RUN_ROOT/mwan3-status.txt"
mwan3 policies >"$RUN_ROOT/mwan3-policies.txt"
[ ! -e "$BACKUP_DIR/recovery-install-$VERSION.log" ] ||
	fail 'install recovery log exists unexpectedly'

printf 'PRE_BOOT_ID=%s\n' "$pre_boot_id"
printf 'POST_BOOT_ID=%s\n' "$post_boot_id"
printf 'READY_POLL_COUNT=%s\n' "$i"
printf '%s\n' 'CHANGED_LOGICALS:'
sed -n '1,64p' "$RUN_ROOT/changed-logicals.txt"
cat "$RUN_ROOT/payload-check.txt"
cat "$RUN_ROOT/watcher.log"
cat "$RUN_ROOT/status-final.json"; echo
printf '%s\n' "openwrt-post-reboot-gate: PASS ($VERSION)"
