# 00 · What is HLD & Napkin Math — Quiz Log

---

## 2026-04-19 · Session 1 (Deep, /hld-next)

**Final: 44/80 (55%) → Level: 1_intro**

---

### Q1 · Scenario / trade-off — Redis cache decision rule

**Question:**
> You're designing the **read path** for a social feed. A product manager says: *"Just cache everything in Redis — it's fast."*
>
> The raw numbers:
> - Redis point-read (same DC): ~500µs (mostly network RTT)
> - Postgres point-read on a well-indexed primary key (same DC): ~1.5ms
> - Postgres full-page scan with a bad index: ~50ms
>
> Under what circumstances does adding a Redis cache **not** make sense, and under what circumstances is it a ~30×+ win? Give me the decision rule you'd write into your design doc — not a vague "depends."

**Learner's answer:**
> When we have a high read/write ratio and it's favourable when hot keys are being read very frequently.

**Score: 5/10**

**Gap:** Identified the right axis (high read ratio + hot keys) but missed the dominant variable — *query cost*, not R:W ratio. Didn't engage with the numbers. Didn't give a crisp decision rule. Missed the "when NOT to cache" direction entirely.

**Ideal answer:**
> *"Cache when (cost_uncached − cost_cached) × read_frequency is large relative to invalidation complexity, AND the working set fits in budgeted memory. Skip if the underlying query is already a cheap indexed lookup — saving ~1ms rarely justifies cache-invalidation bugs."*

Redis vs Postgres PK lookup is only a **3× win** (500µs vs 1.5ms). Redis vs bad-index scan is a **100× win** (500µs vs 50ms) — that's where caching pays for itself.

---

### Q2 · MCQ + why — Video streaming egress bandwidth

**Question:**
> You're sizing egress bandwidth for a video-streaming service. At peak, **80 million concurrent streams** at **5 Mbps each**.
>
> What's the total peak egress bandwidth, and which statement about it is correct?
> - **A.** 400 Gbps — comfortable for a single well-provisioned datacenter with modern spine switches.
> - **B.** 400 Tbps — impossible to serve from a single DC or cloud region; architecture must push content to the edge (CDN / ISP-embedded appliances).
> - **C.** 50 GB/s — fits on ~50 high-end NICs, so a rack of 10 servers handles it.
> - **D.** 50 TB/s — plausible for a single hyperscale DC if you spread across enough racks.
>
> Pick one and **justify the arithmetic**. Also: what was the trap in the wrong options?

**Learner's answer:**
> B. 80M*5Mbps = 400 Tbps = 50TB/s. Because we will have to serve cross continent and rtt is 300x slower than same DC.

**Score: 6/10**

**Strong:** Correct answer + correct arithmetic (400 Tbps = 50 TB/s).

**Gap:** Justification is wrong — cited **latency** (RTT), but the real reason is **raw egress bandwidth capacity**. A hyperscale DC can egress a few Tbps externally; 400 Tbps is ~100-400× that. Didn't diagnose the traps:
- **A** off by 1000× (giga vs tera)
- **C** bits-vs-bytes confusion (50 GB/s ≠ 400 Gbps)
- **D** numerically correct (50 TB/s = 400 Tbps) but false claim about DC capability

**Core rule:** `1 Gbps = 125 MB/s` — commit this to memory.

---

### Q3 · Short-answer — Why napkin math if we load-test anyway?

**Question:**
> An interviewer asks: *"Why do we even do napkin math in a design round? You're going to load-test in production anyway."*
>
> Give a **tight 3-sentence answer** that a Staff+ interviewer would nod at. Don't list benefits vaguely — name the specific failure mode napkin math prevents that you can't recover from later.

**Learner's answer:**
> Napkin math gives us the good idea about what architecture would succeed for our scenario. It helps us design the system which would actually run because it's easy to do without even actually setting up the infra. It's free of cost and helps us understand whether the proposed systems are even possible or not.

**Score: 4/10**

**Gap:** Generic benefits list — rephrased the question rather than answering it. Missed the specific irreversibility insight.

**Ideal answer:**
> *"Load testing happens after the system exists — by then, the wrong storage engine, replication strategy, or topology is already baked in and painfully expensive to reverse. Napkin math catches the architectural errors that load-testing can't: 'this egress can't come from one DC,' 'this workload needs a log, not a queue,' 'this read pattern kills a range-partitioned DB.' It also forces assumptions into writing, which turns design arguments from tribal preference into numbers everyone can poke at."*

Three ideas: **irreversibility** + **wrong-foundation failure mode** + **forcing assumptions onto the whiteboard**.

---

### Q4 · Scenario — Uber location-update capacity

