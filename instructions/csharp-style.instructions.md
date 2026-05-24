---
applyTo:
  - "**/*.cs"
  - "**/*.csx"
  - "**/*.csproj"
  - "**/*.sln"
---

# C# Code Style

- Follow the [Microsoft C# coding conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions).
- Use file-scoped namespaces.
- Prefer `var` when the type is obvious from the right-hand side.
- Keep methods short and focused — extract when a method does more than one thing.
- Nullable reference types should be enabled project-wide.
- Prefer records for immutable data (DTOs, value objects, events).
- Use `TimeProvider` instead of `DateTime.Now` / `DateTimeOffset.Now` for testability.
- Use source generators where applicable (JSON serialization, logging, regex).
- Propagate `CancellationToken` through async call chains.
- Use structured logging — no string interpolation in log messages.
