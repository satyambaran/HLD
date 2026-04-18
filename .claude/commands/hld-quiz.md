---
description: Quiz the learner on a topic (mixed formats) without teaching new content.
---

# /hld-quiz — quiz-only session

**Load context:**
- @guide.md
- @state.json
- @roadmap.md

---

## Steps

1. **Resolve topic:**
   - If `$ARGUMENTS` names a topic (id, slug, or title fragment), use it.
   - Else if `state.json.currentTopicId` is set, use that.
   - Else: list the 5 most recent non-untouched topics and ask which to quiz on.

2. **Refuse if level is `0_untouched`** — respond: `This topic hasn't been taught yet. Run /hld-next first.`

3. **Pick number of questions by `$ARGUMENTS` hint** (default 5): `short` → 3, `standard` → 5, `long` → 8.

4. **Mix all four question styles:**
   - ≥1 MCQ with "why?" follow-up
   - ≥1 short-answer conceptual ("Explain <X> in your own words")
   - ≥1 scenario / trade-off (give specs; ask for a design choice + defense)
   - If the session has ≥5 questions, add 1 edge-case / failure-mode question ("What breaks when <X>? How do you detect and recover?")

5. **One question at a time.** Wait for the answer. Grade 0-10. Explain ideal answer. Highlight gaps/wins. Move on.

6. **Append to `quizzes/<id>-<slug>.md`** — a dated block with each Q, the learner's answer, the score, and the ideal answer.

7. **Update state.json:**
   - `lastPracticedAt` = today
   - `sessionsSeen += 1`
   - Append `{ date, type: "quiz-only", score, max }` to `quizScores`
   - Bump `level` per mastery rules in guide.md (scores <50% of current band drop a level; scores in next band lift a level)
   - Append to `sessionHistory`: `{ date, command: "/hld-quiz", topicIds: [id], score, max }`

8. **Update roadmap.md checkbox** if level changed.

9. **End with:**
   - 📊 Score: `<n>/<max>` (<percentage>%)
   - 🧠 Level: `<previous>` → `<new>` (or "unchanged")
   - 🎯 Weakest area: `<sub-topic>` — suggest `/hld-deepdive <topic>` if you scored <60% on any sub-area

`$ARGUMENTS` (optional): topic id/slug + optional length hint. Examples: `13`, `kafka`, `kafka long`, `caching short`.
