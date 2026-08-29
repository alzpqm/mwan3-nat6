# mwan3 N-WAN NAT6 operations guide

## Scope

`mwan3-nat6` translates IPv6 source addresses into the delegated prefix of the
WAN selected by mwan3. It supports 2 through 32 configured WANs and creates N²
nftables rules for the N currently ready WANs.

The package does not configure mwan3 members/policies or route-table entries,
change weights, reconnect PPP, install firewall includes/netifd hotplug hooks,
create tunnels/proxies, or provide single-flow bonding. Its independent renewal
service and router-local device-bound compatibility rules are opt-in.

## Install

Install the core package and, optionally, the LuCI package built for the target
OpenWrt release:

```sh
apk --no-network add mwan3-nat6-0.0.28-r1.apk
apk --no-network add luci-app-mwan3-nat6-0.0.28-r1.apk
```

On older opkg-based OpenWrt releases, use a matching IPK built with that
release's SDK. Do not install an artifact built for a different OpenWrt ABI.

Package installation creates no active WAN entry and does not run the NAT6
script. The installed procd service remains inert because `monitor` defaults to
`0`.

## Failed-version quarantine

Treat every package version as a single-use certification candidate. If any
build, installation, migration, assertion, or live test fails, keep its logs
and artifacts with a descriptive `rejected-*` suffix, increment the patch
version, and run the complete validation sequence again. Never rebuild or
retest a corrected artifact under a version that has already failed.

Raw nft chain dumps can contain dynamic `counter packets` and `bytes` values.
For refusal tests, normalize only those numeric counter values with
`scripts/normalize-nft-chain.sh` before comparison. Keep expressions, comments,
and handles in the comparison so a real rule replacement still fails the test.

OpenWrt images may not include a `stat` applet. Verify a transferred test
helper with `test -x /tmp/helper.sh`; do not assume GNU `stat -c` exists.

## Configure WANs

Use **Network → mwan3 NAT6 → WAN Configuration** or edit
`/etc/config/mwan3-nat6`. Configure at least two enabled `wan` sections:

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

Options:

| Option | Required | Meaning |
|---|---|---|
| `monitor` | No | Enable the independent renewal service; default 0. |
| `interval` | No | Poll interval, 5–3600 seconds; default 15. |
| `debounce` | No | Identical ready samples required, 1–10; default 2. |
| `refresh_mwan3_after_nat` | No | Advanced opt-in changed-tracker refresh; default 0. |
| `pin_local_icmp` | No | Initial device-bound RPDB lookup plus exact WAN-GUA ICMPv6 bypass rules; default 0. |
| `enabled` | No | Defaults to enabled when a WAN section exists. |
| `label` | No | Display label using simple ASCII characters. |
| `interface` | Yes | IPv6 logical netifd interface used with `ifstatus`. |
| `device` | No | Expected live `l3_device`; mismatch blocks apply. |
| `expected_prefix_length` | No | Expected GUA PD length from 3 through 64. |
| `address_index` | No | WAN global-address index, 0–15; default 0. |
| `prefix_index` | No | Delegated-prefix index, 0–15; default 0. |

Every enabled logical interface and live device must be unique. The table name
must start with a letter or underscore and contain only letters, numbers, and
underscores. A live/expected Linux device name may use at most 15 characters.
WAN addresses and prefix bases must be syntactically valid members of
`2000::/3`; ULA/link-local values are rejected before any nft call.

## Pre-apply checks

Back up the configuration and current table before changing production:

```sh
backup_dir="/root/mwan3-nat6-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
cp -p /etc/config/mwan3-nat6 "$backup_dir/"
cp -p /etc/init.d/mwan3-nat6 "$backup_dir/" 2>/dev/null || true
nft list table inet mwan3_nat6 >"$backup_dir/mwan3_nat6.nft" 2>/dev/null || true
```

Then inspect status:

```sh
/usr/nft-nat6.sh status
mwan3 status
fw4 check
```

For routine degraded failover, apply may use the safe ready subset. For release
certification or policy comparison, require every enabled WAN ready and confirm
the configured mwan3 policy contains all intended IPv6 members.

## Apply and verify

```sh
/usr/nft-nat6.sh apply
/usr/nft-nat6.sh status
nft -a list chain inet mwan3_nat6 srcnat
```

For N ready WANs, verify:

- total `oifname` rules = N²;
- exact `snat ip6 to` rules = N × (N − 1);
- `snat ip6 prefix to` rules = N;
- every prefix rule includes `ip6 saddr 2000::/3`;
- status profile is `managed` and the rule count equals the expected count;
- every expected egress/source/address/prefix tuple exists exactly once and no
  extra handled rule exists;
