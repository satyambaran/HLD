# Quiz Log — 02 SQL Internals

---

## Session 2026-05-01 (Deep — first quiz, all 3 parts)

**Scope:** Topic 02 Parts 1-3 (storage, B-tree, WAL, MVCC, isolation, query planner, locks, concurrency) + spaced revision topic 01 (networking primer).
**Target:** 10 questions. Passing band for 2_practiced = 60-75%.

---

### Q1 — MCQ + Why (Part 1): UUID v4 PK — Postgres vs InnoDB

**Question:** Your team says "UUID v4 as PK works fine in Postgres, so we'll keep it in InnoDB — same behavior." Is this correct? Explain the specific internal mechanism that makes behavior different.

**Learner's answer:** Not correct. UUID v4 leads to higher page segmentation in InnoDB than Postgres because InnoDB stores the full row on clustered leaf pages whereas Postgres stores (pk, ctid) on index leaf pages. UUID v4 is random → inserts anywhere in the tree → page splits throughout. InnoDB PK dictates physical row order; Postgres rows exist anywhere in the heap, the index just stores a pointer. Also noted fillfactor/page utilisation impact.

**Score: 5/10**

**What was right:**
- Conclusion: not the same behavior — correct.
- InnoDB is clustered: PK dictates physical row order. UUID v4 = random inserts across the entire clustered tree = page splits throughout the table. ✓
- Postgres heap is unordered: rows go wherever fillfactor allows free space, independent of PK value. ✓

**Where the model was wrong:**

The claim "Postgres stores (pk, ctid) on leaf pages" is the PK **index** leaf — not the heap. The **heap** stores full rows in both Postgres and InnoDB. The difference is not "Postgres stores less per leaf page." The difference is **which structure UUID v4 fragments**:

- **InnoDB:** The table **is** the clustered B+-tree. UUID v4 randomness → every INSERT hits a different leaf node in the clustered tree → mid-tree page splits → the **table itself** fragments. Page fill drops from ~90% to ~50% on average. The entire table's working set must be hot in cache instead of just the last few leaf pages.
- **Postgres:** The heap is an unordered flat file — rows go wherever fillfactor allows free space. The heap was **never ordered by PK** to begin with. UUID v4 fragments the PK B+-tree index, but that's just one index among potentially many. The heap itself is already "random" by design — UUID v4 makes the PK index worse but doesn't change the heap's behavior.

The severity difference: InnoDB fragments the table data (all row reads are now scattered, range scans are catastrophic). Postgres fragments only one index.

**What was missed entirely — secondary index bloat:**

In InnoDB, secondary index leaves store the **full PK value** (not a ctid pointer). A UUID v4 stored as a string is 36 bytes; binary UUID is 16 bytes. Every secondary index on the table carries 16–36 bytes of PK per leaf entry. With 5 secondary indexes on a 100M-row table:
- UUID v4 string PK: `5 × 100M × 36 bytes = ~18 GB` of secondary index storage.
- BIGINT PK: `5 × 100M × 8 bytes = ~4 GB`.

UUID v4 throws a double punch at InnoDB: fragments the clustered table AND bloats every secondary index.

**Ideal answer (one paragraph):**
> Incorrect. In InnoDB, the table is a clustered B+-tree ordered by PK — leaf pages contain full rows in PK order. UUID v4 is random, so each new insert targets a different leaf in the clustered tree, causing page splits throughout the structure and fragmenting the table itself. Page fill drops from ~90% to ~50% on average; the table's working set balloons. Postgres is insulated: its heap is unordered (rows land wherever fillfactor allows free space, PK-independent), so UUID v4 only fragments the PK B+-tree index — bad, but not the table itself. Additionally, InnoDB secondary indexes store the full PK value in every leaf entry — a 36-byte UUID v4 string PK bloats every secondary index by 36 bytes per row vs 8 bytes for BIGINT.

---

### Q2 — Short conceptual (Part 2): HOT update mechanics

**Question:** A HOT update fires. Walk through exactly what happens step-by-step — which operations a normal UPDATE would do are skipped, and why the skipping is safe.

