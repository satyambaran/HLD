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

---

## 2026-04-19 · Session 3 (Deep, /hld-next) — Part 2 cold quiz + Part 3 teach & quiz

**Final: 48/90 (53%) → Level: 1_intro (unchanged)**

Shape: 6 Qs on Part 2 (HTTP/1→2→3, cold — Part 2 was only written into notes previously, never tested). Then taught Part 3 (gRPC, WebSocket, SSE, long-polling). Then 3 Qs on Part 3, including a mid-quiz pivot where learner flagged that Q9 tested a mechanism (gRPC deadline propagation) I'd name-dropped but not taught. Deep-dive delivered, question re-posed, answered correctly.

---

### Q1 · MCQ + why — HTTP/2 transport-layer HoL

**Question (verbatim as posed):**
> You have a single HTTP/2 connection multiplexing 10 concurrent streams (S1...S10) between a browser and your origin. Mid-flight, **one IP packet carrying frames for stream S3 is dropped on the network**. The packet is eventually retransmitted ~150ms later.
>
> Which of the following best describes what happens to the *other* streams (S1, S2, S4...S10) during that 150ms gap?
>
> - **A)** They proceed normally — HTTP/2's stream multiplexing isolates each stream, so loss on S3 only affects S3.
> - **B)** They stall completely — TCP enforces in-order byte delivery across the whole connection, so frames for S1, S2, S4...S10 that arrived after the gap sit in the kernel buffer and are not delivered to the app until S3's retransmit fills the hole.
> - **C)** They proceed at half throughput — TCP's congestion window halves on detected loss (AIMD), so all streams share the reduced bandwidth but none are blocked.
> - **D)** Only streams whose IDs are lower than 3 (i.e., S1, S2) are blocked, because HTTP/2 stream prioritization preserves ordering for lower IDs.
>
> **Pick one and justify.** What's wrong with each of the wrong options? Bonus: name the HTTP/3 mechanism that fixes this.

**Learner's answer:**
> A: incorrect, it doesnt isolate the streams
> B: correct
> C: all of them are acked and blocked, they are not deleivered to app
> D: incorrect, this ordering is not forced(it was in http/1 but not in http/2)

**Score: 8/10**

**Strong:**
- Correct pick
- **Nailed the subtle ACK≠deliver distinction on C** — packets are ACKed at TCP layer (often via SACK), kernel withholds from app to preserve in-order delivery. That's the staff-level insight.

**Gaps:**
- A justification correct but loose — sharper: H2 isolates at the *framing* layer (frames tagged with stream IDs interleave on wire), but the underlying byte stream is still one TCP connection which is where HoL bites
- D: H2 priority is a hint-based dependency tree (RFC 7540 §5.3); no "lower-ID-first" guarantee ever existed in any HTTP version
- **Missed bonus:** QUIC maintains sequence numbers **per stream**, not per connection. Each stream's bytes are ordered independently in QUIC's reassembly buffer — loss on stream A only stalls stream A.

---

### Q2 · Short-answer — Why QUIC picked UDP

**Question (verbatim as posed):**
> Google built QUIC on top of **UDP** rather than designing a brand-new transport protocol or extending TCP. People often summarize this as "UDP is faster" — but that's a buzzword answer.
>
> **Give the real reason in 2-3 sentences.** Specifically:
> 1. What forced QUIC to live in *userspace* rather than the kernel?
> 2. Why was a new TCP-like protocol (a fresh IP protocol number) considered impractical?
>
> Hint: the words "ossification" and "middlebox" should appear in any good answer.

**Learner's answer:**
> Kernel's TCP stack enforced strict in-order byte delivery across the whole connection, that's why they didnt try to extend tcp. TCP is implemented in the OS kernel and changes would require every OS(mac windows linux android, ios) to update. Even middlebox ossification about the TCP packet shape and all breaks the middleboxes like NATs firewalls etc.

