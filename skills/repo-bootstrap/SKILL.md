---
name: repo-bootstrap
description: >
  Bootstraps a repository for effective agent-driven work by generating a
  tailored agent operating manual (.github/copilot-instructions.md) plus a
  durable docs/ working-memory skeleton (PLAN, TASKS, decisions, features,
  handoffs, reviews, retrospectives). Interviews the user, analyzes the repo,
  and produces tailored content behind an approval gate.
---

# Purpose

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
- **Preserve continuity ownership.** Existing project/cross-agent records and a
  configured session-memory provider coexist; a docs skeleton is not permission
  to generate duplicate per-session handover exports.

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

Before any target mutation, record two separate roots:

- **Target root:** the repository being bootstrapped.
- **Source root:** the verified NP.CoPilot.Config checkout containing the selected
  `skills\repo-bootstrap\SKILL.md` and sibling `templates\repo-bootstrap` assets.
  Resolve it from the selected skill's known installation/source location or an
  explicitly supplied checkout path, not the target's cwd or a guessed home.

Verify that each template needed for the approved outputs exists and is readable
under that source root before creating directories/files. The normal
whole-repository installation supplies these sibling assets. A skill-directory-only
copy is not self-contained and is unsupported unless a compatible source/asset
root is explicitly supplied and verified. Missing assets or unknown provenance
are a bootstrap blocker; do not substitute unrelated target templates, search
other Copilot homes, or silently manufacture replacement templates.

---

# How it works

## Phase 1: Analyze the repo

Before asking anything, gather what the repo already tells you. Run these (or
the equivalents) from the repo root and read the results:

- **Is it a git repo, and what's the root?** `git rev-parse --show-toplevel`.
- **What already exists?** Check for `.github/copilot-instructions.md`,
  `.github/instructions/`, `docs/`, `README.md`, `CONTRIBUTING.md`, and existing
  `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md` at the root and relevant scoped paths.
  Read their roles, scope, ownership, and references; they are existing project
  contracts, not disposable placeholders. Absence of a Copilot-named file does
  not mean there is no project contract.
- **Tech stack & build:** detect manifests — `*.sln`/`*.csproj` (.NET),
  `package.json` (Node), `pyproject.toml`/`requirements.txt` (Python),
  `go.mod`, `Cargo.toml`, etc. Read scripts/targets to infer real build/test/
  lint commands.
- **Conventions:** skim a few source files for naming, layout, and test
  locations. Note CI config (`.github/workflows/`, `azure-pipelines.yml`).
- **Project-config:** if `.github/instructions/project-config.instructions.md`
  declares capabilities, treat it as canonical and preserve its values and
  repository-specific rules. If only a root contract declares them, that remains
  the source until an approved migration/reference change. Note the source path
  and any conflicts before recommending `install-project.ps1`.

Summarize findings concisely. Carry repository-evidenced build/test/lint commands
and their working directories into the contract; distinguish inspected commands
from actually executed/passing checks. Never guess a runner or claim an unrun check.

### Capability Owner Protocol

Resolve capability ownership during discovery, before mutating any target
artifact. The generated Copilot contracts use one of these exact owner markers:

```html
<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->
<!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->
```

These are alternatives, not two markers to emit together. Each participating
capability section carries exactly one marker identifying the same selected
owner. **Only the owner contains the capability table**; a non-owner contains
that marker and a relative reference, never another table or disabled defaults.

- **Existing project-config declaration:** preserve its capability section,
  verified values, and repository-specific rules; update only as approved.
  Use the project-config owner marker there. Fill the root template's
  `{{DELIVERY_CAPABILITIES_SECTION}}` with the same marker and this reference
  (relative to the generated `.github/copilot-instructions.md`):

  ```markdown
  <!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->
  See [Agent Delivery Capabilities](instructions/project-config.instructions.md).
  ```

- **Otherwise, root-owned declaration:** preserve an existing verified root
  table, including a legacy table without a marker, or generate the approved
  verified declaration in `.github/copilot-instructions.md`. Fill
  `{{DELIVERY_CAPABILITIES_SECTION}}` with the root owner marker followed by that
  table. If project-config has a participating capability section, it contains
  only the following reference, relative to that file; do not create an otherwise
  unnecessary project-config file just for a pointer:

  ```markdown
  <!-- np-copilot-capabilities-owner: .github/copilot-instructions.md -->
  See [Delivery capabilities](../copilot-instructions.md).
  ```

