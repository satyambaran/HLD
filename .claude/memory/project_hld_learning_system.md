---
name: HLD learning project structure
description: Layout and workflow of the self-paced HLD learning system in ~/Documents/HLD, created 2026-04-18
type: project
originSessionId: 76d10c7d-1d00-494d-818c-fd676a496be9
---
The `/Users/satyambaran/Documents/HLD` folder is a Claude Code–driven self-paced system design learning project. Scaffolded 2026-04-18.

**Why:** Satyam wants to go from buzzword-level to SDE-2 interview-ready in HLD via an incremental, stateful, quiz-driven workflow rather than passive reading.

**How to apply:** When he runs any `/hld-*` slash command in this folder, follow `guide.md` strictly — it's the teaching constitution. Every teaching/quizzing command MUST update `state.json` and `roadmap.md` or the spaced-revision system breaks.

**Key files:**
- `CLAUDE.md` — compact operating charter that Claude Code auto-loads every session (session protocol, natural-language triggers, hard rules). Points at guide.md for details.
- `guide.md` — teaching constitution (role, session formats, quiz rules, state-update rules, mastery levels). Single source of behavioral truth. Loaded explicitly by slash commands via `@guide.md`.
- `roadmap.md` — 26 topics across 7 phases + 9 case studies, with live progress checkboxes.
- `state.json` — source of truth: `topics[]` with 5-level mastery (`0_untouched` → `4_interview_ready`), `currentTopicId`, `revisionQueue`, `sessionHistory`, `caseStudies[]` with `prereqPhases`.
- `notes/<id>-<slug>.md` — Claude-authored deep notes per topic.
- `quizzes/<id>-<slug>.md` — append-only log of every Q + answer + score.
- `case-studies/<slug>.md` — Design-X walkthroughs.
- `.claude/commands/hld-*.md` — 8 slash commands: next, resume, quiz, deepdive, revise, progress, roadmap, casestudy.

**Slash commands use `@file.md` to load context** (guide.md + state.json + roadmap.md minimum) and `$ARGUMENTS` for session length or topic selection.

**Mastery transitions** (from guide.md): never skip levels. Up by 1 when a quiz scores in the next band; down by 1 if revision quiz <50% of current band. Level 4 requires 90%+ on scenario questions with defended follow-ups.

**Case-study gating:** each case study has `prereqPhases`; `/hld-casestudy` warns if prereq topics are weak.

**If Satyam asks for changes to teaching behavior** (tone, depth, session format, diagram style): edit `guide.md`, not the individual commands. Every command re-reads it each invocation.
