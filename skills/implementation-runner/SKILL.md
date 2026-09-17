---
name: implementation-runner
description: >
  Executes an approved task breakdown in dependency order, producing working
  code with tests alongside, updating task status, and reporting per-phase
  results.
---

# Purpose

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are executing an approved task breakdown, keeping implementation, tests, and task status synchronized.

Your goals are to:

- **Implement in order** — respect dependencies and do not skip ahead.
- **Test alongside code** — add or update tests with each implementation task.
- **Maintain status** — mark completed tasks in `tasks.md` as work is verified.
- **Report progress** — summarize each phase, test results, and any deviations from the design.

---

# When to use this skill

Use this skill whenever:

- A `tasks.md` has been approved and implementation should begin.
- The user asks to execute an existing task breakdown in order.
- Work needs task status updates, per-phase reporting, and test verification.
- You need the fourth atomic step in the chain: `codebase-research` → `feature-design-doc` → `task-breakdown` → `implementation-runner`.

Do **not** use this skill for:

- Initial research — use `codebase-research`.
- Writing a design document — use `feature-design-doc`.
- Creating the task breakdown — use `task-breakdown`.
- Commit review or commit creation — prepare a handoff and recommend `git-commit-review`.

---

# Workflow

Execute tasks in order, producing working code with tests.

1. **Follow task order** — respect dependencies. Do not skip ahead.
2. **For each task:**
   - Implement the code change.
   - Keep applicable tests with changed behavior using the repository's runner;
     record no-runner limits and any policy-permitted direct verification.
   - Verify the task before marking it complete in `tasks.md` (prefix with `[x]`).
3. **After each phase** (group of related tasks), report:
   - What was implemented.
   - Revision-bound verification (commands, working directories, pass/fail/skip
     counts or explicit no-runner limits; never invented `0/0` passes).
   - Any deviations from the design.
4. **Final verification** — run the repository-required final checks, including
   the full existing test suite when applicable. Follow the shared no-runner
   contract; missing required checks remain blockers.
5. **Commit handoff** — return completion and evidence to the invoking workflow
   (such as `prd-workflow`); this phase finishing does not end its parent.
   Standalone, finish this skill before recommending a separate
   `git-commit-review`. Never start it inside an active parent.

After implementation, ask:

> **Implementation status: {complete / blocked}. Verification: {actual results and limitations}. Ready for separate review? (yes / fix issues first)**

---

# Output locations

Produce:

- Code: appropriate source directories per project conventions.
- Tests: appropriate test directories per project conventions.
- Tasks: updated `docs/features/{feature-name}/tasks.md` with completed tasks prefixed by `[x]`.
- Reports: per-phase implementation summaries and final test results in the conversation.

If the project defines a different docs or source structure, follow that instead.

---

# Coordination

- Use `implementer` for substantial approved implementation, test or writing
  assignments. Keep small tasks inline and preserve each assignment's write scope.
- Use `investigator` for substantial unresolved design, test-strategy or security
  questions; independent assessment uses `code-reviewer` with immutable inputs.
- **Documentation skill** — after implementation is complete, recommend using the `documentation` skill to update `docs/` with the implemented feature's documentation.
- **Git commit review skill** — return a verification handoff to the caller;
  recommend `git-commit-review` only as a separate workflow after the owner completes.

---

# Constraints

- **Approved tasks only** — execute the approved `tasks.md`; do not silently add scope.
- **Respect dependencies** — follow task order and do not skip ahead.
- **Behavior needs evidence** — keep applicable tests alongside implementation
  and run the smallest relevant checks, escalating as required. Follow the
  shared no-runner rules; missing required verification is a blocker.
- **Status must stay current** — mark tasks complete in `tasks.md` only after implementation and verification for that task are done.
- **Separate delivery** — prepare a `git-commit-review` handoff after verification;
  never invoke it inside this phase or an active parent.

---
