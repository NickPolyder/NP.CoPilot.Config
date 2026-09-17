# Delivery and Git

Before remote mutation, confirm the repository's allowed delivery path and
required branch, review, CI and integration-queue controls. Missing push authority
does not prevent locally verifiable work or a review-ready handoff.

For negligible non-behavioral edits such as typos, the standing preference allows
a direct commit without the two approval prompts below. It never overrides a
current no-commit restriction, project controls or an active workflow's gates,
and never authorizes a push.

For other commits, obtain user verification of the changes, then explicit
approval of the proposed commit message. Silence or unavailable approval tooling
is not consent. Use `git-commit-review` for these commits; retain its
exact-candidate evidence and independent-review gates.

- Never amend without explicit user direction or commit secrets.
- Ask before destructive deletion or irreversible changes. Warn and obtain
  confirmation before system/environment mutations.
- Prefer rebase when reconciling branches only where the delivery policy permits.
- Use clear conventional imperative commit messages with this trailer:

  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
