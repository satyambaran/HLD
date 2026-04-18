# Quizzes

Every question Claude asks you — and every answer you give — gets logged here. One file per topic, same `<id>-<slug>.md` naming as `notes/`.

Format per session (appended, never overwritten):

```markdown
## Session YYYY-MM-DD — type: standard | warmup | deepdive | revision | quiz-only

### Q1 (scenario)
> You have 50M writes/day, <10ms read SLA... which DB?

**Your answer:** <what you said>
**Score:** 7/10
**Ideal answer:** ...
**Feedback:** Missed the write-amplification angle on LSM-tree storage.

### Q2 (MCQ+why)
...
```

**Why keep these?** Two reasons:
1. **Interview prep:** re-reading your wrong answers from 2 weeks ago is the single most efficient review. Do this before a real interview.
2. **Spaced revision:** `/hld-revise` picks questions partially informed by your historical weak spots.

**Don't edit these by hand.** If you disagree with a grade, tell Claude in the next session and it'll re-score with notes.
