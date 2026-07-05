---
id: "017"
status: proposed
title: "ADR-017: Gate Domain-Dependent Functionality on Ownership Verification"
---

## Status

Proposed

## Date

2026-06-30

## Context

`apps/api/v1/logic/secrets/base_secret_action.rb:456-461`
(`validate_domain_verification`) only blocks secret creation on an
unverified custom domain when `features.domains.require_verified` is
explicitly `true`; the default is `false`. Under the `passthrough` strategy,
`validate_ownership()` always returns `true` and `check_status()` always
reports `ready: true` (no-op by design) — so by default, **any domain
string can be attached to an account and used to create branded secret
links with zero ownership proof**, regardless of whether the customer
actually controls that domain.

The team's original framing for not enabling the gate was UX risk: without
reliable periodic re-validation, a domain could get stuck in "DNS
Incomplete" indefinitely, blocking the product's core functionality for
customers who did nothing wrong.

Research reframes the underlying issue as security, not primarily UX.
OWASP's Subdomain Takeover Prevention Cheat Sheet (3-0 verified): the
canonical takeover pattern is a DNS record pointing at a resource with no
ownership tie, letting an attacker claim it. Under `passthrough`, the
inverse happens: the customer doesn't even need a real DNS record — typing
a domain string into OTS is sufficient to start serving links under it. If
that domain belongs to someone else (typo, an expired/dangling domain, a
domain the customer doesn't control), OTS itself becomes the takeover
vector. This risk extends to `caddy_on_demand` (ADR-016): a Caddy ACME
issuance proves DNS resolution, not account ownership, and the strategy
performs no ownership check today.

The "stuck forever" blocker does not actually require deferring the gate.
Cloudflare's and RFC 8555's validation lifecycles are bounded (finite
backoff, automatic terminal state) — a **one-time** ownership check at
domain-attach time does not depend on a mature always-on re-validation
pipeline (ADR-018) to be safe to enable.

## Decision

Gating is decoupled from the single global `require_verified` flag and
made strategy-aware:

- **`passthrough`**: requires a one-time TXT ownership proof (ADR-016) at
  domain-attach time before the domain can be selected as a `share_domain`
  for link creation. This is independent of whether the operator has set
  `require_verified` — `passthrough` has no other ownership signal, so the
  check is not optional for this strategy.
- **`caddy_on_demand`**: same one-time TXT ownership requirement, kept
  separate from Caddy's ACME-driven cert issuance (ADR-016 non-conflation).
  Cert issuance proceeding does not imply the gate is satisfied.
- **`approximated`**: existing behavior, configurable via
  `require_verified`, since Approximated already performs a TXT check as
  part of its own flow.

This is a one-time gate at attach-time, not a dependency on the periodic
re-validation system (ADR-018). A domain that later stops resolving is a
re-validation concern, not a link-creation concern — already-attached,
already-verified domains are not retroactively blocked by transient DNS
issues.

Rollout: this changes default behavior for any existing `passthrough`
deployment. Ship behind a feature flag with a deprecation window, default
flag value flips after the window closes, so self-hosted installs and
existing production domains have time to complete a one-time ownership
proof rather than losing link-creation capability on upgrade.

## Trade-offs

- **We lose**: `passthrough`'s "zero friction, zero validation" simplicity
  — every domain, even on `passthrough`, now requires one DNS TXT record
  to be added before it's usable for link creation.
- **We gain**: closes a real domain-takeover-style trust gap. Removes
  reliance on the team's stated blocker (mature periodic re-validation)
  for safety, since the gate only needs a one-time check, not an ongoing
  one.
- **Risk**: breaking change for any current `passthrough` install relying
  on instant, unverified domain attachment. Mitigated by the feature-flag
  rollout window above.

## Implementation Notes

### Scope check (2026-06-30)

This ADR governs the **link-creation gate** only. It does not change
`require_verified`'s existing semantics for `approximated`, and it does not
require ADR-018's backoff scheduler to ship first — the one-time check at
attach-time is independent of ongoing re-validation cadence.
