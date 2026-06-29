# Development Workflow

> **Intent (anchor):** Define the default tiered development workflow when no more specific skill or project workflow is active.
> **Always:** classify task scope first; validate changed behavior; defer to explicitly invoked skills for their owned workflow gates.
> **Never:** let the default workflow bypass a skill's approval gates or commit-review requirements.
> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored). Project may extend but must not contradict Global. On conflict, the more specific scope wins; within a file, the **Final Rules (Anchor)** win.

Every task follows a tiered workflow. Assess the scope on entry and apply the appropriate tier. The user can override the classification at any time (e.g., "treat this as trivial" or "use the full workflow").

## Tier Classification

| Tier | When to Use | Examples |
|------|-------------|----------|
| **Trivial** | Single-line change, no behavioral impact, no risk | Typo fix, config value tweak, comment correction, doc formatting |
| **Standard** | Contained change within one module, clear scope | Bug fix, small feature, refactor, adding/updating tests |
| **Full** | Multi-file feature, new module, architectural change, high risk | New service, cross-cutting refactor, schema migration, new integration |

When in doubt, go one tier up. If you realize mid-task that the scope grew, escalate to the next tier.

## Trivial Tier

1. **Understand** — Confirm the change is truly trivial and low-risk.
2. **Execute** — Make the change.
3. **Commit** — Commit directly (see Git Conventions). Skip the `git-commit-review` skill unless the user requests it.

## Standard Tier

1. **Understand** — Read and understand the task. Investigate the codebase: read relevant code, check existing patterns, and follow established conventions.
2. **Execute** — Implement the task. If the task involves code, write unit tests where possible. Tests travel with their code — they belong in the same commit.
3. **Review** — Self-review the outcome. Look for mistakes, refactoring opportunities, and improvements.
4. **Test** — Run existing tests to verify nothing is broken. If bugs are found, fix them.
5. **Commit** — Create commit(s) based on logical separation (see Git Conventions).

## Full Tier

1. **Understand** — Read and understand the task or plan. Investigate the codebase: read relevant code, check existing patterns, and follow established conventions.
2. **Plan & Document** — Create a short doc explaining what will be done and how at a high level. Place the doc based on the type of work:
   - **Feature work** → `docs/features/{feature}.md`
   - **Bug fix** → `docs/bugs/{bug}.md`
   - **Infrastructure** → `docs/infra/{topic}.md`
   - *Exception:* Skip this step when the task itself is updating a document — just update the document directly.
3. **Execute** — Implement the task. If the task involves code, write unit tests where possible. Tests travel with their code — they belong in the same commit.
4. **Review** — Self-review the outcome of step 3. Look for mistakes, refactoring opportunities, and improvements. Update the doc from step 2 if needed (e.g., note future improvements).
5. **Improve** — If the findings from step 4 are worth implementing now, do so — but be extra careful not to break anything. Run tests after each improvement.
6. **Test** — Perform manual testing. If bugs are found, fix them. If improvement opportunities emerge, loop back to step 4. Repeat until satisfied.
7. **Commit** — Create commit(s) based on logical separation. Each commit should represent one coherent change (see Git Conventions).
8. **Reflect** — Write a self-reflection: what went right, what went wrong, how to improve, and what was learned. Store the reflection in the relevant project doc from step 2 if appropriate; otherwise, create or update a retrospective at `docs/retrospectives/`.

## Final Rules (Anchor)

1. Classify every task as Trivial, Standard, or Full before acting.
2. When a user invokes a skill, that skill owns its workflow gates and artifacts.
3. Validate changed behavior before commit handoff, using the smallest existing relevant test/build/lint command.
> If anything above conflicts with these, **these win**.
