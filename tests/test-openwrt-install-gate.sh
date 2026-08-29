#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
GATE="$PROJECT_ROOT/scripts/openwrt-install-gate.sh"
PAYLOADS="$PROJECT_ROOT/scripts/expected-installed-payloads.sh"

fail() {
	printf '%s\n' "test-openwrt-install-gate: FAIL: $*" >&2
	exit 1
}

[ -x "$GATE" ] || fail 'live install gate is missing or not executable'
[ -x "$PAYLOADS" ] || fail 'installed-payload manifest helper is missing or not executable'
sh -n "$GATE" || fail 'live install gate has invalid shell syntax'
sh -n "$PAYLOADS" || fail 'installed-payload helper has invalid shell syntax'
[ "$("$PAYLOADS" | wc -l | tr -d ' ')" -eq 9 ] ||
	fail 'installed-payload helper must emit exactly nine non-conffile files'
[ "$(grep -c 'apk --no-network add' "$GATE")" -eq 3 ] ||
	fail 'simulation, install, and rollback must all disable APK networking'
if grep -Fq -- '--network=' "$GATE"; then
	fail 'live gate uses an apk boolean spelling rejected by OpenWrt'
fi
grep -Fq "jsonfilter -i \"\$RUN_ROOT/post-service.json\"" "$GATE" ||
	fail 'ubus service state is not parsed as JSON'
grep -Fq "jsonfilter -i \"\$RUN_ROOT/status.json\"" "$GATE" ||
	fail 'NAT status is not parsed as JSON'
grep -Fq '@.all_ready' "$GATE" ||
	fail 'live gate does not require all configured WANs ready'
grep -Fq 'active_wan_count' "$GATE" ||
	fail 'live gate does not assert the active ready-WAN count'
if grep -Eq "grep.*(running|status\.json)|fw4[[:space:]]+reload|/etc/init.d/firewall|mwan3[[:space:]]+restart" "$GATE"; then
	fail 'live gate contains a brittle JSON grep or broad network/firewall restart'
fi
if grep -Eq '(^|[[:space:]])stat([[:space:]]|$)' "$GATE"; then
	fail 'live gate assumes an OpenWrt stat applet'
fi
grep -Fq 'cmp -s "$RUN_ROOT/pre-chain.nft" "$RUN_ROOT/post-install-chain.nft"' "$GATE" ||
	fail 'live gate does not preserve the exact handled chain during install'
grep -Fq 'sha256sum -c "$PAYLOAD_MANIFEST"' "$GATE" ||
	fail 'live gate does not verify installed payload bytes'

printf '%s\n' 'test-openwrt-install-gate: PASS'
