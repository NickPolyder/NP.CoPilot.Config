# Agent Coordination Reference

[Coordination policy](../instructions/coordination.instructions.md) owns
precedence, delegation and legal composition. This reference explains the
three-role design without introducing another protocol.

| Activity | Role | Boundary |
|---|---|---|
| Research, diagnosis, requirements or design | `investigator` | Read/search/web; no commands or edits |
| Approved code, tests, configuration or writing | `implementer` | Assignment-scoped changes and applicable verification |
| Independent assessment | `code-reviewer` | Read/search only; immutable intake; no artifacts |

Ordinary work remains inline. A role is not a mandatory handoff, and a long list
of affected technologies does not require an agent per technology. The caller
supplies only the relevant [domain notes](../skills/domain-guidance.md).
Test-only implementation still cannot edit production code.

Required independent reviews remain independent: commit review keeps one core
reviewer and its bounded, signal-driven domain assignments. Explicit exhaustive
review keeps three separately assigned hats and up to three domain specialists.
These are distinct assignments of the reviewer role, not retired dispatch names.
The workflow owns immutable inputs, executed checks, consolidation and reports.
Missing evidence is not a clean review.

Only documented workflow-to-atomic-phase composition is allowed. Terminal agents
return needs to their caller instead of invoking skills or creating sideways
agent chains. A phase completing does not end its parent; a separate workflow
handoff waits for the owning workflow to finish or be explicitly aborted.

[Lifecycle](../instructions/work-lifecycle.instructions.md) owns delivery
capabilities and revision-bound evidence. [Session policy](../instructions/session-awareness.instructions.md)
preserves existing continuity ownership without taking over the external memory
plugin. The three cards preserve the established judgment, implementation and
review model families; disk defaults are not proof of runtime resolution.
