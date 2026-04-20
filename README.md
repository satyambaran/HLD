# HLD — Self-paced system design mastery

A Claude Code–driven learning system. You show up, run a slash command, and Claude teaches, quizzes, and tracks your progress. All state is version-controllable markdown + one JSON file — no hidden databases.

> **Target:** SDE-2 / Senior interview-ready at top-tier companies (Uber, Amazon, LinkedIn, Netflix, Google).

---

## 🚀 First-time setup (one minute)

1. **Open the workspace in VSCode** (substitute your clone path):
   ```bash
   code <path-to-clone>/HLD.code-workspace
   ```

2. **Wire Claude's auto-memory to the repo (one-time, per machine):**
   ```bash
   ./scripts/setup-memory.sh
   ```
   This symlinks Claude Code's per-project memory directory (`~/.claude/projects/<id>/memory/`) to this repo's `.claude/memory/` so feedback memories, user notes, and project context travel with the repo across machines. Idempotent — safe to re-run.

3. **When VSCode prompts "Install recommended extensions?" → click Install All.** You'll get:
   - `bierner.markdown-mermaid` — renders architecture diagrams inline
   - `yzhang.markdown-all-in-one` — TOC, checkboxes, shortcuts
   - `bpruitt-goddard.mermaid-markdown-syntax-highlighting` — colored Mermaid code
   - `davidanson.vscode-markdownlint` — keeps notes tidy
   - `anthropic.claude-code` — the CLI as a sidebar

4. **Open the Claude Code panel** (Cmd+Esc in VSCode, or run `claude` in the terminal inside this folder).

5. **Run your first session:**
   ```
   /hld-next
   ```
   Claude will ask how much time you have, then teach topic `00` and quiz you.

That's it. Come back tomorrow and run `/hld-resume` instead.

### Working across multiple machines

Everything Claude needs — notes, quizzes, `state.json`, `roadmap.md`, and Claude's auto-memory (`.claude/memory/`) — lives in this repo and travels via git. On each new machine, run `./scripts/setup-memory.sh` once.

**Daily discipline (mandatory to avoid merge conflicts on `state.json`):**

```bash
git pull                                       # BEFORE starting a session
# …run /hld-next or /hld-resume with Claude…
git add . && git commit -m "HLD: <topic>" && git push   # AFTER wrapping
```

`state.json` and memory files change every session — skipping `git pull` on the second laptop will force you to hand-resolve JSON conflicts.

---

## 📁 What's in this folder

```
HLD/
├── guide.md              ← teaching constitution (edit to change Claude's behavior)
├── roadmap.md            ← phased plan with live progress checkboxes
├── state.json            ← source of truth: mastery, history, revision queue
├── README.md             ← this file
├── HLD.code-workspace    ← VSCode workspace
│
├── notes/                ← Claude writes deep notes here (one file per topic)
├── quizzes/              ← every Q+A+grade you've ever done, per topic
├── case-studies/         ← "Design X" walkthroughs
│
├── .vscode/
│   └── extensions.json   ← recommended extensions
│
├── scripts/
│   └── setup-memory.sh   ← one-time per-machine: symlinks Claude memory into the repo
│
└── .claude/
    ├── commands/         ← slash commands that power the workflow
    └── memory/           ← Claude's auto-memory (user role, feedback, project context)
                            symlinked from ~/.claude/projects/<id>/memory/ via setup script
```

---

## 🎛️ Slash commands (the core workflow)

| Command | What it does | When to use |
|---|---|---|
| `/hld-next` | Teach the next roadmap topic, then quiz | Most sessions — advance |
| `/hld-resume` | Recap last session, warm-up quiz, then advance | Returning after a break |
| `/hld-quiz <topic>` | Quiz only, no teaching | Self-test before a real interview |
| `/hld-deepdive <topic>` | Go beyond base notes: edge cases, failures, incidents | Topic feels "known but shallow" |
| `/hld-revise` | Spaced quiz across older topics | Every 3-4 sessions |
| `/hld-progress` | Dashboard: mastery, revision queue, recent sessions | "Where am I?" |
| `/hld-roadmap` | Full plan with current position | Zoom out |
| `/hld-casestudy <system>` | End-to-end Design-X walkthrough | After Phase 2 is mostly Practiced+ |

