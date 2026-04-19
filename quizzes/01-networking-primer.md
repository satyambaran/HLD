# 01 · Networking Primer — Quiz Log

---

## 2026-04-19 · Session 2 (Deep, /hld-next) — Part 1: TCP + DNS + TLS

**Final: 40/80 (50%) → Level: 1_intro**

---

### Q1 · Short-answer — Trace every RTT from `curl https://api.example.com/users`

**Question:**
> You `curl https://api.example.com/users` for the first time from a fresh laptop. Cross-continent, 150ms RTT. TLS 1.3. DNS fully cold.
>
> **Walk me through every RTT** between hitting Enter and seeing the response body. Label each one, give a time estimate, and give me the **total time-to-first-byte**.

**Learner's answer:**
> DNS = 2 RTT, TCP Handshake = 1 RTT, TLS1.3 = 1 RTT, https conn = 1 RTT
> Total RTT before time to first byte = 5 RTT ~= 750ms

**Score: 6/10**

**Gap:** Tally rather than walkthrough. Didn't describe *what* each RTT exchanges.

**Ideal walkthrough:**

| RTT | What happens | Cost @ 150ms |
|---|---|---|
| DNS #1 (client → resolver) | `A api.example.com?` → resolver returns IP | ~150 ms |
| DNS #2 (cold resolver cache) | Additional upstream walk visible to client | ~150 ms |
| TCP handshake | `SYN → SYN-ACK → ACK`; both ends get seq numbers + buffers | 150 ms |
| TLS 1.3 handshake | `ClientHello+KeyShare → ServerHello+Cert+Finished → Finished+(piggybacked data)`; ephemeral DH + cert validation | 150 ms |
| HTTP request + response | `GET /users` → server processes → first byte back | 150 ms |
| **Total (cold)** | **5 RTT ≈ 750 ms** | |

**Warm (pooled) contrast to add:** DNS cached + TCP/TLS reused → only 1 RTT (150 ms). **5× faster.** This is the entire justification for connection pooling.

---

### Q2 · MCQ + why — BindException at 5000 req/s

**Question:**
> A Java microservice makes ~5000 outbound HTTPS calls/second to another internal service 1 km away (same DC). It uses `new HttpClient()` for every request. Latency is ~800ms and the service periodically crashes with `java.net.BindException: Cannot assign requested address`.
>
> Options:
> - **A.** Target is overloaded; add retries with exponential backoff.
> - **B.** TLS handshake is the bottleneck; downgrade to TLS 1.2.
> - **C.** Each request pays full DNS+TCP+TLS. TIME_WAIT exhausts ephemeral ports. Fix: pool HttpClient + keep-alive.
> - **D.** IPv6 is slower; force IPv4.
>
> Pick one, justify the arithmetic, refute each distractor.

**Learner's answer:**
> C, because microservice might be using new client per request which could cause 3-4 RTT (DNS, TCP and TLS) that's near 4*70ms=280ms (same DC). Since it has some TIME_WAIT, requests might get queued as well as even though we release the port still it might not get freed immediately and hence it gets added in latency.

**Score: 6/10**

**Strong:** Correct answer, correct diagnostic direction, understood new-client-per-request + TIME_WAIT concept.

**Gaps:**
- **⚠️ Topic-00 spaced-revision slip:** wrote **70ms for same DC** — correct number is **500µs** (0.5ms). Same DC handshake would be ~2ms total, not 280ms. The 800ms observed latency is from **request queuing while waiting for free ports**, not handshake cost.
- **Missed port-exhaustion arithmetic:**
  ```
  Ephemeral port range: ~28,232 ports (Linux default 32768-60999)
  TIME_WAIT duration: 2 × MSL ≈ 60-120s
  Connections in TIME_WAIT at 5000/s over 120s = 600,000
  Exhausted in ~6 seconds → BindException
  ```
- **Skipped distractor analysis entirely:**
  - **A** wrong layer — BindException is local port exhaustion, not target overload
  - **B** backwards — TLS 1.2 is *slower* (2 RTTs vs 1)
  - **D** irrelevant — IPv4 vs IPv6 doesn't affect handshake RTT count

**Fix:**
```java
// Wrong: new client per request → full handshake + port exhaustion
HttpClient.newHttpClient().send(request, BodyHandlers.ofString());

// Right: singleton pooled client
private static final HttpClient CLIENT = HttpClient.newBuilder()
    .version(HttpClient.Version.HTTP_2).build();
CLIENT.send(request, BodyHandlers.ofString());
```

