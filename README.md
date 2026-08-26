# mwan3 N-WAN NAT6

`mwan3-nat6` generates IPv6 source-prefix NAT rules for two or more OpenWrt
WANs. It complements mwan3: mwan3 selects an egress for each connection, while
this package translates the source into the delegated prefix routed by that
egress.

Version `0.0.1` supports 2 through 32 configured IPv6 WANs and includes an
optional LuCI application for configuration, status, counters, and guarded
manual apply.

## What it does

- Reads enabled WANs from `/etc/config/mwan3-nat6`.
- Validates every logical interface, live egress device, WAN IPv6 address, and
  delegated prefix before changing nftables.
- Generates N × (N − 1) exact cross-SNAT rules and N prefix-SNAT rules: N²
  rules for N WANs.
- Restricts prefix translation to IPv6 global-unicast sources (`2000::/3`), so
  DHCPv6 link-local and other control traffic are not translated.
- Runs `nft -c` first and replaces the complete chain in one nftables
  transaction.
- Preserves the previous live chain when configuration, WAN readiness, or rule
  validation fails.

It does not create mwan3 policies, marks, routes, firewall includes, hotplug
hooks, boot hooks, or proxy rules.

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

config wan
	option enabled '1'
	option label 'WAN 1'
	option interface 'wan1_6'
	option device 'pppoe-provider-a'
	option expected_prefix_length '56'
	option address_index '0'
	option prefix_index '0'

config wan
	option enabled '1'
	option label 'WAN 2'
	option interface 'wan2_6'
	option device 'pppoe-provider-b'
	option expected_prefix_length '60'
	option address_index '0'
	option prefix_index '0'
```

`device` and `expected_prefix_length` are optional safety checks. If omitted,
the script accepts the current `l3_device` and delegated-prefix length reported
by netifd. Address and prefix indexes default to zero and support values 0–15.

Logical interfaces and live egress devices must be unique. Each enabled WAN
must expose a global IPv6 address and a delegated prefix with length 1–64.

## Status and apply

Check without changing live rules:

```sh
/usr/nft-nat6.sh status
```

Apply only after every enabled WAN is ready:

```sh
/usr/nft-nat6.sh apply
```

Calling the script without an argument is equivalent to `apply` for backward
compatibility. LuCI calls the same guarded entry point and never bypasses its
validation.

For N enabled WANs, the expected rule count is N²:

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

The OpenWrt package recipes are under `openwrt/mwan3-nat6/` and
`openwrt/luci-app-mwan3-nat6/`. Both are architecture-independent packages.
The core package declares direct dependencies on UCI, jsonfilter, netifd,
nftables, and nft NAT support.

## Operational safety

Do not register `/usr/nft-nat6.sh` as an fw4 script include. A temporarily
missing WAN would make strict validation return nonzero and could make a
firewall reload fail. This release intentionally uses guarded manual apply.

The nftables table is volatile across reboot or a complete ruleset flush. Any
future automatic restoration service must be independent from firewall reload,
non-blocking when WANs are unavailable, and tested separately.

See [NAT6_HANDOFF.md](NAT6_HANDOFF.md) for installation, verification, and
rollback procedures. See
[AGGREGATION_COMPARISON.md](AGGREGATION_COMPARISON.md) for an evidence-bounded
multi-WAN throughput test protocol.

## License

GPL-3.0-only. See [LICENSE](LICENSE).
