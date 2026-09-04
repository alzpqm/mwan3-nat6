# mwan3 多 WAN NAT6 操作指南

## 適用範圍

`mwan3-nat6` 會把 IPv6 來源位址轉換成 mwan3 所選 WAN 的委派前綴。
可設定 2 至 32 條 WAN，並為目前就緒的 N 條 WAN 產生 N² 條 nftables
規則。

本套件不會設定 mwan3 member／policy 或路由表、不會改權重、重新撥接
PPP、安裝 firewall include／netifd hotplug hook，也不會建立 tunnel、
proxy 或提供單一連線頻寬綁定。獨立更新監看與路由器本機的指定 WAN
診斷均為選用功能。

## 安裝

在使用 apk 的 OpenWrt 25.12 以上版本，安裝核心與 LuCI：

```sh
apk --no-network add mwan3-nat6-0.0.47-r1.apk
apk --no-network add luci-app-mwan3-nat6-0.0.47-r1.apk
```

LuCI 預設使用正體中文。如需英文，再安裝同版本的獨立語言包：

```sh
apk --no-network add luci-i18n-mwan3-nat6-en-0.0.47-r1.apk
```

英文包只會加入可選語言，不會自動切換目前 LuCI 語言。舊版 opkg 系統
必須使用該 OpenWrt 版本 SDK 所建置的相容 IPK；不要混用不同 ABI。

安裝主套件不會建立任何 WAN 項目，也不會立即執行 NAT6。procd 服務雖然
會安裝，但 `monitor` 預設為 `0`，因此不會動作。

## 失敗版本隔離規則

每個版本只能作為一次驗收候選。只要建置、安裝、升級、斷言、發佈或
實機測試任一步失敗，都要保留日誌與帶有 `rejected-*` 說明的產物，patch
版本往後加一，再從完整流程重測。不得在同一版本重建修正版。

nft chain dump 可能包含持續變動的 `counter packets` 與 `bytes`。拒絕測試
只能用 `scripts/normalize-nft-chain.sh` 正規化這兩個數字，不得移除規則
運算式、comment 或 handle，以免真正的規則替換被誤判為相同。

部分 OpenWrt 映像沒有 `stat` applet。驗證傳入腳本時請使用
`test -x /tmp/helper.sh`，不要假設 GNU `stat -c` 一定存在。

## 設定 WAN

請由 **網路 → mwan3 NAT6 → WAN 設定** 操作，或編輯
`/etc/config/mwan3-nat6`。至少需要兩個已啟用的 `wan` section：

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
	option device 'pppoe-wan-c'
	option expected_prefix_length '60'
	option address_index '0'
	option prefix_index '0'
