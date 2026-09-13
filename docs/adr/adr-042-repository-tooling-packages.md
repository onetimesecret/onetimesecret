---
id: "042"
status: accepted
title: "ADR-042: Repository Tooling Packages Behind Root Bin Entry Points"
---

## Status

Accepted

## Date

2026-09-12

## Context

The repository contains application-coupled development, validation, release,
and operational tooling in several languages. Much of it currently lives in
`./scripts/`, while the locale workflow has grown into a Python CLI under
`./locales/scripts/`. These locations make ownership, supported invocation,
runtime setup, and test boundaries inconsistent. A contributor can need to know
a tool's implementation language and private directory before they can run it.

The problem is not that the repository is polyglot. Ruby remains the product
runtime, while Python, shell, TypeScript, and other languages may each be an
appropriate implementation choice for tooling. The problem is tooling without a
clear package boundary, reproducible runtime, or stable public command.

The environment-reference workflow is the first adopter. It needs parsing,
validation, and release-version annotation across more than 150 variables. Its
`.env.reference` output is part of the application interface: operators and
dotenv-oriented workflows expect it at the repository root.

## Decision

Application-coupled tooling that has shared logic, dependencies, or tests is a
**tool package**. Tool packages live under `tools/<domain>/`; contributors use
them through a small, language-agnostic root command in `bin/<domain>`.

```text
repo/
├── bin/
│   ├── envref
│   └── locale
├── tools/
│   ├── envref/
│   │   ├── pyproject.toml
│   │   ├── src/envref/
│   │   └── tests/
│   └── locale/
│       ├── pyproject.toml
│       ├── src/locale/
│       └── tests/
├── scripts/                # existing and lightweight automation
└── .env.reference
```

### Package and command boundary

Each tool package owns its implementation, dependency metadata, tests, and
package-specific documentation. It must keep its runtime and third-party
dependencies reproducible using the conventions of its ecosystem. A Python tool
uses `pyproject.toml`, a `src` layout, and a lockfile or another documented
mechanism that resolves its dependencies reproducibly. The repository runtime
configuration must identify a compatible Python version.

`bin/<domain>` is the stable public entry point. It finds the repository root,
starts the package through its managed runtime, and passes arguments through. It
must not contain business logic or duplicate command parsing. Contributors and
CI call the root command rather than a package-private path.

A tool exposes related operations as subcommands under one domain name, such as
`bin/envref check` and `bin/envref bump`. A package may use the CLI framework
appropriate to its language; `envref` uses Cyclopts. If a separate executable
is necessary, its name retains the domain prefix rather than using a generic
name such as `check.py`.

### Initial adopters

`tools/envref/` is the first tool package, exposed through `bin/envref`. It
generates `.env.reference` at the repository root and owns the reference's
release annotation format, including `As of x.y.z` notes. CI must validate both
that format and consistency between the generated reference and the application
environment-variable surface.

`locales/scripts/` is an existing cohesive Python tool and an intended migration
candidate for `tools/locale/`, exposed through `bin/locale`. Its migration is a
separate, behavior-preserving change: existing CI and developer invocations
remain supported until their callers move to the root entry point. The migration
must not couple locale tooling to the product runtime merely to achieve a
single-language repository.

### Incremental migration

This decision does not require a bulk move of `scripts/`. Existing scripts stay
where they are until a tool package or a focused migration improves their
ownership and interface. New multi-file, dependency-bearing, or independently
tested application tooling belongs in `tools/<domain>/`. Small shell adapters,
CI glue, and compatibility wrappers may remain in `scripts/` when introducing a
package would not improve their maintenance.

A migration moves one domain at a time, preserves its behavior and tests, moves
callers to `bin/<domain>`, and removes a legacy wrapper only after repository
callers no longer require it. This prevents a directory cleanup from becoming a
risky rewrite.

## Trade-offs

- **We lose:** A single-language repository, one universal package layout, and
  the lowest setup cost for every one-off script.
- **We gain:** Clear tool ownership, testable package boundaries, reproducible
  runtimes, and stable commands that hide implementation details.
- **Risk:** `bin/` shims and runtime configuration become part of the
  contributor interface. A shim that bypasses its managed environment, or a
  package with unpinned dependencies, reintroduces the drift this decision is
  intended to prevent.

## Consequences

New environment-reference behavior belongs in `tools/envref/` and its tests,
not in loose Python files coupled through `sys.path` changes. The tool remains
in this repository while it documents the application's environment surface.

The same package-and-entry-point rule now provides the destination for other
cohesive tooling domains, including locale tooling. It does not mandate a
language change or a wholesale reorganization of existing scripts.

A later decision may consolidate scripting languages or select a repository-wide
runtime manager only if it preserves each package's behavior, tests,
reproducibility, and stable root entry point (e.g. `mise`).

## Related

- `.env.reference` — environment-variable reference for operators
- `.github/workflows/drift-guards.yml` — existing guard for documented
  environment variables
- `scripts/README.md` — current guidance for the legacy and lightweight script
  directory
- `locales/scripts/pyproject.toml` — current locale tooling package metadata

## Implementation Notes

### 2026-09-12 — envref landed, and two clauses read as intent rather than text

`tools/envref/` exists, behind `bin/envref`, with `pyproject.toml`, a `src`
layout, `uv.lock`, and tests. The six scripts it absorbed moved out of
`scripts/` unchanged in behaviour: the generated version map is byte-identical
before and after the move, and the ratchet reports the same 894 sites and 603
markers. `drift-guards.yml` and `validate-config.yml` now call `bin/envref
check` rather than a path inside the package.

Two clauses were implemented against their intent rather than their letter,
and both are recorded in `tools/envref/README.md` so a later reader can
overrule them deliberately:

**The annotation format.** The Decision gives `envref` ownership of the
reference's release annotation format, "including `As of x.y.z` notes". The
shipped markers say `# Since vX.Y.Z`. That grammar predates this ADR by five
weeks, is written on 605 lines, and is frozen by the ratchet the moment it
merges — a marker is a statement to everyone running that release, so
re-spelling one is not a rename. `docs/development/config-version-annotations.md`
stays the authority on the grammar; this ADR keeps ownership of *where* that
authority lives. Adopting `As of x.y.z` remains available as a deliberate
migration.

**The scope.** The Decision scopes `envref` to `.env.reference`. As built it
also covers `etc/defaults/*.yaml`, because the YAML resolver is the larger
half of the tooling and no other domain in this ADR gives it a home. Splitting
them would put one marker contract behind two commands.

### 2026-09-12 — Two conventions this first package sets

**Polyglot behind one entry point.** `src/envref/sh/` holds three bash-and-awk
implementations. Porting 950 verified lines to Python would have been a
rewrite, which the Decision's own migration rule argues against; the package
boundary and the single public command are what the Decision asks for, and
both hold.

**No repository-wide `.python-version`.** The package states
`requires-python = ">=3.11"` and pins its dependencies in `uv.lock`; CI pins
the interpreter through `actions/setup-python`, as every other Python job in
this repository already does. A root `.python-version` names one exact
interpreter, so pinning CI's 3.14 would oblige every contributor on 3.11 or
3.12 to fetch a second Python to run a guard that works on theirs. If a
repository-wide runtime manager arrives later — the Consequences section
anticipates one — that is the decision that should set this file, not this
package.
