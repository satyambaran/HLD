---
description: Spaced-revision quiz across older topics. No new content.
---

# /hld-revise — spaced revision pass

**Load context:**
- @guide.md
- @state.json
- @roadmap.md

---

## Steps

1. **Compute the revision set:**
   - Candidates = topics with level `1_intro` or `2_practiced` AND `lastPracticedAt` ≥ 2 sessions ago.
   - If fewer than 3 candidates, broaden to include `3_confident` topics not practiced in 5+ sessions.
   - If still < 3, respond: `Not enough older topics to revise yet — keep using /hld-next for a few more sessions.` and stop.

2. **Announce the revision plan** in one line: `Revising: <topic A>, <topic B>, <topic C>. 6 mixed questions.`

3. **Default to 6 questions** (override via `$ARGUMENTS`: `short`=4, `long`=10). Mix formats across the revision set:
   - MCQ+why, short-answer conceptual, scenario/trade-off, at least 1 "compare A vs B" cross-topic question
   - Weight toward topics with the lowest level or oldest `lastPracticedAt`.

4. **One question at a time.** Grade, explain, feedback, next.

5. **Append to each affected `quizzes/<id>-<slug>.md`** under a `## Revision — YYYY-MM-DD` block.

6. **Update state.json for each topic quizzed:**
   - `lastPracticedAt` = today, `sessionsSeen += 1`
   - Append quiz score with `type: "revision"`
   - Apply mastery rules: scores ≥ next band → level up; scores < 50% of current band → level down (but never below `1_intro`).
   - Append ONE entry to `sessionHistory` with `command: "/hld-revise"` and the list of `topicIds`.
   - Recompute `revisionQueue`.

7. **Update roadmap.md** for any topic whose level changed.

8. **End summary (3 bullets):**
   - 📊 Revision score: `<n>/<max>` (<percentage>%)
   - 🔺 Leveled up: `<topics>` · 🔻 Leveled down: `<topics>`
   - 🎯 Weakest across this set: `<topic>` — suggest `/hld-deepdive <topic>` if a topic scored < 50%

`$ARGUMENTS` (optional): `short`, `standard`, `long`, or a specific topic set like `caching,kafka`.
