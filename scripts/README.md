# Local validation and snapshot contracts

These are repository-owned checks, not proof of Copilot runtime discovery, model
resolution, agent execution, human approval, or a deployed MCP service.

## Exact-candidate helper

`GitSnapshot.psm1` exports:

| API | Contract |
|---|---|
| `New-GitReviewCandidate -RepositoryRoot <root> [-IndexPath <absolute-path>] [-AllowEmpty]` | Capture the source index via a disposable copy. Return `Tree`, `State` (`Base`, `Head`, ordered `Parents`, `RefState`, `DestinationRef`, `MergeMode`), `ChangedPaths`, and binary `DiffBytes`. Reject empty candidates by default. An explicit missing/corrupt index is an error, not an empty index. |
| `New-GitTreeSnapshot -Candidate <candidate> [-Base]` | Return `Path`, `Tree`, `Role` (`candidate` or `base`), the tree `Manifest`, and a latched evidence state. Default to the captured candidate tree; `-Base` resolves the captured base's tree, never a moving ref. Materialize complete raw blobs, then check the exact path set, types, modes, and bytes plus the current candidate tuple. |
| `Assert-GitSnapshotIntegrity -Snapshot <snapshot> [-Exact]` | Check all tracked inputs. `-Exact` also rejects additional paths and is required at initial materialization. Later gates permit ordinary untracked build outputs, never links. Any observed failure permanently invalidates this snapshot's evidence. |
| `Invoke-GitSnapshotCheck -Snapshot <snapshot> -Name <label> -FilePath <executable> -ArgumentList <array> [-RequiredPaths <array>]` | Run one declared check in the candidate snapshot with an isolated child home/Git environment. Reject base context as a validation target. Required paths must be tracked snapshot inputs. Check identity before/after execution and native exit status. A missing command/input, failed command, or drift invalidates evidence. |
| `Assert-GitCandidateCurrent -Candidate <candidate>` | Pre-review/pre-acceptance/pre-commit guard for the tree **and** complete base/ordered-parent/ref/destination tuple. Does not approve or create a commit. |
| `Assert-GitCandidateCommit -Candidate <candidate> -CommitId <exact-id>` | Verify the resulting commit's tree, ordered parents, current HEAD, destination, and symbolic/detached state (including the intended unborn-to-born transition). Never amend or repair a mismatched result. |
| `Remove-GitReviewCandidate -Candidate <candidate>` | Remove only that candidate's registered temporary context. Call in `finally`. |

`skills\git-commit-review\SKILL.md` contains the executable entry example between
`tested-snapshot` markers. `Run-GitSnapshotProcedureTests.ps1` executes that example
and the same helper used by the hook; it is not a separately maintained archive
recipe. Wording checks remain wording checks.

The example prepares both candidate and base context using the same materializer.
The base manifest retains deleted/renamed old paths and is empty for an unborn
base. Both contexts belong to the candidate's owned cleanup scope. Keep base
context read-only and check it with `-Exact` before dispatch and acceptance.
Caller-prepared reviewer intake includes repository/scope, resolved identities,
the complete diff, readable contexts/manifests, locked requirements, and exact
validation commands/working directories/results. Missing required evidence is
`Incomplete - missing evidence`, not permission to review current files instead.
Read/search-only reviewers return findings to the active caller; they do not
execute validation or create artifacts.

**Supported inputs:** complete Git trees of regular files, UTF-8 path names that
the host filesystem can represent exactly, and SHA-1 or SHA-256 object IDs.
Raw blob bytes are copied without PowerShell text pipelines, `git archive`,
checkout/smudge filters, EOL conversion, or ident substitution. Export attributes
cannot omit or rewrite inputs. This is a raw-tree contract, not a promise that a
project requiring transformed checkout inputs can be tested without them.

Windows supports Git mode `100644` only: it cannot establish POSIX executable
mode fidelity. POSIX supports `100644` and `100755` with exact mode checks using
PowerShell 7.3+ filesystem APIs. Unrepresentable names, symbolic links, gitlinks
(submodules), and LFS pointer inputs fail closed rather than being silently
renamed, flattened, followed, downloaded, or counted as complete. Finish
rebase/cherry-pick/revert/sequencer operations before this workflow. Ordinary and
explicit merge-parent candidates are checked; post-commit parents must match in
order.
This helper models new commits, not an amend workflow. Even an explicitly
requested amend needs a separately defined approval/parent contract.

