---
name: retrospective
description: >
  Generates a structured retrospective after completing a feature, bug fix, or
  significant piece of work. Captures what was built, what went well, what to
  improve, and concrete follow-up actions.
tags:
  - retrospective
  - reflection
  - workflow
  - improvement
visibility: user
tools:
  [agent, edit/createFile]
---

# Purpose

You are conducting a retrospective on recently completed work.

Your goals are to:

- **Summarize what was built** — scope, artifacts, key decisions.
- **Capture what went well** — patterns, tools, or approaches worth repeating.
- **Identify what to improve** — friction points, mistakes, time sinks.
- **Propose follow-up actions** — concrete next steps, tech debt items, enhancement ideas.
- **Produce a durable artifact** that the team can reference.

---

# When to use this skill

Use this skill whenever:

- A feature, bug fix, or significant task has been completed.
- The user asks to "reflect", "retro", "wrap up", or "summarize what we did".
- After a sprint or milestone as a learning exercise.
- Step 8 (Reflect) of the Development Workflow is reached.

Do **not** use this skill for:

- Mid-work status updates — just report progress inline.
- Planning future work — use the feature-planning or prd-workflow skill instead.

---

# Workflow

## Step 1: Gather Context

Review the work that was done:

1. **Check recent commits** — `git log --oneline -20` to see what was committed.
2. **Read design/plan docs** — if `docs/features/{feature}/design.md` or `tasks.md` exist, review them.
3. **Check test results** — run tests to capture current state.
4. **Note time spent** — if tracking data is available, capture it.

## Step 2: Generate Retrospective

Create the retrospective document with these sections:

### What Was Built

- **Feature/scope:** {brief description}
- **Key artifacts:** {files created/modified, docs produced}
- **Decisions made:** {major technical choices and why}
- **Test coverage:** {tests added, pass/fail summary}

### What Went Well

List 3-5 things that worked effectively. Be specific — not "good teamwork" but "the PRD workflow caught a missing edge case in the data model before implementation."

### What To Improve

List 3-5 concrete friction points. Focus on:

- Time sinks (what took longer than expected and why).
- Mistakes (what went wrong and how to prevent recurrence).
- Process gaps (what was missing from the workflow).
- Tool issues (what tooling slowed us down).

### Follow-Up Actions

List concrete, actionable items:

| Action | Priority | Type |
|--------|----------|------|
| {description} | High/Medium/Low | Enhancement / Tech Debt / Bug / Process |

### Metrics (if available)

- Tasks planned vs completed.
- Tests: total, passed, failed, coverage %.
- Commits: count, average size.

## Step 3: Store the Retrospective

Place the document based on context:

- **Feature work** — `docs/features/{feature}/retrospective.md`
- **Bug fix** — `docs/bugs/{bug}/retrospective.md`
- **General** — `docs/retrospectives/{date}-{topic}.md`

---

# Output Format

Present a concise summary to the user after generating the document:

```
### Retrospective: {Feature Name}

**Built:** {1-sentence summary}
**Went well:** {top 2 highlights}
**Improve:** {top 2 items}
**Follow-up:** {count} action items ({high} high priority)
**Saved to:** {file path}
```

---

# Coordination

- **Architect agent** — consult if architectural lessons emerged.
- **QA engineer agent** — consult if test strategy lessons emerged.
- **Product owner agent** — consult if requirement/scope lessons emerged.
