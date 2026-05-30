---
applyTo:
  - "**/*.py"
  - "**/*.pyi"
  - "**/pyproject.toml"
---

# Python Style

- Follow [PEP 8](https://peps.python.org/pep-0008/) and [PEP 257](https://peps.python.org/pep-0257/) (docstrings).
- Target a supported Python version (3.11+) and prefer modern syntax over legacy idioms.
- Use type hints on all public functions, methods, and module-level variables; check with a static type checker (`mypy` or `pyright`).
- Use built-in generics and `X | None` over `typing.List` / `Optional[X]` (PEP 585 / PEP 604).
- Format with `ruff format` (or `black`) and lint/sort imports with `ruff` — no manual style nits.
- Prefer `pathlib.Path` over `os.path` for filesystem work.
- Use `dataclasses` (or `pydantic` where validation is needed) for structured data instead of bare dicts/tuples.
- Use `f-strings` for interpolation; never use `%` or `str.format` for new code.
- Prefer `logging` over `print`; use structured/parameterized log calls, not f-strings in log messages.
- Manage resources with context managers (`with`); never leak file handles or connections.
- Raise specific exceptions; never use bare `except:` — catch the narrowest type that applies.
- Propagate `async`/`await` consistently; don't block the event loop with sync I/O.
- Pin dependencies and manage environments via `pyproject.toml` (uv/Poetry/pip-tools) — avoid loose `requirements.txt` where possible.
- Write tests with `pytest`; keep them isolated, deterministic, and fast.
