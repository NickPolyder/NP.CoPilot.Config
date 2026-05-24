---
name: scaffold
description: >
  Generates boilerplate for common architectural patterns — services, aggregates,
  controllers, test projects, and more. Ensures new code follows established
  conventions and layer boundaries from the start.
tags:
  - code-generation
  - scaffolding
  - architecture
  - patterns
visibility: user
tools:
  [agent, edit/createFile, edit/editFiles]
---

# Purpose

You are scaffolding new code structures that follow the project's established architecture.

Your goals are to:

- **Generate consistent boilerplate** that respects existing conventions.
- **Enforce layer boundaries** — scaffolded code has correct dependencies from the start.
- **Reduce manual setup** — let the developer focus on business logic, not plumbing.
- **Include test infrastructure** — every scaffolded component gets a corresponding test file/project.

---

# When to use this skill

Use this skill whenever:

- Creating a new service, aggregate, entity, or feature module from scratch.
- Adding a new project/layer to an existing solution (e.g., new bounded context).
- The user asks to "generate", "scaffold", "create a new [component]", or "set up a [pattern]".
- Bootstrapping a new API endpoint with full vertical slice (controller → handler → domain → tests).

Do **not** use this skill for:

- Modifying existing code — that's regular implementation or the `refactor` skill.
- Generating a full feature (design + tasks + implementation) — use `prd-workflow`.
- One-off code snippets — just write them directly.

---

# How it works

## Phase 1: Discover Conventions

Before generating anything, understand what already exists:

1. **Read project config** — check `.github/instructions/project-config.instructions.md` for tech stack.
2. **Identify patterns** — look at existing code for naming, folder structure, namespace conventions.
3. **Detect architecture style** — Clean Architecture layers, vertical slices, or project-specific layout.
4. **Find templates** — check if the project has its own scaffolding templates or item templates.

## Phase 2: Confirm Scope

Present what will be scaffolded and ask for approval:

```
### Scaffold: {Component Name}

**Type:** {Service | Aggregate | Controller | Feature Module | Test Project | ...}
**Pattern:** {Based on existing: path/to/similar/component}
**Files to create:**
- src/{Layer}/{Name}.cs
- src/{Layer}/I{Name}.cs
- tests/{Layer}.Tests/{Name}Tests.cs

**Conventions detected:**
- {Namespace pattern}
- {Naming pattern}
- {DI registration pattern}

Proceed? (yes / no / adjust)
```

## Phase 3: Generate

Create all files in one pass:

1. **Domain layer** — entities, value objects, domain events, interfaces.
2. **Application layer** — commands, queries, handlers, validators.
3. **Infrastructure layer** — repositories, EF configurations, external service clients.
4. **API layer** — controllers/endpoints, DTOs, mapping profiles.
5. **Tests** — unit test classes with arrange-act-assert structure, using the project's test framework.
6. **DI registration** — add to the appropriate service registration extension method.

Only generate layers relevant to the component type. Don't scaffold infrastructure for a pure domain object.

## Phase 4: Wire Up

After file generation:

1. **Register services** — add DI registrations where the project expects them.
2. **Update imports** — if the project uses barrel files or module registrations, update them.
3. **Verify build** — run `dotnet build` to confirm the scaffolded code compiles.

---

# Scaffold Templates

## New Aggregate (DDD)

Files:
- `src/{Domain}/Entities/{Name}.cs` — aggregate root entity
- `src/{Domain}/ValueObjects/` — any value objects mentioned
- `src/{Domain}/Events/{Name}CreatedEvent.cs` — domain event
- `src/{Domain}/Repositories/I{Name}Repository.cs` — repository interface
- `src/{Infrastructure}/Repositories/{Name}Repository.cs` — EF implementation
- `src/{Infrastructure}/EntityConfigurations/{Name}Configuration.cs` — EF type config
- `tests/{Domain}.Tests/{Name}Tests.cs` — domain logic tests

## New API Endpoint (Vertical Slice)

Files:
- `src/{Api}/Endpoints/{Feature}/{Action}{Name}Endpoint.cs` — endpoint or controller action
- `src/{Application}/{Feature}/Commands/{Action}{Name}Command.cs` — command + handler
- `src/{Application}/{Feature}/Validators/{Action}{Name}Validator.cs` — FluentValidation
- `src/{Contracts}/{Feature}/{Action}{Name}Request.cs` — request DTO
- `src/{Contracts}/{Feature}/{Action}{Name}Response.cs` — response DTO
- `tests/{Application}.Tests/{Feature}/{Action}{Name}HandlerTests.cs` — handler tests
- `tests/{Api}.Tests/{Feature}/{Action}{Name}EndpointTests.cs` — integration tests

## New Background Service

Files:
- `src/{Infrastructure}/Services/{Name}Service.cs` — BackgroundService implementation
- `src/{Application}/{Feature}/Options/{Name}Options.cs` — strongly-typed config
- `tests/{Infrastructure}.Tests/Services/{Name}ServiceTests.cs` — service tests

## New Test Project

Files:
- `tests/{ProjectName}.Tests/{ProjectName}.Tests.csproj` — project file with test framework refs
- `tests/{ProjectName}.Tests/GlobalUsings.cs` — common test usings
- `tests/{ProjectName}.Tests/Fixtures/` — shared fixtures directory
- Solution file updated with new project reference

---

# Coordination

- **Consult `architect`** — for pattern validation when scaffolding something that doesn't match existing patterns.
- **Consult `backend-developer`** — for .NET-specific implementation questions.
- **Consult `database-engineer`** — when scaffolding includes EF migrations or data model.

---

# Constraints

- **Never scaffold over existing files** — if a file exists at the target path, stop and ask.
- **Match existing style** — use the same formatting, naming, and patterns as neighboring code.
- **Don't over-scaffold** — only generate what's needed. An aggregate doesn't always need a REST endpoint.
- **This skill is not an orchestrator** — it generates code but doesn't plan features or run review workflows.
