# Agent Coordination Reference

`instructions/coordination.instructions.md` is the canonical policy for configuration precedence, invocation hierarchy, delegation, and handoffs.

Use it when authoring or changing agents and skills.
This document intentionally contains no competing protocol.

## Policy Corrections (2026-09-15)

The canonical policy now makes specialist delegation terminal: additional-domain
needs return to the orchestrator instead of spawning sideways agent chains.
Small regression tests and evidence-backed documentation edits stay inline;
substantial test or writing work still belongs to the appropriate specialist.
Required independent-review gates are unchanged.

Agent guidance now verifies the promised outcome rather than requiring every
UI action to persist data, and assigns completeness findings by demonstrated
impact rather than TODO/stub markers.
Tests may use multiple assertions for one behavior.
Database guidance diagnoses blocking instead of prescribing `NOLOCK`, and
Node/Python guidance respects established repository ownership instead of
assuming domain work must move to .NET.

The trivial auto-commit preference is unchanged.
These corrections do not introduce new hooks, agents, or a metadata framework.
