---
id: "042"
status: accepted
title: "ADR-042: Python Environment-Reference Tooling Behind a Root Bin Entry Point"

---

## Status

Accepted

## Date

2026-09-12

## Context

The product is a Ruby 3.4/Rack 3 application, but the environment-reference
workflow needs parsing, validation, and release-version annotation logic across
more than 150 variables. Python is an appropriate tooling language for that
work; using a language other than the product runtime is normal in a polyglot
repository.

The risk is not the language boundary itself. Tooling decays when its runtime
and dependencies are not pinned and reproducible, or when contributors must
know its implementation language and directory before they can run it. The
resulting `.env.reference` artifact remains part of the application interface:
operators and dotenv-oriented workflows expect it at the repository root.

## Decision

Keep the environment-reference tool in this repository as a standalone Python
package at `tools/envref/`, and expose it through one language-agnostic root
entry point, `bin/envref`.

```text
repo/
├── bin/
│   └── envref
├── tools/
│   └── envref/
│       ├── pyproject.toml
│       ├── src/envref/
│       └── tests/
└── .env.reference
```

`tools/envref/` must use a `src` layout and declare its own pinned, reproducible
Python environment in `pyproject.toml`. It is application-coupled tooling, not
a collection of unrelated scripts: shared parsing and annotation logic belongs
in a package with tests.

`bin/envref` is a small executable shim that starts the tool with its managed
Python environment. Contributors invoke the tool from the repository root
without needing to know that it is implemented in Python or where its package
lives. The shim is the stable public entry point; it must not duplicate tool
logic.

The CLI uses subcommands under the single `envref` name, for example
`envref check` and `envref bump`. Its command-line interface uses Cyclopts so
all subcommands share one help and option convention. If a separate executable
is ever necessary, its name must retain the `envref-` domain prefix rather than
using a generic name such as `check.py`.

The tool generates `.env.reference` at the repository root. It is authoritative
for the release annotation format, including `As of x.y.z` notes. CI must
validate that annotation format and the generated reference remain consistent
with the application environment-variable surface.

This keeps the tool adjacent to the Ruby application whose configuration it
documents, avoiding tool/application version skew. It also avoids a Ruby rewrite
that would add migration risk without improving the user-facing entry point.

## Trade-offs

- **We lose:** A single-language repository and the lowest possible setup cost
  for a one-off script.
- **We gain:** Testable, maintainable tooling with a stable root command and a
  generated artifact in the location consumers expect.
- **Risk:** Python dependency management and the `bin/envref` shim become part
  of the contributor workflow. Unpinned dependencies or a shim that bypasses
  the managed environment would reintroduce the drift this decision is meant to
  prevent.

## Consequences

New environment-reference behavior belongs in the `envref` package and its
tests, not in loose Python files coupled through `sys.path` changes. The tool
must remain in this repository while it documents the application's environment
surface.

A later decision may consolidate scripting languages only if the repository's
tooling mix materially changes and a migration can preserve the package's
behavior, tests, reproducibility, and root entry point.

## Related

- `.env.reference` — generated environment-variable reference for operators
- `.github/workflows/drift-guards.yml` — existing CI guard for documented
  environment variables
- `mise.toml` (or .tool-versions) Consider using the polyglot runtime-pinning
  tool `mise` to pin both Ruby 3.4 and Python 3.x runtimes together in one place.
