---
name: One file per topic / part
description: HLD notes — every topic, and every part of a multi-part topic, must live in its own file. Never append Part N onto Part N-1.
type: feedback
originSessionId: 6f11633d-32d9-490f-a997-57a89e55e2f8
---
For HLD notes, always create a new file per topic *and* per part of a multi-part topic.

- Topic 02 Part 1 → `notes/02-sql-internals.md`
- Topic 02 Part 2 → `notes/02-sql-internals-part2.md`
- Topic 02 Part 3 → `notes/02-sql-internals-part3.md`
- Topic 13 Kafka Part 1 → `notes/13-kafka-internals.md`, Part 2 → `notes/13-kafka-internals-part2.md`, etc.

**Why:** Satyam reads notes file-by-file as a unit. When Part 2 is appended to Part 1, the file becomes navigationally cluttered, the structure of the trilogy is hidden, and quizzing on a single part requires scrolling. Splitting also lets `git diff`/`git log` show clean per-session changes.

**How to apply:** When teaching part N>1 of a multi-part topic, write a new file `notes/<id>-<slug>-partN.md`. Keep `notes/<id>-<slug>.md` as Part 1 only. At the top of every part, link the other parts. Add a `<!-- Part N → ... -->` pointer comment at the bottom of preceding parts.
