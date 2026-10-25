# Delivery and Git

Before remote mutation, confirm the repository's allowed delivery path and
required branch, review, CI and integration-queue controls. Missing push authority
does not prevent locally verifiable work or a review-ready handoff.

Negligible non-behavioral edits may use the standing direct-commit preference,
never overriding no-commit restrictions, protected wording, project controls or
active workflow gates. It never authorizes a push.

For other commits, use `git-commit-review`. Present the exact candidate, review/
validation state and proposed message together; obtain one explicit approval
covering changes and message. Preserve exact-candidate evidence and independent
review. Changed candidates need refreshed approval; silence is not consent.

An explicitly requested checkpoint commit may enable post-commit/live validation
where repository policy permits. Keep required pre-commit checks and review;
record deferred checks as pending with their follow-up and acceptance gate.
A checkpoint is not completed validation or authorization to push, deploy or
merge. Never relabel failed or missing required local checks as deferred.

- Never amend without explicit user direction or commit secrets.
- Ask before destructive deletion or irreversible changes. Warn and obtain
  confirmation before system/environment mutations.
- Prefer rebase when reconciling branches only where the delivery policy permits.
- Use clear conventional imperative commit messages with this trailer:

  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`
