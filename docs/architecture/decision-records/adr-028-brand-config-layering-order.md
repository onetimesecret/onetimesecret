---
id: "028"
status: accepted
title: "ADR-028: Brand Config Layering Order, and Complexity Counted in Active Layers"
---

## Status

Accepted

## Date

2026-07-13

## Context

Before v0.26, branding an install required two disjoint mechanisms: ~15
`BRAND_*` env vars feeding the `brand:` config block (normalized by
`Config#normalize_brand`), and a directory of replacement root-served assets
selected by `BRAND_PACK` / `BRAND_ASSETS_DIR` (#3739, shipped in #3770).
Nothing checked that the two halves agreed.

#3774 consolidates: the pack becomes the single unit of branding — a directory
carrying both the asset files and a `brand.yaml` manifest of identity scalars.
Adding the manifest as a config source raises the question this ADR answers:
where does it sit relative to the existing sources, and does adding a
mechanism count as adding complexity?

## Decision

Precedence, lowest to highest:

```
built-in defaults < pack brand.yaml < operator config brand: < BRAND_* env
```

- **Env always wins.** This preserves `normalize_brand`'s pre-existing contract
  ("an env-set field always wins over a YAML-supplied one") and serves a real
  deployment shape: multi-region production runs one shared pack with
  per-jurisdiction env overrides (`BRAND_SUPPORT_EMAIL`, `BRAND_PRODUCT_DOMAIN`)
  without forking the pack.
- **The pack manifest is a fallback layer, not a replacement.** The `brand:`
  block and `BRAND_*` vars remain fully functional as the override surface;
  docs lead with the pack. (Rewire superseded surfaces, don't delete them.)
- **Meta-principle:** runtime-configuration complexity is measured in *active
  layers per install*, not in files or mechanisms that exist. This holds beyond
  branding: a mechanism that is exercised by specs but contributes nothing
  until an operator opts in adds zero configuration complexity. An unconfigured
  install must have **zero** live brand sources — which is
  [ADR-026](adr-026-brand-nil-means-unconfigured.md)'s invariant seen from the
  layering side.
- Manifest loading is boot-time (`after_load`, alongside `normalize_brand`),
  matching the static-middleware overlay contract: changing packs requires a
  restart.
- Manifest keys are **whitelisted** to the `BRAND_ENV` key set and parsed with
  `YAML.safe_load`. A pack is a semi-trusted artifact (community packs will
  circulate); it must not be able to set `site.host`, SMTP config, or anything
  outside the brand namespace. A drift spec asserts whitelist == `BRAND_ENV`
  keys == the keys documented in the pack README/template. If that spec is
  deleted, this decision should be considered reopened.

## Related

- [ADR-026](adr-026-brand-nil-means-unconfigured.md) — nil means unconfigured
- [ADR-027](adr-027-one-authority-per-value.md) — one authority per value
- [ADR-029](adr-029-brand-pack-vendor-operator-root-split.md) — where packs are found
- `docs/architecture/branding.md` — current mechanics

## Implementation Notes

- Tracking issue: #3774. Prior art: #3612 (brand block normalization).
- Enforcing spec: manifest-whitelist == `BRAND_ENV` == documented keys.
- Referenced from a one-line comment at `OT.brand_overlay_dir`
  (`lib/onetime.rb`).