**Natural language works too.** Any of these are fine:
- "quiz me on Kafka ordering"
- "go deeper on Redis persistence"
- "show my progress"
- "design Uber's ride matching"

---

## 🧭 Suggested weekly rhythm

| Day | Command | Why |
|---|---|---|
| Mon | `/hld-resume` | Warm-up + advance into the week |
| Tue | `/hld-next` | New topic |
| Wed | `/hld-next` | New topic |
| Thu | `/hld-revise` | Prevent decay |
| Fri | `/hld-deepdive <weakest topic>` | Convert Practiced → Confident |
| Sat | `/hld-casestudy <next>` (once eligible) | Apply + integrate |
| Sun | rest, or `/hld-progress` + free reading |

Miss a day? No penalty — `/hld-resume` always knows where you left off.

---

## 📊 Mastery levels (5-stage)

| Level | Meaning |
|---|---|
| ⚪ Untouched | Not yet taught |
| 🟡 Intro | Taught once; quiz <60% |
| 🟠 Practiced | Returned; 60-75% |
| 🟢 Confident | 75-89% on scenario-heavy quiz |
| ⭐ Interview-ready | 90%+ with defended follow-ups |

A topic only reaches **Interview-ready** when you can:
1. Explain it without notes in under 5 minutes
2. Defend one non-obvious trade-off under probing
3. Cite one production example and one failure mode
4. Apply it correctly in a case study

---

## 🧠 How learning is engineered here

- **All four quiz styles** — MCQ with "why?", short-answer, scenario/trade-off, cross-topic compare.
- **Spaced revision** — Claude automatically computes which older topics are decaying (`lastPracticedAt` + current level) and mixes them into new sessions.
- **Socratic case studies** — Claude asks you to propose before revealing the standard approach. That's where interview skill is built.
- **Buzzword challenge** — given your baseline, Claude explicitly flags where your intuition from hearing-about is likely wrong.
- **Every Q+A is logged** — `quizzes/<topic>.md` is a goldmine to re-read the week before an interview.

---

## 🛠️ Customizing behavior

Claude's teaching style is defined entirely in `guide.md`. Don't like something? Edit guide.md.

Examples:
- Want shorter sessions by default? Change the "Session types" table.
- Want more code examples? Add a note to the teaching format: "Include pseudo-code for every algorithm."
- Want a specific company focus (say, Uber-heavy)? Say so in the "Learner profile" section.

Every slash command re-reads guide.md each invocation, so changes take effect immediately.

---

## 🔁 Resetting or exporting

- **Reset progress:** delete `state.json` and re-run — but you'll lose history. Better: set everything in `topics[].level` back to `"0_untouched"`.
- **Export for interview prep:** the `quizzes/` folder is the highest-value review material. Grep for low scores: `grep -r "Score: [0-4]/" quizzes/`.
- **Version control (optional but recommended):**
  ```bash
  cd /Users/satyambaran/Documents/HLD
  git init && git add . && git commit -m "HLD scaffold"
  ```
  Commit after every session — you'll have a complete audit trail of your growth.

---

## ❓ FAQ

**Can I skip ahead to Design Uber?** Yes, but `/hld-casestudy` will warn you if prereqs are weak. You'll get more out of it after Phase 2.

**What if Claude teaches something I already know?** Tell it — "I already know B-trees, skip that part, go straight to WAL." It'll adapt and update state.json accordingly.

**What if I disagree with a quiz score?** Push back in the next session. Claude will re-grade with your rationale.

**Does this replace books / blogs?** No. This is the *structured practice layer*. The `Further reading` section in each note points you at the canonical source (DDIA, Kleppmann papers, company engineering blogs).

**What's the total time budget to "interview-ready"?** 26 topics × ~1 hour average + 9 case studies × ~1.5 hours ≈ **40-50 hours of focused work**, spread over 2-3 months at 4-5 sessions/week.

---

## 🎯 Start now

```
/hld-next
```

Claude will take it from there.
