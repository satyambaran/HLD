---
description: Walk through a system design case study (Design X) end-to-end.
---

# /hld-casestudy — Design-X walkthrough

**Load context:**
- @guide.md
- @state.json
- @roadmap.md

---

## Steps

1. **Resolve the case study** from `$ARGUMENTS`:
   - Match against `state.caseStudies[].slug` or `title`.
   - If missing, list available case studies with their `prereqPhases` and ask which one.

2. **Prereq check:** verify that topics in `prereqPhases` are mostly at `2_practiced` or above. If <50% of prereq topics are at that level, warn: `Prereq phases <N> are weak — you may struggle. Run /hld-next a few more times? [Y/n]`. Proceed if learner insists.

3. **Write (or append to) `case-studies/<slug>.md`** using this exact structure — teach each section conversationally, ask the learner to propose their own approach BEFORE you reveal the "standard" answer for each section:

   ```markdown
   # Design <X>

   ## 1. Functional requirements
   - List what the system must do (the core user stories)

   ## 2. Non-functional requirements
   - Latency SLA · Throughput · Availability · Consistency · Durability · Cost

   ## 3. Capacity estimation (napkin math)
   - DAU → QPS · Storage per day/year · Bandwidth · Cache working-set size
   - Show the math, not just the answers.

   ## 4. API design
   - Core endpoints / RPCs / topic schemas

   ## 5. High-level architecture
   (Mermaid flowchart — client → LB → services → storage)

   ## 6. Deep dive
   Pick 2-3 of the most interesting components; for each:
   - Data model
   - Read path
   - Write path
   - Why this choice over the alternatives

   ## 7. Bottlenecks & scaling
   - What breaks first at 10×? What's the fix?

   ## 8. Follow-up questions interviewers love
   - List 5-8 realistic follow-ups

   ## 9. Common mistakes / red flags
   - 3-5 things juniors say that interviewers dislike
   ```

4. **Teach Socratically.** For each section, ask the learner first: *"How would you estimate the QPS?"* / *"Which DB would you pick and why?"* Grade their answer, then present the standard expert approach. This is where real interview skill develops.

5. **End with a mock interview prompt.** Give them 3 follow-up questions from section 8 — one at a time, grade, coach.

6. **Update state.json:**
   - In `caseStudies[]` for this case: set `status` to `in_progress` (if starting) or `completed` (if reaching section 9 with ≥75% on the mock interview).
   - Set `completedAt` to today if completed.
   - Append to `sessionHistory`: `{ date, command: "/hld-casestudy", caseStudyId, status, mockScore }`.

7. **End summary:**
   - 🏛️ `<X>` — status: `<status>`
   - 📊 Mock interview: `<score>/<max>`
   - 🎯 Biggest gap: `<section>` — suggest a `/hld-deepdive <topic>` from the prereqs

`$ARGUMENTS` (required): case-study slug or title. Examples: `url-shortener`, `uber`, `twitter-feed`.
