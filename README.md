# mwan3 N-WAN NAT6

`mwan3-nat6` generates IPv6 source-prefix NAT rules for two or more OpenWrt
WANs. It complements mwan3: mwan3 selects an egress for each connection, while
this package translates the source into the delegated prefix routed by that
egress.

Version `0.0.28` supports 2 through 32 configured IPv6 WANs and includes an
optional LuCI application for configuration, netifd/mwan3 tracker status,
counters, guarded manual apply, and opt-in renewal monitoring.

## What it does

- Reads enabled WANs from `/etc/config/mwan3-nat6`.
- Validates every configured logical interface and safety constraint before
  changing nftables. Down or unavailable WANs are excluded; malformed data or
  a configured device/prefix mismatch blocks apply.
- Generates N × (N − 1) exact cross-SNAT rules and N prefix-SNAT rules: N²
  rules for the N currently ready WANs.
- Restricts prefix translation to IPv6 global-unicast sources (`2000::/3`), so
  DHCPv6 link-local and other control traffic are not translated.
- Places any required table/chain creation and all rules in one batch, runs
  `nft -c` against that complete batch, then applies the same batch atomically.
- Compares the exact N² egress/source/address/prefix tuple set when reporting a
  managed profile; counts or token presence alone are not accepted.
- Keeps a safe ready-WAN subset active during WAN loss and expands it again
  after recovery. It preserves the previous chain on configuration, safety, or
  rule validation failure.
- Optionally watches stable netifd snapshots independently of fw4, renews stale
  NAT, and leaves mwan3 tracker refresh disabled unless explicitly opted in.
- Optionally gives router-local sockets explicitly bound to a WAN device an
  initial RPDB lookup in that WAN's dynamically verified mwan3 table. Exact
  WAN-source ICMPv6 echo requests also receive mwan3's default/bypass mark at
  the output hook. This is intended for tools such as NextTrace and is disabled
  by default.

It does not create mwan3 policies or route-table entries, change weights,
reconnect PPP, or install firewall includes, netifd hotplug hooks, or proxy
rules. The optional local-device mode owns only tagged RPDB selectors at
priority 1500. The procd renewal service is installed but stays inert while
`monitor` is `0`, its default.

The nftables `snat ip6 prefix to` operation is stateful NAT. It is not
checksum-neutral, stateless RFC 6296 NPTv6 and it does not provide inbound
1:1 translation by itself.

## Important bandwidth limitation

This package does not combine one TCP or QUIC flow across WANs. mwan3
distributes independent connections, so aggregate bandwidth can use multiple
links only when the workload has multiple flows or users. Link capacities,
weights, latency, loss, and destination behavior determine the real result.

## Configuration

The package installs an inert configuration with no WAN entries. Add at least
two entries through LuCI at **Network → mwan3 NAT6 → WAN Configuration**, or
with UCI:

```uci
config globals 'globals'
	option table 'mwan3_nat6'
	option monitor '0'
	option interval '15'
	option debounce '2'
	option refresh_mwan3_after_nat '0'
	option pin_local_icmp '0'

config wan
	option enabled '1'
	option label 'WAN 1'
	option interface 'wan1_6'
	option device 'pppoe-wan1'
	option expected_prefix_length '56'
	option address_index '0'
	option prefix_index '0'

config wan
	option enabled '1'
	option label 'WAN 2'
	option interface 'wan2_6'
	option device 'pppoe-wan2'
	option expected_prefix_length '60'
	option address_index '0'
	option prefix_index '0'
```

`device` and `expected_prefix_length` are optional safety checks. If omitted,
the script accepts the current `l3_device` and delegated-prefix length reported
by netifd. Address and prefix indexes default to zero and support values 0–15.

Logical interfaces and ready egress devices must be unique. Linux egress-device
names are limited to 15 characters. Each WAN admitted to the active subset must
expose a syntactically valid global-unicast IPv6 address and a GUA delegated
prefix with length 3–64.

### Optional router-local ICMPv6 pin

