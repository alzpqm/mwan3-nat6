#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
GATE="$PROJECT_ROOT/scripts/openwrt-post-reboot-gate.sh"

fail() {
	printf '%s\n' "test-openwrt-post-reboot-gate: FAIL: $*" >&2
	exit 1
}

[ -x "$GATE" ] || fail 'post-reboot gate is missing or not executable'
sh -n "$GATE" || fail 'post-reboot gate has invalid shell syntax'
for requirement in \
	'/proc/sys/kernel/random/boot_id' \
	'cmp -s "$BACKUP_DIR/mwan3-nat6.uci" /etc/config/mwan3-nat6' \
	'sha256sum -c "$PAYLOAD_MANIFEST"' \
	'jsonfilter -i "$RUN_ROOT/service.json"' \
	'jsonfilter -i "$RUN_ROOT/status-final.json"' \
	'@.all_ready' \
	'active_wan_count' \
	'cmp -s "$RUN_ROOT/fingerprint-current" /var/run/mwan3-nat6.applied' \
	'renewed NAT6 after 2 stable samples' \
	'default-off compatibility mode unexpectedly refreshed mwan3' \
	'openwrt-post-reboot-gate: timeout interface=' \
	'ifstatus "$logical"' \
	'fw4 check' \
	'mwan3 status'; do
	grep -Fq "$requirement" "$GATE" || fail "missing post-reboot assertion: $requirement"
done
if grep -Eq '(^|[[:space:]])stat([[:space:]]|$)|nft[[:space:]]+(add|delete|flush|replace)|uci[[:space:]]+(set|commit)|apk.*[[:space:]]add|/etc/init\.d/[^[:space:]]+[[:space:]]+(start|stop|restart|reload)|(^|[[:space:]])reboot([[:space:]]|$)|mwan3[[:space:]]+ifup|fw4[[:space:]]+reload|(^|[[:space:]])kill([[:space:]]|$)' "$GATE"; then
	fail 'post-reboot gate contains a mutation or unavailable stat command'
fi

printf '%s\n' 'test-openwrt-post-reboot-gate: PASS'
