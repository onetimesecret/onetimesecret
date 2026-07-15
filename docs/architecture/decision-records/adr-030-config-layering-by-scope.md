---
id: "030"
status: proposed
title: "ADR-030: Configuration Layering by Value Scope"
---

## Status

Proposed

## Date

2026-07-14

## Context

We run multiple instances that each carry their own `.env`. These files
accumulate ~100 variables, most of which do not vary between instances: brand
URLs, feature flags, mail identity, log posture. The values that genuinely
differ — hostname, secrets, deployment-specific integrations — are a small
minority buried in the noise. Standing up a new instance means copying a large
file and hand-auditing which lines to change, and a stale copied value is
indistinguishable from an intentional one. The axis of variance is
incidental — regions, environments (dev/staging/prod), tenants, third-party
self-hosters overriding our defaults — the accumulation is the same.

Three layers already resolve every variable. The deepest layer is the most
shared; shallower layers are sourced later and win:

1. **Product defaults** — `etc/defaults/*.yaml`, ERB templates where
   `<%= ENV['X'] || 'default' %>` (plus `!= 'false'` ⇒ default-true,
   `== 'true'` ⇒ default-false) defines what an *unset* variable resolves to:
   the value for everyone running the software.
2. **Shared operator env** — `.env`, sourced first (`set -a; source .env` in
   production; `dotenv .env` under direnv).
3. **Instance overlay** — `.env.local`, sourced last so its values win.

The mechanism to keep per-instance files small already exists. What's missing
is a placement rule: for any given line, which layer does it belong in?

## Decision

**Author every value at the deepest layer whose scope matches the value's
actual variance.** A value that does not vary at a layer's scope does not
belong at that layer.

Two tests decide placement, both mechanically checkable:

- **Equals what the next layer down already yields?** Delete it. Setting
  `AUTH_ENABLED=true` when the default is `ENV['AUTH_ENABLED'] != 'false'`
  changes nothing; the common case is an instance overlay restating the
  product default.
- **Same across every instance but different from the default?** It isn't
  instance-scoped. Move it down to the shared `.env`, or — if it's what
  *everyone* running the software should get — change the fallback in
  `etc/defaults/*.yaml`. A value repeated identically across N instance files
  is N copies of one fact, which violates one-authority-per-value
  ([ADR-027](adr-027-one-authority-per-value.md)).

Only a value that genuinely varies per instance stays in the instance overlay.

| Value scope | Belongs in | Examples |
| --- | --- | --- |
| Same for everyone (product default) | layer 1 (`etc/defaults/*.yaml`) | flags we enable on every instance — `ENABLE_ORGS`, `DOMAINS_ENABLED`, `JOBS_ENABLED`, `I18N_ENABLED` — all default-off today, candidates for a default flip |
| Same across our instances, not the default | layer 2 (shared `.env`) | `DOCS_URL`, `TERMS_URL`, `PRIVACY_URL`, `FROM_EMAIL`, `AUTHENTICATION_MODE`, `DEFAULT_LOG_LEVEL` |
| Varies per instance | layer 3 (`.env.local`) | `HOST`, deployment integrations; on the regional axis: `JURISDICTION`, `APPROXIMATED_PROXY_*`, `EMAILER_REGION` |
| Per-instance secret | layer 3 (never committed) | `SECRET`, `*_SECRET`, `*_DATABASE_URL`, `RABBITMQ_URL`, `SMTP_PASSWORD`, API tokens, DSNs |

The strongest lever is layer 1: for any value that is the same for everyone,
flip its fallback so a fresh instance needs zero lines for it, and only an
instance that deviates says so. A new instance then collapses to roughly its
hostname, its axis-specific integrations, and its secret set.

## Trade-offs

- **Gain**: an instance file auditable at a glance — every line is a variance
  the instance actually has; no stale-copy drift; one authority per value.
- **Lose**: single-file grep-ability — an instance's effective config now
  spans three layers. Mitigated by the audit tool below, which resolves the
  effective value and reports its source layer.
- **Watch**: flipping a layer-1 default changes behaviour for *every* unset
  deployment, including third-party self-hosters. Flip only values that are
  genuinely the right product default, not merely convenient for our fleet;
  when in doubt, use layer 2.

## Related

- [ADR-027](adr-027-one-authority-per-value.md) — one authority per value;
  this ADR is that principle applied to environment configuration.
- [ADR-028](adr-028-brand-config-layering-order.md) — brand config layering
  order; the same shape (shared defaults deepest, per-deployment overrides
  shallowest and winning) applied to brand assets.
- `docs/architecture/regions.md` — regional deployments, one axis of instance
  variance (`JURISDICTION`, `APPROXIMATED_PROXY_*`, `EMAILER_REGION`).
- `.env.reference` — the enumerated variable catalog with defaults.

## Implementation Notes

### 2026-07-14 — Determination method (audit tool)

Both tests are automatable. An audit script reads the effective default for
every variable straight from `etc/defaults/*.yaml` (parsing the
`ENV['X'] || …`, `!= 'false'`, `== 'true'` shapes) and classifies a set of
`.env` files:

- **Pass 1 (one file):** flag variables whose value equals the baked-in
  default → deletable now.
- **Pass 2 (all instance files together):** diff each variable across
  instances — identical everywhere ⇒ centralize (layer 1 or 2); differs ⇒
  keep (layer 3). Pass 2 is the decisive one and requires every instance's
  file.

A prototype lives at `scratchpad/env_audit.rb` (uncommitted). Promote it to
`bin/` as a CI-runnable check so instance files can't silently re-accumulate
defaults. Two rough edges to fix on promotion: it regex-buckets a few
non-secret names (`AUTH_PASSWORD_REQUIREMENTS_ENABLED`,
`ORGS_INCOMING_SECRETS_ENABLED`, `SECRET_VARIABLE_NAMES`) as secrets, and it
does not resolve chained `ENV['A'] || ENV['B']` fallbacks (mail/AWS/Redis-DB
aliases), marking them for manual review instead of guessing.

### 2026-07-14 — Baseline finding

Against a reference dev `.env` (106 variables): 18 equalled the default
outright (deletable), ~25 were instance-invariant overrides (centralizable),
and the residue was per-instance facts, secrets, and code-level/runtime reads.
`FROM`/`FROMEMAIL`/`FROMNAME` surfaced as legacy aliases of
`FROM_EMAIL`/`FROM_NAME`, candidates for removal. Order of magnitude: an
instance file should be closer to 20 lines than 100.
