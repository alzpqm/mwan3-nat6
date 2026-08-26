# mwan3 N-WAN NAT6 operations guide

## Scope

`mwan3-nat6` translates IPv6 source addresses into the delegated prefix of the
WAN selected by mwan3. It supports 2 through 32 enabled WANs and creates N²
nftables rules for N WANs.

The package does not configure mwan3, policy routing, firewall includes,
hotplug, boot-time restoration, tunnels, proxies, or single-flow bonding.

## Install

Install the core package and, optionally, the LuCI package built for the target
OpenWrt release:

```sh
apk add mwan3-nat6-0.0.1-r1.apk
apk add luci-app-mwan3-nat6-0.0.1-r1.apk
```

On older opkg-based OpenWrt releases, use a matching IPK built with that
release's SDK. Do not install an artifact built for a different OpenWrt ABI.

Package installation is inert. It creates no active WAN entry and does not run
the NAT6 script.

## Configure WANs

Use **Network → mwan3 NAT6 → WAN Configuration** or edit
`/etc/config/mwan3-nat6`. Configure at least two enabled `wan` sections:

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

Options:

| Option | Required | Meaning |
|---|---|---|
| `enabled` | No | Defaults to enabled when a WAN section exists. |
| `label` | No | Display label using simple ASCII characters. |
| `interface` | Yes | IPv6 logical netifd interface used with `ifstatus`. |
| `device` | No | Expected live `l3_device`; mismatch blocks apply. |
| `expected_prefix_length` | No | Expected PD length from 1 through 64. |
| `address_index` | No | WAN global-address index, 0–15; default 0. |
| `prefix_index` | No | Delegated-prefix index, 0–15; default 0. |

Every enabled logical interface and live device must be unique. The table name
must start with a letter or underscore and contain only letters, numbers, and
underscores.

## Pre-apply checks

Back up the configuration and current table before changing production:

```sh
backup_dir="/root/mwan3-nat6-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
cp -p /etc/config/mwan3-nat6 "$backup_dir/"
nft list table inet mwan3_nat6 >"$backup_dir/mwan3_nat6.nft" 2>/dev/null || true
```

Then inspect status:

```sh
/usr/nft-nat6.sh status
mwan3 status
fw4 check
```

Do not apply until every enabled WAN reports ready and the configured mwan3
policy contains the intended IPv6 members.

## Apply and verify

```sh
/usr/nft-nat6.sh apply
/usr/nft-nat6.sh status
nft -a list chain inet mwan3_nat6 srcnat
```

For N WANs, verify:

- total `oifname` rules = N²;
- exact `snat ip6 to` rules = N × (N − 1);
- `snat ip6 prefix to` rules = N;
- every prefix rule includes `ip6 saddr 2000::/3`;
- status profile is `managed` and the rule count equals the expected count;
- interface error/drop counters and `fw4 check` remain healthy.

The script first validates all interfaces and the generated nftables batch. A
failed validation preserves the previous live chain.

## LuCI security boundary

The LuCI application has package-scoped UCI permission only for
`mwan3-nat6`. Its dedicated rpcd object exposes only `status` and `apply`.
It does not grant generic shell/file execution or permission to edit mwan3,
network, firewall, or proxy configuration.

Saving WAN configuration does not apply nftables rules automatically. Apply is
enabled only when the core status reports all configured WANs ready.

## Rollback

Before rollback, save the current state. Restore only the files and table
captured for the affected change:

```sh
cp -p /root/mwan3-nat6-backup-TIMESTAMP/mwan3-nat6 /etc/config/mwan3-nat6
nft delete table inet mwan3_nat6 2>/dev/null || true
nft -f /root/mwan3-nat6-backup-TIMESTAMP/mwan3_nat6.nft
/etc/init.d/rpcd reload
```

If the pre-change table did not exist, omit the final `nft -f` command. Never
restore an fw4 script include or an unreviewed hotplug hook as part of rollback.

## Troubleshooting

```sh
logread -e nft-nat6
/usr/nft-nat6.sh status
ifstatus YOUR_IPV6_INTERFACE
nft list table inet mwan3_nat6
```

Common blockers include fewer than two enabled WANs, a down interface, device
mismatch, missing global address or delegated prefix, duplicate interface or
device, wrong address/prefix index, and unexpected PD length.

The rules are intentionally not restored automatically after reboot or a full
nftables flush. Do not use the script as an fw4 include. Design any restoration
service as an independent, non-blocking component and test it with missing WANs,
reconnects, firewall reloads, and complete ruleset replacement.