**Learner's answer:** HOT fires when no indexed column changes and new tuple fits on the same page. Old tuple's t_ctid points to the new one (HOT chain). Index not touched, still points to old ctid, traverses chain to reach the latest live version.

**Score: 6/10**

**What was right:**
- Both HOT conditions: no indexed column changed + new tuple fits on same page. ✓
- `t_ctid` of the old tuple is set to point to the new tuple (the HOT chain). ✓
- Indexes are not updated; they still point to the old ctid and traverse the chain to find the live version. ✓ — this is the core safety argument.

**What was missing — precisely which operations are skipped:**

Normal UPDATE path on a table with N indexes:
1. Fetch old tuple, set `xmax = current_txn` — always happens, HOT or not.
2. Write new tuple in a free slot (same page, HOT condition 2) with `xmin = current_txn`, `xmax = 0` — always happens.
3. Set old tuple's `t_ctid` to new tuple's slot — always happens.
4. **Walk every one of the N index B+-trees** — find the old ctid entry in each, delete it, insert the new ctid entry. → **This is exactly what HOT skips.** All N index B+-tree writes.

HOT only skips step 4. The tuple mutation (steps 1–3) is identical to a normal UPDATE.

**Why it's safe — the full argument:**

The index stores `(indexed_key → ctid)`. The indexed column's *value* didn't change (HOT condition 1). So the index entry is still routing correctly — it says "for key X, go to ctid (page 5, slot 3)." That ctid still exists in the heap; it's just the old tuple version. When a lookup arrives, it fetches the old tuple and follows `t_ctid` to the new version. The index doesn't need to know the ctid changed because the chain's entry-point (the old ctid) is stable. Index correctness is maintained through one extra pointer hop.

**What was missed entirely — VACUUM's role:**

HOT chains don't stay forever. VACUUM (or opportunistic page-level pruning triggered during a subsequent read of that page) short-circuits the old dead tuple out, rewiring the index entry to point directly to the latest live version. Without this cleanup, chains grow with every update and the per-lookup overhead accumulates. This is why `fillfactor` and `autovacuum` are co-dependent levers: enough free slack to allow HOT chains to form, and autovacuum running fast enough to prune them.

**The magnitude — why HOT matters:**

On a table with 10 indexes, a non-HOT UPDATE touching only a non-indexed column still pays 10 B+-tree writes (because ctid changes → every index must update its pointer). HOT skips all 10. At 50k updates/sec on a hot table: 500k index writes/sec → 50k. This is the exact write-amplification mechanism behind the Uber post's argument about Postgres vs InnoDB.

---

### Q3 — Scenario (Part 3): EXPLAIN ANALYZE — stale statistics diagnosis

**Question (verbatim):**
```
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 9999 AND status = 'pending';

Seq Scan on orders  (cost=0.00..95000.00 rows=2 width=120)
                    (actual time=0.1..820.0 rows=47000 loops=1)
  Filter: ((user_id = 9999) AND (status = 'pending'))
  Rows Removed by Filter: 2953000
  Buffers: shared hit=12000 read=500
```
There is an index on `(user_id, status)`. Three questions: (1) why Seq Scan instead of index? (2) what caused `rows=2` estimated vs `actual rows=47000`? (3) what are your next two concrete actions to fix this?

**Learner's answer:** Status has low cardinality. I would try to remove status from the index.

**Score: 1/10**

**What was right:** Nothing directly applicable to this scenario. Low-cardinality concern is real in general but misapplied here — the index has `user_id` (high cardinality) as the leading column. Status as the second column in a composite index is fine.

**What went wrong — the misapplication:**

The learner pattern-matched to "low cardinality → index skipped" and applied it to the wrong situation. Removing `status` from the index makes it less useful, not more. The composite index `(user_id, status)` is actually well designed for this query — `user_id` narrows to one user's rows, `status` filters within them. The problem is not the index design.

The key diagnostic signal was ignored: `rows=2` estimated vs `actual rows=47000`. A 23,500× underestimate is **always a statistics problem first**.

**Ideal answer — Q1 (Why Seq Scan despite the index):**

