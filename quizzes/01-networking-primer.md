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

---

## 2026-04-20 · Session 4 (Deep, /hld-next — consolidation) — All 3 parts mixed

**Final: 44/90 (48.9%) → Level: 1_intro (unchanged — below 60% Practiced threshold)**

Shape: 8 Qs consolidating all 3 parts of topic 01 (TCP/DNS/TLS + HTTP versions + gRPC/WS/SSE), plus 1 spaced-revision Q on topic 00 (napkin math input-parsing). Goal was to push 01 → 2_practiced. Missed by ~10 percentage points; 3 specific mechanism gaps identified for immediate deep-dive (Anycast, WS Close frames, L4 LB granularity in mesh).

---

### Q1 · Scenario — Mobile TCP connection lifecycle

**Question (verbatim):**
> You're the on-call engineer for a mobile-banking app. The app on a user's phone hits your `/api/balance` endpoint. Typical user pattern: one request every ~30 seconds for a few minutes while the app is in foreground, then the screen goes to background.
>
> Your client SDK currently **closes the TCP connection after each response**. A teammate argues: *"We should switch to a persistent connection — keep it warm, reuse it."*
>
> **Answer three things, concretely:**
> 1. What does the client pay (in measurable quantities — RTTs, CPU, bytes) for opening a fresh TCP+TLS connection on every request? Give me a rough number for the handshake cost.
> 2. What does the **server side** pay if every active phone holds a persistent connection open? Name the specific resource that gets pressured.
> 3. Make the call for this workload. Keep-alive or close-after-each? Defend it in one sentence.

**Learner's answer (verbatim):**
> 1. Client pays TCP(1 RTT), TLS1.3(1 RTT), https conn(1 RTT) for opening a fresh TCP+TLS connection every request. ALso, since client is closing the connection it needs to wait for 30s-120s TIME_WAIT. Roughly the latency will be around 3 RTTs.
> 2. Servers CPU usage will increase.
> 3. If it's in the same DC then using closeafter-each makes sense. No need to keep-alive. It's very similar to long polling so latency doesnt matter that much in this case but server cpu usage does.

**Score: 4/10**

Foundation is there, but two mechanism-level reversals flipped the final call the wrong way.

**What you got right:**
- **RTT decomposition (partial):** TCP 1 RTT + TLS 1.3 1 RTT is correct. But there's no separate "https conn" RTT — HTTPS *is* HTTP running over that TLS channel. So for TLS 1.3 it's **2 RTTs to first byte**, not 3. (TLS 1.2 would be 3.) You padded an extra RTT that doesn't exist.
- **TIME_WAIT flag:** Good instinct to surface it. But you applied it to the wrong axis — TIME_WAIT doesn't add latency to the *next* request (the port is held, not the latency). It's a **resource pressure** issue, which actually belongs in answer (2), not (1).

**What you got wrong:**

**1. Reversed the server-side cost.** Persistent connections *decrease* server CPU, not increase. The CPU-expensive part of HTTPS is the **TLS handshake** — asymmetric crypto (ECDHE key agreement, cert signature verify). An idle keep-alive connection costs almost no CPU; it costs **file descriptors / kernel socket buffers / memory** (~tens of KB per idle conn) and eats into the server's `ulimit -n` and load balancer connection caps. So the pressured resource is **file descriptors + memory**, not CPU. Close-after-each actually *raises* server CPU because you pay a fresh handshake every time.

**2. Missed the #1 mobile-specific cost.** On a phone, every fresh TCP+TLS setup **wakes the LTE/5G radio from idle state**. Radio wake-up burns battery disproportionately — a 2 RTT handshake may trigger ~5s of radio-active state. For a banking app pinging every 30s, this is the dominant cost, not CPU.

**3. Wrong final call + bad analogy.** Correct answer for a 30s-cadence foreground mobile workload: **keep-alive, with a bounded idle timeout (~60-90s)**. You get handshake reuse while active, and the connection dies naturally when the user backgrounds the app. This is literally what OkHttp / Alamofire / URLSession do by default. Long-polling is a *different* pattern (client holds a single request open waiting for server data) — don't conflate "persistent connection" with "long-poll."

**Ideal answer, crisp:**
1. **Client cost:** 2 RTTs to first byte on TLS 1.3 (3 on TLS 1.2) + ~2-5 KB cert chain + ECDHE CPU + **radio wake-up on mobile** (the killer). Roughly 150-300ms added latency cross-region.
2. **Server cost of persistence:** not CPU — **file descriptors, socket buffers, and LB connection slots**. Every idle conn holds kernel memory + an FD. Scales painfully with millions of phones.
3. **Call:** keep-alive with short idle timeout. Handshake amortization + radio/battery savings >> the FD cost at reasonable scale. Use load-balancer `keepalive_timeout` to cap.