```

| 選項 | 必填 | 說明 |
|---|---|---|
| `monitor` | 否 | 啟用獨立更新監看，預設 0。 |
| `interval` | 否 | 檢查間隔 5–3600 秒，預設 15。 |
| `debounce` | 否 | 需要幾個內容相同的就緒樣本，1–10，預設 2。 |
| `refresh_mwan3_after_nat` | 否 | 更新有變動的追蹤器，進階選用，預設 0。 |
| `pin_local_icmp` | 否 | 初始 `oif` RPDB 查詢及精確 WAN GUA ICMPv6 略過規則，預設 0。 |
| `enabled` | 否 | WAN section 存在時預設啟用。 |
| `label` | 否 | 使用簡單 ASCII 字元的顯示名稱。 |
| `interface` | 是 | 傳給 `ifstatus` 的 IPv6 netifd 邏輯介面。 |
| `device` | 否 | 預期的即時 `l3_device`，不符時拒絕套用。 |
| `expected_prefix_length` | 否 | 預期的全域 PD 長度，3–64。 |
| `address_index` | 否 | WAN 全域位址索引，0–15，預設 0。 |
| `prefix_index` | 否 | 委派前綴索引，0–15，預設 0。 |

所有邏輯介面與即時裝置都不得重複。資料表名稱須以英文字母或底線開頭，
其餘只能是英文字母、數字或底線。Linux 裝置名稱最多 15 個字元。WAN
位址與前綴基底必須是格式正確的 `2000::/3`；ULA 與 link-local 會在任何
nft 呼叫前被拒絕。

## 套用前檢查

變更正式環境前，先備份設定與目前的資料表：

```sh
backup_dir="/root/mwan3-nat6-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
cp -p /etc/config/mwan3-nat6 "$backup_dir/"
cp -p /etc/init.d/mwan3-nat6 "$backup_dir/" 2>/dev/null || true
nft list table inet mwan3_nat6 >"$backup_dir/mwan3_nat6.nft" 2>/dev/null || true
```

再確認：

```sh
/usr/nft-nat6.sh status
mwan3 status
fw4 check
```

一般故障切換可使用安全的就緒子集；正式發佈或策略比較則必須要求所有
已啟用 WAN 就緒，且 mwan3 policy 包含預定的全部 IPv6 member。

## 套用與驗證

```sh
/usr/nft-nat6.sh apply
/usr/nft-nat6.sh status
nft -a list chain inet mwan3_nat6 srcnat
```

目前有 N 條 WAN 就緒時，必須確認：

- `oifname` 規則總數為 N²；
- 精確 `snat ip6 to` 為 N × (N − 1) 條；
- `snat ip6 prefix to` 為 N 條；
- 每條前綴規則都包含 `ip6 saddr 2000::/3`；
- status profile 為 `managed`，規則數與預期相同；
- 每個預期的送出介面／來源位址／目標位址／前綴組合只出現一次，沒有
  多餘規則；
- configured、active 與 inactive WAN 數量符合預期；
- 就緒子集的 `policy_ready` 為 true；
- 介面 error／drop 計數與 `fw4 check` 都正常。

若 `pin_local_icmp=1`，還要確認 `local_icmp.profile=managed`，nft 規則數
等於就緒 WAN 數，每條規則只比對一個精確 WAN GUA 與 ICMPv6 Echo
Request，且 chain 是 `type route hook output priority -140`。不得包含
`oifname`、前綴、TCP／UDP 或轉送流量條件。

`routing_rule_count` 與 `expected_routing_rule_count` 也必須等於就緒 WAN
數。每條 priority 1500、protocol 242 的標記 RPDB 規則，都要把一個精確
PPP `oif` 裝置對應到唯一且 IPv6 default route 確實使用該裝置的 mwan3
數字路由表。找不到對應、對應不唯一，或同優先序／裝置已有別的規則時，
套用必須失敗並還原先前的標記規則。

核心會先驗證所有介面，再把必要物件與規則組成單一 nftables 批次。
驗證失敗時必須保留舊 chain，不可留下空資料表或空 chain。替換前，現有
chain 必須被辨識為 `managed`、`managed-stale` 或已知舊版 `unsafe`；
即使 chain 目前沒有規則，手動／RPC Apply 與 watcher 也會拒絕
`unexpected`。請使用專屬資料表；核心與 LuCI 會直接拒絕 `fw4`，也不得
指向其他共用資料表。

移除或降級主套件時，pre-deinstall 會呼叫
`/usr/nft-nat6.sh cleanup-policy`，避免 protocol 242 RPDB 規則殘留。

## 選用的自動更新監看

只有在手動 status／apply 驗證完成後才啟用：

```sh
uci set mwan3-nat6.globals.monitor='1'
uci set mwan3-nat6.globals.interval='15'
uci set mwan3-nat6.globals.debounce='2'
uci set mwan3-nat6.globals.refresh_mwan3_after_nat='0'
uci commit mwan3-nat6
/etc/init.d/mwan3-nat6 restart
/etc/init.d/mwan3-nat6 status
```

服務只會在就緒子集樣本連續相同時動作，可修復 `inactive`、
`managed-stale` 與已知 `unsafe`，但會拒絕 `unexpected`。WAN 中斷或恢復
後，會在 debounce 完成時移出或加回就緒子集。服務絕不呼叫 fw4。

預設停用的相容更新只會對位址或前綴有變動，且確實存在於 mwan3 的邏輯
介面執行 `mwan3 ifup`；不會重新撥接 PPP 或重新啟動全部 mwan3。

## LuCI 安全邊界

LuCI 只取得 `mwan3-nat6` 的 UCI 權限。專用 rpcd object 只提供 `status`
與 `apply`，沒有通用 shell／檔案執行權，也不能編輯 mwan3、network、
firewall 或 proxy 設定。

儲存 WAN 設定不會略過核心驗證。至少有一條 WAN 就緒且現有規則鏈可
安全辨識時，才會允許手動套用。英文語言包只含 LMO 與 LuCI 語言登記，
不含 RPC、UCI 寫入 ACL 或 NAT 執行入口。

## 回復

回復前先保存目前狀態，只還原本次變更所涉及的檔案與資料表：

```sh
cp -p /root/mwan3-nat6-backup-TIMESTAMP/mwan3-nat6 /etc/config/mwan3-nat6
/etc/init.d/mwan3-nat6 stop
nft delete table inet mwan3_nat6 2>/dev/null || true
nft -f /root/mwan3-nat6-backup-TIMESTAMP/mwan3_nat6.nft
/etc/init.d/rpcd reload
```

若變更前不存在該資料表，略過最後的 `nft -f`。不得在回復時重新加入
fw4 script include 或未審查的 hotplug hook。

## 疑難排解

```sh
logread -e nft-nat6
logread -e mwan3-nat6-watch
/usr/nft-nat6.sh status
ifstatus YOUR_IPV6_INTERFACE
nft list table inet mwan3_nat6
```

常見阻擋原因包括：設定不到兩條 WAN、沒有介面就緒、裝置名稱過長或不符、
位址／前綴不是 GUA 或格式錯誤、介面／裝置重複、陣列索引錯誤，以及 PD
長度不符。`ready=true` 表示至少有一個安全子集可用；`degraded=true`
表示部分 WAN 已排除；`policy_ready=false` 則表示就緒子集內有追蹤器未上線。

不要把腳本當成 fw4 include。監看停用時，重新開機或完整 flush 後不會
自動還原；監看啟用時，也只會在資料穩定後恢復。每個部署仍須另外驗證
缺少 WAN、PD 更新、重新開機、防火牆／OpenClash reload 與完整 flush。

精確的本套件子集可視為可修復的 stale 狀態；錯誤路由表、重複規則、
外來裝置或其他無法辨識的規則仍會被拒絕。持續拒絕會先立即寫入日誌，
之後以低頻率定期提醒。

產生的 nft prefix SNAT 是有狀態轉換，不是 RFC 6296 的無狀態、
checksum-neutral NPTv6，也不會建立對外雙向 1:1 轉換。
