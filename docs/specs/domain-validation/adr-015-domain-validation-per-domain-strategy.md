---
id: "015"
status: proposed
title: "ADR-015: Per-Domain Validation Strategy Override"
---

## Status

Proposed

## Date

2026-06-30

## Context

`features.domains.validation_strategy` (`etc/defaults/config.defaults.yaml:60-75`)
is the only place a validation strategy is selected, and it is install-level:
one value for the entire deployment. The motivation for moving off
Approximated as the sole strategy is cost (hundreds/month and growing since
custom domains shipped on free plans) and TLS-termination control (we now
run Approximated's proxies ourselves, in-jurisdiction, for compliance) — not
a feature gap in Approximated itself, which still works well and is the
right choice for some environments. The team wants to cut over
incrementally per regional environment rather than a single global
switchover, and self-hosted installs need a path that doesn't require a
paid third-party account at all.

Research note (see `docs/specs/domain-validation/domain-validation-policy.md`, Issue 2): the
verified evidence pool — Cloudflare for SaaS, Fly.io, CA/Browser Forum —
contains no precedent for per-tenant-domain strategy selection; all
describe single-backend systems from the customer's perspective. This
decision is recorded as an internal cost/migration-economics call, not an
externally-validated best practice. No citation is asserted for "why
per-domain"; the "how" below follows the existing strategy interface, which
needs no reshaping.

## Decision

Add a `validation_strategy` field to `CustomDomain`, nullable. Resolution
order in `Strategy.for_config`: `custom_domain.validation_strategy` if set,
else the install-level `features.domains.validation_strategy` default. The
field is **not** user-facing — no UI control is required for this decision;
it is set by an operator (CLI, admin tooling, or a migration script) per
domain or per regional batch.

This requires `Strategy.for_config` (and its current call sites) to accept
an optional `CustomDomain` instance, not just the global config object,
falling back to current global-only behavior when no domain is passed or
the domain has no override — existing behavior is unchanged for installs
that never set the per-domain field.

`lib/onetime/cli/domains/doctor_command.rb` already audits per-domain
state; extend its output to show effective strategy (override or
install-default) per domain so operators can verify a migration batch
landed correctly without grepping Redis.

## Trade-offs

- **We lose**: the simplicity of a single global toggle — strategy now has
  two possible sources, and debugging "why is this domain using strategy X"
  requires checking both.
- **We gain**: incremental, reversible regional cutover off Approximated
  with no big-bang switch; self-hosted installs get a path to a
  paid-third-party-free strategy without forcing existing Approximated
  customers to move.
- **Risk**: per-domain divergence complicates support/debugging. Mitigated
  by extending the existing doctor command rather than building new
  tooling.