**Question:**
> Design interview, first 5 minutes. Prompt: *"Design a system like Uber for ride matching."*
>
> Produce a capacity estimate for **rider→driver location updates**. Give me:
> 1. Your **explicit assumptions** (DAU, update frequency, payload size, peak multiplier).
> 2. **Peak QPS** for location updates.
> 3. **Peak bandwidth** (MB/s or Gbps — pick units deliberately).
> 4. **One architectural implication** — what does the number force you to decide?

**Learner's answer:**
> DAU = 100M, update frequency per 3 seconds, payload 500B, peak multiplier 4x, daily rides = 3 per user.
> peak qps = 100M*3*4/100000 = 12000 qps
> peak bandwidth = 500B*12000*2(rider and driver)/3 = 500B*8000 = 4MB/s
> Can't think of any architectural implication.

**Score: 4/10**

**Gap:** **~700× too small.** Modeled rides as point events instead of *streams*. A ride lasts ~15 minutes emitting updates every 3s.

**Correct decomposition (streaming workload pattern — memorize):**
```
Total ride-seconds/day = 100M × 3 × 900s = 2.7 × 10¹¹
Avg concurrent rides = 2.7 × 10¹¹ / 86,400 ≈ 3.1M
Peak concurrent rides (4×) = 12.5M
Peak QPS = 12.5M × 2 participants × (1 update / 3s) = ~8.3M updates/s
Peak bandwidth = 8.3M × 500B = 4.15 GB/s ≈ 33 Gbps
```

**Architectural implications forced by the numbers:**
1. 8M writes/s — single datastore impossible; must shard
2. Shard key = geospatial (S2 cells) because queries are "drivers near me" — not user-id
3. In-memory store (Redis) over persistent DB — durability not needed
4. Pub/sub over polling for client updates
5. Anycast / geographic routing for 33 Gbps egress

**Rule:** For streaming workloads, use **concurrent sessions × emission rate**, not events/day ÷ 86400.

---

### Q5 · MCQ + why — Redis caching for payments

**Question:**
> You're designing a **payment processing** system. A colleague says: *"Just cache recent transactions in Redis — reads will be fast."*
>
> Which of these is the correct primary objection?
> - **A.** Redis is slower than Postgres for point lookups.
> - **B.** Payments have a ~1:1 read:write ratio, so the cache hit rate will be low — meanwhile staleness risks double-charging.
> - **C.** Redis doesn't support transactions.
> - **D.** Payment systems are write-heavy only; there are no reads to cache.
>
> Pick one. Then: if a candidate picked **C**, what's technically wrong with their reasoning?

**Learner's answer:**
> B. Because payments have 1:1 read-write ratio so the cache hit rate will be low and there is not seem to be any benefit of adding caching meanwhile staleness risks double charging or showing wrong balances.
>
> C is incorrect but not due to that reason. Redis are atomic via lua script so it's not the reason. Reason is what I mentioned in the above line.

**Score: 8/10**

**Strong:** Correct answer + correctly refuted C with Lua atomicity. Shows awareness of Redis atomicity primitives.

**Gap:** Missed the deeper objection — payments are the *system of record*. Every read precedes a decision that writes, so cache never amortizes. Also didn't mention MULTI/EXEC has no rollback (not true ACID).

**Deeper rule:** For systems where reads and writes are tightly coupled to decisions with legal/financial consequences, cache is rarely the bottleneck — **correctness is**. Cache read-only derived views downstream of the ledger, never the ledger itself.

---

### Q6 · Scenario — Logging system sizing

**Question:**
> You're sizing a **logging system**:
> - **50K req/s** at peak
> - Each request produces **~2 KB of structured log**
> - Retention: **30 days**
> - Replication factor **3**
> - R:W ≈ 1:1000 (write-heavy)
>
> Give me: (1) peak ingest bandwidth, (2) storage for 30 days with replication, (3) one architectural decision the number forces — engage with *why* log-structured beats traditional DB here.

**Learner's answer:**
> peak ingest bandwidth = 50k qps * 2KB = 100MBps
> storage needed for 30 days = 100MBps * 30 * 86400s = 260TB
> Architectural decision = We don't need joins and acid property that's why we don't need traditional SQL dbs. This logs are read-heavy and we can take benefit of that. Due to above mention reason we can take benefit of write heavy log structured merge tree.

**Score: 5/10**

**Strong:** Bandwidth math correct. Landed on **LSM tree** — the right answer.

**Gap:**
- **Forgot 3× replication** in storage math → answer 67% undersized. Correct: ~780 TB raw, ~80-150 TB with typical log compression (5-10×).
- Contradicted self: wrote "logs are read-heavy" then justified a *write-heavy* LSM. The prompt explicitly stated 1:1000 write-heavy.
- Didn't explain *mechanism* — why LSM wins:

