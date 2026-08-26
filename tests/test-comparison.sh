#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
CURRENT="$PROJECT_ROOT/openwrt/mwan3-nat6/files/usr/nft-nat6.sh"
COMPARISON="$PROJECT_ROOT/AGGREGATION_COMPARISON.md"

fail() {
	printf '%s\n' "test-comparison: FAIL: $*" >&2
	exit 1
}

[ -s "$COMPARISON" ] || fail 'comparison protocol is missing'
grep -Fq 'WAN_COUNT * WAN_COUNT' "$CURRENT" ||
	fail 'current source no longer implements the N-squared rule model'

grep -Fq 'nft -c -f "$RULE_FILE"' "$CURRENT" ||
	fail 'hardened source lacks nft validation'
grep -Fq 'ip6 saddr 2000::/3 ip6 saddr != %s snat ip6 prefix to %s' "$CURRENT" ||
	fail 'current source does not exclude link-local control traffic'
grep -Fq 'Do not deploy the historical script' "$COMPARISON" ||
	fail 'comparison protocol does not reject live deployment of legacy code'
grep -Fq 'There is not yet a controlled throughput result' "$COMPARISON" ||
	fail 'comparison protocol overstates the bandwidth evidence'

printf '%s\n' 'test-comparison: PASS'
