# Git Conventions

> **Intent (anchor):** Define the global delivery and commit-safety contract. The `git-commit-review` skill implements detailed exact-revision pre-commit review.
> **Always:** complete the applicable workflow, follow the configured delivery path, and get required user verification before non-trivial commits.
> **Never:** amend history, bypass protected-branch controls, or commit secrets without explicit user direction and safety checks.
> **Precedence:** Global (`~/.copilot/`) < Project (`.github/…`) < Local (gitignored). Project may extend but must not contradict Global. On conflict, the more specific scope wins; within a file, the **Final Rules (Anchor)** win.

## Delivery Path

Before any remote mutation, confirm the repository's allowed delivery path from project configuration and repository evidence.
This may be a protected pull request, merge queue, direct push, or explicit human handoff.
Missing direct-push authority is not a reason to bypass controls or abandon locally verifiable work.

Follow configured branch protection, required checks, code-owner review, and integration-queue requirements.
The work lifecycle policy owns candidate-revision evidence and outcome verification.

## Commit Workflow

Always follow this order:

1. Complete the Development Workflow (appropriate tier steps).
2. When the work is done, ask me to verify the changes before committing. *(Trivial tier: skip this — commit directly.)*
3. After I confirm, use `ask_user` to present the proposed commit message for my approval.
4. Only then create the commit.

## Rules

- **Never** amend commits unless I explicitly ask (use `ask_user` to confirm).
- Prefer `git pull --rebase` over merge when reconciling a local branch is appropriate for the configured delivery path.
- Write clear, conventional commit messages in imperative mood.
- Always include the trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

## Safety Rails

- Always run tests after making changes to verify nothing is broken.
- Ask before deleting files or making irreversible changes.
- Never commit secrets, credentials, or sensitive data.
- Commands that modify the system or environment should be prefixed with a warning and require confirmation before execution.

## Final Rules (Anchor)

1. Never amend commits unless the user explicitly asks.
2. Follow the repository's configured protected-branch and remote-delivery controls; never assume direct write access to `main`.
3. Do not create a non-trivial commit until the user has verified changes and approved the commit message.
4. Always include `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` in commit messages.
> If anything above conflicts with these, **these win**.
