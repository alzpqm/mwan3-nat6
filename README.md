# mwan3 多 WAN NAT6

`mwan3-nat6` 會替兩條以上的 OpenWrt IPv6 WAN 產生來源前綴 NAT 規則。
mwan3 負責為每條連線選擇送出介面，本套件則把來源位址轉換成該介面
可路由的委派前綴，兩者各自處理不同工作。

0.0.47 支援 2 至 32 條 IPv6 WAN，並提供 LuCI 設定頁、netifd／mwan3
追蹤狀態、流量計數、受保護的手動套用，以及選用的自動更新監看。

## 語言

主套件與 LuCI 預設使用正體中文，不需要另外安裝中文語言包。若要使用
英文介面，請另外安裝同版本的選用套件：

```sh
apk --no-network add luci-i18n-mwan3-nat6-en-0.0.47-r1.apk
```

英文包只會把 English 加入 LuCI 的語言選單，不會擅自變更目前使用的
語言。移除英文包後，主程式仍會保留完整的正體中文介面。

## 功能

- 從 `/etc/config/mwan3-nat6` 讀取已啟用的 WAN。
- 變更 nftables 前，先驗證所有邏輯介面及安全條件。未連線或暫時無法
  使用的 WAN 會排除；資料格式錯誤、裝置不符或前綴長度不符則拒絕套用。
- 對目前就緒的 N 條 WAN 產生 N × (N − 1) 條精確 cross-SNAT 規則，
  再加 N 條 prefix-SNAT 規則，合計 N² 條。
- 前綴轉換只接受 IPv6 全域單點傳播來源（`2000::/3`），不會轉換
  DHCPv6、link-local 或其他控制流量。
- 把必要的資料表／規則鏈建立及全部規則放入同一個批次，先以 `nft -c`
  驗證，再原子套用同一批內容。
- 判斷是否由本套件管理時，會比對完整的送出介面、來源位址、目標位址
  與前綴組合，不會只看規則數量或零散關鍵字。
- WAN 中斷時保留安全的就緒子集，恢復後再自動擴充；設定、安全檢查或
  規則驗證失敗時，保留上一份可用規則。
- 只有精確符合本套件格式的 nft／RPDB 子集才可自動修復；手動、RPC 與
  watcher 都會拒絕任何無法辨識的規則鏈，即使該鏈目前沒有規則。
- nft 套用失敗或在可處理的中斷訊號期間中止時，會還原並確認先前的
  RPDB 規則。
- 可選擇獨立於 fw4 的更新監看服務；除非明確啟用，否則不會更新 mwan3
  追蹤器。
- 可選擇讓路由器本機明確綁定 WAN 裝置的程式，先查詢該 WAN 通過驗證
  的 mwan3 路由表；使用精確 WAN 來源的 ICMPv6 Echo Request 也會取得
  略過標記。這項功能供 NextTrace 等診斷工具使用，預設停用。

本套件不會建立 mwan3 策略或路由表項目、不會變更權重或重新撥接 PPP，
也不會安裝 firewall include、netifd hotplug hook 或代理規則。選用的
本機裝置模式只會管理 priority 1500、protocol 242 的 RPDB 規則。

`snat ip6 prefix to` 是有狀態 NAT，不是 RFC 6296 定義的 checksum-neutral
無狀態 NPTv6，也不會單獨提供對外的雙向 1:1 轉換。

## 頻寬限制

本套件不能把單一 TCP 或 QUIC 連線拆到多條 WAN。mwan3 分配的是不同
連線，因此只有多連線下載、多人同時使用或其他多 flow 負載，才可能同時
使用多條線路。實際結果仍取決於各線路速率、權重、延遲、丟包與目的端。

## 設定

安裝後不會預先建立 WAN 項目。請由 **網路 → mwan3 NAT6 → WAN 設定**
新增至少兩條 WAN，或使用 UCI：

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

`device` 與 `expected_prefix_length` 是選用安全檢查。留空時接受 netifd
目前回報的 `l3_device` 與委派前綴長度。位址及前綴索引預設為 0，可用
範圍為 0–15。邏輯介面與目前就緒的送出裝置不得重複；Linux 裝置名稱
不得超過 15 個字元。

每條加入就緒子集的 WAN，都必須提供格式正確的全域 IPv6 位址及長度
3–64 的全域委派前綴。

### 路由器本機的指定 WAN 診斷

