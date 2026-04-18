---
description: Go beyond base notes on a topic — edge cases, failure modes, production incidents.
---

# /hld-deepdive — go deeper

**Load context:**
- @guide.md
- @state.json
- @roadmap.md
- The base notes file: `notes/<id>-<slug>.md` (read before teaching — don't repeat what's there)

---

## Steps

1. **Resolve topic** from `$ARGUMENTS` (required — if missing, ask: "Deep-dive on which topic? (id/slug/title)"). Refuse if topic is `0_untouched` — need base teaching first.

2. **Read the existing notes** for this topic. Identify what's already covered. Your job is to go BEYOND that, not repeat it.

3. **Teach the "senior" layer.** Pick 3-5 of these angles (whichever are most valuable for this topic):
   - **Edge cases** — inputs/conditions that break the naive implementation
   - **Failure modes** — what happens when network partitions / leader crashes / disk fills / clock skews
   - **Real production incidents** — publicly documented postmortems (GitHub, Stripe, AWS, Cloudflare, Slack) — cite the incident year and root cause
   - **Performance tuning** — what knobs actually matter, how to measure
   - **Scaling cliffs** — where the system stops behaving linearly and what to do
   - **Alternative designs** — what else could solve the same problem, and why this one won (or didn't)
   - **Subtle trade-offs** — things junior engineers miss but staff+ engineers obsess over
   - **Cross-system interactions** — how this topic composes with 1-2 other topics (cite other notes files)

4. **Append to `notes/<id>-<slug>.md`** under a new section:
   ```
   ## Deep dive — YYYY-MM-DD
   ### <angle 1>
   ...
   ```
   Don't overwrite existing content.

5. **End with a scenario quiz (3 questions)** focused on the deep-dive material. Grade, feedback, record to `quizzes/<id>-<slug>.md`.

6. **Update state.json:**
   - `lastPracticedAt` = today, `sessionsSeen += 1`
   - Append quiz scores with `type: "deepdive"`
   - Lift level by 1 if scenario quiz ≥ 75% AND current level < `4_interview_ready`
   - Append to `sessionHistory`

7. **Update roadmap.md checkbox** if level changed.

8. **End summary** (2 bullets):
   - 🔬 Deeper angles covered: `<list>`
   - 🧠 Level: `<previous>` → `<new>`

`$ARGUMENTS` (required): topic id/slug/title. Example: `kafka`, `13`, `consensus`.