---

### Q3 · Scenario — DNS TTL choice

**Question:**
> You manage DNS for `api.example.com`. Ops wants TTL=5s for "faster failover."
>
> 1. What's the operational risk of TTL=5?
> 2. What's the operational risk of TTL=86400?
> 3. Under what real-world failure mode does low TTL *hurt* you? (Hint: famous 2016 incident.)
> 4. What would you pick, and why?

**Learner's answer:**
> 1. We might end up DDoSing our DNS resolver with TTL=5s.
> 2. High TTLs lead to slower failover. In case of DC dying, we would want to change IPs for the same DNS which will lead to wrong IP resolutions.
> 3. (blank)
> 4. I would pick somewhere around 3-4 minutes. It should take time which is in similar range of DC getting up again.

**Score: 6/10**

**Strong:** Q1 + Q2 correct. Q4 pick (3-4 min) is in the defensible 60-300s range.

**Gap:** **Q3 left blank — the Staff+ separator.**

**The Dyn-2016 insight:** Low TTL *actively hurts* during a DNS-layer DDoS. When the Mirai botnet flooded Dyn with ~1.2 Tbps on Oct 21 2016:
1. Authoritative DNS became unreachable
2. Resolvers with cached answers kept serving — their users saw no outage
3. Users whose cache just expired couldn't re-resolve → error pages
4. **With TTL=5s, almost every cache expired during the attack → near-total outage**
5. **With TTL=3600s, most users had cached answers → attack invisible to them**

**The cruel inversion:** low TTL "helps failover" but makes you *more fragile* against the actual failure mode that takes down the internet.

**Q4 sharpening:** Staff answer matches TTL to **MTTR**, considers redundant authoritative DNS (two providers), and puts **failover logic at the load-balancer / service-mesh layer** so DNS change isn't on the critical path.

> *"TTL = 300s with redundant authoritative DNS across two providers. Application-layer failover handles sub-minute incidents; DNS change is reserved for regional events where 5 minutes is acceptable downtime."*

---

### Q4 · Short-answer — TCP HoL + HTTP/2 inheritance

**Question:**
> Explain in 2-3 sentences what **"TCP head-of-line blocking"** is, why it exists, and why **HTTP/2 inherits** the problem even though it "fixes" HoL at the HTTP layer.

**Learner's answer:**
> TCP guarantees sequential and at-least delivery of each package. So if let's say out of 5 packages, 1, 3, 4 and 5 has reached to the user but 2nd has not yet reached. In that case, it will keep blocking the ack of 3rd, 4th and 5th package till it retransmits and receives the 2nd package. This is called head-of-line blocking. I am not sure about HTTP/2 as it has not come in the notes yet.

**Score: 6/10**

**Strong:** TCP HoL mechanics correct. Admitted gap honestly rather than bluffing.

**Gaps:**
- **Small precision slip:** TCP *does* ACK out-of-order packets (via SACK); what it blocks is **delivery to the application**, not the ACK itself. Precise: *"TCP ACKs what it gets but delivers bytes to the app in order."*
- **Missed HTTP/2 layer inheritance** — the actual meat of the question:

**HTTP/2 inheritance — the layer-boundary insight:**

| Layer | HTTP/1.1 | HTTP/2 | HTTP/3 (QUIC) |
|---|---|---|---|
| App-layer HoL | Yes (one request blocks next) | **Solved** — multiplex N streams | Solved |
| Transport HoL | Inherited from TCP | **Inherited from TCP** (one lost packet stalls all streams) | **Solved** — UDP + per-stream ordering |

HTTP/2 multiplexes many streams on ONE TCP connection. TCP delivers bytes in order across the whole connection. So one lost packet of stream A stalls streams B, C too — because TCP holds their bytes until stream A's gap is filled. **HTTP/2 solved HoL at its own layer while remaining hostage to TCP's in-order delivery underneath.**

**HTTP/3 / QUIC runs over UDP with independent per-stream ordering** — fixes HoL end-to-end.

**Meta-lesson:** Multiplexing N streams over 1 connection doesn't fix HoL if the underlying connection is itself in-order. You have to push the fix down to the transport.

---

### Q5 · MCQ + why — TLS 1.3 vs 1.2

