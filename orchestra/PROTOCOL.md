# Orchestra Protocol — how agents talk

All coordination for project Dhruva (app AND website) happens in this directory.
Subagents have isolated contexts; this blackboard IS the conversation.

## Rules

1. **Read before work.** Every agent reads `BLACKBOARD.md` (current-loop threads),
   `DECISIONS.md`, and the repo `CLAUDE.md` before doing anything.
2. **Write after work.** Every agent appends exactly one structured report to
   `BLACKBOARD.md` when finished.
3. **Disagreement is a duty.** If you disagree with another agent's decision, post a
   `CHALLENGE` message. Polite silence is a bug. The orchestrator arbitrates within
   the same loop and records the ruling in `DECISIONS.md`.
4. **Append-only.** Never edit or delete existing blackboard messages.

## Message format

```
### [LOOP-NN] [sender → recipient] [TYPE] YYYY-MM-DDTHH:MM
Body: what was done / found / broken. File paths. Test counts. Known gaps.
Request: what you need from the recipient, if anything.
```

Allowed TYPEs: `RESEARCH`, `PROPOSAL`, `HANDOFF`, `BUG`, `CHALLENGE`, `REVIEW`,
`DECISION-REQUEST`, `STATUS`. Anything not in a type is noise — forbidden.

## Files

| File | Purpose |
|---|---|
| `BLACKBOARD.md` | Append-only message log (the conversation) |
| `DECISIONS.md` | Numbered ADR-style rulings by the orchestrator |
| `TASKS.md` | Living kanban: BACKLOG / IN-LOOP / BLOCKED / DONE |
| `LOOP_LOG.md` | One entry per loop: goal, shipped, gate results, retro |
| `RISKS.md` | Open risks with severity + mitigation |
| `NAMING.md` | Brand ceremony verification dossier (Loop 0) |

## Loop protocol

PLAN → BUILD → TEST → REVIEW → REFLECT → COMMIT. No phase skipped.
Exit gate = 3–7 binary checks. Max 3 gate attempts, then root-cause + scope cut.
QA verdict (PASS/FAIL) is required to exit any loop that ships code.
