---
id: "026"
status: accepted
title: "ADR-026: Brand Pack Layering, the nil-Means-Unconfigured Invariant, and the Vendor/Operator Root Split"
---

## Status

Accepted

## Date

2026-07-13

## Context

Before v0.26, branding an install required two disjoint mechanisms: ~15 `BRAND_*`
env vars feeding the `brand:` config block (identity scalars, normalized by
`Config#normalize_brand`), and a directory of replacement root-served assets
selected by `BRAND_PACK` / `BRAND_ASSETS_DIR` (#3739, shipped in #3770). Nothing
checked that the two halves agreed, and a full brand meant setting one env var
plus fifteen more — the same "version-of-truth scattered across files that
disagree" disease documented for the install scripts in
`docs/specs/install-experience-problems.txt`.

#3774 consolidates: the pack becomes the single unit of branding — a directory
carrying both the asset files and a `brand.yaml` manifest of identity scalars —
resolved from a search path that supports both vendored packs and
operator-mounted packs (Debian confext / podman quadlet deployments that mount
`/etc/onetimesecret` into `/app/etc` entry-by-entry).

Designing that consolidation surfaced four decisions whose rationale is
non-obvious and will otherwise be re-litigated. The mechanics (current search
roots, file lists, config keys) live in `docs/architecture/branding.md` and will
evolve; this ADR records only the invariants and why.

## Decision

### 1. `nil` means unconfigured, and that signal is load-bearing

Brand values are never defaulted into configuration. Absence *is* the neutral
state. Presence-keyed conditionals throughout the system — brand head tags,
the TOTP issuer label, favicon redirect logic, the branded-vs-neutral rendering
split — depend on being able to distinguish "operator chose this value" from
"nobody chose anything" (#3049: no brand values ship in YAML).

Consequences:

- The tracked default pack's `brand.yaml` is a **commented template**: it
  documents every whitelisted key and sets none. An unconfigured install has
  brand.\* nil everywhere, exactly as before packs existed.
- Writing "active neutral values" into the default manifest was **rejected**:
  it would flip every presence-keyed conditional to the "configured" branch on
  stock installs — including baking a changed TOTP issuer label into users'
  authenticator apps — and would erase the configured/unconfigured distinction
  permanently.
- Enforced by a spec asserting `YAML.safe_load` of the default pack's manifest
  is nil/empty, so uncommenting a value trips a test and forces the
  conversation deliberately.

### 2. One authority per value; defaults live in exactly one place

Neutral rendering values belong to the frontend's `NEUTRAL_BRAND_DEFAULTS`
(`src/shared/constants/brand.ts`) and nowhere else. Mirroring them into a
backend YAML (the default manifest, config defaults, or anywhere) creates a
second source of truth with no machine checking agreement — the drift pattern
that produced five conflicting Ruby version floors in the install tooling.
Same principle as "one authority per projection" in the schema architecture
notes.

### 3. Layering order, and complexity counted in active layers

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
  layers per install*, not in files or mechanisms that exist. An unconfigured
  install must have **zero** live brand sources — the manifest mechanism exists,
  is exercised by custom-pack specs, and does nothing until someone brands.
- Manifest loading is boot-time (`after_load`, alongside `normalize_brand`),
  matching the static-middleware overlay contract: changing packs requires a
  restart.
- Manifest keys are **whitelisted** to the `BRAND_ENV` key set and parsed with
  `YAML.safe_load`. A pack is a semi-trusted artifact (community packs will
  circulate); it must not be able to set `site.host`, SMTP config, or anything
  outside the brand namespace. A drift spec asserts whitelist ==
  `BRAND_ENV` keys == the keys documented in the pack README/template.

### 4. Vendor/operator root split

Pack name resolution searches, first-existing-wins:

1. `<HOME>/etc/branding/<name>` — **operator-owned**. Never tracked in the
   repo. Arrives via mounts (quadlet, confext, docker volume).
2. `<HOME>/public/branding/<name>` — **vendored**. Tracked packs shipped with
   the image/repo, including `default`, which is always present.

This mirrors `/etc`-vs-`/usr` semantics (local config shadows vendor data —
the confext/sysext split). `BRAND_ASSETS_DIR` remains the explicit-path escape
hatch and outranks `BRAND_PACK`.

**Rejected: a tracked `etc/branding/default`.** The quadlet deployment mounts
each top-level entry of `/etc/onetimesecret` individually into `/app/etc`. The
moment an operator creates `/etc/onetimesecret/branding/<their-pack>`, the
entry being mounted is the `branding` *directory* — landing wholesale over
`/app/etc/branding` and shadowing any tracked `default/` inside the image.
A tracked default there works in every deployment *except the ones that use
the pack feature*: a latent failure, strictly worse than an immediate one.
With `default` in the vendor root, an operator mounting packs never shadows it
unless they deliberately create `etc/branding/default` — which then behaves as
an intentional override, consistent with shadowing semantics everywhere else.

**The default pack is the file-set contract.** Resolution always lands on a
pack (`BRAND_PACK` unset ⇒ `public/branding/default`), so the default pack
enumerates exactly which root-served files are brand-overlayable. Anything
brand-shaped left in `public/web` matching those names is cruft by definition.
Enforced by a spec asserting the default pack contains exactly the canonical
set.

## Trade-offs

- **We lose**: byte-identical no-pack responses relative to ≤0.25.x
  (`brand_asset_path`'s preserved fallback literal). Deliberate: v0.26 ships
  new neutral assets anyway, so this release is the one place the change is
  free.
- **We gain**: one resolution path instead of pack-overlay-plus-fallback; an
  enumerable contract for which files are load-bearing; a single knob
  (`BRAND_PACK=name`) that carries a complete brand; per-persona mechanisms
  (Docker volume / confext / vendored / env overrides) that never require
  another persona's tooling.
- **Risk**: the invariants here are behavioral, not structural — nothing stops
  a future change from defaulting a brand value except the enforcing specs.
  An ADR whose invariants are machine-checked is the only kind that stays
  true; if a spec named here is deleted, the corresponding decision should be
  considered reopened.

## Implementation Notes

- Tracking issue: #3774. Prior art: #3739/#3770 (asset overlay), #3612
  (brand block normalization), #3049 (no-values-in-YAML invariant).
- `public/branding/` is gitignored from #3770; `default/` needs a
  `!public/branding/default/` carve-out.
- Enforcing specs: default-manifest-parses-empty; manifest-whitelist ==
  `BRAND_ENV` == documented keys; default-pack file-set == canonical list.
- Doctor probes the *outcome*, not preconditions: which root won resolution,
  which manifest keys loaded, which overlay URLs will serve from the pack.
  Pack-not-found errors list the searched roots.
- Referenced from `docs/architecture/branding.md` and a one-line comment at
  `OT.brand_overlay_dir` (`lib/onetime.rb`).
