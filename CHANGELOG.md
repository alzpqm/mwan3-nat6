# Changelog

## 0.0.28 - 2026-08-29

- Replace the insufficient output-hook-only NextTrace workaround with an
  initial-route fix: one tagged IPv6 RPDB `oif` rule per ready WAN selects that
  WAN's dynamically verified mwan3 table before mwan3 fwmark rules.
- Keep the exact-GUA ICMPv6 output mark as a second-stage guard. The new RPDB
  selector applies only to router-local sockets explicitly bound to a device;
  forwarded LAN traffic and ordinary unbound mwan3 balancing are unchanged.
- Reject missing/ambiguous mwan3 table mappings and priority/oif conflicts,
  expose exact RPDB health in status/LuCI, restore the prior policy set if nft
  application fails, and clean tagged rules during package removal/downgrade.
- Seal 0.0.26: all three live traces reached the destination, but two WANs still
  emitted initial `sendto: network is unreachable` before reaching the nft
  output hook.
- Generalize private production WAN labels retained in historical public
  changelog entries; exact deployment identifiers remain only in private
  operator evidence.

## 0.0.27 - 2026-08-29 (not published)

- Implemented and locally validated the RPDB initial-route repair carried into
  0.0.28.
- The anonymous public-source scan found private production WAN labels in the
  changelog before any archive or APK was created. Certification therefore
  continues only as 0.0.28.

## 0.0.26 - 2026-08-29

- Accept nft's normalized omission of redundant `meta l4proto ipv6-icmp` when
  listing an `icmpv6 type echo-request` rule.
- Require every local pin rule to match the complete exact-safe shape and
  validate the owned chain as route/output priority -140 (`mangle + 10`).

## 0.0.25 - 2026-08-29 (not published)

- Carry forward the exact local-ICMPv6 source-pin repair after 0.0.24 passed
  source gates but invoked the SDK builder with the wrong calling convention.
- Call the inspected builder as `SDK_DIR=/path build-apk-on-sdk.sh OUTPUT_DIR`.
- Local, Debian, artifact and install gates passed. Live Apply created the
  intended rules, but status rejected nft's equivalent normalized display and
  triggered a successful automatic rollback to 0.0.22 before NextTrace.
  Corrected certification continues only as 0.0.26.

## 0.0.24 - 2026-08-29 (not published)

- Carry forward the opt-in exact router-local ICMPv6 source-pin repair after
  sealing 0.0.23 during anonymous-source preparation.
- Validate anonymous USTAR ownership using BSD tar's actual uid/user/group
  columns instead of a GNU-style owner rendering assumption.
- Local and Debian source gates passed, but package construction never started
  because the caller supplied SDK as a positional argument instead of the
  required `SDK_DIR` environment variable. No APK exists; corrected
  certification continues only as 0.0.25.

## 0.0.23 - 2026-08-29 (not published)

- Add an opt-in router-local ICMPv6 source pin for device-bound diagnostics
  such as NextTrace. It matches only exact configured WAN GUAs and ICMPv6 echo
  requests in an OUTPUT route chain after competing mangle marks, then sets
  mwan3's validated default/bypass mark.
- Keep the option disabled by default. It creates no policy route, does not
  match forwarded LAN traffic, does not alter mwan3 weights or configuration,
  and leaves the N² postrouting prefix-NAT rules unchanged.
- Expose pin enablement, exact rule count, mark and managed profile through the
  core status JSON and LuCI. WAN renewals atomically refresh both owned chains.
- Local source gates passed, but the anonymous-source wrapper incorrectly
  parsed BSD tar ownership columns and exited 1. Its source archive was in fact
  uid0/root/root and private-data-free; monotonic policy nevertheless seals the
  version. Corrected certification continues only as 0.0.24.

## 0.0.22 - 2026-08-28

- Carry forward the locally and SDK-verified ready-subset implementation after
  sealing 0.0.21 during installation preparation.
- Consume the existing installed-payload manifest helper output directly.

## 0.0.21 - 2026-08-28 (not published)

- Carry forward the locally passing ready-subset implementation after sealing
  0.0.20 before its remote source gate.
- Run the SDK stage through a positional-argument stdin script, avoiding nested
  SSH quoting of awk and shell positional parameters.
- Local/SDK/artifact verification passed, but install staging misread complete
  payload-manifest rows as bare paths. No target upload/install occurred; APKs
  are rejected and certification continues only as 0.0.22.

## 0.0.20 - 2026-08-28 (not published)

- Carry forward ready-subset operation and the default-off renamed tracker
  refresh option after sealing 0.0.19.
- Align the aggregation comparison contract with ready-WAN N² calculation.
- Exclude router reboot and manual PPP reconnection from this certification;
  reboot testing requires separate explicit operator approval.
- Local tests passed, but the SDK wrapper exposed a remote awk `$1` to local
  `set -u` and exited before remote tests/build. No APK was produced; corrected
  certification continues only as 0.0.21.

## 0.0.19 - 2026-08-28 (not published)

