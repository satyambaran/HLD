---
description: Resume the HLD journey — quick recap of last session, warm-up quiz, then continue.
---

# /hld-resume — pick up where we left off

**Load context:**
- @guide.md
- @state.json
- @roadmap.md

---

## Steps

1. **Greet & orient in 3-5 lines:**
   - 👋 Welcome back. Last session: `<date>` — covered `<topic titles>`.
   - 📍 Current position: phase `<N>`, topic `<id> — <title>` at level `<level>`.
   - 🎯 Today's plan (proposed): warm-up quiz on `<last topic>` → then advance / deepen / revise.
   - 🤝 **Proceed? (Or redirect to `/hld-revise`, `/hld-deepdive <x>`, or a case study.)**

2. **WAIT for confirmation** before starting the warm-up. Don't dive in.

3. **Ask session length** if not in `$ARGUMENTS`.

4. **Warm-up quiz (2-3 questions)** on the last 1-2 topics from `sessionHistory`. Mixed format. Score them.
   - If warm-up average ≥ 70%: proceed to advance (call the same flow as `/hld-next`).
   - If < 70%: the learner is rusty. Offer: `Want a refresher on <topic> before advancing? [Y/n]`. If yes, re-teach the weak sub-parts (consult previous `notes/<id>-<slug>.md` and go deeper where they stumbled) — update notes with a "Revisit on YYYY-MM-DD" section.

5. **After warm-up,** follow `/hld-next` behavior to advance (or deepen) the current topic.

6. **Update state.json & roadmap.md** exactly as `/hld-next` would. Also mark today's warm-up scores against the relevant topic's `quizScores` with `type: "warmup"`.

7. **End with the 3-bullet summary + one curiosity question** (same format as /hld-next — end with *"Go deeper on X, or move to Y?"*).

`$ARGUMENTS` (optional): `quick`, `standard`, `deep`, or specify a topic id to resume a specific one.