**Score: 7/10**

**Strong:** Got both kernel ossification and middlebox ossification clearly.

**Gap — missed the third leg: protocol-number ossification.**
- You might think "skip TCP, invent a new transport with a fresh IP protocol number (like SCTP = 132)." Doesn't work — most home routers, corporate NATs, ISP firewalls drop any IP packet that isn't TCP (6), UDP (17), or ICMP (1). SCTP is effectively unroutable on the public internet.
- UDP is the only viable "escape hatch" — universally permitted, thin-enough kernel abstraction that real protocol work happens in userspace above it.

**Also small conflation:** in-order delivery is the *motivation* (problem QUIC wanted to fix), not the *deployment constraint* (why UDP + userspace). Keep those two separate.

**Clarification asked later (taught):** full userspace-vs-kernel breakdown with TCP-in-kernel vs QUIC-in-app-process, including CPU cost, iteration-speed wins, tooling maturity trade-offs.

---

### Q3 · Scenario — Protocol pick for consumer video-calling mobile app

**Question (verbatim as posed):**
> You're the tech lead on a **consumer video-calling mobile app** (think: next-gen FaceTime / WhatsApp video). Clients are ~70% cellular, ~30% Wi-Fi. Users commonly walk out of a Wi-Fi zone onto cellular mid-call. Packet loss on mobile averages 1-3%, spikes to 10%+ in poor coverage.
>
> Your architecture already has:
> - Mobile app → CDN edge (TLS-terminating) → origin API (REST + gRPC)
> - A separate media path for the actual audio/video frames (RTP over UDP)
>
> **Question:** For the **control/signaling channel** (login, presence, call-setup RPCs, metadata) between the mobile app and your edge — which protocol would you pick: **HTTP/1.1, HTTP/2, or HTTP/3**? Justify with at least **three** distinct technical reasons tied to the scenario (the specifics: lossy network, mobility, signaling workload). Also name **one downside** you're knowingly accepting.

**Learner's answer:**
> I would pick HTTP/3 as it uses QUIC which handles the connection change of user very swiftly in case of lossy networkm mobility and signaling workload). Downsides are higher cpu cost(userspace udp stack) along with some places udp often gets blocked/throttled.

**Score: 4/10**

**Picked right, gave one distinct technical reason (connection migration) with the rest implied by the prompt's own words.** "Three distinct technical reasons tied to scenario" was the explicit ask — each claim needs a specific mechanism.

**Ideal three mechanism-grounded reasons:**
1. **Connection migration** — QUIC IDs connection by opaque connection ID, not 4-tuple. Wi-Fi → cellular IP change doesn't kill the connection; client sends packet from new IP with same connection ID. No 200-500ms blackout, no re-handshake, no re-auth.
2. **Per-stream ordering eliminates transport HoL on lossy paths** — at 1-3% loss, H2 over TCP routinely stalls every multiplexed signaling RPC behind one lost packet. QUIC's per-stream sequencing means a stalled presence ping has zero impact on a call-setup RPC.
3. **Integrated 1-RTT (or 0-RTT) handshake** — TCP + TLS 1.3 = 2 RTTs; QUIC = 1 RTT (or 0 with PSK). On cellular RTTs of 80-200ms, saves 80-200ms every reconnect.

**Full downside set:** CPU/battery on mobile; UDP blocking on enterprise Wi-Fi; tooling immaturity; edge→origin is still H2/TCP so H3 wins only apply on client→edge leg.

---

### Q4 · Short-answer — HTTP/2 Server Push deprecation

**Question (verbatim as posed):**
> Many old design articles and even some interview prep material still recommend **HTTP/2 Server Push** as a way to "send critical resources to the client before they ask for them" — e.g., pushing `style.css` and `app.js` along with the response to `/index.html`.
>
> **Why was Server Push effectively deprecated** (Chrome disabled it by default in 2022, and HTTP/3 dropped it from the spec)? Be specific about the **mechanism** that broke, not just "it didn't work well."
>
> Then: **what replaced it** for the legitimate use case of "tell the client about resources it'll need before the main response is ready"? Name the HTTP status code and what it's called.

