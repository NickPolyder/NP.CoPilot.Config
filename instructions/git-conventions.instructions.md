# Git Conventions

## Commit Workflow

Always follow this order:

1. Complete the Development Workflow (appropriate tier steps).
2. When the work is done, ask me to verify the changes before committing. *(Trivial tier: skip this — commit directly.)*
3. After I confirm, use `ask_user` to present the proposed commit message for my approval.
4. Only then create the commit.

## Rules

- **Never** amend commits unless I explicitly ask (use `ask_user` to confirm).
- Prefer `git pull --rebase` over merge.
- Write clear, conventional commit messages in imperative mood.
- Always include the trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

## Safety Rails

- Always run tests after making changes to verify nothing is broken.
- Ask before deleting files or making irreversible changes.
- Never commit secrets, credentials, or sensitive data.
- Commands that modify the system or environment should be prefixed with a warning and require confirmation before execution.