---

### Q2 · MCQ + why — DNS failover and stuck 15% of clients

**Question (verbatim):**
> Your service is deployed behind a geo-DNS load balancer (e.g., Route 53 latency-based routing). DNS records have a **TTL of 60 seconds**. During a regional failover, you flip the DNS records to point to the healthy region. You observe that **~15% of clients continue hitting the dead region for 10+ minutes** after the flip.
>
> Which of the following is the **single most likely** explanation? Pick one and justify — and tell me what's wrong with the distractors.
>
> **A.** Route 53's propagation to its own edge resolvers is slow (takes ~10 min globally).
> **B.** Intermediate DNS resolvers (ISPs, corporate) are ignoring or clamping the 60s TTL.
> **C.** Browsers and OS resolver caches store their own DNS entries independent of TTL.
> **D.** The clients have connection-pooled HTTP/2 connections to the dead region's IP and never re-resolve DNS.

**Learner's answer (verbatim):**
> Since percentage of client usage is on lower side(15% only), I feel it might be due to connection pooling.

**Score: 6/10**

Right pick, right instinct — but the defense is thin, and you skipped the distractor analysis that the question explicitly asked for. In an interview round, "15% seems lower, so connection pooling" is a good lead but leaves the interviewer hungry for mechanism depth.

**What you got right:**
- **Picked D — the correct answer.** Well spotted.
- **Used the 15% figure as the signal.** Correct reasoning — *a minority stuck for a long time* is the fingerprint of per-client pooling, not per-resolver caching (which would hit a wide swath).

**What's missing:**
- **The named mechanism.** HTTP/2 uses a **single long-lived, multiplexed TCP connection** per origin. DNS resolution happens **at connection establishment**, not per request. Once the connection is open, the client keeps sending frames over it — it never re-consults DNS. Well-behaved HTTP/2 connections live for tens of minutes (kept alive with PING frames). 10+ minutes of stickiness is completely normal for this. The connection only dies when: (a) TCP breaks, (b) the server sends `GOAWAY`, or (c) the client hits an idle timeout.
- **Distractor rebuttals.** The question asked you to name what's wrong with A/B/C. Always do this — it's 40% of the grade in a real design round.

**Ideal distractor breakdown:**

| Opt | Plausible? | Why it's not the best fit |
|---|---|---|
| **A** | False | Route 53's own propagation to its edge resolvers is fast (seconds to low-minutes). 10-min propagation is a myth conflated with resolver caching. |
| **B** | Real phenomenon | ISPs DO clamp/ignore TTLs (classic DNS lie). BUT if this were the cause, you'd see **majority stuck**, not 15%. Resolver-level caching is not cohort-selective. |
| **C** | Real but weak | Browsers (Chrome) honor TTL fairly well; OS caches short. The big exception is **Java's `InetAddress`** — historical `networkaddress.cache.ttl=-1` caches forever. Real but narrow; 10 min is still unusual without a JVM client. |
| **D** | **Correct** | HTTP/2 long-lived connections bypass DNS entirely for the lifetime of the connection. Explains the small-cohort, long-tail stickiness precisely. |

**Operational fix (interview follow-up bait):** The real-world fix for this is **NOT** "lower TTL." Lowering TTL doesn't help pooled clients. Real fixes:
- Send **`GOAWAY`** from the dead region's LB → forces HTTP/2 clients to re-establish (and re-resolve DNS).
- **Shift to IP-level failover** (BGP/anycast + VIP withdrawal) rather than DNS failover. This is why Cloudflare/AWS ELB use anycast instead of DNS-based for fast failover.
- **Client-side connection age limits** (max connection lifetime, e.g., 5 min) — forces periodic re-resolve. Envoy does this.

---

### Q3 · Short-answer — 3 named HTTP/3 mechanisms helping mobile vs HTTP/2

**Question (verbatim):**
> A team is migrating from HTTP/2 to HTTP/3 (QUIC over UDP) for their mobile-heavy client base. They claim: *"HTTP/3 is strictly better for us."*
>
> **Name three distinct, named technical mechanisms** by which HTTP/3 improves the experience for mobile clients specifically — versus HTTP/2. Each mechanism must be a **specific protocol-level feature**, not a generic outcome like "it's faster" or "better on bad networks."
>
> For each mechanism:
> - **Name it** (e.g., "0-RTT resumption")
> - **What problem it solves** that HTTP/2 could not
> - **Why mobile clients benefit more** than, say, a datacenter-to-datacenter H/3 link

