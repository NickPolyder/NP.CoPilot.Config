---
applyTo: "**"
---

# Project Configuration

This file tells Copilot agents and skills about your project's technology choices.
Place it at `.github/instructions/project-config.instructions.md`. The scalar
`applyTo` uses the documented repository-wide instruction syntax; discovery still
depends on the client's supported instruction locations and active session.

## Technology Stack

- **Framework:** [Angular | Blazor | React | None]
- **Blazor Render Mode:** [Static SSR | Interactive Server | Interactive WebAssembly | Auto | N/A]
- **Backend:** [ASP.NET Core | Node.js | None]
- **Database:** [SQL Server | PostgreSQL | SQLite | CosmosDB | None]
- **ORM:** [Entity Framework Core | Dapper | None]
- **Infrastructure:** [Kubernetes | Service Fabric | App Service | None]
- **CI/CD:** [GitHub Actions | Azure DevOps | None]
- **Messaging:** [Azure Service Bus | RabbitMQ | None]
- **Cloud:** [Azure | AWS | None]

## Build & Test Commands

```
restore:  dotnet restore
build:    dotnet build --no-restore
test:     dotnet test --no-build
lint:     dotnet format --verify-no-changes
```

## Project Conventions

- **Solution file:** [path to .sln]
- **Source root:** src/
- **Test root:** tests/
- **Docs root:** docs/

## Feature Toggles

- **ADO Integration:** OFF
- **Memory Bank:** OFF

## Agent Delivery Capabilities

<!-- np-copilot-capabilities-owner: .github/instructions/project-config.instructions.md -->

This is the single capability declaration. Other project contracts reference it
rather than repeat defaults. If the root project contract already owns verified
capabilities, keep that owner and replace this section with a reference to it.
Declare only capabilities that repository evidence supports. Disabled or blank capabilities add no workflow requirement.

| Capability | Enabled | Repository-specific rule |
|---|---:|---|
| Issue tracking | No | |
| Isolated worktrees | No | |
| Remote delivery | No | |
| Protected branches | No | |
| Integration queue | No | |
| Deployment evidence | No | |

## Agent Guidance

When agents encounter technology choices in this file, they should:

- Skip guidance for technologies not listed (e.g., skip Angular advice if Framework is Blazor).
- Prioritize patterns consistent with the listed stack.
- Use the build/test commands listed above instead of guessing.