Every potentially writing command must have its own before/after gate. If a
command changes a tracked lockfile and tests pass on those changed bytes, restoring
the old file later cannot validate it retroactively. Stage the intended fix,
create a new candidate/snapshot, and rerun affected checks. Boundary checks do not
monitor transient writes hidden inside one process; do not combine mutation,
testing, and restoration to conceal such changes. These are workflow safeguards,
not a sandbox against hostile validation programs or an atomic commit lock.

Validation commands come from the **target repository's declared capabilities**.
NP.CoPilot.Config requires its snapshot-local `scripts\Validate-Config.ps1`.
Another project merely containing Copilot instructions does not. A declared
required command missing from a candidate is a failure, never a worktree fallback.
If no applicable suite exists, report `Not run - no applicable suite` and its
coverage limit, not a zero-test pass. This does not waive a declared required check.

An explicitly approved checkpoint can leave only eligible post-commit/live
checks pending; required local pre-commit checks still apply. Classify deferrals
before executing checks: the helper's latched failure is not a mechanism for
waiving failures. Validation evidence reuse is a caller policy, not an automatic
cache in `GitSnapshot.psm1`; it requires the same captured tuple, immutable inputs,
command/environment and freshness, with readable successful integrity evidence.
Worktree-only results do not satisfy it. Reuse never skips current integrity
gates or a repository requirement for a fresh check.

## Daily-work policy scenarios

`Validate-GitCommitReviewSkills.ps1` checks selected wording in the review
contracts, shared policy owners and affected atomic skills. `-SkillRoot` selects
the skill inputs; `-InstructionRoot` defaults to the sibling `instructions`
directory, including for isolated fixtures. Its isolated mutation
suite verifies that deleting these safeguards fails the validator; it does not
prove an agent obeys them. The snapshot procedure suite separately exercises
real Git/byte-integrity behavior. Use the following scenarios to assess actual
agent traces when the updated instructions are loaded:

| Scenario | Expected behavior |
|---|---|
| Clear small bug-fix request | Make in-scope edits and focused checks without another start/phase approval; no automatic commit. |
| Documentation-only commit | Keep requested review, run applicable documentation/configuration checks, and present candidate plus message in one confirmation. |
| Review suggests a change to approval-controlled prose | Show exact replacement wording; do not apply or stage it before approval. Declining optional polish does not block the commit. |
| Commit required to test live | With explicit authorization and permitted policy, retain local checks/review, record pending check/owner/trigger/acceptance gate, and bind follow-up to the commit SHA. Do not push or deploy without authorization. |
| Required local check fails or its command is missing | Block committing; do not relabel it as live validation or use a checkpoint to bypass it. Preserve independent authorized work. |
| An earlier committed revision failed live testing | Keep that failure visible. A changed fix may be checkpointed after local checks/review; its live retest remains pending, not resolved or passed. |
| Same candidate reaches another phase | Reuse successful evidence only when tuple, inputs, command/environment and freshness match; otherwise rerun affected checks. Approval must match the current tuple and message. |
| Unrelated staged/unstaged changes exist | Preserve them; isolate authorized hunks without reset or silent index rearrangement. |
| Standalone research/design/audit request | Return the requested result and stop. An explicitly requested coordinator owns its own next-phase approval, asked once. |
| Active workflow awaits live validation | The explicit checkpoint request supplies suspension direction without a duplicate prompt; release active ownership, keep pending tasks incomplete and resume afterward. |
| Routine clean review finishes | Save one compact outcome in the configured durable provider or required record, not duplicate reports. |

Missing trace evidence is **Not evaluated**, not a behavioral pass. Do not create
real commits, pushes, deployments or installation changes merely to exercise
these scenarios; use isolated fixtures and explicitly authorized evaluations.

## Isolated validation processes

`IsolatedProcess.psm1` supplies `New-IsolatedProcessContext`,
`Invoke-IsolatedProcess`, and `Remove-IsolatedProcessContext`. Child homes, app
configuration/cache/temp paths, Git global/system config and templates are owned
temporary paths. Inherited `GIT_*` controls are cleared; hooks, signing, fsmonitor,
replacement objects, global attributes, and interactive prompts are disabled.
Only explicitly supplied overrides (for example the disposable `GIT_INDEX_FILE`)
are applied afterward. Native stdout remains available as bytes; every nonzero
exit is an error unless the caller explicitly requests a result for inspection.
This process isolation does not prevent arbitrary commands from writing absolute
paths, contacting networks, or reading repository-local config.

## Configuration validator input domain

