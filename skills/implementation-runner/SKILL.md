---
name: implementation-runner
description: >
  Executes an approved task breakdown in dependency order, producing working
  code with tests alongside, updating task status, and reporting per-phase
  results.
---

# Purpose

> **Intent (anchor):** Execute an approved `tasks.md` in dependency order, producing working code with tests and updated task status.
> **Always:** follow task order; respect dependencies; write tests alongside code; update completed tasks; report after each phase and final verification.
> **Never:** skip ahead, ignore failing tests, or change approved scope silently.

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
   - Write unit tests alongside the code.
   - Mark the task as complete in `tasks.md` (prefix with `[x]`).
3. **After each phase** (group of related tasks), report:
   - What was implemented.
   - Test results (pass/fail counts).
   - Any deviations from the design.
4. **After all tasks are complete**, run the full test suite and report results.
5. **Commit handoff** — after implementation is verified, delegate commit review and commit creation to `git-commit-review`.

After implementation, ask:

> **Implementation complete. {passed}/{total} tests passing. Ready for review? (yes / fix issues first)**

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

- **Backend/Frontend developer agents** — consult during implementation for pattern questions and framework-specific work.
- **QA engineer agent** — consult for test coverage, edge cases, and verification strategy.
- **Security engineer agent** — consult when implementation touches authentication, authorization, input validation, secrets, or sensitive data.
- **Documentation skill** — after implementation is complete, recommend using the `documentation` skill to update `docs/` with the implemented feature's documentation.
- **Git commit review skill** — after implementation is verified, prepare a handoff and recommend `git-commit-review` for commit review and commit creation.

---

# Constraints

- **Approved tasks only** — execute the approved `tasks.md`; do not silently add scope.
- **Respect dependencies** — follow task order and do not skip ahead.
- **Tests are required** — write tests alongside implementation and run the smallest relevant verification, escalating as needed.
- **Status must stay current** — mark tasks complete in `tasks.md` only after implementation and verification for that task are done.
- **Delegate commits** — prepare a `git-commit-review` handoff after verification; this skill does not own commit strategy or commit creation.

---

## Final Rules (Anchor)

1. Follow the approved task order, respect dependencies, and keep `tasks.md` status current.
2. Write tests alongside code and verify each phase before continuing.
3. After verification, hand off commit review and commit creation to `git-commit-review`.
> If anything above conflicts with these, **these win**.
