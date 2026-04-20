---
name: Quiz log format — include verbatim Q+A
description: In HLD quiz logs, always include the full question text and the learner's verbatim answer, not just summaries
type: feedback
originSessionId: ac26631e-a6bd-42c5-98ef-56746644d164
---
HLD quiz logs (`quizzes/<id>-<slug>.md`) must include **the full question text** and **the learner's verbatim answer** for each question, not just summarized bullets. Alongside: score, gap analysis, and ideal answer.

**Why:** Satyam explicitly asked for this after session 2 (topic 01). Summary-only logs are worthless for later revision because they lose the exact framing of the question (which is often where the learner's confusion lives) and the exact wording of the answer (which shows the actual gap in reasoning, not a paraphrase).

**How to apply:** Every entry in a quiz log should have this shape:

```markdown
### Q<N> · <type> — <topic>
**Question:** <full prompt, blockquoted>
**Learner's answer:** <verbatim, blockquoted, preserving typos if they reveal thinking>
**Score: X/10**
**Strong:** <what landed>
**Gap:** <what was missed>
**Ideal answer:** <the Staff-level version>
```

Applies to all `/hld-next`, `/hld-quiz`, `/hld-revise`, and `/hld-deepdive` sessions.
