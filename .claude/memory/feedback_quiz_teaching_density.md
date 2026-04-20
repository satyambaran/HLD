---
name: Quiz must test taught concepts
description: Every quiz question must test a mechanism that was actually taught with depth — not just name-dropped in notes. If teaching was thin, expand teaching first, then quiz.
type: feedback
originSessionId: 688abaed-84d1-4dd6-ad2b-985324e049e7
---
Every quiz question must test a mechanism that was **actually taught with depth** — either in chat or in the notes file. Name-dropping a term ("deadline propagation", "QPACK", "MVCC") and then asking a probing scenario question on its internals is unfair grading and bad teaching.

**Why:** Learner explicitly flagged this on 2026-04-19 during topic 01 Part 3 quiz — "I like the question level but concept teaching input is low." He could not answer Q9 on gRPC deadline propagation because the underlying mechanism (the `grpc-timeout` header, server-side Context propagation, why downstream calls drop the deadline) was only mentioned, not explained.

**How to apply:**
- Before posing a quiz question, audit: was the *mechanism being tested* actually taught (with the header name / state machine / sequence / code pattern), or just the *concept name*?
- If teaching was thin, expand the teaching first (chat + notes), THEN ask the question.
- Question difficulty is fine — keep it staff-level. The constraint is that the underlying material must have been delivered with internals-level depth.
- This applies even when the learner is reasonably expected to "know it from work" — Satyam's stated baseline is buzzwords-shallow, so don't assume.
