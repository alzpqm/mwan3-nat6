#!/bin/sh

set -eu

if [ "$#" -ne 9 ]; then
	printf '%s\n' "usage: $0 VERSION CORE_APK LUCI_APK ROLLBACK_DIR ROLLBACK_CORE ROLLBACK_LUCI CORE_SHA LUCI_SHA PAYLOAD_MANIFEST" >&2
	exit 2
fi

VERSION="$1"
CORE_APK="$2"
LUCI_APK="$3"
ROLLBACK_DIR="$4"
ROLLBACK_CORE="$5"
ROLLBACK_LUCI="$6"
CORE_SHA="$7"
LUCI_SHA="$8"
PAYLOAD_MANIFEST="$9"
RUN_ROOT="/tmp/mwan3-nat6-install-$VERSION"
COMPLETE=0
RECOVERING=0
MUTATION_STARTED=0

fail() {
	printf '%s\n' "openwrt-install-gate: ERROR: $*" >&2
	exit 1
}

assert_eq() {
	expected="$1"
	actual="$2"
	label="$3"
	[ "$actual" = "$expected" ] ||
		fail "$label: expected '$expected', got '$actual'"
}

file_sha() {
	line="$(sha256sum "$1")"
	printf '%s\n' "${line%% *}"
}

recover() {
	[ "$RECOVERING" -eq 0 ] || return 0
	RECOVERING=1
	set +e
	{
		printf 'RECOVERY_TIME='; date -Iseconds
		/etc/init.d/mwan3-nat6 stop 2>/dev/null || true
		apk --no-network add --allow-untrusted "$ROLLBACK_CORE" "$ROLLBACK_LUCI"
		cp -p "$ROLLBACK_DIR/mwan3-nat6.uci" /etc/config/mwan3-nat6
		nft -c -f "$ROLLBACK_DIR/rollback.nft" && nft -f "$ROLLBACK_DIR/rollback.nft"
		/etc/init.d/mwan3-nat6 enable
		/etc/init.d/mwan3-nat6 restart
		rm -f /tmp/luci-indexcache
		/etc/init.d/rpcd reload
		fw4 check
		/usr/nft-nat6.sh status
	} >"$ROLLBACK_DIR/recovery-install-$VERSION.log" 2>&1
}

on_exit() {
	rc=$?
	trap - 0
	if [ "$COMPLETE" -ne 1 ] && [ "$MUTATION_STARTED" -eq 1 ]; then
		recover
	fi
	exit "$rc"
}

case "$VERSION" in
	''|*[!0-9.]*) fail 'unsafe version string' ;;
esac
case "$CORE_SHA:$LUCI_SHA" in
	*[!0-9a-f:]*) fail 'invalid package SHA-256 characters' ;;
esac
[ "${#CORE_SHA}" -eq 64 ] || fail 'invalid core SHA-256 length'
[ "${#LUCI_SHA}" -eq 64 ] || fail 'invalid LuCI SHA-256 length'
for required in "$CORE_APK" "$LUCI_APK" "$ROLLBACK_CORE" "$ROLLBACK_LUCI" \
	"$ROLLBACK_DIR/mwan3-nat6.uci" "$ROLLBACK_DIR/rollback.nft" "$PAYLOAD_MANIFEST"; do
	[ -s "$required" ] || fail "missing required file: $required"
done
[ ! -e "$RUN_ROOT" ] || fail "evidence directory already exists: $RUN_ROOT"
mkdir -m 0700 "$RUN_ROOT"

trap on_exit 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

assert_eq "$CORE_SHA" "$(file_sha "$CORE_APK")" 'core package SHA-256'
assert_eq "$LUCI_SHA" "$(file_sha "$LUCI_APK")" 'LuCI package SHA-256'

sha256sum /etc/config/mwan3-nat6 /etc/config/mwan3 /etc/config/network \
	/etc/config/firewall >"$RUN_ROOT/pre-uci.sha256"
/usr/nft-nat6.sh status >"$RUN_ROOT/pre-status.json"
NAT_TABLE="$(jsonfilter -i "$RUN_ROOT/pre-status.json" -e '@.nat.table')"
printf '%s\n' "$NAT_TABLE" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' ||
	fail 'status returned an unsafe nft table name'
[ "$NAT_TABLE" != fw4 ] || fail 'status returned the shared fw4 table'
nft -a list chain inet "$NAT_TABLE" srcnat >"$RUN_ROOT/pre-chain.nft"
ubus call service list '{"name":"mwan3-nat6"}' >"$RUN_ROOT/pre-service.json"
pre_pid="$(jsonfilter -i "$RUN_ROOT/pre-service.json" \
	-e '@["mwan3-nat6"]["instances"]["instance1"]["pid"]' 2>/dev/null || true)"
case "$pre_pid" in
'' | *[!0-9]*) pre_pid='' ;;
esac

apk --no-network add --simulate --allow-untrusted "$CORE_APK" "$LUCI_APK" \
	>"$RUN_ROOT/simulation.txt" 2>&1
sha256sum /etc/config/mwan3-nat6 /etc/config/mwan3 /etc/config/network \
	/etc/config/firewall >"$RUN_ROOT/post-simulation-uci.sha256"
nft -a list chain inet "$NAT_TABLE" srcnat >"$RUN_ROOT/post-simulation-chain.nft"
cmp -s "$RUN_ROOT/pre-uci.sha256" "$RUN_ROOT/post-simulation-uci.sha256" ||
	fail 'simulation changed a protected UCI file'
