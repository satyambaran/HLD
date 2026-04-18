# Notes

Per-topic deep notes live here, named `<id>-<slug>.md`. One file per roadmap topic.

Claude writes these automatically via `/hld-next`, `/hld-resume`, and `/hld-deepdive`. Don't create them manually — the slash commands own the structure and the filenames (the mapping is in `state.json`).

**How to revise a topic:**
1. Open the file directly in VSCode — markdown preview with Mermaid renders architecture diagrams inline.
2. Read top-to-bottom: TL;DR → Why it exists → Mental model → Internals → Trade-offs.
3. Want to test yourself without Claude teaching? Run `/hld-quiz <id>`.
4. Want to push further? `/hld-deepdive <id>`.

**Editing your own thoughts:**
You can add your own reflections anywhere in the file under a `## My notes — YYYY-MM-DD` section. Claude will preserve anything it didn't write.