**Learner's answer:**
> It used to push some might be needed resources even before client has asked(there might be some scenario where it could be cached already and not needed) and banwidth got wasted. Mechanism which replaced it is `103` `Early Hints` sends preload link before sending full response is ready

**Score: 6/10**

**Got:** Symptom (wasted bandwidth on cache hits) and named `103 Early Hints` correctly.

**Missed the deeper mechanism:**
- **Server has no way to know client cache state.** No protocol-level mechanism for browser to tell server "I already have style.css v3.7" before requesting /index.html. Push is forced binary lose-lose: always push (waste on cache hits) or don't push (defeats purpose).
- **Browser cache ↔ push-stream matching was buggy across implementations.** Pushed streams sat in "unclaimed pushes" buffer; browser matched on HTML parse. Led to double-fetch bugs (browser fetches the same resource a push is in-flight for).

**Why Early Hints is the right fix:** it's a *hint*, not data. `Link: </style.css>; rel=preload` in a 103 interim response → client does its own cache check (client knows what it has) → only fetches if needed. Decision lives on the cache-aware side.

Pattern to internalize: **push a hint, not the bytes** — let the cache-holder decide.

---

### Q5 · Scenario — When HTTP/1.1 wins: service mesh

**Question (verbatim as posed):**
> You're designing a **service mesh** for an internal microservice architecture: ~200 services, all running inside the same datacenter / VPC, behind mTLS. Average request size: 4 KB request, 10 KB response. Median network loss between services: <0.01% (essentially zero). RTT between services: 0.5-2 ms.
>
> Your platform team is debating whether the mesh sidecar (e.g., Envoy / Linkerd-proxy) should default to **HTTP/1.1 with keep-alive + connection pooling** or **HTTP/2** for service-to-service traffic.
>
> **Argue the case for HTTP/1.1 here.** What about *this specific environment* erodes HTTP/2's usual advantages? Give at least **two** technical reasons. Then state under what condition you'd flip the recommendation back to HTTP/2.
>
> (Hint: think about what HoL blocking, multiplexing, and HPACK each *cost* — not just what they buy.)

**Learner's answer:**
> Not sure

**Score: 0/10** (no attempt — contrarian question, kept the honest admission)

**The argument structure to internalize: every H2 advantage has a precondition that may not hold here.**

**H2's usual wins eroded:**
1. **Multiplexing's value is gone** — sidecar already pools 20-50 long-lived H1.1 connections per upstream. Parallelism exists. Multiplexing 50 streams on one conn vs 50 parallel H1.1 conns in clean DC is a wash.
2. **HPACK saves nothing here** — internal service-to-service reqs have 200-500B of headers (trace ID, auth token). 80% compression on 300B = 240B saved on 14KB exchange = 2% bandwidth.
3. **No HoL fix needed** — at <0.01% loss, multiplexing-over-TCP's HoL vs pipelined-H1.1's HoL never actually bites.

**What H2 *costs* you:**
4. **Bigger blast radius on connection failure** — H1.1 + 20-conn pool, one dying = 1/20 requests fail. H2 multiplexing 200 streams on 1 TCP = 200 streams die together.
5. **Flow-control complexity = prod bugs** — H2 per-stream WINDOW_UPDATE math has caused grpc-go, nginx, Envoy CVEs/deadlocks.
6. **CPU in sidecar** — H2 framing, HPACK, stream state, pings cost measurable CPU at 100K req/s.
7. **L4 LB distributes less evenly** — 1 H2 connection carrying 200 streams lands all load on one backend; 200 H1.1 conns spread across 20 backends.