Statistics are severely stale. The planner estimated `rows=2` for this query. With those estimates, it computed the Seq Scan cost using wrong page-count assumptions, and the comparison to the index scan cost was unreliable. When table stats (page count, row count) are also stale, the Seq Scan looks cheaper than it is. Secondary factor: `random_page_cost` defaulting to `4.0` (calibrated for spinning HDD) on an NVMe instance over-penalizes index scan cost — should be `1.1`.

**Ideal answer — Q2 (What caused the estimate gap):**

Two root causes working together:
1. **Stale `ANALYZE`** — statistics were last computed when user 9999 had ~2 pending orders. Since then they've accumulated 47,000. Autovacuum triggers ANALYZE at `autovacuum_analyze_scale_factor × n_live_tup + threshold`. Default scale factor is 0.2 — on a 3M-row table, that's 600,000 row changes before ANALYZE fires. One user's row growth doesn't cross that threshold for the whole table.
2. **Missing multi-column statistics** — Postgres independently estimates `P(user_id=9999)` × `P(status='pending')` (column independence assumption). If each individual value is rare, the joint estimate is near zero. Reality: user 9999 has 47,000 pending orders — the two columns are highly correlated for this user. Fix: `CREATE STATISTICS`.

**Ideal answer — Q3 (Two concrete actions):**

```sql
-- Action 1: fix stale statistics immediately
ANALYZE orders;

-- Action 2: teach the planner the joint distribution of user_id + status
CREATE STATISTICS stat_orders_user_status ON user_id, status FROM orders;
ANALYZE orders;  -- must re-run after creating the statistics object

-- Optional: increase statistics target if user_id has high cardinality
ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS 500;
ANALYZE orders;
```

After this, re-run `EXPLAIN ANALYZE` — the planner should switch to an Index Scan on `(user_id, status)`.

**Pattern takeaway:** `rows=X estimated` vs `actual rows=Y` with a large ratio → always investigate statistics first (`ANALYZE`, multi-column stats, statistics target). Don't modify the index design based on EXPLAIN output showing wrong row estimates — fix the estimates first, then re-evaluate.

---

### Q4 (mid-quiz deep-dive pause) — Short conceptual (Part 2): Lost update under Repeatable Read

**Question (verbatim):**

```sql
-- T1                                    -- T2
BEGIN;                                   BEGIN;
SELECT balance FROM accounts             SELECT balance FROM accounts
  WHERE id = 1;   -- returns 500           WHERE id = 1;  -- returns 500
-- T1 checks: 500 >= 100, ok             -- T2 checks: 500 >= 100, ok
UPDATE accounts SET balance = 400        UPDATE accounts SET balance = 400
  WHERE id = 1;                            WHERE id = 1;
COMMIT;                                  COMMIT;
```

What is the final value of `balance`? Why doesn't REPEATABLE READ prevent this? What is the minimum change to prevent it?

**Learner's answer:** Final balance is 400. We should use `balance = balance - 100`. Repeatable read is about taking the snapshot at the first statement and keeping the lock. Second transaction is directly updating it to a value calculated before this transaction started.

**Score: 4/10**

**What was right:**
- Final balance = 400 ✓
- `balance = balance - 100` is the right fix direction ✓
- T2 is using a stale/pre-transaction value ✓

**What was wrong — "RR keeps the lock":**

Postgres REPEATABLE READ is **snapshot isolation**, not 2PL. It takes a snapshot at transaction start and reads stay consistent with that snapshot. It does **not** hold shared locks on rows you've read. T2 can freely read and write after T1 commits — there's no lock held on the balance row from T1's read.

**The actual mechanism — why RR doesn't prevent this (Lost Update):**

This is a **lost update**. Walk through exactly what Postgres does:
1. T1 reads balance=500 from its snapshot.
2. T2 reads balance=500 from its snapshot.
3. T1 executes `UPDATE ... SET balance = 400`. Postgres writes apply to the **current committed row version**, not the snapshot. Current version = 500, T1 sets to 400. T1 commits.
4. T2 executes `UPDATE ... SET balance = 400`. Postgres applies this write to the current committed version (now 400 from T1). T2 sets it to 400. T2 commits.
5. Final: 400. T1's deduction was overwritten — lost.

The snapshot controlled *what T2 read*. It did not control *what T2 wrote*. T2's UPDATE blindly set `balance = 400` (a literal from a stale read) and overwrote T1's committed deduction.

