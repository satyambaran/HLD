# HLD Roadmap

> Legend: `[ ]` Untouched · `[~]` Intro/Practiced · `[✓]` Confident · `[★]` Interview-ready
> `state.json` is the source of truth — this file mirrors it for human-readable progress.

---

## Phase 0 — Foundations

- [~] **00** · [What is HLD & napkin math](notes/00-what-is-hld.md) — QPS, latency numbers every engineer should know, back-of-envelope sizing *(Practiced — input-parsing discipline locked)*
- [~] **01** · [Networking primer](notes/01-networking-primer.md) — HTTP/1.1 vs HTTP/2 vs HTTP/3, TCP, DNS, TLS, gRPC, WebSocket *(All 3 parts taught. Consolidation quiz 48.9% — missed Practiced. Deep-dive queued on: Anycast/BGP, WebSocket Close frames + graceful deploy, mesh LB granularity with H/2.)*

## Phase 1 — Storage

- [~] **02** · [SQL internals](notes/02-sql-internals.md) — B-tree indexes, WAL, MVCC, isolation levels, query planner *(All 3 parts taught. First quiz 32/100 (32%) → 1_intro. Weak: EXPLAIN stale-stats diagnosis, atomic-UPDATE vs race condition, H2 multiplexing blast radius. Mid-quiz deep-dive on isolation anomalies added to Part 2 notes.)*
- [ ] **03** · [NoSQL landscape](notes/03-nosql-landscape.md) — KV, document, column-family, graph — when each wins
- [ ] **04** · [Replication](notes/04-replication.md) — sync vs async, leader-follower, multi-leader, leaderless (Dynamo-style)
- [ ] **05** · [Partitioning & sharding](notes/05-partitioning.md) — range, hash, consistent hashing, hotspot mitigation
- [ ] **06** · [CAP, PACELC, consistency models](notes/06-cap-consistency.md) — linearizability, sequential, causal, eventual
- [ ] **07** · [DB comparison](notes/07-db-comparison.md) — MySQL, Postgres, DynamoDB, Cassandra, MongoDB, Neo4j — pick-the-right-tool

## Phase 2 — Speed layer (caching)

- [ ] **08** · [Caching patterns & failure modes](notes/08-caching-patterns.md) — cache-aside / write-through / write-back / read-through, invalidation, **thundering herd, cache stampede, hot keys, cache penetration**
- [ ] **09** · [Redis deep dive](notes/09-redis-deep.md) — data structures, persistence (RDB/AOF), cluster, pub/sub, distributed locks, rate limiting, leaderboards
- [ ] **10** · [Memcached vs Redis](notes/10-redis-vs-memcached.md) — when to pick the simpler tool
- [ ] **11** · [CDN & edge caching](notes/11-cdn-edge.md) — pull vs push, cache keys, origin shielding, Cloudflare/Akamai/CloudFront

## Phase 3 — Async & messaging

- [ ] **12** · [Queues vs pub/sub vs streams](notes/12-queues-vs-streams.md) — the three shapes and when each applies
- [ ] **13** · [Kafka internals](notes/13-kafka-internals.md) — partitions, consumer groups, ISR, exactly-once semantics, compaction
- [ ] **14** · [RabbitMQ, SQS/SNS, Pulsar](notes/14-rabbitmq-sqs-pulsar.md) — trade-offs vs Kafka
- [ ] **15** · [Delivery semantics & idempotency](notes/15-delivery-semantics.md) — at-most/at-least/exactly-once, dedup keys, outbox pattern

## Phase 4 — Data pipelines

- [ ] **16** · [Batch vs stream processing](notes/16-batch-vs-stream.md) — Spark vs Flink vs Kafka Streams
- [ ] **17** · [ETL/ELT & CDC](notes/17-etl-cdc.md) — Debezium, log-based vs trigger-based CDC
- [ ] **18** · [Lambda & Kappa architectures](notes/18-lambda-kappa.md) — historical context + modern alternatives

## Phase 5 — Distributed systems core

- [ ] **19** · [Consensus: Raft & Paxos](notes/19-consensus.md) — leader election, log replication, committed index
- [ ] **20** · [Leader election & leases](notes/20-leader-election.md) — ZooKeeper/etcd, fencing tokens
- [ ] **21** · [Load balancing](notes/21-load-balancing.md) — L4 vs L7, round-robin vs least-conn vs consistent-hash, sticky sessions
- [ ] **22** · [Fault tolerance](notes/22-fault-tolerance.md) — circuit breakers, retries with jitter, backpressure, bulkheads, timeouts

## Phase 6 — Production concerns

- [ ] **23** · [Rate limiting](notes/23-rate-limiting.md) — token bucket, leaky bucket, fixed/sliding window, distributed rate limiters
- [ ] **24** · [API design](notes/24-api-design.md) — REST vs gRPC vs GraphQL, pagination, versioning, idempotency keys
- [ ] **25** · [Observability](notes/25-observability.md) — metrics (Prometheus), tracing (OpenTelemetry), logs, SLIs/SLOs
- [ ] **26** · [Security basics](notes/26-security-basics.md) — AuthN vs AuthZ, OAuth2/OIDC, JWT pitfalls, secrets management

---

## Phase 7 — Case studies (Design X)

- [ ] **cs-01** · [URL shortener](case-studies/url-shortener.md)
- [ ] **cs-02** · [Rate limiter (distributed)](case-studies/rate-limiter.md)
- [ ] **cs-03** · [Notification system](case-studies/notification-system.md)
- [ ] **cs-04** · [Twitter feed](case-studies/twitter-feed.md)
- [ ] **cs-05** · [WhatsApp / chat](case-studies/whatsapp.md)
- [ ] **cs-06** · [Uber ride matching](case-studies/uber.md)
- [ ] **cs-07** · [YouTube / Netflix streaming](case-studies/video-streaming.md)
- [ ] **cs-08** · [Distributed cache](case-studies/distributed-cache.md)
- [ ] **cs-09** · [Google Drive / Dropbox](case-studies/dropbox.md)
- [ ] **cs-10** · [Payment system](case-studies/payment-system.md) — idempotency, exactly-once, double-entry ledger
- [ ] **cs-11** · [Google Maps](case-studies/google-maps.md) — geospatial indexing, tile serving, routing
- [ ] **cs-12** · [Logging / Metrics system](case-studies/logging-metrics.md) — Datadog/Prometheus/Elastic-style ingestion at scale

---

## How progress flows

1. `/hld-next` picks the next `[ ]` topic, teaches, quizzes, and updates state + this file.
2. After 2-3 topics in a phase, `/hld-revise` will mix in older topics for spaced repetition.
3. Start case studies only after Phase 2 is at least Practiced across the board — you need storage + caching mental models first. The earlier case studies (URL shortener, rate limiter) can be tackled after Phase 2. Uber/Twitter/WhatsApp should wait until Phase 5.
4. A phase is "done" when every topic hits **Confident (`[✓]`)**. "Interview-ready (`[★]`)" is earned per-topic via scenario + defense.

---

## Meta

- [ ] Full revision pass (re-read all notes in roadmap order — run `/hld-revise` repeatedly)
- [ ] Mock interview series (invoke `/hld-quiz` with `interview mode` — Claude plays Staff+ interviewer)