**Flip back to H2 when:** gRPC (mandatory H2), long-lived streaming RPCs, bidi patterns, genuinely-big headers (heavy auth tokens + trace baggage).

**Interview tell:** direction of reasoning matters more than conclusion. "H1.1 is fine intra-DC because H2's preconditions don't apply" sounds staff-level; "always H2" sounds junior.

---

### Q6 · Spaced revision — Napkin math (topic 00)

**Question (verbatim as posed):**
> Pulling from your weakest area on topic 00 (streaming-workload modeling).
>
> **Scenario:** You're sizing capacity for an Uber-style location-tracking service.
> - 5 million active drivers worldwide at peak
> - Each driver's app emits its GPS location **every 4 seconds** while driving
> - Each location update payload: 200 bytes (driver_id + lat + lng + heading + speed + timestamp + protobuf overhead)
> - The locations are written to a hot store (Redis Geo) and tee'd to a Kafka topic for downstream analytics
>
> **Compute the following — show your math, don't just give numbers:**
>
> 1. **Write QPS** to the hot store (per second, peak).
> 2. **Ingress bandwidth** at the location-ingest service (in MB/s and Mbps — both, please).
> 3. **Daily storage** if every event is durably retained on Kafka for 7 days (assume no compression).
> 4. **Replication factor of 3** on Kafka — what does that do to the storage number?
>
> Then: **one design observation.** Looking at your numbers, what's the *first* bottleneck you'd worry about, and why?

**Learner's answer:**
> DAU=5M, driver app emit rate =1/4s, payload = 200B.
> assuming average ride duration 25 mins, number of rides per day = 30
> peak=3*average
>
> bandwidth = 5M*30*(25*60)/86400/4 * 200 B = 150M*1500*50B/86400 = 1.5*1.5*5/86.4 GBps = 125 MBps
> peak bandwidth = 375 MBps
>
> peak qps = 375MBps/0.2KB = 375*5*1000 qps = 1.7M qps
>
> Daily storage = 125MBps*86400*7  = 12 TB for each day*7
>  = near 100 TB
>
> With replication factor =3, storage needed will be around 300TBmm

**Score: 5/10**

**Strong:** Used average for storage (not peak) — key conceptual win most candidates miss. Implicit Little's Law in deriving average concurrent drivers. RF × storage math right.

**Gaps:**
- **Misread prompt.** "5M active at peak" is already the peak concurrent number. No need to derive from DAU × rides × duration. In interview this wastes 4-5 min + compounds error.
  - Clean read: 5M ÷ 4s = **1.25M peak QPS**
- **Missed Mbps conversion** (question asked for both MB/s and Mbps): 250 MB/s × 8 = **2,000 Mbps = 2 Gbps**
- **Arithmetic slip:** 375 ÷ 0.2 = 1,875K, not 1.7M
- **No design observation.** Whole point of napkin math is to drive a design decision.

**Ideal design observation:** Bandwidth and storage are trivially horizontal. **Real bottleneck: Redis Geo hot-key writes.** GEOADD is single-threaded per shard; at 1.25M writes/sec needs 10+ shards. Events cluster geographically (Manhattan 6pm) → naive geohash sharding creates hotspots. Picking the shard dimension (driver_id hash vs S2 cell vs hybrid) **is the design problem**; numbers are a sanity check.

---

### Q7 · MCQ + why — Protocol for LLM streaming API

**Question (verbatim as posed):**
> You're building the streaming API for a **large language model product** (think ChatGPT / Claude). The core UX: user sends a prompt (single HTTP request), and the model streams response tokens back as they're generated — a user sees text appearing character-by-character. Typical stream: 500-2000 tokens over 3-15 seconds. Clients are browsers (web app) and mobile SDKs.
>
> Which protocol would you pick for the streaming response channel?
>
> - **A)** WebSocket — because tokens are streaming in real-time and WebSocket is the default real-time choice.
> - **B)** Server-Sent Events (SSE) — because the direction is one-way (server → client), it's plain HTTP so it passes through CDNs/proxies/corporate firewalls, and auto-reconnect with resume is browser-native.
> - **C)** gRPC server-streaming — because typed Protobuf contracts are strictly better than loose JSON, and H2 multiplexing handles parallel chats.
> - **D)** Long-polling — because it's the simplest and most universally compatible option.
>
> **Pick one and defend it on at least two axes.** Then: give one concrete reason each wrong option loses to your pick — not just "it's worse." Bonus: what specific HTTP response header is essential for this to work over a reverse proxy like nginx?

