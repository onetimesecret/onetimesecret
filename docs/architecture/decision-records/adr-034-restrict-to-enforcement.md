---
id: 034
status: accepted
decided: 2026-08-11
title: "ADR-034: Authentication Method Restriction Resolution and Fail-Closed Enforcement"
---

## Context

PR #4130 shipped the display half of domain `restrict_to` (every value
rendered, single-method picker enabled) but left two gaps: no server-side
enforcement, no server-side re-validation. Split out of [ADR-024](adr-024-custom-domain-auth-override-resolution.md#amendments),
which recorded the underlying decisions. Deciding principle throughout:
security, privacy, and long-term codebase health; the default posture is
fail-closed.

Section headings below declare their own citation anchors (ADR-036#anchors-are-declared) — reference them as
`ADR-034#slug` rather than by position; sections may be reordered or reworded without
breaking a citation.

## Decision

### Restrict_to is an access control, not a display preference {#restrict-to-is-an-access-control-not-a-display-preference}

When resolution yields a single method for a request host, the server MUST
reject submission of every other method on that host — crafted POSTs
included. Corollary, broader than `restrict_to`: a disabled auth method must
never function even when fully and correctly configured (e.g. a complete SSO
configuration with SSO disabled stays dark at every surface). Configuration
presence is never availability.

Scope note: this is request-host enforcement — *which methods* work on this
host. *Which accounts* may authenticate on this host is [ADR-035](adr-035-tenant-identity-auth-policy-scope.md).

### Resolution is model-owned {#resolution-is-model-owned}

`SigninConfig.resolve_restrict_to(global, config)` is the single resolver
consumed by all three gates — display, runtime, settings API. No caller
re-derives.

### Degradation is fail-closed {#degradation-is-fail-closed}

A restriction whose backing method is unavailable — globally disabled,
credentials dormant, incapable on this host, or a stray/invalid value —
resolves to *sign-in unavailable* (or a method-specific notice), never to
standard mode. Widening re-exposes exactly the methods the restriction was
meant to hide. This holds at both layers: a domain restriction degrades to
unavailable, and a *global* `restrict_to` naming a method the system already
knows is unavailable at boot is a fatal boot error, not a runtime fallback —
surfaced at deploy time to the operator who holds the config and can fix it.

### Settings API serializes effective_restrict_to {#settings-api-serializes-effective-restrict-to}

`details` carries `effective_restrict_to` (the resolver's output) alongside
`global_restrict_to`. The client displays resolver output and never
re-implements resolution.

### Custom-domain WebAuthn fails closed pending RP-ID scoping {#custom-domain-webauthn-fails-closed-pending-rp-id-scoping}

WebAuthn credentials are registered on the canonical host only;
`account_webauthn_keys` carries no per-domain RP-ID column, so nothing can
assert on a branded domain today. Until that scoping exists (tracked
separately), `restrict_to='webauthn'` on a custom domain is not policy — it
fails closed under [degradation-is-fail-closed](#degradation-is-fail-closed)
like any other unavailable method.

### Reject as not-found, not forbidden {#reject-as-not-found-not-forbidden}

A restricted-away method rejects as 404, matching Rodauth's behavior for a
feature that was never loaded — not a 403. A 403 gate means the handler is
still mounted, still reachable, still one bug away from executing; that is
configuration presenting as availability, the exact shape this ADR exists to
kill. The marginal information disclosed by a 404 here is nil: the sign-in
page on that host already advertises the one method it offers.

Enforcement covers every reachable route per restricted method, not only the
primary sign-in POST — secondary endpoints (verify, resend, callback,
ceremony-start) included, since a gate that covers the primary route and
misses a secondary one leaves the gap open while looking closed.

Enforcement is request-host scoped and applies to the pre-auth sign-in
surface only. Second-factor completion ceremonies and authenticated
credential-management endpoints (`change-password`, `webauthn-setup`,
`webauthn-remove`) are account-scoped, not host-scoped, and stay exempt —
they remain governed by [ADR-035](adr-035-tenant-identity-auth-policy-scope.md)
and `SsoOnlyGating` respectively. Pre-auth password surfaces
(`create-account`, `reset-password-request`, `reset-password`) are not
exempt.

The durable assertion of complete coverage is the coverage spec reading the
live route table and failing on any route classified neither gated nor
exempt, exemptions listed explicitly and never defaulted open — not a
prose enumeration, which is a hypothesis until tested.

### Resolution intersects, never widens {#resolution-intersects-never-widens}

An enabled domain config that leaves `restrict_to` unset does not erase a
global restriction on that host — resolution intersects rather than
replaces:

| global | domain | result |
|---|---|---|
| set | unset | global restriction stands |
| unset | set | domain restriction stands |
| set | set, equal | that method |
| set | set, different | `:unavailable` |
| unset | unset | `:unrestricted` |

Two different single-method restrictions have no intersection, so a
conflict fails closed rather than picking a winner — picking one would mean
either a tenant overriding the operator or the operator silently discarding
a tenant's deliberate setting.

### Conflicting AUTH-only env flags are a boot error {#conflicting-auth-only-env-flags-are-a-boot-error}

More than one `AUTH_*_ONLY` env flag set at once is a fatal boot error naming
every flag set, not a silent empty restriction. Zero or one flag behaves as
before.

### Invite signup is gated {#invite-signup-is-gated}

`POST /api/invite/:token/signup` mints a session via `Auth::Config.create_account`
(Rodauth `internal_request`) and is gated by `Auth::RestrictTo.allows?`
before any invitation state is touched, rejecting 404 per
[reject-as-not-found-not-forbidden](#reject-as-not-found-not-forbidden). The
internal-request exemption used for second-factor and account-management
flows does not extend here: the endpoint itself knows the request host even
though the inner Rodauth call does not. `GET /:token` (display) and
`POST /:token/accept` (account-scoped) stay ungated.

## Consequences

- Enforcement spans three surfaces that don't share a single hook point:
  Rodauth routes (`before_rodauth`), OmniAuth (`omniauth_setup` /
  `before_omniauth_callback_route`, middleware-served and outside
  `before_rodauth`), and simple mode (`POST /auth/login` served from Core,
  not Rodauth). All three must be gated or enforcement is silently partial.
- `SsoOnlyGating` predates this decision and keeps its own 403 + `error_key`
  shape for already-authenticated account-management operations; that
  divergence is a deliberate split, not reconciliation debt.
- A global boot-time restriction naming an unavailable method now refuses to
  boot rather than silently discarding the restriction.

## References

- `apps/web/auth/restrict_to.rb` — enforcement gate
- `apps/web/auth/config/hooks/restrict_to.rb`, `omniauth_tenant.rb` — OmniAuth surface
- `lib/onetime/auth_config.rb`, `lib/onetime/initializers/validate_auth_config.rb` — boot-time validation
- `apps/web/core/controllers/base.rb` — resolution gathering
- `apps/web/auth/spec/integration/full/restrict_to_enforcement_spec.rb`,
  `spec/integration/simple/restrict_to_enforcement_spec.rb`,
  `apps/web/auth/spec/unit/restrict_to_gate_spec.rb` — coverage spec (the durable route enumeration)
