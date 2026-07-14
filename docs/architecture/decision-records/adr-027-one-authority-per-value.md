---
id: "027"
status: accepted
title: "ADR-027: One Authority per Value — Defaults Live in Exactly One Place"
---

## Status

Accepted

## Date

2026-07-13

## Context

The install-script audit (`docs/specs/install-experience-problems.txt`) found
five conflicting Ruby version floors across files that each believed they were
authoritative. The same disease threatens any value that exists in more than
one layer of the stack: the copies drift, and nothing machine-checks agreement.

The v0.26 brand pack work (#3774) hit this concretely: neutral rendering
values already live in the frontend's `NEUTRAL_BRAND_DEFAULTS`
(`src/shared/constants/brand.ts`), and the new default pack manifest was a
tempting second home for them.

## Decision

Every defaulted value has exactly one authoritative definition; other layers
consume it or stay silent, they do not restate it. This is the configuration
counterpart of "one authority per projection" in the schema architecture notes,
and it applies generally — not only to branding.

For the brand instance: neutral rendering values belong to
`NEUTRAL_BRAND_DEFAULTS` and nowhere else. Mirroring them into a backend YAML
(the default pack manifest, config defaults, or anywhere) was **rejected** —
it creates a second source of truth with no machine checking agreement.
Keeping the backend silent is what
[ADR-026](adr-026-brand-nil-means-unconfigured.md)'s nil invariant enforces.

## Related

- [ADR-026](adr-026-brand-nil-means-unconfigured.md) — nil means unconfigured
- [ADR-028](adr-028-brand-config-layering-order.md) — brand config layering order
- Schema architecture notes — "one authority per projection"
