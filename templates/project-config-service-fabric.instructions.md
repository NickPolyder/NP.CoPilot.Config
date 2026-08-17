# Project Configuration — Service Fabric

This file tells Copilot agents and skills about your project's technology choices.
Place it at `.github/instructions/project-config.instructions.md` so Copilot loads it automatically.

## Technology Stack

- **Platform:** Azure Service Fabric
- **Service Types:** [Reliable Services | Reliable Actors | Both]
- **Communication:** [Service Remoting | HTTP/REST | gRPC | Mixed]
- **Backend:** ASP.NET Core (latest) hosted in Reliable Services
- **Database:** [SQL Server | CosmosDB | Reliable Collections | Mixed]
- **ORM:** [Entity Framework Core | Dapper | None (Reliable Collections only)]
- **CI/CD:** [Azure DevOps | GitHub Actions]
- **Messaging:** [Azure Service Bus | Reliable Queues | Both]
- **Cloud:** Azure
- **Auth:** [Azure AD / Entra ID | Certificate-based | Custom]

## Build & Test Commands

```
restore:       dotnet restore
build:         dotnet build --no-restore
test:          dotnet test --no-build
test-single:   dotnet test --no-build --filter "FullyQualifiedName~{TestClassName.MethodName}"
lint:          dotnet format --verify-no-changes
package:       msbuild /t:Package {ServiceFabricProject}.sfproj
deploy-local:  Connect-ServiceFabricCluster; Publish-ServiceFabricApplication
```

## Project Conventions

- **Solution file:** [path to .sln]
- **Source root:** src/
- **Test root:** tests/
- **SF Application project:** src/{AppName}.Application/
- **Service projects:** src/{ServiceName}/
- **Docs root:** docs/

## Service Fabric Conventions

- **Service naming:** {BoundedContext}.{ServiceName}Service (e.g., Orders.ProcessingService)
- **Actor naming:** {Entity}Actor (e.g., OrderActor, InventoryItemActor)
- **Partitioning:** [Singleton | Named | Uniform Int64 Range] per service
- **State management:** [Reliable Collections | External database | Hybrid]
- **Health reporting:** Custom health checks registered with SF health subsystem
- **Upgrade strategy:** [Rolling | Monitored rolling | Manual]
- **Configuration:** Settings.xml + environment overrides via ApplicationManifest

## Communication Patterns

- **Service-to-service:** [Remoting (internal) | HTTP (external-facing) | Event-driven]
- **Client-to-service:** [API Gateway + HTTP | Direct service resolution]
- **Pub/Sub:** [Azure Service Bus topics | Actor events | Custom pub/sub on Reliable Queues]

## Deployment

- **Cluster:** [Local dev cluster | Azure managed cluster | Standalone]
- **Environments:** [Dev | Staging | Production]
- **Manifest parameterization:** Cloud.xml / Local.1Node.xml / Local.5Node.xml

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
| Deployment evidence | No | Configure CI/deployment and health evidence from the repository. |

## Agent Guidance

When agents encounter technology choices in this file, they should:

- Service Fabric engineer agent is the primary authority for SF-specific decisions.
- Backend developer should implement services as standard ASP.NET Core within SF hosting.
- Architect should consider partition boundaries as part of aggregate/bounded context design.
- DevOps engineer handles cluster management, deployment scripts, and upgrade policies.
- Use the build/test commands listed above instead of guessing.