| | B-tree | LSM tree |
|---|---|---|
| Writes | Random I/O (in-place update + WAL) | Sequential I/O (memtable → SSTable flush) |
| Win | Low write amplification | 10-100× higher write throughput |
| Reads | Fast | May check multiple SSTables (bloom filters help) |
| Fit for logs | Wastes capacity on update machinery | Perfect — writes cheap, reads rare |

This is why Cassandra, Elasticsearch, ClickHouse dominate logging while Postgres doesn't.

---

### Q7 · Short-answer — Why latency numbers over QPS formulas?

**Question:**
> Explain in **2-3 sentences**, without jargon-dropping, **why memorizing latency numbers is more valuable than memorizing QPS formulas**. (Hint: one is derivable from the other.)

**Learner's answer:**
> Latency number is more valuable because we can always calculate the qps using latency, ram and request size.

**Score: 5/10**

**Gap:** Core insight correct (derivability) but thin. Didn't name **Little's Law** or the *"physical constants vs arithmetic"* framing.

**Ideal answer:**
> *"Latency numbers are the physical primitives — RAM, SSD, same-DC RTT, cross-continent RTT — and they don't change unless hardware does. By Little's Law (throughput = concurrency / latency), once you know latencies you can compute achievable QPS for any system on the fly. Latencies also let you falsify bad proposals instantly: 'synchronous cross-region replication with <100ms p99' is impossible the moment you know one cross-continent RTT is already 150ms — no formula needed."*

---

### Q8 · Synthesis — WhatsApp-scale global chat SLA refutation

**Question:**
> *"We're building a global chat app (WhatsApp-scale). Product wants **end-to-end delivery p99 <200ms** globally. 2B users, 100B messages/day. We'll replicate synchronously across 5 regions for durability."*
>
> 1. Is this SLA physically achievable? Defend with numbers.
> 2. Which assumption forces a redesign?
> 3. What would you propose, and what trade-off does that force?

**Learner's answer:**
> SLA is 200ms for round trip should be possible as round trip cross continent is some 150ms.
> 2 Billion users, 100Billion messages per day, 2KB per message means 200*10^9*2KB = 400TB per day. Replicating this synchronously across 5 regions will increase the latency to some 150ms + (5-1)*70ms = 450ms. Best proposal is to go for eventual consistency. We would trade-off consistency for latency.

**Score: 7/10**

**Strong:** Used latency numbers as a **refutation tool** — exactly the point of this topic. Identified sync-5-region as the blocker. Proposed right direction.

**Gap:**
- The `(5-1)×70ms` math is hand-wavy — no real protocol looks like sequential chain replication cross-region.
- Sharper: even **1-RTT quorum** (~150ms) eats 75% of the 200ms budget; **Paxos/Raft** needs 2 RTTs (~300ms, already over). SLA is mathematically impossible regardless of protocol.
- Trade-off named but missing mechanics: **causal consistency**, client-visible "nearest-region ACK" (~30ms "✓ sent"), global replication happens async, vector clocks / Lamport timestamps, client-side retention + idempotent retries. This is how WhatsApp / Signal / Telegram actually work.

**Meta-pattern:** When physics says no, **decouple user-facing latency from durability latency**. Users see nearest-region ACK; global replication runs in the background. Trade simultaneous durability for perceived speed, mitigate with client-side cleverness.

---

## Session rollup

### Strongest
- **Q5 (payments caching):** correctly refuted option C with Lua atomicity — 8/10
- **Q8 (SLA refutation):** used latency numbers as a tool of refutation — 7/10

### Weakest
- **Q4 (Uber location):** modeled streaming as point events, off by 700×
- **Q6 (logging storage):** forgot replication factor → 67% undersized
- **Q3 (why napkin math):** answered generically instead of naming the failure mode

### Calibration notes for next session
- Practice **streaming-workload decomposition** (concurrent sessions × emit rate)
- **Replication factor is a 3× multiplier** that's easy to drop under pressure
- Work on *naming the mechanism* behind a decision, not just naming the decision
- Internalize **Little's Law**: throughput = concurrency / latency

---

## 2026-04-19 · Session 2 (spaced revision during topic 01)

**Q8 Q1 of session 2:** *"Using latency numbers from topic 00, what's the RTT between two microservices in the same datacenter?"*

**Learner's answer:** 0.5ms ✓

**Score: 2/2** — ⭐ Recalibrated correctly after the earlier Q2 slip (same session) where 70ms was mistakenly used for same-DC. Spaced repetition worked within-session.
