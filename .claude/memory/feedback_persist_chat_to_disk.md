---
name: All chat content must persist to disk
description: Any substantive teaching, mid-quiz deep-dive, decision rubric, or clarification delivered in chat must be saved to notes/quizzes file IMMEDIATELY — never wait for the learner to ask.
type: feedback
originSessionId: 688abaed-84d1-4dd6-ad2b-985324e049e7
---
**Rule:** Every substantive piece of content delivered in chat — teaching, mid-quiz deep-dives, decision rubrics, clarifying explanations, worked examples — must be saved to the relevant disk file in the same turn it's produced. Chat is ephemeral; only files persist across sessions.

Specifically:
- **Teaching content** → `notes/<id>-<slug>.md` (full depth, not summarized)
- **Quiz Q+A+grade** → `quizzes/<id>-<slug>.md` (verbatim question + verbatim learner answer + grade + ideal answer / gap analysis — see also `feedback_quiz_log_format.md`)
- **Mid-quiz deep-dives** (e.g., when learner flags a teaching gap and you teach a mechanism inline before re-posing the question) → save the deep-dive into the **notes file** (in an appendix or appropriate section), not just into the quiz log

**Why:** Learner explicitly stated this preference on 2026-04-19 after catching two violations in the same session — (1) Part 2 quiz Qs stored with condensed question text instead of verbatim, and (2) the inline mini-deep-dive on gRPC deadline propagation was only stored in the quiz log, not woven back into `notes/01-networking-primer.md`. Required two follow-up requests to fix. This is the rule from `guide.md` ("Chat is dialogue; disk is memory") restated as direct user feedback.

**How to apply:**
- Default behavior: **save before posting the chat message, not after.** Treat the chat output as a *summary* of what's already on disk, not the source of truth.
- Never ship a teaching response without also persisting it. If a deep-dive is delivered to answer a clarifying question, append/edit the relevant notes file before responding.
- For quiz logs: paste the question text exactly as posed in chat (including MCQ option letters, prompt formatting, sub-questions, hints) and the learner's answer character-for-character — no paraphrasing, no condensing.
- If a session ends with quizzes/teaching that didn't get persisted live, do a sweep at session-end before the wrap message.
- This applies to ALL slash commands: `/hld-next`, `/hld-quiz`, `/hld-deepdive`, `/hld-revise`, `/hld-casestudy`. Same rule for case studies → `case-studies/<slug>.md`.
