---
id: "030"
status: proposed
title: "ADR-030: Regional Instance Configuration Layering"
---

## Status

Proposed

## Date

2026-07-14

## Context

Each regional instance (`REGIONS_ENABLED`, per-jurisdiction — see
`docs/architecture/regions.md`) carries its own `.env`. In practice these files
accumulate ~100 variables, and most of them are the same in every region:
brand URLs, feature flags, mail identity, log posture. The genuinely
per-region facts — `HOST`, `JURISDICTION`, the Approximated proxy block, and
the region's secrets — are a small minority buried in the noise. Standing up a
new region means copying a large file and hand-auditing which lines actually
need to change, which is both slow and error-prone (a stale copied value is
indistinguishable from an intentional one).

Three layers already resolve a variable, deepest to shallowest, later-wins:

1. **`etc/defaults/*.yaml`** — ERB templates where `<%= ENV['X'] || 'default' %>`
   (and `!= 'false'` ⇒ default-true, `== 'true'` ⇒ default-false) define what
   an *unset* variable resolves to. This is the product default.
2. **Shared operator env** — `.env`, sourced first (`set -a; source .env` in
   production; `dotenv .env` under direnv).
3. **Region overlay** — `.env.local`, sourced last so its values win
   (`dotenv .env.local`).

The mechanism to keep per-region files small already exists. What's missing is
a placement rule and a way to tell, for any given line, which layer it belongs
in.

## Decision

**A variable lives in the deepest layer that can hold its value.** A line in a
region's `.env.local` must earn its place by being a per-region *fact*.

Two tests decide placement, both mechanically checkable:

- **Equals the product default?** → delete it. Setting `AUTH_ENABLED=true` when
  the default is `ENV['AUTH_ENABLED'] != 'false'` changes nothing. This is the
  "duplicates default behaviour" case.
- **Identical across every region but differs from the default?** → move it to
  the shared operator env (layer 2), or, if it's what we want *everyone*
  running the software to get, change the fallback in `config.defaults.yaml`
  (layer 1). A value repeated identically in N region files has N copies of one
  fact; that violates one-authority-per-value ([ADR-027](adr-027-one-authority-per-value.md)).

Only what survives both tests — a value that is neither the default nor
region-invariant — stays in the region overlay.

| Class | Belongs in | Examples |
| --- | --- | --- |
| Product default | layer 1 (`config.defaults.yaml`) | feature flags on everywhere: `ENABLE_ORGS`, `DOMAINS_ENABLED`, `JOBS_ENABLED`, `I18N_ENABLED` |
| Org-wide, region-invariant | layer 2 (shared `.env`) | `DOCS_URL`, `TERMS_URL`, `PRIVACY_URL`, `FROM_EMAIL`, `AUTHENTICATION_MODE`, `DEFAULT_LOG_LEVEL` |
| Per-region fact | layer 3 (`.env.local`) | `HOST`, `JURISDICTION`, `JURISDICTIONS`, `APPROXIMATED_PROXY_*`, `EMAILER_REGION`, region-scoped OIDC |
| Per-region secret | layer 3 (never committed) | `SECRET`, `*_SECRET`, `*_DATABASE_URL`, `RABBITMQ_URL`, `SMTP_PASSWORD`, API tokens, DSNs |

The strongest lever is layer 1: for any flag we run **on** in every region,
flip its `config.defaults.yaml` fallback so a new region needs zero lines for
it, and only a region that wants it *off* says so. A new region collapses to
roughly its `HOST`, jurisdiction, proxy block, and secret set.

## Trade-offs

- **We gain**: a region file that is auditable at a glance (every line is a
  region-specific reason); no stale-copy drift; one authority per value.
- **We lose**: single-file grep-ability — an operator now reads three layers to
  know an instance's effective config. Mitigated by the audit tool below, which
  resolves and reports the effective value and its source layer.
- **Watch**: flipping a layer-1 default changes behaviour for *every* unset
  deployment, including third-party self-hosters. Default flips are for values
  that are genuinely the right product default, not merely convenient for our
  fleet; when in doubt, use layer 2.

## Related

- [ADR-027](adr-027-one-authority-per-value.md) — one authority per value; this
  applies it to environment configuration.
- [ADR-028](adr-028-brand-config-layering-order.md) — brand config layering
  order; same deepest-layer-wins shape for brand assets.
- `docs/architecture/regions.md` — what makes an instance regional.
- `.env.reference` — the enumerated variable catalog with defaults.

## Implementation Notes

### 2026-07-14 — Determination method (audit tool)

The two tests are automatable. An audit script reads the effective default for
every variable straight from `etc/defaults/*.yaml` (parsing the `ENV['X'] || …`,
`!= 'false'`, `== 'true'` shapes) and classifies a set of `.env` files:

- **Pass 1 (one file):** flag variables whose value equals the baked-in
  default → deletable now.
- **Pass 2 (all region files):** diff variables across regions —
  **identical everywhere ⇒ centralize** (layer 1 or 2); **differs ⇒ keep**
  (layer 3). Pass 2 is the decisive one and requires every regional file at
  once.

A prototype lives at `scratchpad/env_audit.rb`; promoting it to `bin/` as a
committed, CI-runnable check is the natural home so region files can't silently
re-accumulate defaults. Two known rough edges to fix on promotion: it
regex-buckets a few non-secret names (`AUTH_PASSWORD_REQUIREMENTS_ENABLED`,
`ORGS_INCOMING_SECRETS_ENABLED`, `SECRET_VARIABLE_NAMES`) as secrets, and it
does not resolve chained `ENV['A'] || ENV['B']` fallbacks (mail/AWS/Redis-DB
aliases) — it marks them for manual review rather than guessing.

### 2026-07-14 — Baseline finding

Run against the reference dev `.env` (106 variables): 18 equalled the default
outright (deletable), ~25 were region-invariant overrides (centralizable), and
the residue was per-region facts, secrets, and code-level/runtime reads
(`FROM`/`FROMEMAIL`/`FROMNAME` surfaced as legacy aliases of
`FROM_EMAIL`/`FROM_NAME`, candidates for removal). Order-of-magnitude: a region
file should be closer to 20 lines than 100.