**Learner's answer:**
> B SSE:- It's oneway(server->client), supports auto-reconnect(in case of connection breaks). Users payload are once in a while events, can be handled by sepearate http post request. gRPC has no retry loogic. Long polling is not usable because LLMs usually takes some time and then sends a burst of tokens(bursty traffic)
>
> My choice SSE provides Last-Event-Id for retry in case of connection break and also we need only oneway connection. Response header Content-Type: text/event-stream.

**Score: 7/10**

**Strong:** Correct pick. Two solid axes (one-way + auto-reconnect). Nice observation that user prompt rides a separate POST.

**Gaps:**
- **Long-polling rationale off-target.** It handles bursts fine (holds conn, responds when data). *Real* reason it loses: 500-2000 tokens via long-poll = 500-2000 HTTP round trips per prompt to preserve token-by-token UX. Batching kills the real-time feel.
- **gRPC rationale imprecise.** gRPC *does* have retry/deadline mechanisms. Real reasons: browsers only speak gRPC-Web (subset); no native reconnect/resume for gRPC streams; Protobuf codegen overkill for streaming text; JSON-over-SSE is the ecosystem default for LLM APIs.
- **Bonus partial credit.** `Content-Type: text/event-stream` IS essential for browser to treat it as SSE. But the *proxy-specific* gotcha is **response buffering**. Nginx default buffers proxy responses in 4-8KB chunks → user sees nothing for seconds, then bursts.
  - Per-response fix: `X-Accel-Buffering: no`
  - Server-config fix: `proxy_buffering off;`
  - Also: `Cache-Control: no-cache` to prevent intermediate caching.

---

### Q8 · Scenario — WebSocket collab-editor scaling