**Why `balance = balance - 100` fixes it:**

When T2 executes `UPDATE accounts SET balance = balance - 100 WHERE id = 1`, Postgres evaluates the expression `balance - 100` against the **current committed row version at UPDATE time**, not against the snapshot:
- T1 commits: balance = 500 - 100 = 400.
- T2's UPDATE evaluates: current balance = 400 (T1's committed value), so 400 - 100 = 300.
- T2 commits: balance = 300 ✓

Key insight: **DML always targets the current committed row, even under RR**. Only reads are snapshot-isolated.

**When `balance - 100` is NOT enough (what was missed):**

```sql
SELECT balance FROM accounts WHERE id = 1;  -- sees 100
IF balance >= 100 THEN
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
END IF;
```

T1 commits (balance → 0). T2's IF was evaluated on stale snapshot (balance=100) → passes. T2's UPDATE executes, balance → -100. Invariant violated. This is **write skew**. Fix: `SELECT ... FOR UPDATE` (forces T2 to re-read T1's committed value before the IF check) or `SERIALIZABLE` (SSI detects the cycle, aborts one transaction).

**Decision matrix:**

| Scenario | RR + literal | RR + expression | RR + FOR UPDATE | SERIALIZABLE |
|---|---|---|---|---|
| Blind decrement (no check) | Lost update ✗ | Correct ✓ | Correct ✓ | Correct ✓ |
| Conditional decrement (IF ≥ 100) | Write skew ✗ | Write skew ✗ | Correct ✓ | Correct ✓ |

Minimum change for this specific question: use the expression. Minimum change for the general conditional case: `SELECT ... FOR UPDATE`.

> **Note:** Mid-quiz, learner requested a deep-dive on isolation levels. Full anomaly × level breakdown with real-world scenarios added to `notes/02-sql-internals-part2.md` (Revisit section dated 2026-05-02).

---

### Q5 — Scenario (Part 3): FOR UPDATE without SKIP LOCKED — job queue thundering herd

**Question (verbatim):**

```java
// 10 worker threads all run:
while (true) {
    beginTransaction();
    Long jobId = query("SELECT id FROM jobs WHERE status='pending' ORDER BY created_at LIMIT 1 FOR UPDATE");
    if (jobId == null) { rollback(); sleep(100ms); continue; }
    query("UPDATE jobs SET status='processing' WHERE id = ?", jobId);
    commit();
    process(jobId);  // ~2 seconds outside any transaction
}
```

Two questions: (1) What is the specific performance problem? (2) Write the fixed SELECT — one line — and explain why it fixes the problem.

**Learner's answer:** "We also need to make sure of read committed."

**Score: 3/10**

**What was right:**
- READ COMMITTED is the correct isolation level for this pattern. ✓ Under REPEATABLE READ, a worker's snapshot is frozen at transaction start — newly committed pending jobs arriving after the snapshot won't be seen. RC takes a fresh snapshot per statement, ensuring workers always see the latest pending jobs.

**What was missing — the primary problem:**

All 10 workers execute `ORDER BY created_at LIMIT 1 FOR UPDATE` — they all target the **same row** (the oldest pending job). Worker 1 acquires the lock on job 1. Workers 2-9 all block, queued behind that same lock. When Worker 1 commits, the 9 waiting workers all wake up, race for job 1 — but job 1 is now 'processing', not 'pending'. They re-scan, all land on job 2, same pile-up. 10 workers executing serially. This is the **thundering herd on a single row** — `FOR UPDATE` without `SKIP LOCKED` turns concurrent workers into a sequential queue.

**The one-line fix:**

```sql
SELECT id FROM jobs WHERE status='pending' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED
```

`SKIP LOCKED` tells each worker: if a row is already locked by someone else, don't wait — skip it and try the next one. Worker 1 locks job 1. Worker 2 sees job 1 locked → skips it → locks job 2. Worker 3 skips jobs 1 and 2 → locks job 3. All 10 workers process different jobs in parallel.

**Complete fixed pattern:**

```java
while (true) {
    beginTransaction();  // READ COMMITTED
    Long jobId = query(
        "SELECT id FROM jobs WHERE status='pending' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED"
    );
    if (jobId == null) { rollback(); sleep(100ms); continue; }
    query("UPDATE jobs SET status='processing' WHERE id = ?", jobId);
    commit();  // lock released here — claim durable in table
    process(jobId);  // outside any transaction — lock not held during 2s processing
}
```

**Pattern takeaway:** `FOR UPDATE` without `SKIP LOCKED` = correct locking but serial execution. `FOR UPDATE SKIP LOCKED` = correct locking + parallel execution. The isolation level (RC) ensures fresh snapshots so no worker misses newly committed pending jobs.

---

### Q7 — Scenario (Part 3): Deadlock detection and prevention

**Question (verbatim):**

```sql
-- Service A: account 1 → account 2
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- locks row 1
UPDATE accounts SET balance = balance + 100 WHERE id = 2;  -- waits for row 2
COMMIT;

-- Service B: account 2 → account 1 (simultaneously)
BEGIN;
UPDATE accounts SET balance = balance - 50  WHERE id = 2;  -- locks row 2
UPDATE accounts SET balance = balance + 50  WHERE id = 1;  -- waits for row 1
COMMIT;
```

Three questions: (1) what happens and name it, (2) how does Postgres resolve it, (3) one code-level change that prevents it.

**Learner's answer:** Each transaction holds a lock on one row and waits for a lock on the other, which is held by the other transaction. Neither can proceed. This is a **Deadlock**. Postgres detects it via the deadlock detector after `deadlock_timeout` seconds (default 1s). If a cycle is found, Postgres picks the transaction with less work done, rolls it back with error code `40P01`, survivor continues. Fix: use SKIP LOCKED and retry.

**Score: 6/10**

**What was right:**
- Deadlock: correct name, correct cycle description. ✓
- Postgres mechanism: `deadlock_timeout` (1s), cycle scan, victim = less work done, `40P01` error, survivor continues. ✓
- Retry: conceptually mentioned. ✓

**What was wrong — SKIP LOCKED doesn't apply:**

`SKIP LOCKED` is for job queues — it tells a transaction "if this row is locked, skip it and pick another row." In a fund transfer, you cannot skip a locked account. You specifically need both account rows locked. SKIP LOCKED has no relevance here and does not prevent deadlocks.

**The actual prevention — consistent lock ordering:**

The deadlock is caused by inconsistent lock acquisition order: Service A locks `1 → 2`, Service B locks `2 → 1`. Fix: always acquire locks in **ascending ID order** across all services.

```java
long first  = Math.min(fromAccountId, toAccountId);
long second = Math.max(fromAccountId, toAccountId);

// Both services lock lower ID first
query("SELECT balance FROM accounts WHERE id = ? FOR UPDATE", first);
query("SELECT balance FROM accounts WHERE id = ? FOR UPDATE", second);
query("UPDATE accounts SET balance = balance - ? WHERE id = ?", amount, fromAccountId);
query("UPDATE accounts SET balance = balance + ? WHERE id = ?", amount, toAccountId);
conn.commit();
```

Now Service A and Service B both try to lock row 1 first. Service B blocks on row 1 while Service A holds it. No cycle. Deadlock structurally impossible.

**Complete two-part answer:**

| Part | Fix |
|---|---|
| Prevention | Consistent lock ordering (always min-ID first) — eliminates cycles by construction |
| When it happens anyway | Catch `40P01`, retry entire transaction with exponential backoff |

**Pattern takeaway:** SKIP LOCKED ≠ deadlock prevention. Deadlock prevention = consistent lock ordering. Deadlock handling = catch `40P01` + retry. Both needed: ordering prevents 99% of cases; retry catches edge cases from inconsistent legacy paths.

---

### Q8 — Short conceptual (Part 2): Group commit

**Question (verbatim):** Your Postgres database is handling 10,000 commits/second. A junior engineer says: "Each commit requires an fsync, which takes 5ms. That means we can do at most 1/0.005 = 200 commits/second. How are we doing 10,000?" What is the mechanism that makes this math wrong, and how does it work?

**Learner's answer:** Every transaction's commit piles their record on the WAL buffer. We use batching before doing fsync which flushes the buffer and everyone's commit returns.

**Score: 7/10**

**What was right:**
- Transactions pile WAL records into a shared buffer before the fsync. ✓
- One fsync flushes the buffer and all waiting commits return simultaneously. ✓
- This is the core of the mechanism. ✓

**What was missing:**

**The name:** This is **group commit**. Must be named in interviews.

**The math — why N/5ms not 1/5ms:**

At 10,000 TPS, one transaction arrives every 0.1ms. An fsync takes 5ms. During those 5ms, `5ms / 0.1ms = 50 transactions` pile their WAL records into the buffer. One fsync serves all 50. Throughput = `50 / 5ms = 10,000 commits/second`. The junior engineer's error: assumed 1 fsync = 1 transaction. Actual ratio: 1 fsync = N transactions, where N scales with arrival rate.

```
T=0ms:    T1 commits → writes to WAL buffer, kicks off fsync
T=0.1ms:  T2 commits → writes to WAL buffer, waits
...
T=4.9ms:  T50 commits → writes to WAL buffer, waits
T=5ms:    fsync completes → T1 through T50 all return simultaneously
```

**How the flush actually triggers (the subtle part):**

Not purely "batch then flush." When T1 calls `COMMIT`, it appends to `wal_buffers` then calls fsync up to its LSN. If another fsync is already in-flight, T1's thread waits. When the in-flight fsync completes, T1's LSN is already covered (WAL is sequential). The batching is **opportunistic** — high-concurrency systems batch naturally because commits arrive faster than a single fsync completes. The `commit_delay` parameter can artificially sleep before fsync to force more batching on low-concurrency systems.

**Pattern takeaway:** Group commit is why high-throughput databases aren't bottlenecked by disk fsync latency. Throughput = `N_concurrent / fsync_latency`, not `1 / fsync_latency`. This is the same principle behind batched writes in Kafka (producer linger.ms) and LSM commitlogs.

---

### Q9 — Scenario (Part 3): Atomic UPDATE guard vs read-then-write race condition

**Question (verbatim):** Two users simultaneously buy the last 1 unit. Which implementation is correct — A (SELECT then conditional UPDATE) or B (UPDATE with guard in WHERE clause)?

**Learner's answer:** A

**Score: 0/10**

**What was wrong — A is the classic overselling bug:**

Implementation A separates the guard check from the write into two statements with a gap between them:
```
T1: SELECT stock → 1. Check: 1 >= 1. Pass.
T2: SELECT stock → 1. Check: 1 >= 1. Pass.     ← reads before T1 commits
T1: UPDATE stock = stock - 1 → stock = 0. INSERT order. COMMIT.
T2: UPDATE stock = stock - 1 → stock = -1. INSERT order. COMMIT.
```
Two orders created. Stock = -1. The guard check ran on a stale read. By the time T2's UPDATE executes (on the current committed row), the check was already done on old data. This is the lost-update pattern from Q4 — the check and the write are not atomic.

**Why B is correct — check and decrement are one atomic statement:**

```sql
UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?
```

The `WHERE stock >= qty` guard and the `stock - qty` decrement are evaluated together at write time on the current committed row — no gap:
```
T1: UPDATE WHERE stock >= 1 → current: stock=1 → sets stock=0 → returns 1. Commits.
T2: UPDATE WHERE stock >= 1 → current: stock=0 → 0 >= 1 false → returns 0. Rollback. OutOfStockException.
```
One order. Stock = 0. Correct.

**The principle (same as Q4):** DML always targets the current committed row. Conditions in the WHERE clause are evaluated atomically with the write. A separate SELECT + conditional + UPDATE has a time-of-check / time-of-use (TOCTOU) gap — any concurrent commit in that window makes the check stale.

**When A's pattern IS safe:** Only when using `SELECT ... FOR UPDATE`. The `FOR UPDATE` locks the row at read time, so no concurrent transaction can modify it before your UPDATE. T2's locked SELECT would block until T1 commits, then T2 re-reads stock=0, check fails, safe.

```java
// Safe version of pattern A — FOR UPDATE eliminates the gap
int stock = query("SELECT stock FROM products WHERE id = ? FOR UPDATE", productId);
if (stock >= qty) { /* T2 will see 0 here after T1 commits */ }
```

**This exact bug ships in production regularly.** Symptom: negative inventory counts during flash sales. Fix: always use atomic guard in WHERE clause (B) or `SELECT FOR UPDATE` (A with the lock). Never plain SELECT + conditional + UPDATE.

**Clarification on `updated == 0` — what the UPDATE return value means:**

The pseudocode `int updated = query("UPDATE ...")` maps to JDBC's `ps.executeUpdate()`, which returns the **number of rows affected** (not a value from the row):

```java
PreparedStatement ps = conn.prepareStatement(
    "UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?"
);
ps.setInt(1, qty);
ps.setLong(2, productId);
ps.setInt(3, qty);
int rowsAffected = ps.executeUpdate();  // 1 = row was updated; 0 = WHERE matched nothing
```

`rowsAffected == 0` means the WHERE clause matched zero rows — either the product doesn't exist, OR `stock < qty`. In production code these should be differentiated (product-not-found is a different error than out-of-stock), but for the concurrency correctness argument, `0` correctly signals "the decrement did not happen."

---

### Q10 — Spaced revision (Topic 01): HTTP/2 multiplexing under downstream slowdown

**Question (verbatim):** Your microservice connects to a downstream over HTTP/2 with 5 persistent connections. Downstream slows from 10ms to 2s. (1) What happens to your connection pool and threads? Name the mechanism. (2) HTTP/1.1 with same 5 connections — larger, smaller, or same blast radius? Why? (3) Correct infrastructure-level fix (not "add a timeout").

**Learner's answer:** Not sure.

**Score: 0/10**

**Full answer:**

**Q1 — What happens (HTTP/2 + 5 connections):**

HTTP/2 multiplexes many **streams** over a single TCP connection. A pool of 5 connections does not mean 5 max concurrent requests — each connection can carry hundreds of concurrent streams (server's `SETTINGS_MAX_CONCURRENT_STREAMS`, often 100-1000). HTTP/2 happily accepts new streams on existing connections as requests arrive.

When downstream slows to 2s: every request blocks its caller thread for 2s. At 1000 RPS: `1000 RPS × 2s = 2000 threads` simultaneously blocked. Application thread pool exhausts. New requests cannot be served. Service appears to hang — not because connections are saturated, but because **all threads are stuck waiting on open streams**.

The specific mechanism: **HTTP/2 stream multiplexing removes the natural cap on in-flight requests**. The 5-connection pool provides no bulkhead against a slow downstream.

**Q2 — HTTP/1.1 blast radius: smaller.**

HTTP/1.1 allows 1 request per connection at a time. With 5 connections: max 5 concurrent in-flight requests. The 6th request blocks at the **connection pool**, not the thread pool. When downstream slows: exactly 5 threads are stuck, all others queue at pool level and fail fast on pool timeout. Thread pool never exhausts.

```
HTTP/1.1, 5 connections:  max 5 threads blocked → small, bounded blast radius
HTTP/2,   5 connections:  hundreds of threads blocked → large, unbounded blast radius
```

HTTP/1.1's connection-pool size acts as a **natural bulkhead** that HTTP/2's multiplexing eliminates. This is the counterintuitive cost of HTTP/2's performance win.

**Q3 — Infrastructure fix:**

**Circuit breaker.** When downstream error rate or p99 latency crosses a threshold, the circuit trips — subsequent requests fail immediately (fast-fail) without reaching the downstream. No threads are blocked.

```
CLOSED → normal → (error rate > threshold) → OPEN (fast-fail)
OPEN → (after timeout) → HALF-OPEN (probe) → success: CLOSED / failure: OPEN
```

Java: Resilience4j `CircuitBreaker`. Service mesh: Envoy/Istio outlier detection.

Secondary HTTP/2-specific fix: configure `maxConcurrentStreams` per connection to a low value (e.g., 10). Caps in-flight requests to `5 × 10 = 50`, recreating the HTTP/1.1 bulkhead.

**Pattern takeaway:** HTTP/2 multiplexing is a performance win under normal conditions but a blast-radius amplifier under slow downstreams. Circuit breakers are the mandatory infrastructure pairing. Never run HTTP/2 to external dependencies without a circuit breaker.

---
