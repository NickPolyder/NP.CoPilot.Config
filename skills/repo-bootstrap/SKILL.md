---
name: repo-bootstrap
description: >
  Bootstraps a repository for effective agent-driven work by generating a
  tailored agent operating manual (.github/copilot-instructions.md) plus a
  durable docs/ working-memory skeleton (PLAN, TASKS, decisions, features,
  handoffs, reviews, retrospectives). Interviews the user, analyzes the repo,
  and produces tailored content behind an approval gate.
tags:
  - bootstrap
  - onboarding
  - instructions
  - documentation
  - agent-config
  - scaffolding
visibility: user
tools:
  [agent, edit/createFile, edit/editFiles, todo]
---

# Purpose

> **Intent (anchor):** Bootstrap one repository with a tailored Copilot agent contract and durable docs working-memory skeleton.
> **Always:** analyze the repo before interviewing; tailor templates with verified commands; get approval before writing or overwriting files.
> **Never:** copy raw templates verbatim or commit generated files.

> **Shared policy:** Follow `instructions/coordination.instructions.md` for precedence, invocation, delegation, and handoffs. Apply `instructions/workflow.instructions.md` for proportional work and verification.

You are bootstrapping a repository so that any Copilot agent working in it has a
**clear contract** and a **durable, file-based working memory** — the same
structure that makes agent-driven repos effective:

- A tight **`.github/copilot-instructions.md`** contract: repository mission,
  agent role, hard rules, verified commands, delivery capabilities, and
  handover conventions.
- A **`docs/` memory tree** the agent reads before working and updates as it
  goes: `PLAN.md` (canonical design), `TASKS.md` (phased execution), plus
  `decisions/`, `features/`, `handoffs/`, `reviews/`, `retrospectives/`.

This is **bootstrap only**: it seeds the agent/docs configuration baseline. It
does not maintain docs, write detailed ADR/feature/retrospective content, or
implement application code.

Your goals:

- **Tailor, don't dump.** Interview the user and analyze the repo, then generate
  content specific to *this* repo — never copy raw templates verbatim.
- **Extend, don't contradict.** The repo-level config layers on top of the
  global `~/.copilot/` config. Reference global conventions; don't restate them.
- **Be safe and idempotent.** Never overwrite existing files without explicit
  approval. Augment a partial structure instead of clobbering it.

---

# When to use this skill

Use this skill whenever:

- A repo has no `.github/copilot-instructions.md` and/or no `docs/` working
  structure, and the user wants agents to work in it effectively.
- The user asks to "bootstrap", "onboard this repo for Copilot", "set up the
  agent operating manual", or "give this repo the AgentMemory structure".
- An existing repo's instructions/docs are ad-hoc and need a consistent baseline.

Do **not** use this skill for:

- Generating application code or boilerplate — use `scaffold`.
- Maintaining existing docs as code changes — use `documentation`.
- Planning/implementing a single feature — use `feature-planning` / `prd-workflow`.

> **Boundary:** This skill seeds repository configuration only. For detailed ADRs,
> feature plans, or retrospectives, recommend the relevant workflow rather than
> producing those artifacts.

---

# Source templates