- Keep prefix NAT active for the current ready subset instead of coupling every
  configured WAN to one all-or-nothing rule set. Configuration still requires
  at least two WANs; runtime failover may safely retain one ready WAN.
- Report configured, active and inactive WAN counts plus explicit degraded
  state; certify releases only when all configured WANs are active.
- Replace the inherited default-on tracker refresh control with the new
  `refresh_mwan3_after_nat` compatibility option, default off.
- Local package, core, watcher and LuCI tests passed, but the comparison test
  retained an obsolete configured-WAN literal. No APK was built; corrected
  certification continues only as 0.0.20.

## 0.0.18 - 2026-08-28 (not published)

- Restart full certification after the 0.0.17 reboot left an upstream PPPoE WAN
  without PADO responses for the entire post-reboot gate window.
- Its all-WAN refusal removed NAT from two healthy WANs when a third WAN was
  unavailable. APKs are rejected; corrected work continues only as 0.0.19.

## 0.0.17 - 2026-08-28 (not published)

- Restart full certification after the 0.0.16 missing-WAN test sampled a
  retiring watcher PID immediately after a procd restart.
- Require a different post-restart PID and two consecutive stable PID samples
  before beginning missing-WAN watcher-stability timing.
- All pre-reboot gates passed, but one external PPPoE discovery never received
  PADO after reboot, leaving its IPv6 member unavailable and NAT intentionally
  absent.
  Its APKs are rejected; certification continues as 0.0.18.

## 0.0.16 - 2026-08-28 (not published)

- Restart certification after the 0.0.15 private preflight piped from quiet
  grep, making its negative APK-mutation assertion ineffective.
- Validate target scripts with independent exact line counts and no quiet-grep
  pipelines.
- Local/SDK/install/unexpected gates passed, but missing-WAN certification hit
  a watcher-PID sampling race and recovered cleanly. Its APKs are rejected;
  corrected full certification continues as 0.0.17.

## 0.0.15 - 2026-08-28 (not published)

- Restart certification after the 0.0.14 private rollback-script scanner
  misclassified quoted rollback documentation as live mutation commands.
- Anchor target-script mutation scans to executable line starts while retaining
  the exact unavailable-`stat` rejection.
- The revised preflight still contained an ineffective quiet-grep pipeline. No
  router contact or APK build occurred; certification continues as 0.0.16.

## 0.0.14 - 2026-08-28 (not published)

- Restart full certification after the 0.0.13 rollback gate repeated a known
  unavailable-`stat` probe before any backup or installation action.
- Require long target procedures to be transferred, syntax-checked scripts and
  scan them for unavailable/mutating commands before execution.
- The first private-script preflight produced a scanner false-positive before
  router contact or APK build. Corrected full certification continues only as
  0.0.15.

## 0.0.13 - 2026-08-28 (not published)

- Restart full certification after the 0.0.12 Debian command repeated a nested
  remote-shell/awk interpolation error before source extraction or APK build.
- Verify transferred source archives with a generated checksum file and
  `sha256sum -c`, eliminating remote awk-field interpolation.
- Local and Debian gates passed, but rollback preparation called unavailable
  `stat` before backing up or installing. Its APKs are rejected; corrected full
  certification continues only as 0.0.14.

## 0.0.12 - 2026-08-28 (not published)

- Restart full certification under a fresh version after the 0.0.11 local test
  execution session disappeared before its complete output and exit code could
  be collected.
- Run short local suites as a single foreground result and retain the
  transferred, syntax/contract-tested post-reboot gate introduced in 0.0.11.
- Local gates passed, but the first Debian build command expanded awk `$1` in
  the remote shell and stopped before extraction. No APK was built; corrected
  certification continues only as 0.0.13.

## 0.0.11 - 2026-08-28 (not published)

- Continue certification under a fresh version after the 0.0.10 combined
  post-reboot SSH audit ended with an unterminated-quote syntax error.
- Add a transferred, syntax/contract-tested, read-only post-reboot gate for boot
  ID, packages, protected UCI, payloads, procd/status JSON, fingerprints,
  renewal logs, fw4, and mwan3 evidence.
- The first full local test session disappeared before its final output and exit
  code could be collected. Its partial PASS output is insufficient; its APKs
  were never built, and corrected certification continues only as 0.0.12.

## 0.0.10 - 2026-08-28 (not published)

- Continue certification under a fresh version after apk-tools 3.0.5 rejected
  the 0.0.9 gate's `--network=false` spelling before any mutation.
- Use target-proven `apk --no-network` for local-file simulation, install, and
  rollback; reject `--network=...` spellings in the live-gate contract.
- Installation and all fault gates passed; reboot recovery also worked, but the
  final combined audit command had a shell-quote failure. Its APKs are rejected;
  corrected full certification continues only as 0.0.11.

## 0.0.9 - 2026-08-28 (not published)

- Continue certification under a fresh version after the 0.0.8 router transfer
  gate assumed an unavailable GNU-style `stat` command.
- Use portable `test -x` for OpenWrt helper validation and document that target
  images may omit `stat`; retain the transferred offline install-gate design.