`Validate-Config.ps1` checks **on-disk installable definitions**, not a Git-tracked
inventory: all immediate `agents\*.md` files and `skills\<name>\SKILL.md` files,
including hidden, ignored, and untracked entries. Nested agent directories are
rejected, not silently skipped or recursively searched. Each immediate skill directory
must contain `SKILL.md`. It also reads `README.md`, `mcp-config.json`, and
`mcps\docker-compose.yml` for the named inventory/runtime checks. It does not scan
private `.copilot`/Git state, external plugins, instruction-file applicability,
or arbitrary skill assets. Ignored plugin-provided definitions inside the stated
domain are not silently excluded. Inside a hook snapshot, this same on-disk
contract naturally contains only captured tracked inputs.

`skills\domain-guidance.md` is a shared on-demand reference, not another skill
directory. The global word budget and domain-note semantics are not asserted
by this structural validator. The focused review-policy validator checks
separate, immutable, read-only domain assignments rather than requiring a
duplicated final-rule anchor.

The root, ancestors, definition directories/files, and other named inputs must
not be symbolic links, junctions, or other reparse points. Linked definitions, directory
collisions at file paths, or unsupported layouts fail closed **before** reading
linked contents. Use a physical source checkout rather than a linked installed
home. This is intentional containment, not a claim that Copilot cannot load links.

The dependency-free YAML validator supports a **strict repository subset**, not
full YAML: one block mapping, two-space indentation, nested block mappings and
scalar sequences, scalar-only flow sequences, plain/string-quoted scalars,
comments outside flow sequences, and `>`/`|` block strings with optional `-` chomping. Double-quoted
strings use JSON-compatible escapes; single quotes escape by doubling. Duplicate
keys (including quoted spellings), malformed collections, raw control characters, tabs, anchors,
aliases, tags, flow mappings, complex keys, and ambiguous plain scalars are
rejected. Frontmatter must be a closed block and use only the repository's named
fields. `name` and `description` must be nonempty strings; agents also require a
model string. Optional `tools` must be a nonempty string sequence and `license` a
nonempty string. Reviewer tool restrictions and the model allowlist are
**repository policy**, not a list of all CLI-supported models or metadata.

Runtime checks inspect parsed `mcpServers` local Docker/npx argument fields and
Compose `services.<name>.image`, not arbitrary `latest` text in notes. Supported
Docker/npx options are explicit; unknown launchers/options and dynamically
resolved runtime references fail closed. Image references require an explicit
three-part version tag (including numeric calendar versions) or a SHA-256 digest.
An explicit tag is **not** an immutability guarantee. npx packages require exact
semantic versions, not ranges or moving channels. The existing `playwright` npx
server's exact `@playwright/mcp@latest` reference retains its documented
user-approved warn/pass waiver. No other moving channel inherits it.

Compose uses the same strict YAML subset. Includes, extends, build-only services,
and external `env_file` resolution are not supported by these static pin checks.
Optional `docker compose config --no-interpolate --quiet` uses a byte-identical isolated Compose
copy, an empty environment file, and an isolated client home, never the private
deployment `.env`. It does not verify relative bind-mount existence or start or
contact a deployed service.
Required runtime variables, including the SearXNG secret, remain unresolved in
this structural check. Passing it does not establish secret readiness or permit
placeholder keys: actual deployment must independently reject missing or
placeholder secrets. The regression suite includes an unset synthetic required
variable and a malformed owned `.env`, plus a native interpolation-failure control.

## Opt-in Git hook and platform enablement

Run `pwsh -NoProfile -File .\scripts\Enable-ConfigGitHook.ps1` only when opting in.
It checks Git discovery, the regular launcher, and `pwsh`, sets and verifies local
`core.hooksPath`, and on POSIX runs checked `chmod +x -- <resolved-hook-path>` then
verifies owner execute permission. `-WhatIf` changes neither config nor mode.

The tracked launcher remains mode **100644** until an independently authorized
Git mode change is staged and committed. The setup script does not touch the
index; a fresh POSIX checkout therefore requires setup again. Preview may create
and remove isolated temporary probe state, but does not change checkout config or
mode. Actual POSIX Git
dispatch and executable snapshot cases need POSIX verification; Windows success
does not establish them.

The shell launcher, PowerShell driver, and helper are worktree-resident bootstrap
code. Only the validator and validation inputs are captured-tree-resident.
Deletions/type changes and both rename sides trigger the gate. Empty or unrelated
changes can skip only after successful, checked Git discovery. Native Copilot
lifecycle hooks remain deferred.
