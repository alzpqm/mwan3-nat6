# Changelog

## 0.0.41 - 2026-08-31

- 延續 0.0.40 的動態 nftables 資料表安裝閘門，不變更核心 NAT、RPDB、
  watcher 或 LuCI 執行期行為。
- 0.0.40 的針對性測試通過，但公開來源隱私掃描發現「禁止部署專用名稱」
  的測試本身仍寫入該名稱，因此在建置前封存。
- 改以通用正規式禁止任何硬編碼 nftables 資料表名稱，不在公開測試中
  重述私有部署標籤。

## 0.0.40 - 2026-08-31

- 將實機安裝閘門內的 nftables 資料表改為從核心狀態安全解析，不再包含
  任何特定部署的資料表名稱，供使用不同專屬名稱的 OpenWrt 使用者測試。
- 新增安裝閘門契約，要求三個安裝前後鏈檢查都使用動態資料表，並禁止
  再次加入部署專用名稱。
- 0.0.39 已通過實機，但匿名發佈前的隱私閘門發現上述硬編碼；同一次
  掃描也因從絕對路徑執行而錯誤讀取暫存 clone 的 `.git` reflog。GitHub
  尚未寫入，該版本依規則封存；後續掃描固定從公開工作樹內執行。

## 0.0.39 - 2026-08-31

- 延續 0.0.38 已通過的 `fw4` 共用資料表與空白外來鏈保護修正。
- 修正實機安裝閘門的 procd 非同步競態：升級後不再只確認服務仍顯示為
  running，而會等待 watcher PID 離開升級前的程序並保持穩定，再驗證套件
  與網路狀態。
- 0.0.38 的安裝及即時稽核已通過，但 12 秒後正常完成的 watcher PID
  切換使錯誤的「PID 不得改變」斷言失敗，因此依版本隔離規則封存。

## 0.0.38 - 2026-08-31

- 延續 0.0.37 的共用 `fw4` 資料表與空白外來鏈保護修正。
- 0.0.37 在建置與實機測試前，因首次加入的 Debian `shellcheck` 使用
  預設嚴格度，把既有且已人工覆核的刻意分詞、布林鏈及讀取佔位欄位警告
  視為失敗；該版本依測試隔離規則封存。
- 後續靜態檢查明確排除上述既有警告類別，仍保留 shell 語法、差異格式及
  其他 ShellCheck 診斷。

## 0.0.37 - 2026-08-31

- 拒絕使用 OpenWrt 共用的 `fw4` nftables 資料表，LuCI 儲存前與核心套用
  前都會檢查，避免誤刪防火牆規則鏈。
- 不再把任何空白但無法證明由本套件管理的 `srcnat` 或 `local_icmp` 鏈
  視為可替換狀態；手動、RPC 與 watcher 均會保留並拒絕處理。
- 修正測試模擬器對初次安裝狀態的建模，新增共用資料表及空白外來鏈的
  保留測試。

## 0.0.36 - 2026-08-30

- 延續 0.0.35 已通過的正體中文、英文語言包、隱私修正與完全相同的
  執行期程式。
- 0.0.35 在任何 GitHub 寫入前，因遠端檢查誤在沒有 `origin` 的私有
  根工作樹執行而停止；公開 main、tag 與 Release 均未變更。
- 所有 GitHub 遠端檢查與推送固定指定獨立匿名公開工作樹，避免目前
  工作目錄影響發佈命令。

## 0.0.35 - 2026-08-30

- 延續 0.0.34 已通過的正體中文、英文語言包與完全相同的執行期邏輯。
- 0.0.34 在 GitHub 寫入前的匿名隱私閘門發現文件與測試範例仍使用一個
  與實機相同的第三 WAN 裝置名稱，因此封存且未建立 commit、tag 或
  Release。
- 將公開範例與測試裝置改為不對應任何實機的 `pppoe-wan-c`；不改動
  套件讀取使用者 UCI 裝置名稱的能力。

## 0.0.34 - 2026-08-30