Conflicting explicit owners, duplicate/malformed markers, a table in a marked
non-owner, an existing reference to a missing owner file/declaration, or
unresolved contradictory declarations are preflight conflicts: stop before
mutation and identify the affected paths. Do not manufacture default values to
repair a dangling reference, reset verified values, or silently choose a
different marker to hide the conflict. Marker additions and approved
legacy-table reconciliation must appear in the write plan.

Keep discovered `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` contracts intact.
If they own capability facts not yet represented by this two-path marker
protocol, resolve an explicit preservation/reference or migration plan before
generation; do not invent a third owner marker or override those facts with
defaults.

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
    evidence from existing declarations and host rules. Preserve declared values;
    use disabled/unknown defaults only for genuinely undeclared optional
    capabilities, never to reset an existing enabled rule.
7. **Commit grouping & continuity mechanism** — phase prefixes? Which existing
    project/cross-agent artifacts must stay current, and which provider owns
    per-session persistence? Do not assume Markdown session exports are needed.
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
- {existing Copilot/AGENTS/CLAUDE/GEMINI contracts, plans, and other conflicts}

**Source/target roots:** {verified config source and target repository}
**Capability owner:** {selected marker; sole table path; preserved values; all marker/reference/migration edits}
**Continuity:** {existing records to maintain; provider; explicitly requested new artifacts}

**Tailored from:**
- Mission: {…}   Role: {…}   Hard rules: {…}   Build/test: {…}
- Delivery capabilities: {tracked work / worktrees / protected branches / CI evidence}

**Also recommended (run separately):**
- install-project.ps1 → .github/instructions/project-config (if missing)
  preserving/referencing existing capability declarations, not defaulting them off

Proceed? (yes / adjust / cancel)
```

If files already exist, ask per-file: overwrite, merge, or skip.

## Phase 4: Generate

For each approved target file: read its verified source template, replace every
`{{PLACEHOLDER}}` with tailored content, and create or apply the approved merge.
Skip unapproved existing files. Then:

- Ensure the `docs/` subfolders exist (creating a folder requires a file in it —
  the `README.md` seeds serve that purpose).
- Keep the contract **short and specific** — it's rules, not a manual. Push
  background and design detail into `docs/PLAN.md`.
- Make `PLAN.md`/`TASKS.md` real: use the interview answers, not the placeholder
  prose. An empty PLAN is worse than no PLAN.
- Fill `{{DELIVERY_CAPABILITIES_SECTION}}` using the capability owner protocol
  above: a marker plus reference for a non-owner, or the selected owner marker
  plus its preserved/approved verified table. Apply approved marker/reference
  edits consistently; never emit both owner markers or a second table.
- Reuse existing plan/task/handoff locations instead of creating competing
  records. Maintain their truthful state under `session-awareness.instructions.md`.
  An approved handoffs index can describe project coordination, but does not
  require unsolicited per-session Markdown exports or replacement of plugin
  persistence. Do not vendor or modify an external continuity provider.

## Phase 5: Verify & hand back

- Confirm every intended file exists and links resolve.
- Confirm nothing in the generated config contradicts the global instructions.
- Confirm discovered project contracts remain intact, links name the actual
  capability owner, and no conflicting default-disabled declaration was added.
- Confirm each participating capability section has one matching owner marker,
  only the selected owner contains the table, and references resolve relative
  to their generated files. Compare capability values/rules with the approved
  source declaration; a correct marker alone does not prove preservation.
- Confirm existing continuity requirements remain usable without duplicate
  session exports; missing provider tools are reported, not assumed available.
- Summarize what was created and the recommended next steps (e.g. "run
  `install-project.ps1` for project-config", "create your first ADR with the
  `architecture-decision-record` skill", "fill in the first feature doc").
- Do **not** commit. Let the user review, then commit per the repo's git
  conventions.

---

# Agent coordination

Use repository evidence directly. A substantial unresolved question about
boundaries, scope, the detected stack or security can go to `investigator` with
only relevant domain notes. The caller supplies command evidence; this skill
retains file ownership and all source/target approval gates.

---

# Relationship to other scaffolding

- **`install-project.ps1`** (this config repo) drops `project-config` +
  `local-preferences` into `.github/instructions/` — tech-stack *facts*. This
  skill produces the agent *contract* + docs *memory*. They are complementary;
  when recommending installation, require preservation/reference or coordinated
  migration of any existing root capability declaration. Bootstrap and template
  installation must not create competing default-disabled capability values.
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
