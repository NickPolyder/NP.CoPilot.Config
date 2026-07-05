# Choosing a Model

_Last reviewed: 2026-07-05. The model list below is a point-in-time snapshot — availability changes over time, so treat the tiers as the durable guidance and re-check the exact ids._

This guide helps you pick the right AI model when you set the `model:` field on an
agent, or when you run a one-off task. It assumes you're comfortable with the repo
but are **not** a model expert. Read the [decision cheat-sheet](#decision-cheat-sheet)
first; read the rest when you want the reasoning.

## The one rule

**Match the model to the task, not to the role.**

Every model choice trades three things off against each other:

- **Reasoning depth** — how hard is the thinking? Novel design and threat analysis need more; boilerplate needs almost none.
- **Cost of a mistake** — a wrong schema migration is expensive and hard to reverse; a reworded paragraph is not.
- **Frequency and latency** — an agent that runs constantly should be cheaper and faster than one you invoke occasionally.

This mirrors the guidance in
[`coordination.instructions.md`](../instructions/coordination.instructions.md):
keep judgment work on strong models, push mechanical work to cheap ones, and keep
the orchestrator on a strong model while it delegates.

## Decision cheat-sheet

Pick the tier that matches the **work**, then pick the newest model in that tier.

| Work type | Examples | Use tier | Good picks |
|---|---|---|---|
| **Deep judgment** | Architecture review, security/threat modeling, data-model design, test strategy | Top-tier reasoning | `claude-opus-4.8`, `gpt-5.5` |
| **Craft / implementation** | Feature code, refactoring with judgment, editing, writing documentation | Mid-tier | `claude-sonnet-5` |
| **Code review (second opinion)** | Catching bugs, logic errors, pattern violations | Top-tier, different family | `gpt-5.5` |
| **Mechanical / high-volume** | Renames, boilerplate, simple extraction, straight formatting | Fast / cheap | `claude-haiku-4.5`, `gpt-5-mini`, `gemini-3.5-flash` |

When in doubt, go one tier up. Under-powering a judgment task fails silently; over-powering a mechanical one only costs a little.

## Available models

Grouped by family and tier. The **effort** column lists the supported
[reasoning-effort](#reasoning-effort) settings — some models don't support the setting at all.

### Anthropic Claude

| Model id | Name | Tier | Effort settings |
|---|---|---|---|
| `claude-opus-4.8` | Claude Opus 4.8 | Top-tier judgment | low, medium, high, xhigh, max |
| `claude-opus-4.7` | Claude Opus 4.7 | Top-tier judgment | low, medium, high, xhigh, max |
| `claude-opus-4.6` | Claude Opus 4.6 | Top-tier judgment | low, medium, high, max |
| `claude-sonnet-5` | Claude Sonnet 5 | Mid-tier (flagship craft) | low, medium, high, xhigh, max |
| `claude-sonnet-4.6` | Claude Sonnet 4.6 | Mid-tier | low, medium, high, max |
| `claude-sonnet-4.5` | Claude Sonnet 4.5 | Mid-tier | not supported |
| `claude-haiku-4.5` | Claude Haiku 4.5 | Fast / cheap | not supported |

### OpenAI GPT

| Model id | Name | Tier | Effort settings |
|---|---|---|---|
| `gpt-5.5` | GPT-5.5 | Top-tier reasoning / review | low, medium, high, xhigh |
| `gpt-5.4` | GPT-5.4 | Top-tier reasoning | low, medium, high, xhigh |
| `gpt-5.3-codex` | GPT-5.3-Codex | Code-specialized | low, medium, high, xhigh |
| `gpt-5.4-mini` | GPT-5.4 mini | Fast / cheap | low, medium, high, xhigh |
| `gpt-5-mini` | GPT-5 mini | Fast / cheap | low, medium, high |

### Google Gemini

| Model id | Name | Tier | Effort settings |
|---|---|---|---|
| `gemini-3.1-pro-preview` | Gemini 3.1 Pro | Strong general | low, medium, high |
| `gemini-3.5-flash` | Gemini 3.5 Flash | Fast / cheap | low, medium, high |

A different **family** (Claude vs GPT vs Gemini) sometimes reasons differently about
the same problem. That's why code review runs on GPT while most authoring runs on
Claude — a second family is more likely to spot what the first missed.

## Worked example: how this repo assigns models

The specialist agents in [`agents/`](../agents) are a live application of the tiering.
Each agent's `model:` reflects its dominant work type.

| Model | Agents | Why |
|---|---|---|
| `claude-opus-4.8` | `architect`, `security-engineer`, `systems-engineer`, `database-engineer`, `service-fabric-engineer` | Deep judgment where mistakes are expensive — system design, threat models, schema and cluster decisions |
| `gpt-5.5` | `code-reviewer` | Review benefits from a strong, cross-family second opinion |
| `claude-sonnet-5` | `backend-developer`, `frontend-developer`, `fullstack-developer`, `node-developer`, `python-developer`, `devops-engineer`, `qa-engineer`, `test-engineer`, `product-owner`, `ux-engineer`, `technical-writer` | Craft and implementation — high-quality output without top-tier cost |

A few choices, spelled out:

- **`architect` → Opus** — dependency direction and boundary decisions are hard to reverse, so the expensive-mistake factor dominates.
- **`backend-developer` → Sonnet-5** — implementing a well-specified feature is craft, not novel reasoning; Sonnet delivers it at lower cost.
- **`code-reviewer` → GPT-5.5** — a different family reviewing Claude-authored code catches issues a same-family model tends to share the blind spot on.
- **`technical-writer` → Sonnet-5** — writing is craft and runs often; near-top prose quality without Opus overhead.

## Setting the model

### On an agent (persistent)

Custom-agent files support a `model:` field in their YAML frontmatter. If you omit it,
the agent inherits the session's default model.

```yaml
---
name: my-agent
description: What this agent does.
model: claude-sonnet-5
---
```

### For a one-off task (per-invocation)

You can override the model when delegating a single task, without changing any
frontmatter — useful when one document or one analysis needs more (or less) horsepower
than the agent's default. Prefer the **newest** model within a tier unless you have a
specific reason not to (for example, `claude-sonnet-5` over `claude-sonnet-4.6`).

## Reasoning effort

Some models accept a **reasoning-effort** setting (see the effort column above). Higher
effort makes the model think more deliberately — better on hard problems, but slower and
costlier.

- Use **higher** effort (`high`, `xhigh`, `max`) for genuinely hard judgment: thorny
  architecture trade-offs, subtle security analysis, tricky debugging.
- Use **lower** effort (`low`, `medium`) for routine work, where extra deliberation adds
  cost without changing the answer.
- Models marked _not supported_ (for example `claude-sonnet-4.5`, `claude-haiku-4.5`)
  ignore the setting entirely.

## Related

- [`coordination.instructions.md`](../instructions/coordination.instructions.md) — model-fit rule and delegation discipline.
- [Agent definitions](../agents) — each agent's `model:` choice in context.
- [Agent coordination protocol](./agent-coordination.md) — how agents hand work to one another.
