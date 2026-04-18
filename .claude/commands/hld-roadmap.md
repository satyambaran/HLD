---
description: Show the full HLD roadmap with current position highlighted.
---

# /hld-roadmap — the plan

**Load context:**
- @roadmap.md
- @state.json

---

## Output

1. Print the full roadmap, grouped by phase.
2. For each topic, show the checkbox matching its level in state.json:
   - `[ ]` Untouched · `[~]` Intro or Practiced · `[✓]` Confident · `[★]` Interview-ready
3. Mark the current topic (`currentTopicId`) with a **👉** pointer at the line start.
4. After each phase, show the phase completion percentage (% of topics at Confident+).
5. At the bottom, show:
   - Overall completion: `<n>/<total>` topics at Confident+ (`<percentage>%`)
   - Case studies completed: `<n>/9`
6. End with a single-line recommendation (same logic as `/hld-progress`).

**No state changes.** Read-only.

`$ARGUMENTS` (optional): `phase 2` to filter to a single phase; `case-studies` to filter to case-study rows only.
