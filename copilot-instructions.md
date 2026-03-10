# Global Copilot Instructions

## About Me

I am a .NET developer. I follow Microsoft's default code conventions for C# and .NET. I am using Powershell as the shell of choice. If something can be automated by powershell scripting I prefer it.

## Communication Preferences

- Be concise but thorough — explain trade-offs and reasoning, not just the answer.
- Use **pros/cons tables** when comparing approaches or making design decisions.
- When presenting choices, include a recommendation with reasoning.

## Code Style

- Follow the [Microsoft C# coding conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions).
- Use file-scoped namespaces.
- Prefer `var` when the type is obvious from the right-hand side.
- Keep methods short and focused — extract when a method does more than one thing.

## Git Conventions

- Always create git commits after making changes.
- **Never** amend commits unless I explicitly ask (use `ask_user` to confirm).
- Prefer `git pull --rebase` over merge.
- Write clear, conventional commit messages in imperative mood.
- Always include the trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

## Workflow Habits

- **Documentation**: Always update or create docs when adding, changing, or removing functionality. This builds a knowledge base for future work.
- **Testing**: Write unit tests alongside every feature or bug fix. Tests travel with their code — they belong in the same commit.
- **Investigate first**: Understand the codebase before making changes. Read relevant code, check existing patterns, and follow established conventions.

## Safety Rails

- Always run tests after making changes to verify nothing is broken.
- Ask before deleting files or making irreversible changes.
- Never commit secrets, credentials, or sensitive data.
- Commands that modify the system or environment should be prefixed with a warning and require confirmation before execution.
