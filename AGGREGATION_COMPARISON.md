# N-WAN aggregation comparison

## Current conclusion

The 0.0.22 implementation supports two through thirty-two configured IPv6 WANs.
For N ready WANs it generates N × (N − 1) exact cross-SNAT rules plus N safe
prefix-SNAT rules, for N² rules total.

| Enabled WANs | Cross-SNAT rules | Prefix-SNAT rules | Total rules |
|---:|---:|---:|---:|
| 2 | 2 | 2 | 4 |
| 3 | 6 | 3 | 9 |
| 4 | 12 | 4 | 16 |
| N | N × (N − 1) | N | N² |

Each prefix rule is restricted to IPv6 global-unicast sources (`2000::/3`), so
DHCPv6 link-local and other control traffic are not translated. The script
validates configuration/safety plus the complete nftables batch before
atomically replacing the live chain. Its optional monitor is independent of
fw4, keeps a stable ready subset during WAN loss/recovery, and leaves tracker
refresh disabled unless explicitly opted in.

`snat ip6 prefix to` is stateful nftables NAT. It is not the stateless,
bidirectional, checksum-neutral translation specified by
[RFC 6296](https://www.rfc-editor.org/rfc/rfc6296), even though both approaches
rewrite prefixes. Neither approach aggregates a flow by itself.

There is not yet a controlled throughput result for any particular two-,
three-, or higher-WAN deployment. More eligible links increase the theoretical
aggregate ceiling only when mwan3 distributes many independent connections.
Prefix NAT does not select a WAN and cannot combine a single TCP or QUIC flow.

## Architecture comparison

| Approach | One ordinary TCP/QUIC flow can span links? | External endpoint | Primary trade-off |
|---|---|---|---|
| mwan3 + this stateful prefix SNAT | No | No | Native routing and low operational overhead; aggregate gains require multiple flows/users. |
| Stateless symmetric NPTv6 | No | No | Predictable 1:1 prefix mapping, but needs both directions and checksum-neutral design; it still does not bond bandwidth. |
| Native MPTCP | Yes, for MPTCP-capable endpoints or a proxy | Usually | Kernel/application/path support and middlebox behavior determine whether extra subflows are usable. |
| OpenMPTCProuter / MPTCP tunnel | Yes, through the tunnel/proxy | Yes, normally a VPS | Can aggregate a single application flow, at the cost of VPS, encapsulation, MTU, CPU, latency, loss/reordering sensitivity, and another failure domain. |
| Glorytun-style multipath tunnel | Yes, inside its bonded tunnel | Yes | Similar tunnel overhead and endpoint dependency; operationally different from mwan3 policy routing. |

The Linux [MPTCP project](https://www.mptcp.dev/) documents multipath TCP and
its endpoint/path-manager model. [OpenMPTCProuter](https://www.openmptcprouter.com/)
packages an MPTCP/VPS design, while [Glorytun](https://github.com/angt/glorytun)
is a separate multipath tunnel. These are candidates when single-flow bonding
is the actual requirement; they are not drop-in replacements for prefix
translation on an endpoint-free OpenWrt deployment.

Community `mwan3-nft` work can modernize mwan3's firewall backend and includes
an IPv6 SNAT option for router-originated traffic, but that does not translate
forwarded LAN source prefixes into each selected WAN PD. A separate forwarded
prefix-translation layer is still required for this project's traffic model.

## Safe comparison protocol

Keep the same hardened N-WAN NAT6 configuration in every test arm. Change only
the reviewed mwan3 policy membership or weights:

1. Back up mwan3, firewall, `/etc/config/mwan3-nat6`, and the configured NAT6
   nftables table. Record an exact rollback command.
2. Confirm all candidate IPv6 WANs are ready, delegated prefixes are current,
   the NAT6 status is exactly managed, tracked mwan3 members are online,
   `fw4 check` passes, and interface error/drop counters are stable.
3. Define test arms such as two-WAN, three-WAN, and all-WAN by changing only the
   mwan3 policy. Do not replace the hardened NAT6 implementation between arms.
4. From the same downstream client, run the same destinations and enough
   parallel IPv6 downloads or iperf3 sessions for mwan3 to distribute flows.
5. Alternate arms at comparable times. Record aggregate throughput, per-WAN
   byte deltas, retransmissions, failures, latency, and error/drop deltas.
6. Repeat enough rounds to compare medians and variability, then restore the
   original mwan3 policy and verify router health.

Prefer the smallest WAN set that delivers a repeatable aggregate improvement
without materially increasing failures, retransmissions, latency, errors, or
drops. A higher WAN count is not automatically better when one link is slow,
lossy, metered, or congested.

## Evidence still required per deployment

- Controlled repeated throughput measurements for each policy being compared.
- Link capacity, congestion, loss, and latency during the same test windows.
- Tests with traffic-altering proxies or tunnels bypassed and, separately,
  enabled when applicable.
- Reboot, PPP reconnect, WAN loss/recovery, and full nftables-flush behavior.
- A controlled test of the 0.0.22 renewal service with WAN loss/recovery,
  ensuring the ready subset changes without any default-mode mwan3 refresh or
  unrelated policy/service change.

Production diagnosis during 0.0.2–0.0.4 development found why destination diversity
matters: stale NAT made one tracker genuinely unusable, while a different WAN
repeatedly reached Google/Quad9 but not one Cloudflare ICMP target. The latter
is a destination/path observation, not proof that the entire WAN is offline.

Do not deploy the historical script. It is retained only as private research
evidence and is not part of the public release.