**Learner's answer (verbatim):**
> Mobile can switch connection which http/3 handle with 0 RTT where as http/2 will take at least 2 RTT(TCP + TLS1.3). 0RTT resumption. Datacaentres usually do not face this problem as they have the same connection throughout.
> Quic over UDP has parallel streaming which helps in delivering packets in low bandwidth.
> Quic has TLS1.3 integrated in it, saves 1 RTT.

**Score: 4/10**

This is **the exact failure pattern we've been circling**. You have the right territory in mind for all three, but you're naming outcomes and buzzwords instead of specific protocol mechanisms. Two of the three are mis-named, and one conflates two separate features.

**Where each answer broke:**

**#1 — "Mobile can switch connection, handled by 0-RTT resumption."**

You've correctly identified the **scenario** (Wi-Fi ↔ LTE handoff) but named the **wrong mechanism**. These are two different QUIC features:

| Feature | What it does | When triggered |
|---|---|---|
| **Connection migration** | Client changes IP/port; server still recognizes the connection because the QUIC header carries a **Connection ID** independent of the 5-tuple | Network switch (Wi-Fi → LTE) |
| **0-RTT resumption** | Client reuses a cached TLS session ticket to send app data in the *first* packet when reconnecting to a previously-seen server | Cold reconnect after connection loss |

For the Wi-Fi → LTE case, the mechanism is **Connection ID + connection migration**, not 0-RTT resumption. HTTP/2 over TCP is screwed here because TCP's identity IS the 5-tuple — change the source IP and the connection is dead; you pay full TCP+TLS (2 RTT).

**#2 — "QUIC has parallel streaming which helps in low bandwidth."**

HTTP/2 **also** has multiplexed streams. That's not the differentiator. The real named mechanism is:

> **Per-stream loss recovery / no transport-layer head-of-line blocking.**

In HTTP/2, all streams share **one TCP byte stream**. A single lost TCP packet stalls EVERY multiplexed stream until retransmission arrives (~1 RTT). In QUIC, each stream has independent sequencing — loss on stream A does not block stream B.

Also: this helps with **packet loss**, not "low bandwidth." Mobile networks have elevated loss rates from radio interference / handoffs, not necessarily bandwidth scarcity. Low bandwidth is a different problem (solved by congestion control, compression).

**#3 — "QUIC has TLS 1.3 integrated, saves 1 RTT."**

✅ Correct mechanism, correctly named. But missing the "why mobile specifically benefits more" part:

> Mobile links have 50-150ms RTT vs. 1-5ms intra-datacenter. Saving one RTT on a 100ms link is a 40-50% reduction in handshake time; on a DC link, it's noise.

**The cleanly-named three:**
1. **Connection migration via Connection ID** — survives Wi-Fi/LTE handoffs without a new handshake. (HTTP/2: connection dies with the 5-tuple.)
2. **Per-stream loss recovery (no transport HoL blocking)** — one lost packet doesn't stall unrelated streams. (HTTP/2: lost TCP segment freezes all multiplexed streams.)
3. **1-RTT combined transport+TLS handshake** (or 0-RTT on resume) — QUIC folds TLS 1.3 into the transport handshake. (HTTP/2: TCP + TLS = 2 RTT.)

All three are mobile-dominant because mobile clients: (a) switch networks, (b) see 2-5% packet loss vs. ~0% in DC, (c) pay high RTT where handshake savings are amplified.

**Pattern to internalize:** When an interviewer asks "name N technical reasons," your answer template should be:
```
Mechanism: <specific named protocol feature>
Problem it solves: <what the older protocol couldn't>
Why this cohort benefits: <environment-specific amplification>
```

You tend to reach for scenario-level language ("parallel streaming", "switch connection", "low bandwidth") — that's the gap between Intro and Practiced. Named mechanisms are what an interviewer is scoring for.

---

### Q4 · Short-answer — WebSocket graceful deploy (retest)