- 延續 0.0.33 已成功安裝的正體中文介面、英文語言包與完全相同的
  NAT／RPDB／watcher／mwan3 行為。
- 0.0.33 的最終稽核又使用一個不存在的手寫介面字串，因此雖然安裝、
  網路狀態與其餘稽核均通過，仍依版本規則封存。
- 實機 UI 驗證改以安裝檔案對已測試來源的 SHA-256 為唯一依據；來源
  本身已通過 119 條正體中文對英文翻譯測試，不再抽樣猜測畫面文字。

## 0.0.33 - 2026-08-30

- 延續 0.0.32 已成功安裝的正體中文介面、獨立英文語言包及相同執行期
  程式；不變更 NAT、RPDB、watcher 或 mwan3 行為。
- 0.0.32 的安裝本身通過，但最終唯讀稽核使用了不存在的介面字串，並
  假設實機 BusyBox 提供 `diff` 與 `pgrep -c`，因此依版本規則封存。
- 0.0.33 的實機稽核只比對來源中確定存在的正體中文文字，並限制為
  OpenWrt BusyBox 實際支援的命令。

## 0.0.32 - 2026-08-30

- 延續 0.0.31 已通過的正體中文介面、獨立英文語言包與所有執行期
  行為，不變更 nft、RPDB、watcher 或 mwan3 分流邏輯。
- 0.0.31 的來源 tar 在 macOS 產生 AppleDouble `._*` 檔案，導致 Debian
  傳輸 manifest 在 SDK builder 執行前拒絕建置；0.0.32 的傳輸明確停用
  macOS copyfile 延伸資料，避免把非專案檔案帶入 SDK。

## 0.0.31 - 2026-08-30

- 延續 0.0.30 的正體中文介面與獨立英文語言包；核心 nft、RPDB、
  watcher 與 mwan3 分流程式沒有變更。
- 修正比較文件翻譯後仍搜尋舊英文安全聲明的測試，改為核對文件中的
  正體中文原文。
- 語言測試改由 `VERSION` 取得英文語言包檔名，避免下一版再次因文件
  內的硬編碼版本造成假失敗。
- 0.0.30 在 SDK 建置與實機安裝前，因上述過期測試契約而未通過完整
  本機閘門；依版本規則封存，不沿用該版本測試。

## 0.0.30 - 2026-08-30

- 將 LuCI 主介面、選單及套件說明固定為自然的正體中文，技術名詞依
  OpenWrt 與台灣網路管理的常用說法整理，避免生硬逐字翻譯。
- 新增獨立的 `luci-i18n-mwan3-nat6-en` 英文語言包；主套件不依賴此
  語言包，安裝後才會提供英文介面。
- 延續 0.0.29 已完成的 2→3 WAN 生命週期修復；不變更 nft、RPDB、
  watcher 或 mwan3 分流行為。
- 將所有可執行測試腳本統一為 0755，避免公開暫存工作樹保留舊權限而
  再次造成來源 manifest 不一致。
- 0.0.29 已通過實機測試，但匿名發佈閘門發現暫存工作樹的一個檔案
  權限與來源 manifest 不符，因此未建立 commit、tag 或 GitHub Release；
  依版本規則封存，後續版本不再沿用該候選版。

## 0.0.29 - 2026-08-30

- Repair the real ready-subset lifecycle regression found after 0.0.28:
  package-owned two-WAN nft/RPDB state is now classified as managed-stale and
  automatically expands when a third WAN returns; shrink transitions are
  covered as well.
- Keep wrong-table, duplicate, foreign-device, and nonempty unexpected chains
  refused by the watcher and by manual/LuCI RPC Apply.
- Restore and verify the prior tagged RPDB set when nft apply fails or a handled
  interruption lands between policy reconciliation and nft commit.
- Periodically repeat a persistent refusal warning without log spam, and create
  watcher fingerprint files with mode 0600.
- Seal 0.0.28 after live monitoring remained stuck at NAT 4/9 and local nft/
  RPDB 2/3 while all three WANs had recovered and mwan3 was balancing 33/33/33.

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
