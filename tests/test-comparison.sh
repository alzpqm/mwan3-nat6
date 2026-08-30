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
grep -Fq 'READY_WAN_COUNT * READY_WAN_COUNT' "$CURRENT" ||
	fail 'current source no longer implements the ready-subset N-squared rule model'

grep -Fq 'nft -c -f "$RULE_FILE"' "$CURRENT" ||
	fail 'hardened source lacks nft validation'
grep -Fq 'ip6 saddr 2000::/3 ip6 saddr != %s snat ip6 prefix to %s' "$CURRENT" ||
	fail 'current source does not exclude link-local control traffic'
grep -Fq '不得部署歷史舊腳本' "$COMPARISON" ||
	fail 'comparison protocol does not reject live deployment of legacy code'
grep -Fq '目前還沒有任何特定雙 WAN、三 WAN 或更多 WAN 部署的完整對照效能結果' "$COMPARISON" ||
	fail 'comparison protocol overstates the bandwidth evidence'

printf '%s\n' 'test-comparison: PASS'
