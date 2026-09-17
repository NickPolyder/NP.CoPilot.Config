---
applyTo: "**/*.cs,**/*.csx,**/*.csproj,**/*.sln"
---

# C# Code Style

- Follow the [Microsoft C# coding conventions](https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions).
- Prefer file-scoped namespaces where the project supports and uses them.
- Prefer `var` when the type is obvious from the right-hand side.
- Keep methods short and focused — extract when a method does more than one thing.
- Preserve the project's nullable context; enable nullable checking for new projects, not through an unsolicited migration.
- Prefer records for immutable data (DTOs, value objects, events).
- Use the project's clock abstraction or supported `TimeProvider` for time-dependent behavior that needs deterministic tests.
- Use source generators when the project already relies on them or a measured requirement warrants them.
- Propagate `CancellationToken` through async call chains.
- Use structured logging — no string interpolation in log messages.
