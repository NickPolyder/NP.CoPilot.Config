---
applyTo:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.mts"
  - "**/*.cts"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---

# TypeScript & Node.js Style

> Framework-agnostic conventions. Framework-specific rules (Angular, React, etc.) belong in project-level config.

## TypeScript

- Enable `strict` mode in `tsconfig.json` — no opting out of `strictNullChecks` or `noImplicitAny`.
- Prefer `unknown` over `any`; reserve `any` for genuine escape hatches and comment why.
- Let inference work — annotate public APIs, function boundaries, and exported types, not obvious locals.
- Prefer `type` aliases and discriminated unions; use `interface` for object shapes meant to be extended/implemented.
- Use `readonly` and `as const` for immutable data; avoid mutating shared state.
- Avoid type assertions (`as`) and non-null `!` — narrow with guards instead.
- Model absence explicitly (`X | undefined`); don't conflate `null` and `undefined` across a codebase — pick one convention.
- Prefer `enum`-free unions of string literals unless a real enum is required.

## Style & Tooling

- Format with Prettier and lint with ESLint (typescript-eslint) — no manual style nits.
- Use ESM (`import`/`export`); avoid CommonJS `require` in new code.
- Prefer named exports over default exports for refactor-safety and discoverability.
- Use `async`/`await` over raw `.then()` chains; always handle rejections.
- Never leave floating promises — `await`, return, or explicitly `void` them.

## Node.js Runtime

- Target an active LTS Node version; declare it via `engines` in `package.json` and/or `.nvmrc`.
- Read config and secrets from the environment — never hardcode; validate env at startup.
- Use the built-in `fetch` and Web APIs where available before reaching for dependencies.
- Prefer async, non-blocking I/O; don't block the event loop with sync calls in request paths.
- Pin dependencies with a committed lockfile; keep `dependencies` and `devDependencies` separated correctly.
- Use a structured logger (pino/winston) over `console.log` for application logging.

## Testing

- Write tests with the project's runner (Vitest, Jest, or `node:test`); keep them isolated and deterministic.
- Prefer testing behavior through public APIs over implementation details.