Templates live in this config repo at `templates/repo-bootstrap/`. They use
`{{PLACEHOLDER}}` tokens you fill from the interview + analysis. Mapping from
source → target (in the user's repo):

| Source template | Target path |
|---|---|
| `copilot-instructions.template.md` | `.github/copilot-instructions.md` |
| `docs/PLAN.md` | `docs/PLAN.md` |
| `docs/TASKS.md` | `docs/TASKS.md` |
| `docs/decisions/0000-template.md` | `docs/decisions/0000-template.md` |
| `docs/decisions/README.md` | `docs/decisions/README.md` |
| `docs/features/README.md` | `docs/features/README.md` |
| `docs/handoffs/README.md` | `docs/handoffs/README.md` |
| `docs/reviews/README.md` | `docs/reviews/README.md` |
| `docs/retrospectives/README.md` | `docs/retrospectives/README.md` |

---

# How it works

## Phase 1: Analyze the repo

Before asking anything, gather what the repo already tells you. Run these (or
the equivalents) from the repo root and read the results:

- **Is it a git repo, and what's the root?** `git rev-parse --show-toplevel`.
- **What already exists?** Check for `.github/copilot-instructions.md`,
  `.github/instructions/`, `docs/`, `README.md`, `CONTRIBUTING.md`.
- **Tech stack & build:** detect manifests — `*.sln`/`*.csproj` (.NET),
  `package.json` (Node), `pyproject.toml`/`requirements.txt` (Python),
  `go.mod`, `Cargo.toml`, etc. Read scripts/targets to infer real build/test/
  lint commands.
- **Conventions:** skim a few source files for naming, layout, and test
  locations. Note CI config (`.github/workflows/`, `azure-pipelines.yml`).
- **Project-config:** if `.github/instructions/project-config.instructions.md`
  is missing, note that `install-project.ps1` (in this config repo) can drop it.

Summarize findings concisely. Carry verified build/test/lint commands into the
contract — never guess them.

## Phase 2: Interview

Ask only what you couldn't reliably infer. Prefer multiple-choice, one question
at a time. Cover:

1. **Repository mission** — what outcome, users, and non-negotiable constraints define this repository?
2. **Agent role & primary objective** — what is the agent here *for*? (e.g.
   "implementing agent delivering per PLAN/TASKS", "maintenance agent", "library
   author").
3. **Hard rules (4–8)** — the non-negotiable constraints unique to this repo.
   Seed suggestions from analysis (e.g. "runtime data lives outside X", "never
   touch generated folder Y").
4. **Don'ts** — the mistakes most likely to happen here.
5. **Build/test/lint commands** — confirm the detected commands (or correct
   them).
6. **Delivery capabilities** — confirm issue tracking, isolated worktrees,
   remote delivery, protected branches, integration queue, and deployment
   evidence from repository configuration and host rules; default unknown
   capabilities to disabled.
7. **Commit grouping & handover mechanism** — phase prefixes? where do session
   handovers go?
8. **PLAN seed** — the problem, the high-level approach, the major components.
9. **TASKS seed** — the first few phases and their dependencies.
10. **Decided-up-front items** — locked decisions to record so they aren't
   re-litigated.

## Phase 3: Confirm scope (approval gate)

Present the full plan and get explicit approval before writing anything:

```
### repo-bootstrap plan for {repo}

**Will create:**
- .github/copilot-instructions.md   (agent contract)
- docs/PLAN.md, docs/TASKS.md
- docs/decisions/{0000-template.md, README.md}
- docs/{features,handoffs,reviews,retrospectives}/README.md

**Already exists (will NOT overwrite without your OK):**
- {list any conflicts found}

**Tailored from:**
- Mission: {…}   Role: {…}   Hard rules: {…}   Build/test: {…}
- Delivery capabilities: {tracked work / worktrees / protected branches / CI evidence}

**Also recommended (run separately):**
- install-project.ps1 → .github/instructions/project-config (if missing)

Proceed? (yes / adjust / cancel)
```

If files already exist, ask per-file: overwrite, merge, or skip.

## Phase 4: Generate

For each target file: read the source template, replace every `{{PLACEHOLDER}}`
with tailored content, and create the file. Then:

- Ensure the `docs/` subfolders exist (creating a folder requires a file in it —
  the `README.md` seeds serve that purpose).
- Keep the contract **short and specific** — it's rules, not a manual. Push
  background and design detail into `docs/PLAN.md`.
- Make `PLAN.md`/`TASKS.md` real: use the interview answers, not the placeholder
  prose. An empty PLAN is worse than no PLAN.

## Phase 5: Verify & hand back

- Confirm every intended file exists and links resolve.
- Confirm nothing in the generated config contradicts the global instructions.
- Summarize what was created and the recommended next steps (e.g. "run
  `install-project.ps1` for project-config", "create your first ADR with the
  `architecture-decision-record` skill", "fill in the first feature doc").
- Do **not** commit. Let the user review, then commit per the repo's git
  conventions.

---

# Agent coordination

Consult specialists for content quality — they advise; this skill writes:

| Need | Consult agent |
|---|---|
| PLAN architecture, component boundaries, hard rules | `architect` |
| Problem framing, scope, decided-up-front items | `product-owner` |
| Build/test/lint accuracy for the detected stack | `backend-developer` / `frontend-developer` / `devops-engineer` |
| Security-relevant hard rules / Don'ts | `security-engineer` |

---

# Relationship to other scaffolding

- **`install-project.ps1`** (this config repo) drops `project-config` +
  `local-preferences` into `.github/instructions/` — tech-stack *facts*. This
  skill produces the agent *contract* + docs *memory*. They are complementary;
  recommend running the installer if project-config is missing.
- **ADRs / features / retros** are seeded as templates + indexes only. Detailed
  content belongs in separate runs of `architecture-decision-record`,
  `feature-planning` / `prd-workflow`, and `retrospective`; recommend those
  skills rather than embedding their workflows here.

---

# Constraints & rules

- **Never overwrite without explicit approval** — surface conflicts in the
  approval gate and ask per file.
- **Tailor every file** — no `{{PLACEHOLDER}}` token may survive into a
  generated file.
- **Extend, never contradict, the global config** — state the repository
  mission and capabilities, then reference `~/.copilot/instructions/` for
  global workflow, lifecycle, coordination, and delivery policy.
- **Keep the contract tight** — state repository facts and local exceptions,
  not duplicated global policy; design detail belongs in `PLAN.md`.
- **Verified commands only** — build/test/lint commands must come from the repo,
  not assumptions.
- **Don't commit** — leave the user to review and commit.

---

## Final Rules (Anchor)

1. Never overwrite without explicit approval — surface conflicts in the approval gate and ask per file.
2. Tailor every file — no `{{PLACEHOLDER}}` token may survive into a generated file.
3. Do not commit generated files; leave review and delivery to the repository's configured process.
> If anything above conflicts with these, **these win**.
