# Session Awareness

> **Intent (anchor):** Define lightweight session start and wrap-up behavior, including when to hand off to the `resume` skill.
> **Always:** check for active work at session start; summarize incomplete work at wrap-up; store durable context only when it is not already captured.
> **Never:** fabricate prior context or run a full resume workflow when the user is starting fresh.
> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored). Project may extend but must not contradict Global. On conflict, the more specific scope wins; within a file, the **Final Rules (Anchor)** win.

## Starting a Session

When a session begins on a repo where I've worked recently:

- **Check for active work** — look for uncommitted changes, in-progress branches, or open plan/task docs (e.g., `docs/features/*/tasks.md` with unchecked items).
- **If active work exists** — briefly summarize what's in progress and ask whether to continue or start something new.
- **If the user says "continue", "resume", or "pick up where I left off"** — use the `resume` skill for full context recovery.

## Ending a Session

When wrapping up substantial work that isn't fully complete:

- **Summarize state** — briefly note what's done, what's next, and any decisions pending.
- **Store critical context in memory** — if there's information the next session will need that isn't captured in code or docs (e.g., "decided to use approach X because of Y"), store it.
- **Leave breadcrumbs** — if a plan/tasks doc, issue tracker, or handover exists, ensure it reflects the truthful lifecycle state and blockers. See `work-lifecycle.instructions.md`.

## Final Rules (Anchor)

1. Check for active work before assuming the session is fresh.
2. Use the `resume` skill for explicit continue/resume context recovery; otherwise keep the check lightweight.
3. When substantial work remains incomplete, summarize state and leave breadcrumbs in existing durable artifacts.
> If anything above conflicts with these, **these win**.
