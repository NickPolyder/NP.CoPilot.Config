---
name: resume
description: >
  Recovers context from previous sessions. Queries session history, finds
  recent work in the current repository, summarizes progress, and reloads
  relevant plans, tasks, and decisions so work can continue seamlessly.
tags:
  - session
  - continuity
  - context
  - resume
visibility: user
tools:
  [agent]
---

# Purpose

> **Intent (anchor):** Recover recent repository and session context so work can resume from an accurate next step.
> **Always:** gather git, docs, session history, and memory signals; synthesize concise status; identify the most likely next action.
> **Never:** fabricate context or expose another user's session data.

> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored).
> Project may extend but must not contradict Global. On conflict, the more specific
> scope wins; within a file, the **Final Rules (Anchor)** win.

You are recovering context from previous work sessions so the user can continue seamlessly.

This skill is **informational only**. It pairs with the session-awareness
instruction to recover context, but it does not run an implementation workflow or
modify files.

Your goals are to:

- **Find recent activity** — query session history for work done in this repository.
- **Summarize progress** — what was accomplished, what's still in progress, what's blocked.
- **Reload context** — surface relevant plans, task lists, decisions, and open questions.
- **Establish next steps** — present a clear "here's where you left off, here's what's next."

---

# When to use this skill

Use this skill whenever:

- The user says "continue", "resume", "pick up where I left off", or "what was I working on?"
- The session-awareness instruction finds in-progress work and the user explicitly chooses to continue or recover it.
- The user returns after a break and needs to re-establish context.

Do **not** use this skill for:

- Searching for specific past sessions by topic — use the session store directly.
- Starting fresh work — just start normally.
- Historical research ("what did I do last month?") — query the session store directly.

---

# Workflow

## Step 1: Gather Signals

Check these sources in parallel:

### Git State

- **Current branch** — is it a feature branch? What does the name suggest?
- **Uncommitted changes** — `git status`. Are there work-in-progress modifications?
- **Recent commits** — `git log --oneline -10`. What was the last thing committed?
- **Stashed work** — `git stash list`. Anything stashed that might be relevant?

### Project Docs

- **Active plans** — check `docs/features/*/design.md` and `docs/features/*/tasks.md` for documents with incomplete items.
- **Bug docs** — check `docs/bugs/` for in-progress investigations.
- **Retrospectives** — recent entries in `docs/retrospectives/` for context on what just wrapped up.

### Session History

- Query the session store for recent sessions in this repository (last 7 days).
- Look for: summaries, checkpoints, and turn content that describes work state.

### Copilot Memory

- Check stored memories relevant to this repository for context about active decisions.

## Step 2: Synthesize

Compile findings into a concise status report:

```
### Session Resume: {Repository Name}

**Branch:** {current branch}
**Last session:** {date and brief summary}

#### In Progress

- {What's actively being worked on}
- {Current state — e.g., "Phase 3 implementation, tasks 1-4 done, task 5 next"}

#### Uncommitted Work

- {Summary of unstaged/staged changes, if any}

#### Key Decisions (from memory/docs)

- {Decision 1 — brief recap}
- {Decision 2 — brief recap}

#### Next Steps

1. {Most logical next action}
2. {Follow-up after that}
3. {Anything blocked and why}

---

Continue with {recommended next action}? (yes / different task / show more context)
```

## Step 3: Hand Off

Based on the user's choice:

- **Continue** — hand off to the appropriate workflow, skill, or direct task after the user confirms. Load the relevant plan/task doc if one exists, but do not implement inside `resume`.
- **Different task** — acknowledge the context but pivot to what the user wants.
- **Show more context** — provide deeper detail from session history, including specific decisions, code snippets discussed, or full task lists.

---

# Context Depth Levels

Adjust detail based on how long since the last session:

| Time Gap | Context Needed |
|----------|----------------|
| Same day | Minimal — just "you were doing X, uncommitted changes are Y" |
| 1-2 days | Standard — branch, progress, next steps |
| 3-7 days | Full — include key decisions and design rationale |
| 7+ days | Extended — re-read design docs, summarize architecture context |

---

# Coordination

- This skill is **informational** — it gathers and presents context but doesn't make changes.
- After resume, the user will likely invoke other skills (continue `prd-workflow`, use `refactor`, etc.) — hand off cleanly.

---

# Constraints

- **Don't guess** — if session history is empty or unclear, say so. Don't fabricate context.
- **Be concise** — the user wants to get back to work quickly, not read an essay.
- **Respect privacy** — don't surface information from other users' sessions if the session store contains multi-user data.
- **This skill is not an orchestrator** — it establishes context but doesn't drive implementation workflows.

---

## Final Rules (Anchor)

1. Don't guess — if session history is empty or unclear, say so.
2. Be concise — the user wants to get back to work quickly, not read an essay.
3. Respect privacy — don't surface information from other users' sessions.
> If anything above conflicts with these, **these win**.
