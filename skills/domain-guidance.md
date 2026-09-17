# Domain Guidance

On-demand reference, not a skill or agent. Resolve this file from the verified
configuration source (it travels with the linked `skills` directory). The caller
includes only applicable sections in a bounded assignment. Missing notes are an
explicit input gap, not permission to claim a domain review occurred.

Select by work: `investigator` for analysis, `implementer` for authorized changes,
`code-reviewer` for independent assessment. Naming several domains does not
require several agents. Preserve separate scopes when required reviews or
independently shippable outcomes justify them.

## Architecture and requirements

Start from actual users, observable acceptance criteria, existing boundaries
and constraints. Distinguish what/why from implementation choices. Make
assumptions and out-of-scope work explicit. Prefer incremental options with
concrete file/contract evidence; do not prescribe DDD, CQRS, repositories,
MediatR, microservices or a rewrite by default. Completion depends on the story's
declared capabilities, not a universal staging-deployment requirement.

## Backend and .NET

Follow the repository's supported .NET version, API conventions and error model;
do not upgrade the framework to satisfy generic guidance. Preserve authorization,
cancellation and failure propagation through changed call chains. Inject time
where clock behavior needs deterministic tests. For EF queries, inspect actual
SQL/plans and project only required data; choose tracking, splitting or compiled
queries from the workload rather than a checklist. Keep transport/domain
boundaries where the project declares them.

## Data and migrations

Enforce required integrity with database constraints and parameterized queries.
Review generated migration SQL, transaction/locking behavior, backfills,
compatibility and an authorized recovery strategy before destructive actions.
Measure query changes with plans and representative data.

Pagination needs a unique total order and matching cursor predicate. For
ascending `(CreatedAt, Id)`, the continuation is `CreatedAt > lastTime OR
(CreatedAt = lastTime AND Id > lastId)` with the same ordering. Reverse both
comparisons for descending order. Concurrent data changes need an explicit
consistency policy; deterministic ordering alone does not create a snapshot.

## Frontend and UX

Follow the existing Angular, Blazor, React or other stack. Preserve actual user
flows, keyboard access, semantic controls and loading/error/empty/success states.
Verify the operation behind feedback, not merely that a success toast appears.
Use observed requirements or user evidence rather than invented personas.

Blazor Interactive Auto chooses a render mode for an instance; an existing
server-rendered interactive component does not migrate to WebAssembly after
download. Later visits can use cached WebAssembly assets. For a coupled UI/API
change, own and verify the contract on both sides; otherwise keep scopes separate.

## Node and Python

Preserve established runtimes, package managers and lockfiles. Validate external
inputs at public boundaries; do not trust model-supplied MCP arguments. Keep
server secrets out of browser bundles and public environment-variable prefixes.
Do not duplicate capabilities owned by an existing service simply because a
dashboard or script uses another language. For async Python, avoid blocking the
event loop and preserve cancellation/resource cleanup.

## Integration and concurrency

Identify contracts, side effects and failure boundaries. External calls need
bounded timeouts; retries need an idempotency/reconciliation story. Verify
deduplication, ordering, partial failure and recovery with the intended delivery
semantics. Use outbox or broker patterns when the required guarantee warrants
them, not automatically. Keep application/service observability distinct from
deployment infrastructure and do not claim readiness from startup alone.

## Infrastructure and deployment

Treat target identity, command/argument transport, private configuration,
publication and recovery as separate concerns. Preserve environment/key
lifecycle and co-located services. Preview must not mutate targets or claim
readiness. A deployment is not transactional or rollback-capable unless that
behavior is actually implemented and verified. Live actions require the
repository's authorization and target-specific evidence.

## Service Fabric

Use supported service resolution and cancellation; keep external I/O outside
Reliable Collection transactions. Reliable Actors are not a license to assume
cross-actor atomicity. Use monitored rolling upgrades with meaningful health
policies. Partition rules depend on scheme: supported named-partition scaling
differs from fixed uniform ranges. Removing stateful partitions can lose data;
the platform does not automatically redistribute application state. Plan and
authorize any migration or scale-in explicitly.

## Security

Trace assets, trust boundaries, authorization and abuse cases on reachable
paths. Prefer established cryptography and least privilege. Separate secure
secret storage from approved runtime delivery: vault retrieval and approved
environment injection can both be valid under project policy. Never hardcode,
log or expose secrets to clients. Report unsupported assumptions and actual
impact rather than severity from a keyword alone.

## Tests

Choose cases from changed behavior and risk using the existing runner. Use
deterministic inputs, real public APIs and assertions about observable results;
derive signatures from supplied code rather than inventing them. Do not mock
the system under test. Make a plan only when complexity or the active workflow
requires one. A test-only implementer may edit tests/fixtures, not production
code; return production defects as blockers. Strategy is read-only analysis;
integration/E2E test implementation is an authorized writing task, not a QA
role implicitly acquiring production ownership.

## Writing

Identify audience and purpose; ground claims and examples in verified behavior.
Reuse existing implementation evidence rather than requiring another accuracy
handoff for a small edit. Technical documentation follows `documentation`;
emails, posts and articles use `communication-writing` when requested. Preserve
important qualifications, not generic prose or invented operational guarantees.
