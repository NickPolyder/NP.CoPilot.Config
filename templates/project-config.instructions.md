# Project Configuration

This file tells Copilot agents and skills about your project's technology choices.
Place it at `.github/instructions/project-config.instructions.md` so Copilot loads it automatically.

## Technology Stack

- **Framework:** [Angular | Blazor | React | None]
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

## Agent Guidance

When agents encounter technology choices in this file, they should:

- Skip guidance for technologies not listed (e.g., skip Angular advice if Framework is Blazor).
- Prioritize patterns consistent with the listed stack.
- Use the build/test commands listed above instead of guessing.
