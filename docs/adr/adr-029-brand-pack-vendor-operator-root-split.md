---
id: "029"
status: accepted
title: "ADR-029: Brand Pack Vendor/Operator Root Split"
---

## Status

Accepted

## Date

2026-07-13

## Context

Brand packs ([ADR-028](adr-028-brand-config-layering-order.md)) must be
resolvable both when vendored (tracked packs shipped with the image/repo) and
when operator-mounted (Debian confext / podman quadlet deployments that mount
`/etc/onetimesecret` into `/app/etc` entry-by-entry). The change-driver here is
deployment tooling — how mounts behave — not config semantics.

## Decision

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
set; if that spec is deleted, this decision should be considered reopened.

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

## Related

- [ADR-026](adr-026-brand-nil-means-unconfigured.md) — the default pack's manifest sets nothing
- [ADR-028](adr-028-brand-config-layering-order.md) — brand config layering order
- `docs/architecture/branding.md` — current mechanics

## Implementation Notes

- Tracking issue: #3774. Prior art: #3739/#3770 (asset overlay).
- `public/branding/` is gitignored from #3770; `default/` needs a
  `!public/branding/default/` carve-out.
- Enforcing spec: default-pack file-set == canonical list (lands with the
  #3774 implementation; not yet in tree as of acceptance).
- Doctor probes the *outcome*, not preconditions: which root won resolution,
  which manifest keys loaded, which overlay URLs will serve from the pack.
  Pack-not-found errors list the searched roots.
