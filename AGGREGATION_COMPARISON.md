# N-WAN aggregation comparison

## Current conclusion

The configurable implementation supports two through thirty-two IPv6 WANs.
For N enabled WANs it generates N × (N − 1) exact cross-SNAT rules plus N safe
prefix-SNAT rules, for N² rules total.

| Enabled WANs | Cross-SNAT rules | Prefix-SNAT rules | Total rules |
|---:|---:|---:|---:|
| 2 | 2 | 2 | 4 |
| 3 | 6 | 3 | 9 |
| 4 | 12 | 4 | 16 |
| N | N × (N − 1) | N | N² |

Each prefix rule is restricted to IPv6 global-unicast sources (`2000::/3`), so
DHCPv6 link-local and other control traffic are not translated. The script
validates every enabled WAN and the complete nftables batch before atomically
replacing the live chain.

There is not yet a controlled throughput result for any particular two-,
three-, or higher-WAN deployment. More eligible links increase the theoretical
aggregate ceiling only when mwan3 distributes many independent connections.
Prefix NAT does not select a WAN and cannot combine a single TCP or QUIC flow.

## Safe comparison protocol

Keep the same hardened N-WAN NAT6 configuration in every test arm. Change only
the reviewed mwan3 policy membership or weights:

1. Back up mwan3, firewall, `/etc/config/mwan3-nat6`, and the configured NAT6
   nftables table. Record an exact rollback command.
2. Confirm all candidate IPv6 WANs are ready, delegated prefixes are current,
   the NAT6 status is managed, `fw4 check` passes, and interface error/drop
   counters are stable.
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

Do not deploy the historical script. It is retained only as private research
evidence and is not part of the public release.
