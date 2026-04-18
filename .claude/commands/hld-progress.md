---
description: Show a progress dashboard — mastery breakdown, revision queue, recent sessions.
---

# /hld-progress — progress dashboard

**Load context:**
- @state.json
- @roadmap.md

---

## Output (format strictly, no teaching)

### 🧭 Current position
- **Current topic:** `<id> — <title>` (`<level>`) · or `None — ready for /hld-next`
- **Last session:** `<date>` — `<command>` — `<topics>`
- **Sessions so far:** `<count>`
- **Started:** `<user.startedAt>` (`<days>` days ago)

### 📊 Mastery by level
| Level | Count | Topics |
|---|---|---|
| ⚪ Untouched | N | id list |
| 🟡 Intro | N | id list |
| 🟠 Practiced | N | id list |
| 🟢 Confident | N | id list |
| ⭐ Interview-ready | N | id list |

### 🧱 Mastery by phase
| Phase | Progress bar | % Confident+ |
|---|---|---|
| 0 Foundations | `████░░░░░░` | 40% |
| 1 Storage | `██░░░░░░░░` | 20% |
| ... | ... | ... |

(Use 10-char bars. Percentage = topics at `3_confident` or `4_interview_ready` / total topics in the phase.)

### 🔁 Revision queue (due)
List each topic in `revisionQueue`:
- `<id> — <title>` · level `<level>` · last practiced `<relative date>`

If empty: `🎉 Nothing due for revision right now.`

### 📅 Last 5 sessions
| Date | Command | Topics | Score |
|---|---|---|---|
(tail of `sessionHistory`)

### 🏛️ Case studies
| ID | Title | Status |
|---|---|---|
(from `state.caseStudies`, only show `in_progress` + `completed` + first 3 `not_started` that have prereqs met)

### 🎯 Recommendation
One line based on state:
- If current topic level < `3_confident` → `Continue with /hld-next (will deepen current topic).`
- If revisionQueue has 3+ items → `Run /hld-revise — 3+ topics due.`
- If current phase is Confident+ across all topics → `Time for a case study: /hld-casestudy <slug>.`
- Otherwise → `Advance with /hld-next.`

---

**No state changes.** This is a read-only command — do not modify state.json or roadmap.md.