- All pre-install gates passed, but apk rejected the boolean network spelling
  during simulation before mutation. Its APKs are rejected; corrected offline
  certification continues only as 0.0.10.

## 0.0.8 - 2026-08-28 (not published)

- Continue certification under a fresh version after the 0.0.7 live install
  harness broke its ubus assertion through nested SSH/grep quoting.
- Move live install assertions into a transferred, syntax-checked shell script,
  parse JSON with jsonfilter, and disable network access for local APK
  simulation/install/rollback operations.
- Local, Debian, artifact and source synchronization gates passed, but the
  router transfer assertion called unavailable `stat`. Nothing was installed;
  its APKs are rejected and certification continues only as 0.0.9.

## 0.0.7 - 2026-08-28 (not published)

- Continue certification under a fresh version after the 0.0.6 independent
  byte/mode synchronization command failed from nested awk/shell quoting.
- Use a checked, standalone manifest generator without nested interpolation;
  require successful local and remote generation before comparing contents.
- Local, Debian, artifact, source-sync, rollback and install-transaction gates
  passed, but a nested grep quote broke the live ubus assertion. Recovery to
  0.0.4 passed; the APKs are rejected and certification continues as 0.0.8.

## 0.0.6 - 2026-08-28 (not published)

- Continue certification under a fresh version after the 0.0.5 Debian APK
  metadata command failed and a shell pipeline masked that failure.
- Require package inspection to use a supported SDK command, capture its own
  exit code before filtering output, and verify metadata, payload bytes, and
  modes before an artifact can be promoted.
- All source and integrated APK verification gates passed, but an independent
  byte/mode sync assertion command failed before comparison because `$1` was
  expanded by the wrong shell. The APKs are rejected; corrected certification
  continues only as 0.0.7.

## 0.0.5 - 2026-08-28 (not published)

- Continue certification under a fresh version after the 0.0.4 live refusal
  test used an invalid raw comparison of changing nft counter values.
- Add a portable chain-dump normalizer and regression test that ignore only
  dynamic packet/byte counts while retaining expressions, comments, and rule
  handles, so watcher refusal and genuine replacement remain distinguishable.
- Document the monotonic failed-version quarantine policy: preserve failed
  artifacts, increment the patch version, and rerun the full validation suite.
- Source regressions and APK construction passed, but a misused `apk manifest`
  metadata assertion failed and was masked by a non-pipefail shell. The APKs
  are rejected; corrected package inspection continues only as 0.0.6.

## 0.0.4 - 2026-08-28 (not published)

- Reject malformed, ULA, link-local, and other non-`2000::/3` WAN addresses or
  delegated prefixes before any nft call; enforce PD lengths 3–64 and the Linux
  15-character device-name limit.
- Validate required table/chain creation together with the complete ruleset and
  apply that exact batch atomically, preventing empty live objects after a
  failed check.
- Replace count/token-based managed detection with exact N² tuple matching and
  reject extra rules.
- Report netifd readiness separately from mwan3 tracker online state and score.
- Add an opt-in, procd-managed, debounced renewal service. It is disabled by
  default, ignores unavailable WANs, refuses unexpected chains, never reloads
  fw4, and can narrowly run `mwan3 ifup` only for changed matching interfaces.
- Explicitly enable/register the newly introduced init service during both
  fresh installation and upgrade; its default `monitor=0` keeps it inert.
- Verify the narrow tracker refresh contract correctly: `mwan3 ifup` sends USR2
  to only the matching tracker, which reruns `firstconnect()` and source lookup
  in-process; a PID change is neither required nor expected.
- Add LuCI controls/status for renewal and tracker health, correct overlength
  sample device names, and document that nft prefix SNAT is stateful NAT rather
  than RFC 6296 NPTv6.
- Expand regressions for GUA syntax/scope, exact tuple association, extra rules,
  atomic absent-object failures, apply serialization, tracker visibility, and
  renewal debounce/scope.
- Live unexpected-rule refusal behaved correctly, but its raw textual chain
  comparison failed because the injected rule's packet/byte counters advanced.
  The version is sealed by policy; the corrected oracle continues as 0.0.5.

## 0.0.3 - 2026-08-28 (not published)

- Passed package installation and monitor idle testing on production.
- Synthetic stale-rule recovery repaired NAT after two samples and selected
  only the changed IPv6 member, but the test incorrectly required its
  `mwan3track` PID to change.
  Installed mwan3 source confirms its supported USR2 refresh intentionally
  rereads the source inside the same process.
- Closed by the monotonic failed-version policy even though the failure was in
  the test assertion; corrected verification continues only as 0.0.4.

## 0.0.2 - 2026-08-28 (not published)

- Installed for production testing after repairing one member's stale-prefix
  outage, but closed under the monotonic failed-version policy.
- Candidate testing found and fixed a real nft `chain`-handle miscount and a
  0.0.1 upgrade path that failed to enable the newly introduced init service.
- Corrected runtime Apply passed, but no 0.0.2 artifact is eligible for GitHub
  release; the fixes and remaining monitor tests continue as 0.0.3.

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
