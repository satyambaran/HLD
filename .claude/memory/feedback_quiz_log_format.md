---
name: Quiz log format — include verbatim Q+A + full ideal-answer depth
description: In HLD quiz logs, always include the full question text, the learner's verbatim answer, AND the full ideal-answer explanation at the same depth as delivered in chat (no condensation)
type: feedback
originSessionId: ac26631e-a6bd-42c5-98ef-56746644d164
---

HLD quiz logs (`quizzes/<id>-<slug>.md`) must include **the full question text**, **the learner's verbatim answer**, AND **the ideal-answer explanation at the same depth and structure as delivered in chat**. Do not condense the ideal answer into summary bullets — the log is the durable teaching artifact; chat is ephemeral.

**Why:** Satyam raised this twice. First (session 2) about preserving verbatim Q+A. Second (session 4, 2026-04-20) about the ideal-answer explanation being truncated to summary bullets in the log when the in-chat version had full tables, mechanism breakdowns, code snippets, distractor-by-distractor refutations, and "pattern takeaway" sections. The quiz log is what he revises from later; losing the teaching depth makes the log useless for revision, since the summary doesn't re-teach — it only reminds.

**How to apply:** Every entry in a quiz log should have this shape:

```markdown
### Q<N> · <type> — <topic>
**Question (verbatim):** <full prompt, blockquoted>
**Learner's answer (verbatim):** <blockquoted, preserving typos if they reveal thinking>
**Score: X/10**
**Strong:** <what landed, substantively>
**Gap:** <what was missed, substantively>
**Ideal answer:** <the Staff-level version at chat-depth — tables, code snippets, named mechanisms, distractor refutations, pattern takeaways. NOT compressed to bullets. If chat gave a table, log must include the table. If chat gave a Java snippet, log must include it.>
**Pattern takeaway** (when relevant): <what this question's failure/success reveals about a recurring behavior>
```

**Rule of thumb:** if the log entry is noticeably shorter than the in-chat grading response, it's too short. The only thing that should be removed in the log is the transient chat framing ("Let's break this down…"); every piece of actual teaching content must survive.

Applies to all `/hld-next`, `/hld-quiz`, `/hld-revise`, and `/hld-deepdive` sessions.
