# Changelog

## 0.0.1 - 2026-08-27

- Added UCI-driven support for 2 through 32 IPv6 WANs instead of fixed
  interface names.
- Generate N² rules for N WANs: N × (N − 1) exact cross-SNAT rules plus N
  global-unicast-scoped prefix-SNAT rules.
- Added optional egress-device and delegated-prefix-length checks, plus
  configurable address and prefix indexes.
- Added a machine-readable `status` command and dynamic managed, stale,
  unsafe, inactive, and unexpected rule profiles.
- Added a LuCI WAN configuration page, dynamic status/counters, calculated
  expected rule count, and guarded manual apply.
- Kept installation inert: no WAN is enabled by default and no firewall,
  hotplug, boot, route, mark, mwan3-policy, or proxy hook is installed.
- Added 2-, 3-, and 4+-WAN regressions, configuration validation, failure-path
  preservation tests, RPC tests, package checks, and the controlled throughput
  comparison protocol.