**Question:**
> Most accurate statement about TLS 1.3 vs TLS 1.2?
> - **A.** 1.3 uses stronger ciphers (AES-256 instead of 128), so it's more secure but slower.
> - **B.** 1.3 cuts handshake from 2 RTTs to 1 RTT, removes legacy ciphers, mandates forward secrecy.
> - **C.** 1.3 changes transport from TCP to UDP.
> - **D.** 1.3 eliminates certificates by using PSKs.
>
> Pick + refute each wrong option specifically.

**Learner's answer:**
> A is incorrect because it's not slower.
> B is correct.
> C is incorrect cause TCP and TLS are independent networking layer.
> D is also incorrect it share the certs and keys during the handshake.

**Score: 7/10**

**Strong:** Correct answer, refuted all distractors in the right direction. **Also pushed back on my initial "TLS 1.3 always over TCP" claim** — correctly sensed imprecision. Clarified:
- Classic TLS 1.3 (RFC 8446) = over TCP
- DTLS 1.3 (RFC 9147) = TLS reimagined for UDP — used by WebRTC, VoIP, OpenVPN
- QUIC (RFC 9000) = UDP transport that embeds TLS 1.3's crypto (not TLS running over UDP; reuses only the crypto layer)

**Gaps (precise refutations):**
- **A:** AES-256 was already in 1.2. 1.3 *shrunk* cipher surface, didn't enlarge keys. Symmetric AES-128 vs AES-256 indistinguishable in perf on modern CPUs with AES-NI.
- **C:** Classic TLS 1.3 still on TCP. QUIC uses UDP but isn't the same protocol.
- **D:** Certs still required for initial auth. PSKs are a **session-resumption** mechanism (enabling 0-RTT for returning clients), not a replacement for certs.

**Shape to take away:** TLS 1.3's improvements are all about **reduction** — fewer RTTs, fewer cipher options. Security came from *removing* broken things, not adding stronger ones.

---

### Q6 · Scenario — Trace the 420ms p99 latency gap

**Question:**
> Java service calls internal gRPC API. Same region (~70ms RTT), TLS 1.3, connection pooling on, DNS cached. p99 = 420ms. Budget = 150ms.
>
> Where's the extra 270ms? Give top 3 things to investigate in priority order.

**Learner's answer:**
> Not sure.

**Score: 2/10** (no attempt — Deep-session fatigue)

**Systematic decomposition for next time:**

**Flag the premise first:** "same region 70ms" is suspicious — same region should be <5ms in most clouds. Always question inputs.

**#1 Server-side application latency (usually biggest eater):**
- Slow DB queries, missing index, N+1
- Synchronous downstream fan-out
- **JVM GC pauses** — 50-500ms stop-the-world under pressure is common in p99
- Lock contention, thread pool exhaustion
- *Diagnose:* distributed tracing (OpenTelemetry), GC logs, flamegraphs

**#2 Transport / connection-level (even with pooling + TLS 1.3):**
- TLS session resumption failing (LB terminates TLS without shared session cache → full 1-RTT handshake each "new" connection)
- TCP slow start on bursty traffic after idle
- HTTP/2 stream HoL blocking under loss
- gRPC keep-alive timing mismatch with middleboxes
- *Diagnose:* `ss -tnp`, TLS session resumption metrics, Wireshark

**#3 Middleboxes and network path:**
- Service mesh sidecars (Envoy/Istio/Linkerd) — 2-10ms each × 4 hops
- Cross-AZ hops (1-2ms each) adding up
- Packet loss → ~200ms RTO waits for retransmit
- Noisy neighbor CPU steal in cloud VMs
- *Diagnose:* tcpdump for retransmits, traceroute, access logs

**Framework to internalize:**
```
Total latency = client pre-send
              + transport (handshake if any)
              + wire time (RTT)
              + server queue + processing + downstream calls
              + wire time back
              + client post-receive
```
Instrument each stage, find the fat one. **90% of mystery latency is slow DB queries or GC pauses.**

---

### Q7 · Short-answer — Why DNS primarily uses UDP

**Question:**
> Why does DNS primarily use **UDP** when TCP is available? Give **two concrete reasons** and describe **the one situation where DNS falls back to TCP**.

**Learner's answer:**
> (After asking for elaboration) Not sure.

**Score: 2/10** (no attempt)

**Answer:**

**Two reasons UDP is default:**

1. **No handshake cost.** DNS is single-request/single-response. TCP would add 1 RTT handshake before every lookup — for a service whose entire purpose is to *reduce* latency, this is absurd. Every fresh HTTPS request would cost an extra RTT.

