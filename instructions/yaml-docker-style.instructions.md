---
applyTo: "**/*.yml,**/*.yaml,**/Dockerfile,**/*.dockerfile,**/docker-compose*.yml,**/docker-compose*.yaml"
---

# YAML & Docker Style

## YAML

- Use 2-space indentation; never tabs.
- Quote strings that could be misread as another type (`"true"`, `"123"`, `"yes"`, version numbers).
- Keep keys consistently cased (kebab- or snake-case) within a file.
- Never commit secret values to YAML — reference repository-approved secret
  storage or runtime injection instead.
- Use YAML anchors/aliases only where the consuming schema/parser supports them.
- Use the repository's existing schema validation or YAML checks.

## Dockerfile

- Pin base images to a specific tag or digest — never bare `latest`.
- Order instructions from least- to most-frequently-changing to maximize layer cache reuse.
- Combine related `RUN` steps and clean up package caches in the same layer to keep images small.
- Use multi-stage builds when build tooling would otherwise ship in the runtime image.
- Run as a non-root `USER`; expose only the ports you need.
- Use `COPY` over `ADD` unless you need `ADD`'s archive/URL behavior.
- Give long-running services a meaningful health signal through the image or deployment platform.
- Use `.dockerignore` to keep build context (and secrets) out of the image.

## Docker Compose

- Pin image tags explicitly; avoid implicit `latest`.
- Define health and restart behavior appropriate to the service lifecycle.
- Use repository-approved runtime delivery, such as explicitly mapped environment
  values, `secrets:`, or direct provider retrieval; never bake secret values into
  Compose files/images or forward an entire environment indiscriminately.
- Name volumes and networks explicitly; prefer named volumes over host binds for portability.
- Keep service definitions minimal and composable; use override files for env-specific changes.
