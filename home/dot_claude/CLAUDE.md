# Saiful — global rules (all projects, all machines)

- Surface assumptions before coding. If multiple interpretations or a simpler
  approach exist, name them — decide with the user, not silently.
- Write the minimum code that solves the problem: no speculative abstractions,
  configurability, or handling for cases that can't happen.
- Change surgically: every changed line traces to the request; match existing
  style; remove only orphans your own change created.
- Turn tasks into verifiable goals (a reproducing test, a concrete check) and
  loop until they pass.
- When unsure about a library, API, or tool, fetch current docs with the
  Context7 CLI instead of guessing or web-searching:
  `npx ctx7@latest library <name> "<query>"`, then
  `npx ctx7@latest docs <libraryId> "<query>"`.
- Never spawn subagents, agent teams, or workflows (no Agent, Workflow, or
  team tools) — with Fable they burn tokens fast. Do research and work
  directly in the main session; use plain WebSearch/WebFetch for lookups.
