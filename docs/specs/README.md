# Specifications

Durable specifications and models for discrete features — the intended
behaviour and its rationale, kept current with the code.

## Contents

- [secret-creation-flows.md](./secret-creation-flows.md) — The paths through
  which a secret can be created and the state each produces.
- [domain-permissions.md](./domain-permissions.md) — Permission rules governing
  secret creation on custom domains.
- [schema-source-of-truth.md](./schema-source-of-truth.md) — Treating the schema
  as the single source of truth, with validation at the boundary.

## Scope

This directory holds specifications that remain useful over time. Single-issue
forensic write-ups (root-cause analyses, one-off investigation notes) belong on
the issue itself, not here — git history preserves any that were retired.