When `pin_local_icmp=1`, Apply also owns an `inet` route/output chain at
priority `-140`. For each ready WAN it matches only that WAN's exact global
address and ICMPv6 echo request, then sets the validated
active `/var/run/mwan3/mmx_mask` value, falling back to
`mwan3.globals.mmx_mask` and then mwan3's `0x3f00` default. Official mwan3
defines its default/bypass mark to equal that mask. The chain runs after the
normal mangle priority. Before that hook, Apply adds one tagged IPv6 RPDB rule
per ready WAN at priority 1500, mapping its `oif` device to the only numeric
mwan3 table whose default route uses that device. This participates in the
initial lookup made by `SO_BINDTODEVICE`, ahead of mwan3's mark rules. Ambiguous
or missing mappings and an existing rule for the same priority/device are
rejected. The `oif` selector is available only to router-local sockets bound to
a device; it cannot see forwarded LAN traffic and does not change ordinary
unbound TCP/UDP load balancing.

Leave this off unless router-local device-bound ICMP diagnostics need it. The
status `local_icmp` object reports both nft and RPDB rule counts and whether the
complete ready-WAN profile is `managed`, missing, unexpected, or disabled.

## Status and apply

Check without changing live rules:

```sh
/usr/nft-nat6.sh status
```

Apply when at least one configured WAN is ready and no safety check fails:

```sh
/usr/nft-nat6.sh apply
```

Calling the script without an argument is equivalent to `apply` for backward
compatibility. LuCI calls the same guarded entry point and never bypasses its
validation.

Status reports `active_wan_count`, `inactive_wan_count`, `all_ready`, and
`degraded`. `ready=true` means a safe subset can operate; full release/live
certification still requires `all_ready=true`. `policy_ready` covers trackers
for the active subset only.

## Optional renewal monitor

The monitor is disabled by default. Enable it through LuCI, or explicitly:

```sh
uci set mwan3-nat6.globals.monitor='1'
uci set mwan3-nat6.globals.interval='15'
uci set mwan3-nat6.globals.debounce='2'
uci set mwan3-nat6.globals.refresh_mwan3_after_nat='0'
uci commit mwan3-nat6
/etc/init.d/mwan3-nat6 restart
```

It requires identical ready-subset snapshots for the configured sample count. It may
automatically repair only `inactive`, `managed-stale`, and recognized `unsafe`
profiles; it refuses an `unexpected` chain. Down/unavailable WANs are removed
from the active rule subset after debounce and restored after recovery. The
advanced `refresh_mwan3_after_nat=1` compatibility option runs `mwan3 ifup`
only for matching interfaces whose address or prefix changed; it defaults off.
The monitor never calls fw4, reloads all mwan3, reconnects PPP, or edits weights.
Official mwan3's interface hotplug sends USR2 to only that tracker; the existing
process reruns `firstconnect()` and source-address lookup, so its PID normally
stays unchanged.

For N ready WANs, the expected rule count is N²:

| WANs | Expected rules |
|---:|---:|
| 2 | 4 |
| 3 | 9 |
| 4 | 16 |
| 5 | 25 |

## Building and testing

Run the local regression gate:

```sh
make check
```

Build the two OpenWrt 25.12+ APKs with the SDK path in the required environment
variable and the output directory as the sole positional argument:

```sh
SDK_DIR=/path/to/openwrt-sdk scripts/build-apk-on-sdk.sh /path/to/output
```

Do not pass the SDK directory as the first positional argument. The integrated
builder invokes `verify-apk-artifacts.sh` before reporting package hashes.

The OpenWrt package recipes are under `openwrt/mwan3-nat6/` and
`openwrt/luci-app-mwan3-nat6/`. Both are architecture-independent packages.
The core package declares direct dependencies on mwan3, UCI, jsonfilter,
netifd, nftables, and nft NAT support.

## Operational safety

Do not register `/usr/nft-nat6.sh` as an fw4 script include. A temporarily
missing WAN would make strict validation return nonzero and could make a
firewall reload fail. Manual Apply and the independent monitor are the only
supported update paths.

The nftables table is volatile across reboot or a complete ruleset flush. When
enabled, the monitor restores it only after WAN data is ready and stable; when
disabled, apply manually. The service remains independent from firewall reload
and non-blocking while WANs are unavailable.

See [NAT6_HANDOFF.md](NAT6_HANDOFF.md) for installation, verification, and
rollback procedures. See
[AGGREGATION_COMPARISON.md](AGGREGATION_COMPARISON.md) for an evidence-bounded
multi-WAN throughput test protocol.

## License

GPL-3.0-only. See [LICENSE](LICENSE).
