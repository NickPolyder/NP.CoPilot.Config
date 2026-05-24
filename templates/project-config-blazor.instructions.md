# Project Configuration — Blazor + .NET

This file tells Copilot agents and skills about your project's technology choices.
Place it at `.github/instructions/project-config.instructions.md` so Copilot loads it automatically.

## Technology Stack

- **Frontend Framework:** Blazor
- **Blazor Render Mode:** [Static SSR | Interactive Server | Interactive WebAssembly | Auto]
- **UI Library:** [MudBlazor | Radzen | Fluent UI Blazor | Custom]
- **State Management:** [Fluxor | Cascading values | Scoped services | None]
- **Backend:** ASP.NET Core (latest)
- **Database:** [SQL Server | PostgreSQL | SQLite | CosmosDB]
- **ORM:** Entity Framework Core
- **Infrastructure:** [Kubernetes | App Service | Service Fabric | Docker Compose]
- **CI/CD:** [GitHub Actions | Azure DevOps]
- **Messaging:** [Azure Service Bus | RabbitMQ | None]
- **Cloud:** [Azure | AWS | None]
- **Auth:** [Azure AD / Entra ID | IdentityServer | Auth0 | ASP.NET Core Identity]

## Build & Test Commands

```
restore:       dotnet restore
build:         dotnet build --no-restore
test:          dotnet test --no-build
test-single:   dotnet test --no-build --filter "FullyQualifiedName~{TestClassName.MethodName}"
lint:          dotnet format --verify-no-changes
watch:         dotnet watch run --project src/{BlazorProject}
```

## Project Conventions

- **Solution file:** [path to .sln]
- **Source root:** src/
- **Test root:** tests/
- **Docs root:** docs/
- **Shared components:** [src/Components/ | src/Shared/]

## Blazor Conventions

- **Render mode scope:** [Per-page | Per-component | Global]
- **Component organization:** [By feature folder | By type (Pages, Components, Layouts)]
- **State persistence:** [PersistentComponentState | LocalStorage | Server-side session]
- **JS Interop:** [Minimal — avoid if possible | IJSRuntime for specific features]
- **Forms:** [EditForm + DataAnnotations | EditForm + FluentValidation | Custom]
- **Error boundaries:** [Per-page ErrorBoundary | Global error handling]
- **Streaming rendering:** [Enabled for data-heavy pages | Disabled]

## API Conventions

- **Internal communication:** [Direct service injection (Server) | HttpClient (WASM) | Both (Auto)]
- **Error format:** Problem Details (RFC 9457)
- **Auth flow:** [Cookie-based (Server) | Token-based (WASM) | BFF pattern (Auto)]

## Feature Toggles

- **ADO Integration:** OFF
- **Memory Bank:** OFF
- **Prerendering:** [ON | OFF]

## Agent Guidance

When agents encounter technology choices in this file, they should:

- Skip guidance for technologies not listed (e.g., skip Angular advice).
- Frontend agent should use Blazor/Razor component patterns.
- Consider the render mode implications for every component (especially state and interactivity).
- Use the build/test commands listed above instead of guessing.
