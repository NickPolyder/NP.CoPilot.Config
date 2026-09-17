# Choosing a Model

Match an authorized model choice to reasoning difficulty, cost of a mistake and
task frequency. Do not change assigned defaults or approved overrides merely
because another model is newer, cheaper or from a different family.

## Configured defaults

| Role | Requested model | Reason |
|---|---|---|
| `investigator` | `claude-opus-4.8` | Preserve the judgment-oriented default for substantial investigation/design |
| `implementer` | `claude-sonnet-5` | Preserve the implementation/craft default |
| `code-reviewer` | `gpt-5.5` | Preserve the independent-review default and read/search-only boundary |

The role reduction does not automatically make every investigation a top-tier
agent call. Handle small questions directly. A different model family can offer
a complementary perspective, but neither price nor diversity proves correctness.
Required expertise is selected by assignment, not by multiplying agent files.

## Explicit alternatives

For a user-authorized one-off choice, verify model availability and supported
effort settings against the active CLI/build. Use a cheaper model for bounded
mechanical work when approved; deeper reasoning fits consequential uncertainty.
Do not infer a request to change defaults from general cost guidance.

Agent frontmatter can request `model:`. This repository's validator accepts the
three configured IDs above as a local policy; that is not the CLI's complete
model catalogue. A proposed persistent change must update the relevant policy
and definition together, without silently changing other roles.

## Discovery and runtime evidence

Repository conflict policy does not determine CLI discovery, same-name agent
precedence, effective tool permissions or model resolution. Auto selection,
overrides, availability and fallback may affect a particular invocation.
Record requested and resolved models separately when exposed; otherwise say the
resolution is unverified. Symlink updates do not prove a running session reloaded.

`investigator` declares read/search/web. `code-reviewer` declares exactly
read/search. `implementer` retains the prior implementation agents' inherited
tool access so approved MCP capabilities remain usable; its instructions still
forbid child-agent/skill dispatch and unauthorized side effects. Repository
frontmatter/tool restrictions are not a claim about all supported CLI syntax.

Use the official [custom-agent configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
and [CLI reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
for build-specific capabilities, rather than maintaining a stale model catalogue
inside global instructions.