啟用 `pin_local_icmp=1` 後，套用時會另外管理 priority `-140` 的
`inet` route/output 鏈。每條就緒 WAN 只比對該 WAN 的精確全域位址與
ICMPv6 Echo Request，再套用目前 `/var/run/mwan3/mmx_mask` 的值；若該檔案
不存在，才依序使用 `mwan3.globals.mmx_mask` 與預設值 `0x3f00`。

在 nft output hook 之前，套件也會為每條就緒 WAN 建立一條 priority 1500
的標記 RPDB 規則，把 `oif` 裝置對應到唯一且預設路由確實使用該裝置的
mwan3 數字路由表。此規則會參與 `SO_BINDTODEVICE` 的第一次路由查詢，
並早於 mwan3 的 fwmark 規則。找不到對應、對應不唯一，或相同優先序／
裝置已有其他規則時，一律拒絕套用。

這些規則只影響路由器本機且明確綁定裝置的 socket，看不到 LAN 轉送
流量，也不會改變一般未綁定 TCP／UDP 連線的分流方式。

## 查看狀態與套用

唯讀查看：

```sh
/usr/nft-nat6.sh status
```

至少有一條已設定 WAN 就緒且安全檢查全部通過時套用：

```sh
/usr/nft-nat6.sh apply
```

為相容舊版，不加參數等同 `apply`。LuCI 也使用同一個受保護入口，不會
略過核心驗證。

`ready=true` 表示至少有一個安全子集可以運作；正式發佈或完整實機驗收
仍應要求 `all_ready=true`。`policy_ready` 只檢查目前就緒子集的追蹤器。

## 自動更新監看

監看服務預設停用。完成手動驗證後，可由 LuCI 啟用，或執行：

```sh
uci set mwan3-nat6.globals.monitor='1'
uci set mwan3-nat6.globals.interval='15'
uci set mwan3-nat6.globals.debounce='2'
uci set mwan3-nat6.globals.refresh_mwan3_after_nat='0'
uci commit mwan3-nat6
/etc/init.d/mwan3-nat6 restart
```

服務會等待指定數量且內容相同的就緒樣本，只會自動修復 `inactive`、
`managed-stale` 與已知的舊版 `unsafe` 狀態；`unexpected` 一律拒絕。
WAN 中斷或恢復後，會在 debounce 完成時縮減或擴充就緒子集。進階選項
`refresh_mwan3_after_nat=1` 只會對位址或前綴已變更且確實存在的 mwan3
介面執行 `mwan3 ifup`，預設停用。

監看服務不會呼叫 fw4、不會重新載入全部 mwan3、不會重新撥接 PPP，
也不會修改權重。

| 就緒 WAN 數 | 預期規則數 |
|---:|---:|
| 2 | 4 |
| 3 | 9 |
| 4 | 16 |
| 5 | 25 |

## 建置與測試

執行本機回歸測試：

```sh
make check
```

使用 OpenWrt 25.12 以上版本的 SDK 建置核心、LuCI 與英文語言包三個 APK：

```sh
SDK_DIR=/path/to/openwrt-sdk scripts/build-apk-on-sdk.sh /path/to/output
```

SDK 路徑必須放在 `SDK_DIR` 環境變數，輸出目錄是唯一的位置參數。整合
建置器會先執行 `verify-apk-artifacts.sh`，確認簽章、metadata、相依套件、
檔案內容、權限及英文 PO 編譯出的 LMO，再回報雜湊。

套件 recipe 位於 `openwrt/mwan3-nat6/` 與
`openwrt/luci-app-mwan3-nat6/`，三個套件皆不限定 CPU 架構。

## 操作安全

不要把 `/usr/nft-nat6.sh` 登記成 fw4 script include。WAN 暫時缺少時，
嚴格驗證會回傳非零，可能連帶讓防火牆重新載入失敗。唯一支援的更新方式
是手動套用或獨立監看服務。

nftables 資料表會在重新開機或完整 ruleset flush 後消失。監看服務啟用
時，會等 WAN 資料穩定後再恢復；未啟用時必須手動套用。服務始終獨立於
防火牆重新載入，WAN 不可用時也不會阻塞系統。

安裝、驗證與回復程序請見 [NAT6_HANDOFF.md](NAT6_HANDOFF.md)，多 WAN
效能比較方式請見 [AGGREGATION_COMPARISON.md](AGGREGATION_COMPARISON.md)。

## 授權

GPL-3.0-only，詳見 [LICENSE](LICENSE)。
