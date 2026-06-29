---
applyTo:
  - "**/*.yml"
  - "**/*.yaml"
  - "**/Dockerfile"
  - "**/*.dockerfile"
  - "**/docker-compose*.yml"
  - "**/docker-compose*.yaml"
---

# YAML & Docker Style

> **Intent (anchor):** Apply YAML, Dockerfile, and Docker Compose style rules only to files matched by `applyTo`; project-specific platform rules win when more specific.

## YAML

- Use 2-space indentation; never tabs.
- Quote strings that could be misread as another type (`"true"`, `"123"`, `"yes"`, version numbers).
- Keep keys consistently cased (kebab- or snake-case) within a file.
- Never commit secrets to YAML — reference environment variables or a secret store.
- Anchor and alias (`&`/`*`) to avoid repetition in large configs, but don't sacrifice readability.
- Validate/lint YAML (`yamllint` or schema validation) before relying on it.

## Dockerfile

- Pin base images to a specific tag or digest — never bare `latest`.
- Order instructions from least- to most-frequently-changing to maximize layer cache reuse.
- Combine related `RUN` steps and clean up package caches in the same layer to keep images small.
- Use multi-stage builds to separate build tooling from the runtime image.
- Run as a non-root `USER`; expose only the ports you need.
- Use `COPY` over `ADD` unless you need `ADD`'s archive/URL behavior.
- Add a `HEALTHCHECK` for long-running services.
- Use `.dockerignore` to keep build context (and secrets) out of the image.

## Docker Compose

- Pin image tags explicitly; avoid implicit `latest`.
- Define `healthcheck` and `restart` policies for services.
- Pass secrets/config via environment or `secrets:` — never bake them into the file.
- Name volumes and networks explicitly; prefer named volumes over host binds for portability.
- Keep service definitions minimal and composable; use override files for env-specific changes.

## Final Rules (Anchor)

Apply these rules only to YAML/Docker assets: never commit secrets, pin images, validate config, define health checks, and avoid root runtime containers.