**Question (verbatim):**
> You operate a chat service with **500,000 concurrent WebSocket connections** pinned to a fleet of 50 app servers (~10k conns each). You need to deploy a new version of the service. A naive rolling deploy that just kills an old pod and replaces it would disconnect ~10k users per pod with a TCP RST.
>
> **Answer three parts:**
>
> 1. What is the **server-initiated mechanism** in the WebSocket protocol that tells a connected client "please go away cleanly"? Be specific about the **frame type** and what the server sends in it.
>
> 2. What must the **client library** be written to do when it receives that signal? (i.e., what behavior turns the server's "please leave" into a seamless user experience)
>
> 3. There's a classic problem if **all 10k clients on a pod reconnect simultaneously** the instant they're told to disconnect. Name the problem and name the **mitigation** — both the client-side change and the server/infra-side change.

**Learner's answer (verbatim):**
> 1. Server sends {"action":"reconnect"} before closing the connection for please go away cleanly. Client needs to implement randomized backoff. Server can use pub-sub based stateless reconnects. We want to avoid hard-close for each connections and drain. We can also use LB level blue-green deployment.

**Score: 3/10**

You've gestured at the ecosystem but missed the **specific named mechanism** the WebSocket protocol gives you — which was the whole point of part 1. You've also smeared parts 2 and 3 together.

**The critical miss on #1:**

You wrote `{"action":"reconnect"}`. That's an **application-level JSON message** — which of course you could send, but it's NOT the WebSocket protocol mechanism, and it has no standard semantics. The actual answer:

> The server sends a **Close frame (opcode 0x8)** with **close code `1001 — "Going Away"`** and optionally a reason string.

Per **RFC 6455 §5.5.1**, the Close frame is the graceful-shutdown signal. Close codes include:
- `1000` — normal closure
- `1001` — **going away** (server shutting down / deploying) ← the one you want
- `1002` — protocol error
- `1011` — server unexpected condition

Upon receiving a Close frame, the client is expected to send its own Close frame back (the WebSocket closing handshake is bidirectional — both sides acknowledge), and *then* the underlying TCP can be torn down cleanly. Crucially: **the server should wait briefly** for the client's Close reply before closing the TCP socket, so you don't slam into RST.

This matters because: a TCP RST (what happens when you just `kill -9` the pod) looks identical on the wire to "network died, retry immediately." The `1001 Going Away` signal tells the client "this is intentional, cooperate."

**On #2 — client library behavior:**

Your answer here was "randomized backoff," which is actually part of the #3 answer. The #2 question is about **client library design for seamlessness**. The expected answer:

1. **Dispatch close code to the reconnect handler**, not the error handler. `1001` means "plan a reconnect," not "show user an error."
2. **Buffer outgoing messages** in an in-memory queue during the gap.
3. **Re-resolve the server endpoint** (DNS or a stateless LB) — not reconnect to the same dead IP.
4. **Restore session context** (authn token, last-seen-message-id / server cursor, presence state) on the new socket.
5. **Hide the gap from the UI** — don't flash "disconnected"; just show "reconnecting…" after a threshold.

Libraries like `socket.io`, `reconnecting-websocket`, and native SDKs (Slack's, WhatsApp's) all implement roughly this pattern.

**On #3 — partial credit:**

You did hint at the right things — randomized backoff (client) and draining (server) — but didn't name the problem and didn't tie the mitigations to it precisely.

**Problem name: thundering herd / reconnection stampede.** If you send 10k `1001` frames at t=0, 10k clients will attempt reconnection within the same RTT window. The remaining pods see a traffic spike of 10k new handshakes + 10k TLS setups + 10k app-level auth flows all at once. This cascades — the pods that absorb the herd get CPU-saturated and may start failing.

**Mitigations (both sides, explicitly):**

| Side | Mitigation | Mechanism |
|---|---|---|
| **Client** | **Randomized jittered backoff** | Delay reconnect by random jitter (e.g., uniform 0-30s). Alternative: **capped exponential backoff with full jitter**. See the AWS Architecture Blog's "Exponential Backoff and Jitter" — this is standard practice. |
| **Server / infra** | **Staggered drain window** | Don't send all 10k Close frames at t=0. Drain over N minutes (e.g., 50/sec over 200s). This turns a spike into a flat load-redistribution. |
| **Infra** | **Connection-draining at the LB** (Envoy / ALB) | LB marks pod "draining," stops routing *new* connections to it, gives existing connections an SLA (e.g., 5 min) to complete before hard-close. |
| **Infra** | **Bounded rolling deploy** | `maxUnavailable: 1` instead of replacing all 50 pods simultaneously. |

You said "blue-green at LB" — that's a different pattern (version-switching) that can help but doesn't address the herd directly. With blue-green, the herd is still concentrated at the switchover.

**The clean answer structure:**
1. **Frame**: Close frame opcode `0x8`, close code `1001 "Going Away"`.
2. **Client**: treat `1001` as reconnect-signal (not error), buffer pending messages, re-resolve endpoint, re-auth, restore session cursor, keep UI calm.
3. **Herd problem**: reconnection stampede. **Client** = jittered exponential backoff. **Server** = stagger the Close frames across a drain window + bounded rolling deploy + LB connection draining.

**Pattern to fix:** When a question says "what is the **protocol-level mechanism**," resist the urge to invent an app-level JSON shape. The RFC defines specific frames, codes, and handshakes. Always reach for those first.

---

### Q5 · Scenario — HTTP/1.1 in service mesh (retest, previously 0/10)

**Question (verbatim):**
> You're the tech lead for a service mesh at a mid-size company. Your org has **hundreds of microservices** communicating east-west (service-to-service) inside a single Kubernetes cluster, with Envoy sidecars on every pod. You propose migrating all internal traffic from HTTP/1.1 to HTTP/2 for efficiency gains.
>
> A senior engineer pushes back: *"For east-west traffic through sidecars, HTTP/1.1 is often the right answer. HTTP/2 can actually make things worse."*
>
> You're skeptical but want to understand. **Give me two distinct, mechanism-level reasons why HTTP/1.1 may be the correct choice for east-west sidecar-to-sidecar traffic**, even though HTTP/2 is "newer and better."
>
> Hint scaffolding (use these as angles, don't just restate them):
> - Think about **how load balancing works** in a service mesh. What does the LB see in HTTP/1.1 vs HTTP/2?
> - Think about **what the RTT between two pods in the same cluster actually is**.

**Learner's answer (verbatim):**
> http1.1 can have 6 parallel connections which are independent which usually outperforms http2 with single tcp connection. So a loss on one doesn't stall many of other in http1.1(application layer HoL) unlike http2(transport layer HoL).

**Score: 4/10**

**Big improvement over last time's 0/10** — you attempted, you named a mechanism, you formed a coherent sentence. Real progress. But the mechanism you named is actually the *weaker* of the two canonical reasons, and you missed the dominant one that every service-mesh team actually cites.

**Credit where due:**
- Named a real mechanism (**transport-layer HoL blocking in HTTP/2 vs parallelism in HTTP/1.1**). That's a legitimate protocol-level observation.
- Correctly identified HTTP/2 has TCP-layer HoL, HTTP/1.1 avoids it with separate connections.

**Why this answer is weaker than it looks in the mesh context:**

HoL blocking is a real mechanism, but its **impact inside a Kubernetes cluster is small**. Intra-cluster packet loss is near-zero (you're on a virtual switch / datacenter fabric, not public internet). HTTP/2's TCP-HoL only bites when you have meaningful loss — mobile, cross-continent, lossy WAN. In east-west DC traffic, loss is low, so HoL blocking is a minor concern, not a dominant one.

Also: "6 parallel connections" is a **browser**-level cap, not inherent to HTTP/1.1. Envoy sidecars don't have that limit — they open as many connections as their pool config allows. Don't cite that number in a mesh context.

**The reason the senior engineer was actually talking about: Load balancing granularity at the sidecar / L4 LB level.**

Here's the mechanism:

| Protocol | How requests map to connections | What the LB sees |
|---|---|---|
| **HTTP/1.1** | One request in-flight per TCP connection (serialized on a keep-alive connection) | LB can route **each new connection** to a different backend. If Envoy opens 10 connections to a service, they can land on 10 different pods. Request-level load balancing = automatic. |
| **HTTP/2** | Many multiplexed streams over **one** long-lived TCP connection | LB picks a backend **once** — when the connection is established. Every subsequent request (could be thousands over minutes) pins to **that one backend**. |

**Consequence with HTTP/2 at L4:** imagine Service A with 20 pods talking to Service B with 20 pods. With HTTP/2, each A-pod opens exactly one H/2 connection per B-pod (or fewer). You now have **extremely coarse load distribution** — one hot B-pod handles all traffic from one A-pod regardless of request volume. If requests from one A-pod spike, that one B-pod melts while others sit idle.

**Fix options (all with trade-offs):**
1. Stick with HTTP/1.1 (request-level LB for free).
2. Use an **L7-aware LB / sidecar** that can rebalance H/2 streams across backends (Envoy does this, but it's operationally heavier — requires the sidecar to terminate and re-initiate H/2).
3. Configure aggressive **max-requests-per-connection** / **max-connection-duration** to force periodic reconnection and rebalancing (Envoy's `max_requests_per_connection`).

This is the reason **Istio/Envoy historically defaulted upstream to HTTP/1.1** for a long time, and why you still see H/1.1 east-west in many production meshes.

**The clean two-reason answer:**

1. **Load balancing granularity.** HTTP/1.1's one-request-per-connection model means each connection can be LB'd to a different backend — request-level distribution is automatic. HTTP/2's multiplexing pins many requests to one connection → one backend, defeating L4 LB. Without an L7-aware rebalancer, H/2 east-west creates load skew.
2. **Complexity vs. marginal gain.** The RTT between pods in a cluster is ~0.5ms. H/2's handshake / multiplexing / header-compression savings are designed for high-RTT, high-handshake-cost environments (mobile, public internet). In a mesh where RTT is sub-millisecond and connections are already long-lived via keep-alive, the wins are negligible — but you inherit H/2's complexity (binary framing, flow control per stream, harder to debug, harder to LB). Net: mechanism cost > mechanism benefit.

(You could also fold HoL blocking in as a third minor reason, but it's genuinely minor in this environment.)

**Pattern takeaway:** When someone says "newer protocol X is worse in environment Y," the answer almost always hinges on: **what does X assume about the environment that Y violates?** HTTP/2 assumes high-RTT, many-request, single-client-to-server public internet. Service mesh violates that: low-RTT, many-client-to-many-server, LB-centric. The "better" protocol is the wrong fit.

---

### Q6 · Scenario — Live sports scores protocol pick (SSE vs WS vs long-poll)

**Question (verbatim):**
> You're designing a **live sports scores feed** for a mobile app with 5M daily active users. During a cricket/football match, users open the app and want to see the score update live. Requirements:
>
> - **Updates are server-initiated** (score changes when a goal is scored).
> - **Traffic is one-way**: server → client. Client never sends messages back on this channel (tap-to-refresh would be a separate REST call).
> - **Latency SLO**: user sees update within **500ms** of the event.
> - Match duration: 90–120 min. User is on-app for ~20 min on average during that window.
>
> You're picking between **WebSocket**, **Server-Sent Events (SSE)**, and **long-polling**.
>
> **Answer three things:**
> 1. Which do you pick, and why — name two mechanism-level reasons it fits the requirements **better than the other two specifically**.
> 2. What is the **single biggest operational cost** of your chosen approach at 5M DAU scale? Name a specific resource.
> 3. What would make you change your mind and switch to a different one? Give a concrete requirement shift.

**Learner's answer (verbatim):**
> I would pick SSE. SLO is acheivable as it's just 1 RTT on opened connection. Light weight than websocket.
> 1. I need only one way connection. We can use auto-reconnect feature of it.
> 2. Too many open connections
> 3. When updates are not that frequent then we can use long-polling.

**Score: 4/10**

You landed on the right protocol, but the defense is thin in places and one of your claims is actually backwards.

**What you got right:**
- **Picked SSE.** Correct choice — one-way, server-push, HTTP-native, simple. Nails the requirements.
- **Auto-reconnect with Last-Event-ID** — this is a real, named differentiator. SSE is the only one of the three that has this in the **protocol itself**. In WebSocket or long-polling, you'd have to implement reconnection + dedup logic in your client library. SSE gives you this for free via the `Last-Event-ID` header that the client automatically sends on reconnect.

**What's thin or vague:**

**Reason #1 — "one-way connection":** Fit reason, not a superiority reason. WebSocket can also do one-way — you'd just waste the bidirectional capability. You need to frame it as: "WebSocket is over-engineered for this; SSE is natively one-way, so no protocol overhead for a channel I'll never use."

**The second mechanism-level reason you didn't name:** SSE rides on **plain HTTP/1.1 or HTTP/2** without the WebSocket `Upgrade` handshake and without the 101 Switching Protocols flow. This means:
- Passes through **every HTTP-aware proxy, CDN, reverse proxy, LB** transparently. WebSocket trips up on old corporate proxies, cache servers, and some older LB configs because they don't understand the Upgrade handshake.
- You can **fan-out through existing HTTP infrastructure** (CloudFront, Fastly, Cloudflare all support SSE). WebSocket at edge-fanout needs dedicated WebSocket-aware infra (AWS API Gateway WebSockets, Pusher, Ably) or expensive origin-reaching.
- Debuggable with `curl`. WebSocket requires a dedicated client.

That's your second mechanism-level reason: **infrastructure compatibility** because SSE is plain HTTP streaming.

**#2 is too vague:**

"Too many open connections" is directional but not specific — the question asked for a **named resource**. Precise answer:

> **File descriptors and kernel socket memory on the app-server fleet.** Each SSE client holds a persistent HTTP connection = 1 FD + ~64–128 KB of kernel socket buffers per connection. At 5M DAU, peak concurrent on-app during a match is maybe 500k–1M. That's 1M FDs (`ulimit -n` typically 65k per process → you need 15+ pods just for FDs), and ~100 GB of kernel-level socket memory distributed across the fleet.

Also: SSE keeps the connection pinned to one backend, so **L4 load balancers create hot pods** during a match (same problem as HTTP/2 east-west from the previous question). You need either request-level-aware LB, short connection lifetimes forcing reshuffle, or capacity-planned for the peak.

**#3 has the intuition backwards:**

You said: "When updates are not that frequent then we can use long-polling."

This is actually reversed. **Infrequent updates favor SSE, not long-polling.** Here's why:

- SSE: one persistent connection, events pushed as they happen. Server holds the connection at essentially zero cost between events.
- Long-polling: client sends a request, server holds it, responds when an event happens OR times out. After EACH event, client must reconnect = new HTTP request = new TCP/TLS handshake cost if connection pool expired.

For sparse events (goals in a football match = ~3 events in 90 min), long-polling forces frequent reconnection on timeout (typical 30-60s timeout). SSE just sits on the long-lived connection. SSE wins on sparse events.

**When you'd actually switch away from SSE:**

| Requirement shift | Switch to |
|---|---|
| Client needs to **send messages back** on the same channel (e.g., live chat alongside scores) | **WebSocket** (bidirectional) |
| Need **binary payloads** (audio/video frames, protobuf binary frames) | **WebSocket** (binary frames; SSE is text/UTF-8 only) |
| Corporate/legacy network environment strips chunked transfer-encoding, or you're stuck with HTTP/1.0 or very old proxies | **Long-polling** (plain request/response works everywhere) |
| Ultra-low-power IoT clients where holding a connection open drains battery | **Long-polling** or push notifications |

**The clean answer:**
1. **SSE.** Because (a) protocol-native auto-reconnect with `Last-Event-ID` gives at-least-once delivery semantics for free, and (b) rides on plain HTTP streaming — passes through every proxy, CDN, and LB without upgrade-handshake complications. WebSocket overshoots (bidirectional we don't need, adds proxy compatibility risk); long-polling under-shoots (reconnection cost on every event).
2. **FDs + kernel socket memory** on the app-server fleet, with secondary pain from backend pinning (LB hot-pod skew).
3. Add a client-send-back requirement (WebSocket) or hit legacy-proxy environments that break long-lived HTTP (long-polling).

---

### Q7 · Short-answer — gRPC deadline propagation mechanics (Java) — retest sharper

**Question (verbatim):**
> Service A → B → C with `withDeadlineAfter(200, MILLISECONDS)`. B does 80ms of work then calls C.
> 1. Header gRPC uses to propagate deadline + approximate format syntax.
> 2. What deadline should C see in incoming metadata?
> 3. In Java, what makes B's outgoing call to C inherit A's deadline automatically — specific construct?
> 4. Silent bug when a dev in B spawns a worker thread (e.g. `CompletableFuture.supplyAsync(...)`) before calling C — name the failure + the Java API that fixes it.

**Learner's answer:**
> 1. grpc-timeout
> 2. 200-80ms = 120ms
> 3. Context.current()
> 4. Worker thread might not get the context hence grpc-timeout. We can wrap with context before even supplying the task in thread.

**Score: 7/10**

**Mechanism owned.** Correct on all four parts. Losses are on precision-of-naming:

- **#1 format missing:** `{number}{unit}` where unit = `H`/`M`/`S`/`m`/`u`/`n` (hour/min/sec/millisec/microsec/nanosec). Example: `grpc-timeout: 200m`. Travels as an HTTP/2 header frame.
- **#2 nuance:** remaining time is computed **at the moment B initiates the outbound call** (not a fixed recomputation). Operational: you often want B to give C a *tighter* deadline than its own remaining budget (budgeting pattern via `withDeadlineAfter` on the stub).
- **#3 underlying detail:** `Context.current()` is stored in a **ThreadLocal** — which is the setup for #4's bug.
- **#4 specific Java APIs not named:** `Context.current().wrap(Runnable/Callable)` wraps a single task; `Context.currentContextExecutor(executor)` wraps an entire Executor to propagate context automatically. Concept right ("wrap with context"), interview-depth needs the method names.

**Pattern recognized:** thread-local + thread boundary → need explicit propagation. Same pattern in OpenTelemetry context propagation, SLF4J MDC, Reactor Context, RxJava Scheduler. Own once, transfer across domains.

---

### Q8 · Scenario — DNS TTL + Anycast

**Question (verbatim):**
> Multi-region e-commerce. Architect proposes DNS-based failover with TTL=30s. CFO: "why not TTL=1s for near-instant failover?"
> 1. Real-world effective TTL vs authoritative TTL — name the two compounding factors.
> 2. Two production costs of dropping authoritative TTL 30s → 1s; each with a specific pressured resource.
> 3. What industry-standard mechanism do Cloudflare/AWS/Google actually use for fast regional failover? Name + why faster than DNS.

**Learner's answer (after asking for clarification):**
> 1. ISP and OS resolver
> 2. a. DNS Resolver b. how client will face it when autorative dns server is down for more than the TTL amount
> 3. dead dns resolver should signal something to reresolve if it's down.

**Score: 3/10**

**#1 correct** — named ISP recursive resolver + OS resolver cache. Extra color: resolvers clamp TTL floors (60-300s) to prevent zone-level DoS; OS/runtime caches (Java's `InetAddress`, .NET `ServicePointManager`) add another layer; browsers add a 4th.

**#2 imprecise.** Three real costs:
- **Authoritative DNS QPS + query billing** — 5M DAU × frequent re-resolves = millions of QPS; Route 53 charges per query ($0.40/M).
- **Client-side tail latency** — fresh DNS lookup adds 10-50ms per request when cache expires every 1s. p99 degrades visibly.
- **Domain availability against auth-DNS outage** — 1s TTL means 1s buffer before entire domain becomes unresolvable if authoritative NS blips.

**#3 MISSED: Anycast routing via BGP.**
- Same IP announced from multiple geographic locations via BGP. Internet routing picks nearest. Withdraw BGP advertisement on a location → reconvergence in 10-30s, traffic shifts elsewhere transparently.
- Why faster: no resolver/OS/runtime/pooled-connection cache to wait on. Client keeps using the same IP; the *network* routes packets to a different datacenter.
- Used by: Cloudflare (1.1.1.1 and every edge IP), AWS Global Accelerator (2 static anycast IPs), Google Public DNS (8.8.8.8), Akamai/Fastly.
- Related: VIP/floating IP failover (within DC), `GOAWAY` for HTTP/2/WS graceful shutdown, client-side health-aware LB (gRPC's `round_robin` + health check subchannels).

**Pattern to internalize:** "what do large providers actually do?" → **drop a layer**. DNS → BGP. HTTP → TCP. TCP → UDP/QUIC. Application → Kernel.

---

### Q9 · Spaced revision — Topic 00 napkin math (input-parsing discipline)

**Question (verbatim):**
> Event ingestion pipeline, mobile game.
> - 1B events/day ingested globally
> - Payload: 200B post-serialization
> - Peak-to-average ratio: 5x
> - Retention: 30 days
> - Replication factor: 3
>
> 1. Peak QPS (ingestion layer)?
> 2. Peak ingress bandwidth (MB/s + Gbps)?
> 3. Total raw storage (TB) for 30 days, accounting for replication?

**Learner's answer:**
> Event per day = 1B
> Events per second = 1B/86400 = 1M/86.4 = 12K (qps)
> Peak qps = 5*12K = 60K per second
> Avg Bandwidth(ingestion) = 12K qps * 200 Bytes = 2.4 MB/s
> Peak Bandwidth = 5*2.4 = 12MB/s = 96 Mbps = 0.1 Gbps
> Storage for 30 days (w/o replication)  = 30*1B*200bytes = 6 TB
> Storage with replication = 3*6TB = 18TB

**Score: 9/10**

**⭐ The exact rep the revision queue was asking for.** Clean input parsing (didn't misread any number), correct multipliers on right metrics (peak applies to rate, total volume applies to storage), byte↔bit conversion correct (×8 MB/s → Mbps), replication factor applied correctly.

**Failure mode from prior sessions (over-derive, misread "at peak" vs DAU) explicitly avoided.** Topic 00 spaced-revision can come off the queue.

**Minor polish for interview context:**
- Add storage overhead factor (20-30% for metadata/indexes/compaction) → 18TB → plan ~25TB
- Tier-cost framing: 18TB × $100/TB/month hot SSD ≈ $1,800/mo for 30-day retention; tier to Glacier at $0.004/GB for longer retention

---

## Session rollup

### Strongest
- **Q9 (napkin math spaced revision):** ⭐ clean input parsing. Failure mode fixed. Topic 00 → 2_practiced. 9/10
- **Q7 (gRPC deadline propagation):** mechanism owned post-teach from last session. 7/10
- **Q2 (DNS failover pooled-H2):** right pick with correct cohort-size reasoning. 6/10

### Weakest
- **Q4 (WebSocket Close frame):** invented app-level JSON instead of naming `0x8 / 1001 Going Away`. Protocol mechanism miss.
- **Q8 (Anycast):** missed the industry-standard mechanism entirely. Senior-interview-critical concept.
- **Q5 (H1.1 in mesh):** named weaker of two reasons, missed L4 LB granularity (the dominant one).

### Pattern watchlist (carrying forward)
- ✅ Input-parsing discipline on napkin math: **FIXED** (topic 00 off revision queue).
- ❌ Named-mechanism vs. scenario-words: still leaking. Q3 (QUIC connection migration vs 0-RTT), Q4 (invented JSON), Q8 (resolver "should signal" instead of Anycast).
- **Immediate next:** `/hld-deepdive 01` targeting the three mechanism gaps — Anycast/BGP, WebSocket Close frames + graceful deploy internals, service-mesh LB granularity with H/2.

### Outcome
- Topic 01: 44/90 = 48.9% → stays `1_intro`. Need 60%+ on a mixed-format quiz to advance.
- Topic 00: 9/10 → `1_intro` → `2_practiced`. Off the revision queue.

