---
applyTo: "**/*.py,**/*.pyi,**/pyproject.toml"
---

# Python Style

- Follow [PEP 8](https://peps.python.org/pep-0008/) and [PEP 257](https://peps.python.org/pep-0257/) (docstrings).
- Respect the project's supported Python versions and use compatible syntax.
- Type public APIs and use the project's existing type checker, formatter and linter.
- Prefer built-in generics and `X | None` when the supported version permits them.
- Prefer `pathlib.Path` over `os.path` for filesystem work.
- Use `dataclasses` (or `pydantic` where validation is needed) for structured data instead of bare dicts/tuples.
- Use `f-strings` for interpolation; never use `%` or `str.format` for new code.
- Prefer `logging` over `print`; use structured/parameterized log calls, not f-strings in log messages.
- Manage resources with context managers (`with`); never leak file handles or connections.
- Raise specific exceptions; never use bare `except:` — catch the narrowest type that applies.
- Propagate `async`/`await` consistently; don't block the event loop with sync I/O.
- Preserve the existing environment manager and reproducible dependency inputs; do not migrate tooling for an unrelated task.
- Use the project's test runner; prefer `pytest` for new projects. Keep tests isolated and deterministic.