cmp -s "$RUN_ROOT/pre-chain.nft" "$RUN_ROOT/post-simulation-chain.nft" ||
	fail 'simulation changed the handled chain'

MUTATION_STARTED=1
apk --no-network add --allow-untrusted "$CORE_APK" "$LUCI_APK" \
	>"$RUN_ROOT/install.txt" 2>&1
i=0

while :; do
	ubus call service list '{"name":"mwan3-nat6"}' >"$RUN_ROOT/service-settle.json"
	settled_running="$(jsonfilter -i "$RUN_ROOT/service-settle.json" \
		-e '@["mwan3-nat6"]["instances"]["instance1"]["running"]' 2>/dev/null || true)"
	settled_pid="$(jsonfilter -i "$RUN_ROOT/service-settle.json" \
		-e '@["mwan3-nat6"]["instances"]["instance1"]["pid"]' 2>/dev/null || true)"
	settled_command="$(jsonfilter -i "$RUN_ROOT/service-settle.json" \
		-e '@["mwan3-nat6"]["instances"]["instance1"]["command"][0]' 2>/dev/null || true)"
	case "$settled_pid" in
	'' | *[!0-9]*) settled_pid='' ;;
	esac
	if [ "$settled_running" = true ] && [ -n "$settled_pid" ] &&
		[ "$settled_command" = /usr/sbin/mwan3-nat6-watch ] &&
		{ [ -z "$pre_pid" ] || [ "$settled_pid" != "$pre_pid" ]; }; then
		break
	fi
	i=$((i + 1))
	[ "$i" -lt 15 ] || fail 'project watcher did not complete its post-upgrade restart'
	sleep 1
done

apk list --installed >"$RUN_ROOT/installed-packages.txt" 2>&1
grep -q "^mwan3-nat6-$VERSION-r1 " "$RUN_ROOT/installed-packages.txt" ||
	fail 'expected core package version is not installed'
grep -q "^luci-app-mwan3-nat6-$VERSION-r1 " "$RUN_ROOT/installed-packages.txt" ||
	fail 'expected LuCI package version is not installed'

sha256sum /etc/config/mwan3-nat6 /etc/config/mwan3 /etc/config/network \
	/etc/config/firewall >"$RUN_ROOT/post-install-uci.sha256"
nft -a list chain inet "$NAT_TABLE" srcnat >"$RUN_ROOT/post-install-chain.nft"
cmp -s "$RUN_ROOT/pre-uci.sha256" "$RUN_ROOT/post-install-uci.sha256" ||
	fail 'installation changed a protected UCI file'
cmp -s "$RUN_ROOT/pre-chain.nft" "$RUN_ROOT/post-install-chain.nft" ||
	fail 'installation changed the handled chain'
sha256sum -c "$PAYLOAD_MANIFEST" >"$RUN_ROOT/payload-check.txt"

/etc/init.d/mwan3-nat6 enabled || fail 'project watcher is not enabled'
/etc/init.d/mwan3-nat6 running || fail 'project watcher is not running'
ubus call service list '{"name":"mwan3-nat6"}' >"$RUN_ROOT/post-service.json"
assert_eq true "$(jsonfilter -i "$RUN_ROOT/post-service.json" -e '@["mwan3-nat6"]["instances"]["instance1"]["running"]')" 'ubus running'
assert_eq /usr/sbin/mwan3-nat6-watch "$(jsonfilter -i "$RUN_ROOT/post-service.json" -e '@["mwan3-nat6"]["instances"]["instance1"]["command"][0]')" 'ubus command'
assert_eq "$settled_pid" "$(jsonfilter -i "$RUN_ROOT/post-service.json" -e '@["mwan3-nat6"]["instances"]["instance1"]["pid"]')" 'stable post-upgrade watcher PID'

/usr/nft-nat6.sh status >"$RUN_ROOT/status.json"
assert_eq true "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@.ok')" 'status ok'
assert_eq true "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@.ready')" 'status ready'
assert_eq true "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@.all_ready')" 'status all_ready'
assert_eq false "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@.degraded')" 'status degraded'
assert_eq true "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@.policy_ready')" 'status policy_ready'
assert_eq managed "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@["nat"]["profile"]')" 'NAT profile'
assert_eq 3 "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@["nat"]["wan_count"]')" 'configured WAN count'
assert_eq 3 "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@["nat"]["active_wan_count"]')" 'active WAN count'
assert_eq 0 "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@["nat"]["inactive_wan_count"]')" 'inactive WAN count'
assert_eq 9 "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@["nat"]["rule_count"]')" 'NAT rule count'
assert_eq 9 "$(jsonfilter -i "$RUN_ROOT/status.json" -e '@["nat"]["expected_rule_count"]')" 'expected NAT rule count'

fw4 check >"$RUN_ROOT/fw4-check.txt" 2>&1
mwan3 status >"$RUN_ROOT/mwan3-status.txt"
mwan3 policies >"$RUN_ROOT/mwan3-policies.txt"

COMPLETE=1
printf 'INSTALL_TIME='; date -Iseconds
cat "$RUN_ROOT/simulation.txt"
cat "$RUN_ROOT/install.txt"
cat "$RUN_ROOT/payload-check.txt"
cat "$RUN_ROOT/status.json"; echo
printf '%s\n' "openwrt-install-gate: PASS ($VERSION)"