2. **Stateless server → massive scalability.** A resolver like `8.8.8.8` handles millions of QPS globally. TCP state (seq numbers, buffers, TIME_WAIT) would need orders of magnitude more memory and hit port exhaustion. UDP = process packet, forget, done.

**Bonus:** DNS payloads are tiny (typical query ~50B, response <512B) — all fits in one UDP packet, no streaming benefit from TCP.

**When DNS falls back to TCP:**

**Response exceeds 512 bytes (UDP DNS limit, RFC 1035).** Server sets the **TC (truncation) bit**, client retries same query over TCP.

Common triggers:
- **DNSSEC** — cryptographic signatures bloat records past 512B
- **Zone transfers (AXFR/IXFR)** — bulk server-to-server zone copies, *always* over TCP
- **Modern privacy DNS:** DoT (DNS-over-TLS) and DoH (DNS-over-HTTPS) run DNS over TCP+TLS deliberately, for privacy (2018+ retrofit)

EDNS0 extends UDP DNS to ~4096 bytes but IP fragmentation + DDoS amplification concerns still push many resolvers to TCP for large responses.

---

### Q8 · Synthesis + spaced revision (topic 00)

**Question:**
> Two microservices in the **same datacenter** communicate over HTTPS with TLS 1.3.
>
> 1. Using latency numbers from topic 00, what's the RTT?
> 2. Total handshake cost (TCP + TLS 1.3) for the first request?
> 3. If server processing is ~5ms, what fraction of first-request total latency is handshakes? Second pooled request?
> 4. Is connection pooling worth the engineering effort here, or is it overkill? Take a position with numbers.

**Learner's answer:**
> 1. 0.5ms
> 2. 2 RTT (one for each tcp and tls1.3) = 1ms
> 3. 1/5*100 = 20%. Second pooled request will use near 0%
> 4. I think no, it seems to be overkill for 1ms per request.

**Score: 7/10**

**Strong:** ⭐ **Topic-00 revision landed.** Same-DC RTT correctly recalled as 0.5ms — up from the 70ms slip in Q2 of this same quiz. Spaced repetition worked within-session.

**Correct:** Q1, Q2 spot-on. Q3 arithmetic directionally right (strict denominator: ~15% of 6.5ms total; 20% of just server-time is fine for napkin).

**Gap on Q4:** Position defensible at **low** QPS but misses the lesson from **Q2 of this same quiz**:

**Why pooling still matters same-DC (at non-trivial QPS):**
1. **TIME_WAIT port exhaustion** — at 5000 req/s, ports run out in ~6s regardless of distance (Q2 insight)
2. **CPU cost of TLS handshakes** — ephemeral DH + cert validation is 1-5ms of CPU per handshake. At 5000 new handshakes/s you saturate a core.
3. **Server-side connection churn** — server has to accept, handshake, allocate, tear down for every request. Scalability collapses.
4. **Tail latency** — p50 looks fine, p99 explodes when CPU saturates or GC kicks in on connection churn.

**Staff-level answer:**
> *"Latency-wise, 1ms is trivial and doesn't justify pooling alone. But operational reasons do: TIME_WAIT port exhaustion, CPU burn on repeated handshakes, p99 tail. Pool always — config change vs outage-waiting-to-happen."*

**Rule:** Distance doesn't change whether you pool. **Pooling is the default; not-pooling requires justification.**

---

## Session rollup

### Strongest
- **Q5 (TLS 1.3 vs 1.2):** correct answer + good instinct pushing back on my imprecise "always over TCP" statement — 7/10
- **Q8 Q1 (spaced revision):** same-DC RTT recalibrated after an in-session slip. Calibration stuck. 2/2

### Weakest
- **Q6 + Q7:** no attempt. Classic Deep-session fatigue around questions 6-7.
- **Q3 Q3:** skipped the Dyn-2016 counterintuitive finding (low TTL hurts during DNS DDoS).
- **Q4:** missed HTTP/2 HoL inheritance — the layer-boundary insight.

### Notes for next session
- **Part 2 (HTTP/1.1 → H2 → H3)** will revisit HoL in depth — good lever for Q4's missed insight.
- **Tracing / debugging scenarios (Q6) need explicit decomposition muscle.** Practice "attribute time to each layer."
- Watch for cognitive fade around Q6-Q7 mark; consider shorter sessions or mid-session breaks.
- Spaced revision worked within-session (Q8). Trust that rhythm.
