# Project Configuration — Angular + .NET API

This file tells Copilot agents and skills about your project's technology choices.
Place it at `.github/instructions/project-config.instructions.md` so Copilot loads it automatically.

## Technology Stack

- **Frontend Framework:** Angular (latest)
- **UI Library:** [Angular Material | PrimeNG | Tailwind | Custom]
- **State Management:** [NgRx | Signals | RxJS Subjects | None]
- **Backend:** ASP.NET Core (latest)
- **API Style:** [REST | gRPC | GraphQL]
- **Database:** [SQL Server | PostgreSQL | SQLite | CosmosDB]
- **ORM:** Entity Framework Core
- **Infrastructure:** [Kubernetes | App Service | Service Fabric | Docker Compose]
- **CI/CD:** [GitHub Actions | Azure DevOps]
- **Messaging:** [Azure Service Bus | RabbitMQ | None]
- **Cloud:** [Azure | AWS | None]
- **Auth:** [Azure AD / Entra ID | IdentityServer | Auth0 | ASP.NET Core Identity]

## Build & Test Commands

### Backend (.NET)

```
restore:       dotnet restore
build:         dotnet build --no-restore
test:          dotnet test --no-build
test-single:   dotnet test --no-build --filter "FullyQualifiedName~{TestClassName.MethodName}"
lint:          dotnet format --verify-no-changes
watch:         dotnet watch run --project src/{ApiProject}
```

### Frontend (Angular)

```
install:       npm ci
build:         ng build
test:          ng test --watch=false --browsers=ChromeHeadless
test-single:   ng test --watch=false --include='**/path/to/spec.ts'
lint:          ng lint
serve:         ng serve --open
e2e:           ng e2e
```

## Project Conventions

- **Solution file:** [path to .sln]
- **Backend source:** src/
- **Frontend source:** [src/ClientApp/ | client/ | frontend/]
- **Tests (backend):** tests/
- **Tests (frontend):** inline (*.spec.ts alongside components)
- **Docs:** docs/
- **API contracts:** [src/Contracts/ | shared/api-types/]

## Angular Conventions

- **Component style:** [Standalone components | NgModules | Mixed]
- **Change detection:** [OnPush everywhere | Default]
- **Routing:** [Lazy-loaded feature modules | Standalone routes]
- **HTTP:** [Generated API client (NSwag/OpenAPI) | Manual HttpClient services]
- **Forms:** [Reactive forms | Template-driven | Typed forms]
- **Naming:** kebab-case files, PascalCase classes, camelCase members

## API Conventions

- **Error format:** Problem Details (RFC 9457)
- **Versioning:** [URL (/api/v1/) | Header | Query string]
- **Pagination:** [Cursor-based | Offset/limit | Keyset]
- **DTOs:** [Separate request/response | Shared models]

## Feature Toggles

- **ADO Integration:** OFF
- **Memory Bank:** OFF

## Agent Delivery Capabilities

| Capability | Enabled | Repository-specific rule |
|---|---:|---|
| Issue tracking | No | Configure only after repository evidence confirms this capability. |
| Isolated worktrees | No | Configure only after repository evidence confirms this capability. |
| Remote delivery | No | Configure the verified pull request, direct-push, or human-handoff path. |
| Protected branches | No | Configure required checks and reviewers from host policy. |
| Integration queue | No | Configure only after repository evidence confirms this capability. |
| Deployment evidence | No | Configure CI/deployment evidence from the repository. |

## Agent Guidance

When agents encounter technology choices in this file, they should:

- Skip guidance for technologies not listed (e.g., skip Blazor advice if Frontend is Angular).
- Frontend agent should use Angular patterns, not Blazor.
- Backend agent should generate API endpoints that match the Angular client's expectations.
- Use the build/test commands listed above instead of guessing.
