# 多 WAN 分流方案比較

## 目前結論

0.0.36 支援 2 至 32 條已設定的 IPv6 WAN。就緒 WAN 為 N 條時，會產生
N × (N − 1) 條精確 cross-SNAT，加上 N 條安全的 prefix-SNAT，總數為 N²。

| 就緒 WAN | cross-SNAT | prefix-SNAT | 規則總數 |
|---:|---:|---:|---:|
| 2 | 2 | 2 | 4 |
| 3 | 6 | 3 | 9 |
| 4 | 12 | 4 | 16 |
| N | N × (N − 1) | N | N² |

每條前綴規則只接受 IPv6 全域單點傳播來源（`2000::/3`），因此不會轉換
DHCPv6、link-local 或其他控制流量。完整設定、安全條件及 nftables 批次
都驗證通過後，才會原子替換 live chain。選用監看服務獨立於 fw4，能在
WAN 中斷或恢復時維持安全的就緒子集；追蹤器更新預設停用。

`snat ip6 prefix to` 是有狀態 nftables NAT，不是 RFC 6296 所規範的
無狀態、雙向及 checksum-neutral 轉換。兩者都會改寫前綴，但都不會單獨
把一條連線拆到多條 WAN。

目前還沒有任何特定雙 WAN、三 WAN 或更多 WAN 部署的完整對照效能結果。
只有在 mwan3 能把大量獨立連線分配到不同線路時，更多可用 WAN 才會提高
理論總頻寬。Prefix NAT 不負責選路，也無法合併單一 TCP 或 QUIC flow。

## 架構差異

| 方案 | 一般單一 TCP／QUIC 能跨線路嗎？ | 需要外部節點 | 主要取捨 |
|---|---|---|---|
| mwan3 + 本專案的有狀態 prefix SNAT | 否 | 否 | 使用原生路由、維護成本低；需要多連線或多人使用才可能提高總吞吐。 |
| 對稱無狀態 NPTv6 | 否 | 否 | 可預期的 1:1 前綴對應，但必須設計雙向與 checksum-neutral；仍不會綁定頻寬。 |
| 原生 MPTCP | 支援 MPTCP 的兩端或 proxy 可以 | 通常需要 | 是否能使用額外 subflow，取決於 kernel、應用程式、path manager 與中間設備。 |
| OpenMPTCProuter／MPTCP tunnel | 可以，經由 tunnel／proxy | 通常需要 VPS | 可整合單一應用連線，但增加 VPS、封裝、MTU、CPU、延遲、丟包／亂序及額外故障點。 |
| Glorytun 類多路 tunnel | 可以，但只在其 tunnel 內 | 需要 | 同樣有 tunnel 與端點成本，操作方式不同於 mwan3 policy routing。 |

Linux [MPTCP 專案](https://www.mptcp.dev/)說明了 multipath TCP 的端點與
path manager 架構。[OpenMPTCProuter](https://www.openmptcprouter.com/)提供
MPTCP／VPS 整合方案，[Glorytun](https://github.com/angt/glorytun)則是另一種
多路 tunnel。若目標是「單一連線綁定頻寬」，這些方案才是比較對象；它們
不是不需要外部端點的 OpenWrt 前綴轉換替代品。

社群 `mwan3-nft` 可把 mwan3 firewall backend 現代化，也包含路由器本機
流量的 IPv6 SNAT 選項，但不會把 LAN 轉送來源前綴轉換成各 WAN 所選 PD。
本專案的流量模型仍需要獨立的轉送前綴轉換層。

## 安全的比較流程

每個測試組都使用相同且已驗證的 N-WAN NAT6 設定，只變更經過審查的
mwan3 policy member 或權重：

1. 備份 mwan3、firewall、`/etc/config/mwan3-nat6` 與 NAT6 nftables
   資料表，並先寫好精確回復指令。
2. 確認所有候選 IPv6 WAN 已就緒、PD 是最新狀態、NAT6 profile 正好是
   `managed`、mwan3 追蹤成員 online、`fw4 check` 通過，且介面 error／
   drop 計數穩定。
3. 只透過 mwan3 policy 定義雙 WAN、三 WAN 或全 WAN 測試組，不要在各組
   之間更換 NAT6 實作。
4. 從同一台下游裝置，對相同目的地執行足夠數量的平行 IPv6 下載或
   iperf3 session，讓 mwan3 有機會把 flow 分散到不同 WAN。
5. 在相近時段交替測試各組，記錄總吞吐、各 WAN byte 差值、重傳、失敗、
   延遲及 error／drop 差值。
6. 重複足夠輪次，比較中位數與波動；最後還原原始 mwan3 policy 並確認
   路由器健康狀態。

應選擇能穩定提高總吞吐、同時沒有明顯增加失敗、重傳、延遲、error 或
drop 的最小 WAN 組合。某條線路較慢、丟包、計量收費或壅塞時，WAN 越多
不一定越好。

## 每個部署仍需補齊的證據

- 各 policy 的多輪受控吞吐測試；
- 同一測試時段內的線路容量、壅塞、丟包及延遲；
- 流量代理／tunnel 關閉與開啟時分開測試；
- 重新開機、PPP 重新連線、WAN 中斷／恢復及完整 nftables flush；
- 就緒子集變動時，確認預設模式不會更新全部 mwan3 或變更無關服務／策略。

早期正式環境診斷也證明目的地必須多樣化：stale NAT 曾讓一條追蹤器真的
無法使用；另一條 WAN 則可到達 Google／Quad9，卻無法到達某個 Cloudflare
ICMP 目標。後者只是目的地或路徑差異，不能據此判定整條 WAN 離線。

不得部署歷史舊腳本；它只保留在私有研究記錄中，不是公開發佈的一部分。