- configured, active and inactive WAN counts match the intended state;
- `policy_ready` is true for trackers in the active subset;
- interface error/drop counters and `fw4 check` remain healthy.

If `pin_local_icmp=1`, also verify `local_icmp.profile=managed`, its rule count
equals the number of ready WANs, every rule matches one exact WAN GUA plus
ICMPv6 echo request, and the chain is `type route hook output priority -140`.
It must contain no `oifname`, prefix, TCP/UDP or forwarded-traffic match.
The bypass mark comes from the active `/var/run/mwan3/mmx_mask`; UCI and
`0x3f00` are used only when that runtime file is absent.

Also require `routing_rule_count` and `expected_routing_rule_count` to equal the
ready-WAN count. Each tagged protocol-242 rule at priority 1500 must map one
exact ready PPP device through `oif` to the unique numeric mwan3 table whose
IPv6 default route uses that device. Priority 1500 must precede mwan3's fwmark
lookup rules. Missing/ambiguous mappings or another rule at that priority for
the same device must make Apply fail and restore the prior tagged set.

The script first validates all interfaces, then validates required object
creation and all generated rules as one nftables batch. A failed validation
preserves the previous live chain and does not leave an empty table or chain.
If package removal or downgrade is required, its pre-deinstall invokes
`/usr/nft-nat6.sh cleanup-policy` so tagged RPDB rules do not survive the code
that owns them.

## Optional automatic renewal

Enable monitoring only after manual status/apply verification:

```sh
uci set mwan3-nat6.globals.monitor='1'
uci set mwan3-nat6.globals.interval='15'
uci set mwan3-nat6.globals.debounce='2'
uci set mwan3-nat6.globals.refresh_mwan3_after_nat='0'
uci commit mwan3-nat6
/etc/init.d/mwan3-nat6 restart
/etc/init.d/mwan3-nat6 status
```

The service acts only after identical ready-subset snapshots. It repairs `inactive`,
`managed-stale`, and recognized historical `unsafe` profiles, but refuses an
`unexpected` chain. Down/unavailable WANs are removed from the active subset
after debounce and restored after recovery. It never calls fw4. With the
default-off compatibility refresh enabled, it runs `mwan3 ifup` only for changed logical
interfaces that also exist as mwan3 interface sections; it does not reconnect
PPP or restart all of mwan3. mwan3 signals only that tracker with USR2; its
existing process reruns `firstconnect()` and source lookup, so verify a stable
PID plus refreshed state rather than expecting process replacement.

## LuCI security boundary

The LuCI application has package-scoped UCI permission only for
`mwan3-nat6`. Its dedicated rpcd object exposes only `status` and `apply`.
It does not grant generic shell/file execution or permission to edit mwan3,
network, firewall, or proxy configuration.

Saving WAN configuration does not bypass guarded core validation. Apply is
enabled when at least one WAN is ready and all safety checks pass. LuCI also
shows whether each existing mwan3 tracker is online and its score.

## Rollback

Before rollback, save the current state. Restore only the files and table
captured for the affected change:

```sh
cp -p /root/mwan3-nat6-backup-TIMESTAMP/mwan3-nat6 /etc/config/mwan3-nat6
/etc/init.d/mwan3-nat6 stop
nft delete table inet mwan3_nat6 2>/dev/null || true
nft -f /root/mwan3-nat6-backup-TIMESTAMP/mwan3_nat6.nft
/etc/init.d/rpcd reload
```

If the pre-change table did not exist, omit the final `nft -f` command. Never
restore an fw4 script include or an unreviewed hotplug hook as part of rollback.

## Troubleshooting

```sh
logread -e nft-nat6
logread -e mwan3-nat6-watch
/usr/nft-nat6.sh status
ifstatus YOUR_IPV6_INTERFACE
nft list table inet mwan3_nat6
```

Common blockers include fewer than two configured WANs, no ready interface,
overlength/device mismatch, non-GUA or malformed address/prefix, duplicate
interface/device, wrong array index, and unexpected PD length. `ready=true`
means at least one safe ready-WAN subset is usable; `degraded=true` means one or
more configured WANs are excluded. `policy_ready=false` identifies a tracker in
the active subset that is not online.

Do not use the script as an fw4 include. With monitoring disabled, rules are not
restored after reboot/full flush. With monitoring enabled, the independent
service restores them only after stable readiness. Test missing-WAN, PD renewal,
reboot, firewall/OpenClash reload, and full-flush behavior on each deployment.

The generated nft prefix SNAT is stateful. It is not stateless,
checksum-neutral RFC 6296 NPTv6 and does not create inbound 1:1 translation.
