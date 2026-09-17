---
applyTo: "**/*.ts,**/*.tsx,**/*.mts,**/*.cts,**/*.js,**/*.jsx,**/*.mjs,**/*.cjs"
---

# TypeScript & Node.js Style

## TypeScript

- Preserve existing strict checks; prefer `strict` for new projects. Do not migrate a repository's compiler settings merely to complete an unrelated edit.
- Prefer `unknown` over `any`; reserve `any` for genuine escape hatches and comment why.
- Let inference work — annotate public APIs, function boundaries, and exported types, not obvious locals.
- Prefer `type` aliases and discriminated unions; use `interface` for object shapes meant to be extended/implemented.
- Use `readonly` and `as const` for immutable data; avoid mutating shared state.
- Avoid type assertions (`as`) and non-null `!` — narrow with guards instead.
- Model absence explicitly (`X | undefined`); don't conflate `null` and `undefined` across a codebase — pick one convention.
- Prefer `enum`-free unions of string literals unless a real enum is required.

## Style & Tooling

- Use the project's formatter and linter rather than adding tooling for style alone.
- Follow the project's module system; prefer ESM for new projects.
- Prefer named exports over default exports for refactor-safety and discoverability.
- Use `async`/`await` over raw `.then()` chains; always handle rejections.
- Await or return promises; intentional fire-and-forget work must still handle failures.

## Node.js Runtime

- Respect the declared supported Node version; prefer active LTS for new projects, not an unsolicited runtime upgrade.
- Read configuration from declared sources and secrets through repository-approved
  runtime injection or direct secret-provider retrieval. Environment variables
  are a delivery channel, not a secret store; never hardcode, commit, log, or
  expose secrets to clients. Validate required values at startup.
- Use the built-in `fetch` and Web APIs where available before reaching for dependencies.
- Prefer async, non-blocking I/O; don't block the event loop with sync calls in request paths.
- Pin dependencies with a committed lockfile; keep `dependencies` and `devDependencies` separated correctly.
- Use the project's structured logger for application logging.

## Testing

- Write tests with the project's runner (Vitest, Jest, or `node:test`); keep them isolated and deterministic.
- Prefer testing behavior through public APIs over implementation details.