**Question (verbatim as posed):**
> You're the tech lead on a **real-time collaborative editor** (think Google Docs / Figma). At scale: **5 million concurrent connected users globally**, editing documents with 1-30 collaborators each. Clients send keystrokes + cursor positions; server broadcasts operational transforms to all collaborators on that document. You've picked **WebSocket** (correctly — it's bidi, low per-message overhead, classic use case).
>
> Your naive first architecture:
> ```
> clients ───► L7 LB (AWS ALB) ───► WS fleet (100 hosts, 50K conns each)
>                                        │
>                                        └─► in-process pub/sub: each host holds
>                                            the doc state for connections on it
> ```
>
> Problem: users on document `D` whose WebSocket connections land on *different* hosts can't see each other's edits. Host A has 3 users on doc D; host B has 2 users on doc D. Host A doesn't know about host B's users.
>
> **Walk me through the fix.** Specifically:
> 1. What component do you introduce between the WS hosts to make edits fan out across the fleet?
> 2. What's the ordering/consistency guarantee you need (think about OT / CRDT)?
> 3. What's the blast radius when one of your 100 WS hosts dies — how many users reconnect, to where, and what do they re-sync from?
> 4. Name one thing about WebSocket that makes graceful deploys (rolling restarts) harder than for stateless HTTP services.
>
> Don't over-engineer. 4-6 sentences per sub-question max.

**Learner's answer:**
> There should be central component which merges the documents of host A and host B. Later send it to respective WS which will send to users.
>
> We can use operational transformation in the central component to acheive eventual consistency.
>
> When one of our host from WS fleet dies, near 50K users gets affected. After disconnecting they can try reconnect using the same http api call to existing host nodes or the new nodes which gets provisioned and later it will get upgraded in websockets. Newly provisioned host will fetch the truth from the central component.
>
> not sure

**Score: 4/10**

**Right shape on answered parts, missing concrete mechanism on every one.**

**Sub-1 — fan-out:** "central component" conflates two things. Standard architecture: **(a) Doc server** (sharded by doc_id, owns OT/CRDT state, single-writer per doc) + **(b) Pub/sub layer** (Redis pub/sub / Kafka / Pulsar) for fanout across WS hosts. You missed pub/sub explicitly — without it, doc server would have to know which WS host has which user (unwanted coupling).

**Sub-2 — ordering:** OT named correctly. Missed: **per-document ordering must be preserved end-to-end.** Pub/sub must support per-key ordering (Kafka with partition-by-doc-id, Redis Streams per doc). Naive Redis pub/sub doesn't preserve ordering. Right term is **strong eventual convergence**, not plain eventual consistency.

**Sub-3 — blast radius:** right headline. Missed:
- Re-sync from **version cursor**, not from scratch. Client tracks last-seen op version; on reconnect sends `last_seen_op=V`; doc server replays V+1...current.
- **Reconnect storm** — 50K simultaneous reconnects melt auth + doc server + pub/sub. Mandatory **exponential backoff with jitter** client-side.
- **Cold-cache thundering herd on new host** — 50K reconnects → 50K doc-server lookups on empty cache. DDoSes doc server. Mitigation: gradual connection allocation, doc-server cache + request coalescing.

**Sub-4 — graceful deploys:** This is the #1 operational pain of WebSocket at scale.
- WS connections are long-lived (hours); stateless HTTP deploys via 30-60s drain. WS has no equivalent.
- Two bad choices: **hard close** (50K reconnect storm) or **drain** (could take hours, blocks deploy).
- Production fix is a combination: (a) server sends in-band `{"action":"reconnect"}` message *before* close, (b) restart 5-10% of fleet at a time with settle time between waves, (c) client implements randomized backoff, (d) LB-level blue/green, (e) stateless reconnection via pub/sub + version cursors means any host can pick up any client.

---

### Q9 · Short-answer — gRPC deadline propagation

**Question (verbatim as posed, first attempt):**
> Your team is migrating an internal Java microservice from REST/JSON to gRPC. After the migration, you notice a strange production incident: **service A's deadlines aren't being respected by downstream service C**. Specifically, A calls B with a 200ms deadline; B calls C; C runs for 500ms with no error; A times out and retries; but C continues executing the original request anyway, doing duplicate work.
>
> **Two-part question:**
>
> 1. What is gRPC's mechanism for **deadline propagation** supposed to do here, and why isn't it working in this scenario? Specifically, what is the gRPC metadata header involved, and what does each service in the chain do with it?
> 2. What's the most likely **bug** causing C to ignore the deadline? (Hint: it's not a missing header — it's about *how the application code uses the deadline once it receives it*.)

**Learner's first-attempt answer (verbatim — including the feedback that drove the pivot):**
> It's probably deadline is not propagating correctly.
>
> I feel like you are asking question which you have not taught me yet. I like the questions' level but concept teching input is low.

**Pivot action taken (mid-quiz, by teacher):**
- Acknowledged feedback as valid — Q9 tested mechanism (`grpc-timeout` wire format, Context propagation, thread-hopping bug) that was only name-dropped in Part 3 notes, not taught with internals depth.
- Saved feedback memory `feedback_quiz_teaching_density.md` to enforce the rule going forward: every quiz question must test a mechanism that was actually taught with depth.
- Delivered inline mini-deep-dive in chat covering: (a) `grpc-timeout` header format `<int><unit>` (e.g., `200m` = 200ms; units H/M/S/m/u/n), (b) per-hop subtraction of elapsed time, (c) `Context.current().getDeadline()` in gRPC-Java, (d) the canonical broken pattern (`executor.submit(...)` without `Context.current().wrap(...)` strips deadline from new thread's empty Context), (e) the fix patterns (`Context.current().wrap(runnable)` or explicit `cStub.withDeadline(deadline)`), (f) deadline-as-signal-not-kill (must wire into JDBC `setQueryTimeout`, HTTP client read timeouts, periodic `Context.current().isCancelled()` checks in CPU loops), (g) retry × idempotency interaction (even with perfect propagation, A's retry can race C's still-running original → idempotency keys still required for mutating RPCs).
- Re-posed the same Q9 with the mechanism now on the table.

**Question (re-posed, verbatim):**
> Re-posing the question with the same setup:
>
> **Scenario recap:** A calls B with 200ms deadline; B calls C; C runs for 500ms; A retries; C keeps running the original.
>
> 1. What is the gRPC metadata header involved, and what does each service do with it?
> 2. What's the most likely application bug causing C to "ignore" the deadline?
>
> Take a fresh swing now that the mechanism is on the table.

**Learner's post-teach answer (verbatim):**
> grpc-timeout, they need to follow what they have receive and forward it's updated values to the next server.
>
> B not propagating grpc-timeou

**Score: 7/10** (post-teach — first attempt was discounted as the teaching-density issue was on the teacher, not the learner)

**Correct on both parts, tersely.**

**Q1 sharpening:** Framework reads `Context.current().getDeadline()` (deserialized from inbound `grpc-timeout`) and serializes remaining time into outbound `grpc-timeout` — *if Context is propagated correctly across the call.*

**Q2 sharpening:** Most common cause = **thread-hopping**. B's handler dispatches downstream call via `executor.submit(...)` without `Context.current().wrap(...)`; new thread's `Context.current()` is the empty JVM-default with no deadline → outbound stub has nothing to encode → C receives no `grpc-timeout` → framework has nothing to cancel. Other variants: explicit stub without `withDeadline(...)`, deadline lost across reactive / CompletableFuture chains.

**Validation of the teach-then-test pivot:** learner went from "I'd guess deadline isn't propagating" (pre-teach) to nailing both parts (post-teach) — exactly the intended outcome. Also a strong meta-signal: knowing what you don't know and naming the gap is interview-ready behavior on its own.

---

## Session rollup

### Strongest
- **Q1 (H2 transport HoL):** nailed the subtle ACK≠deliver distinction — 8/10
- **Q7 (LLM streaming SSE):** correct pick with good auto-reconnect insight — 7/10
- **Q9 (post-teach):** locked the feedback loop — correct diagnosis after deep-dive — 7/10
- **Self-awareness:** correctly flagged that Q9 tested a mechanism not adequately taught → drove the only memory save of the session

### Weakest
- **Q5 (H1.1 in service mesh):** no attempt. Contrarian questions about when older protocol wins need explicit practice.
- **Q8 sub-4 (WS graceful deploys):** no attempt. Worth standalone deep-dive.
- **Q3 (video-calling scenario):** "three distinct technical reasons" requirement not met — pattern of relying on scenario words instead of specific mechanisms.
- **Q6 (napkin math):** misread "5M at peak" as DAU → overcomplicated the problem. Also forgot Mbps conversion.

### Notes for next session
- **Pattern to watch:** when a question asks "give N technical reasons," each needs a named mechanism, not a restatement of scenario words.
- **Deep dives queued:** WebSocket at scale (connection migration ≠ WS; WebTransport; reconnect storms; graceful deploy patterns). gRPC Java production patterns (Context, interceptors, deadline propagation, retry policies).
- **Interview drill:** read prompt units carefully — "active at peak" vs DAU is a recurring trap.
- **Spaced revision landed** on napkin math (topic 00) but showed the same "over-derive" failure mode. Worth another targeted rep on input-parsing.

