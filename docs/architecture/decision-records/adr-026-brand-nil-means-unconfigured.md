---
id: "026"
status: accepted
title: "ADR-026: Brand Values — nil Means Unconfigured, and That Signal Is Load-Bearing"
---

## Status

Accepted

## Date

2026-07-13

## Context

Brand identity scalars (product name, support email, colors, TOTP issuer label,
…) reach the `brand:` config block from `BRAND_*` env vars and, from v0.26,
from a brand pack's `brand.yaml` manifest ([ADR-028](adr-028-brand-config-layering-order.md)).
Presence-keyed conditionals throughout the system — brand head tags, the TOTP
issuer label, favicon redirect logic, the branded-vs-neutral rendering split —
depend on being able to distinguish "operator chose this value" from "nobody
chose anything" (#3049: no brand values ship in YAML).

Introducing a tracked default pack created pressure to write "sensible neutral
values" into its manifest, which would silently destroy that distinction.

## Decision

Brand values are never defaulted into configuration. Absence *is* the neutral
state: an unconfigured install has brand.\* nil everywhere, exactly as before
packs existed.

Consequences:

- The tracked default pack's `brand.yaml` is a **commented template**: it
  documents every whitelisted key and sets none.
- Writing "active neutral values" into the default manifest was **rejected**:
  it would flip every presence-keyed conditional to the "configured" branch on
  stock installs — including baking a changed TOTP issuer label into users'
  authenticator apps — and would erase the configured/unconfigured distinction
  permanently.
- Enforced by a spec asserting `YAML.safe_load` of the default pack's manifest
  is nil/empty, so uncommenting a value trips a test and forces the
  conversation deliberately. If that spec is deleted, this decision should be
  considered reopened.

Where the actual neutral rendering values live is
[ADR-027](adr-027-one-authority-per-value.md): in the frontend's
`NEUTRAL_BRAND_DEFAULTS`, and nowhere else.

## Related

- [ADR-027](adr-027-one-authority-per-value.md) — one authority per value
- [ADR-028](adr-028-brand-config-layering-order.md) — brand config layering order
- [ADR-029](adr-029-brand-pack-vendor-operator-root-split.md) — vendor/operator root split
- `docs/architecture/branding.md` — current mechanics

## Implementation Notes

- Tracking issue: #3774. Prior art: #3612 (brand block normalization), #3049
  (no-values-in-YAML invariant).
- Enforcing spec: default-manifest-parses-empty.
